#!/bin/bash

# PXE Server Setup Script
# This script sets up a complete PXE server with DHCP, TFTP, and NFS services

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/src/config"
LOG_FILE="${LOG_FILE:-/var/log/pxe-server.log}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Info logging
log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}[INFO]${NC} $*"
}

# Warning logging
log_warn() {
    log "WARN" "$*"
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Error logging
log_error() {
    log "ERROR" "$*"
    echo -e "${RED}[ERROR]${NC} $*"
}

# Success logging
log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
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
        log_warn "No .env file found, using default values"
        # Load defaults from .env.example
        if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
            set -a
            source "${PROJECT_ROOT}/.env.example"
            set +a
        fi
    fi
}

# Install required packages
install_packages() {
    log_info "Installing required packages..."
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y isc-dhcp-server tftpd-hpa nfs-kernel-server syslinux-common pxelinux ipcalc
    elif command -v yum &> /dev/null; then
        yum install -y dhcp-server tftp-server nfs-utils syslinux ipcalc
    elif command -v dnf &> /dev/null; then
        dnf install -y dhcp-server tftp-server nfs-utils syslinux ipcalc
    else
        log_error "Unsupported package manager"
        exit 1
    fi
    
    log_success "Packages installed successfully"
}

# Create directories
create_directories() {
    log_info "Creating required directories..."
    
    mkdir -p "${TFTP_ROOT}"
    mkdir -p "${TFTP_ROOT}/pxelinux.cfg"
    mkdir -p "${NFS_ROOT}"
    mkdir -p "${NFS_ROOT}/images"
    mkdir -p "${NFS_ROOT}/boot"
    mkdir -p "$(dirname "${LOG_FILE}")"
    
    log_success "Directories created"
}

# Generate configurations
generate_configs() {
    log_info "Generating configuration files..."
    
    # Run the configuration generator
    "${SCRIPT_DIR}/generate-configs.sh"
    
    log_success "Configuration files generated"
}

# Setup TFTP files
setup_tftp_files() {
    log_info "Setting up TFTP boot files..."
    
    # Copy syslinux files
    if [[ -d /usr/lib/syslinux/modules/bios ]]; then
        cp /usr/lib/syslinux/modules/bios/*.c32 "${TFTP_ROOT}/"
    elif [[ -d /usr/share/syslinux ]]; then
        cp /usr/share/syslinux/*.c32 "${TFTP_ROOT}/"
    fi
    
    # Copy pxelinux.0
    if [[ -f /usr/lib/PXELINUX/pxelinux.0 ]]; then
        cp /usr/lib/PXELINUX/pxelinux.0 "${TFTP_ROOT}/"
    elif [[ -f /usr/share/syslinux/pxelinux.0 ]]; then
        cp /usr/share/syslinux/pxelinux.0 "${TFTP_ROOT}/"
    fi
    
    # Set proper permissions
    chown -R tftp:tftp "${TFTP_ROOT}"
    chmod -R 755 "${TFTP_ROOT}"
    
    log_success "TFTP files setup completed"
}

# Start services
start_services() {
    log_info "Starting PXE server services..."
    
    # Start and enable services
    systemctl enable isc-dhcp-server || systemctl enable dhcpd
    systemctl enable tftpd-hpa || systemctl enable tftp
    systemctl enable nfs-kernel-server || systemctl enable nfs-server
    
    systemctl restart isc-dhcp-server || systemctl restart dhcpd
    systemctl restart tftpd-hpa || systemctl restart tftp
    systemctl restart nfs-kernel-server || systemctl restart nfs-server
    
    log_success "Services started successfully"
}

# Validate setup
validate_setup() {
    log_info "Validating PXE server setup..."
    
    # Run validation script
    "${SCRIPT_DIR}/validate-env.sh"
    
    log_success "Setup validation completed"
}

# Main setup function
main() {
    log_info "Starting PXE server setup..."
    
    check_root
    load_environment
    install_packages
    create_directories
    generate_configs
    setup_tftp_files
    start_services
    validate_setup
    
    log_success "PXE server setup completed successfully!"
    log_info "Server IP: ${PXE_SERVER_IP}"
    log_info "TFTP Root: ${TFTP_ROOT}"
    log_info "NFS Root: ${NFS_ROOT}"
    log_info "Log file: ${LOG_FILE}"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi