#!/bin/bash

# Environment and Configuration Validation Script
# Validates PXE server environment and configuration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

# Validate required environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    local required_vars=(
        "DHCP_SUBNET"
        "DHCP_NETMASK"
        "DHCP_RANGE_START"
        "DHCP_RANGE_END"
        "DHCP_GATEWAY"
        "PXE_SERVER_IP"
        "TFTP_ROOT"
        "NFS_ROOT"
    )
    
    local errors=0
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: $var"
            ((errors++))
        else
            log_success "Environment variable set: $var=${!var}"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "All required environment variables are set"
        return 0
    else
        log_error "Missing $errors required environment variable(s)"
        return 1
    fi
}

# Validate IP addresses
validate_ip_addresses() {
    log_info "Validating IP addresses..."
    
    local ip_vars=(
        "DHCP_SUBNET"
        "DHCP_RANGE_START"
        "DHCP_RANGE_END"
        "DHCP_GATEWAY"
        "PXE_SERVER_IP"
    )
    
    local errors=0
    
    for var in "${ip_vars[@]}"; do
        local ip="${!var:-}"
        if [[ -n "$ip" ]]; then
            if validate_ip "$ip"; then
                log_success "Valid IP address: $var=$ip"
            else
                log_error "Invalid IP address: $var=$ip"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "All IP addresses are valid"
        return 0
    else
        log_error "$errors invalid IP address(es) found"
        return 1
    fi
}

# Validate single IP address
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Validate network configuration
validate_network() {
    log_info "Validating network configuration..."
    
    local errors=0
    
    # Check if IP range is within subnet
    if command -v ipcalc &> /dev/null; then
        local subnet_check
        if ! subnet_check=$(ipcalc -c "${DHCP_SUBNET}/${DHCP_NETMASK}" 2>/dev/null); then
            log_error "Invalid subnet: ${DHCP_SUBNET}/${DHCP_NETMASK}"
            ((errors++))
        else
            log_success "Valid subnet: ${DHCP_SUBNET}/${DHCP_NETMASK}"
        fi
        
        # Check if DHCP range is within subnet
        local range_start_check
        if ! range_start_check=$(ipcalc -c "${DHCP_RANGE_START}" "${DHCP_SUBNET}/${DHCP_NETMASK}" 2>/dev/null); then
            log_error "DHCP range start (${DHCP_RANGE_START}) is not in subnet ${DHCP_SUBNET}/${DHCP_NETMASK}"
            ((errors++))
        else
            log_success "DHCP range start is in subnet"
        fi
        
        local range_end_check
        if ! range_end_check=$(ipcalc -c "${DHCP_RANGE_END}" "${DHCP_SUBNET}/${DHCP_NETMASK}" 2>/dev/null); then
            log_error "DHCP range end (${DHCP_RANGE_END}) is not in subnet ${DHCP_SUBNET}/${DHCP_NETMASK}"
            ((errors++))
        else
            log_success "DHCP range end is in subnet"
        fi
    else
        log_warn "ipcalc not available, skipping network validation"
    fi
    
    # Check if network interface exists
    if [[ -n "${DHCP_INTERFACE:-}" ]]; then
        if ip link show "${DHCP_INTERFACE}" &>/dev/null; then
            log_success "Network interface exists: ${DHCP_INTERFACE}"
        else
            log_error "Network interface not found: ${DHCP_INTERFACE}"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Network configuration is valid"
        return 0
    else
        log_error "$errors network configuration error(s) found"
        return 1
    fi
}

# Validate file permissions and directories
validate_filesystem() {
    log_info "Validating filesystem permissions and directories..."
    
    local errors=0
    
    # Required directories
    local required_dirs=(
        "${TFTP_ROOT:-/var/lib/tftpboot}"
        "${NFS_ROOT:-/var/lib/nfs}"
        "$(dirname "${LOG_FILE:-/var/log/pxe-server.log}")"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ -r "$dir" && -w "$dir" ]]; then
                log_success "Directory accessible: $dir"
            else
                log_error "Directory not accessible: $dir"
                ((errors++))
            fi
        else
            log_warn "Directory does not exist: $dir (will be created)"
        fi
    done
    
    # Configuration files
    local config_files=(
        "${DHCP_CONFIG_FILE:-/etc/dhcp/dhcpd.conf}"
        "${TFTP_CONFIG_FILE:-/etc/default/tftpd-hpa}"
        "${NFS_CONFIG_FILE:-/etc/exports}"
    )
    
    for file in "${config_files[@]}"; do
        local dir="$(dirname "$file")"
        if [[ -f "$file" ]]; then
            if [[ -r "$file" ]]; then
                log_success "Configuration file readable: $file"
            else
                log_error "Configuration file not readable: $file"
                ((errors++))
            fi
        else
            if [[ -d "$dir" && -w "$dir" ]]; then
                log_warn "Configuration file missing but directory writable: $file"
            else
                log_error "Cannot create configuration file: $file (directory not writable)"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "Filesystem validation passed"
        return 0
    else
        log_error "$errors filesystem error(s) found"
        return 1
    fi
}

# Validate required packages
validate_packages() {
    log_info "Validating required packages..."
    
    local errors=0
    local packages=()
    
    # Check for DHCP server
    if command -v dhcpd &> /dev/null; then
        log_success "DHCP server package installed"
        packages+=("dhcp")
    else
        log_error "DHCP server package not installed"
        ((errors++))
    fi
    
    # Check for TFTP server
    if command -v in.tftpd &> /dev/null || systemctl list-unit-files | grep -q tftp; then
        log_success "TFTP server package installed"
        packages+=("tftp")
    else
        log_error "TFTP server package not installed"
        ((errors++))
    fi
    
    # Check for NFS server
    if command -v exportfs &> /dev/null || systemctl list-unit-files | grep -q nfs; then
        log_success "NFS server package installed"
        packages+=("nfs")
    else
        log_error "NFS server package not installed"
        ((errors++))
    fi
    
    # Check for syslinux/pxelinux
    if [[ -f /usr/lib/PXELINUX/pxelinux.0 ]] || [[ -f /usr/share/syslinux/pxelinux.0 ]]; then
        log_success "PXE boot files available"
        packages+=("syslinux")
    else
        log_error "PXE boot files not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All required packages are installed"
        return 0
    else
        log_error "$errors required package(s) missing"
        return 1
    fi
}

# Validate ports availability
validate_ports() {
    log_info "Validating port availability..."
    
    local errors=0
    local ports=(
        "${TFTP_PORT:-69}:UDP:TFTP"
        "${NFS_PORT:-2049}:TCP:NFS"
        "67:UDP:DHCP"
    )
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -ra port_data <<< "$port_info"
        local port="${port_data[0]}"
        local protocol="${port_data[1]}"
        local service="${port_data[2]}"
        
        if command -v netstat &> /dev/null; then
            local proto_flag
            case "$protocol" in
                TCP) proto_flag="-t" ;;
                UDP) proto_flag="-u" ;;
                *) proto_flag="-a" ;;
            esac
            
            if netstat -ln $proto_flag | grep -q ":${port} "; then
                log_warn "Port $port/$protocol already in use (may be $service)"
            else
                log_success "Port $port/$protocol available for $service"
            fi
        else
            log_warn "netstat not available, cannot check port $port/$protocol for $service"
        fi
    done
    
    return 0
}

# Run all validations
run_all_validations() {
    log_info "Starting PXE server environment validation..."
    echo "============================================="
    
    local total_errors=0
    
    # Load environment first
    load_environment
    
    # Run all validation functions
    validate_environment || ((total_errors++))
    echo
    validate_ip_addresses || ((total_errors++))
    echo
    validate_network || ((total_errors++))
    echo
    validate_filesystem || ((total_errors++))
    echo
    validate_packages || ((total_errors++))
    echo
    validate_ports || ((total_errors++))
    
    echo
    echo "============================================="
    if [[ $total_errors -eq 0 ]]; then
        log_success "All validations passed! PXE server environment is ready."
        return 0
    else
        log_error "Validation completed with $total_errors error(s). Please fix the issues before proceeding."
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    all                 Run all validations (default)
    env                 Validate environment variables
    ip                  Validate IP addresses
    network             Validate network configuration
    filesystem          Validate filesystem permissions
    packages            Validate required packages
    ports               Validate port availability
    
Examples:
    $0                  # Run all validations
    $0 env              # Validate only environment variables
    $0 network          # Validate only network configuration
    
EOF
}

# Main function
main() {
    local command="${1:-all}"
    
    case "$command" in
        all)
            run_all_validations
            ;;
        env)
            load_environment
            validate_environment
            ;;
        ip)
            load_environment
            validate_ip_addresses
            ;;
        network)
            load_environment
            validate_network
            ;;
        filesystem)
            load_environment
            validate_filesystem
            ;;
        packages)
            validate_packages
            ;;
        ports)
            load_environment
            validate_ports
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi