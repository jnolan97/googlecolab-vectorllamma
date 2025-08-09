#!/bin/bash

# Configuration Generator Script
# Generates configuration files from templates using environment variables

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/src/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Load environment variables
load_environment() {
    local env_file="${PROJECT_ROOT}/.env"
    
    if [[ -f "${env_file}" ]]; then
        log_info "Loading environment from ${env_file}"
        set -a
        source "${env_file}"
        set +a
    else
        log_warn "No .env file found, using defaults from .env.example"
        if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
            set -a
            source "${PROJECT_ROOT}/.env.example"
            set +a
        fi
    fi
}

# Substitute environment variables in template
substitute_template() {
    local template_file="$1"
    local output_file="$2"
    
    if [[ ! -f "${template_file}" ]]; then
        log_error "Template file not found: ${template_file}"
        return 1
    fi
    
    log_info "Processing template: $(basename "${template_file}")"
    
    # Create backup of existing config if it exists
    if [[ -f "${output_file}" ]]; then
        cp "${output_file}" "${output_file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing config: ${output_file}"
    fi
    
    # Ensure output directory exists
    mkdir -p "$(dirname "${output_file}")"
    
    # Process template with envsubst
    envsubst < "${template_file}" > "${output_file}"
    
    # Verify output file was created
    if [[ -f "${output_file}" ]]; then
        log_success "Generated: ${output_file}"
    else
        log_error "Failed to generate: ${output_file}"
        return 1
    fi
}

# Generate DHCP configuration
generate_dhcp_config() {
    log_info "Generating DHCP configuration..."
    
    local template="${CONFIG_DIR}/dhcpd.conf.template"
    local output="${DHCP_CONFIG_FILE:-/etc/dhcp/dhcpd.conf}"
    
    # Calculate broadcast address if not provided
    if command -v ipcalc &> /dev/null; then
        export BROADCAST_ADDRESS=$(ipcalc -b "${DHCP_SUBNET}/${DHCP_NETMASK}" 2>/dev/null | cut -d= -f2 || echo "")
    fi
    
    substitute_template "${template}" "${output}"
}

# Generate TFTP configuration
generate_tftp_config() {
    log_info "Generating TFTP configuration..."
    
    local template="${CONFIG_DIR}/tftpd.conf.template"
    local output="${TFTP_CONFIG_FILE:-/etc/default/tftpd-hpa}"
    
    substitute_template "${template}" "${output}"
}

# Generate NFS configuration
generate_nfs_config() {
    log_info "Generating NFS configuration..."
    
    local template="${CONFIG_DIR}/exports.template"
    local output="${NFS_CONFIG_FILE:-/etc/exports}"
    
    substitute_template "${template}" "${output}"
}

# Generate PXE boot menu
generate_pxe_menu() {
    log_info "Generating PXE boot menu..."
    
    local template="${CONFIG_DIR}/pxelinux.cfg.template"
    local output="${PXELINUX_CONFIG_DIR:-/var/lib/tftpboot/pxelinux.cfg}/default"
    
    # Ensure pxelinux.cfg directory exists
    mkdir -p "${PXELINUX_CONFIG_DIR:-/var/lib/tftpboot/pxelinux.cfg}"
    
    substitute_template "${template}" "${output}"
}

# Validate generated configurations
validate_configs() {
    log_info "Validating generated configurations..."
    
    local errors=0
    
    # Check DHCP config syntax
    if command -v dhcpd &> /dev/null; then
        if ! dhcpd -t -cf "${DHCP_CONFIG_FILE:-/etc/dhcp/dhcpd.conf}" 2>/dev/null; then
            log_error "DHCP configuration syntax error"
            ((errors++))
        else
            log_success "DHCP configuration syntax valid"
        fi
    fi
    
    # Check if required files exist
    local required_files=(
        "${DHCP_CONFIG_FILE:-/etc/dhcp/dhcpd.conf}"
        "${TFTP_CONFIG_FILE:-/etc/default/tftpd-hpa}"
        "${NFS_CONFIG_FILE:-/etc/exports}"
        "${PXELINUX_CONFIG_DIR:-/var/lib/tftpboot/pxelinux.cfg}/default"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_success "Configuration file exists: ${file}"
        else
            log_error "Missing configuration file: ${file}"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "All configurations validated successfully"
        return 0
    else
        log_error "Configuration validation failed with ${errors} errors"
        return 1
    fi
}

# Main function
main() {
    log_info "Starting configuration generation..."
    
    load_environment
    
    # Generate all configurations
    generate_dhcp_config
    generate_tftp_config
    generate_nfs_config
    generate_pxe_menu
    
    # Validate configurations
    validate_configs
    
    log_success "Configuration generation completed!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi