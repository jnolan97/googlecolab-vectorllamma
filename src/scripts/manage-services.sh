#!/bin/bash

# Service Management Script for PXE Server
# Manages DHCP, TFTP, and NFS services

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

# Service names (try multiple variants for different distributions)
DHCP_SERVICES=("isc-dhcp-server" "dhcpd")
TFTP_SERVICES=("tftpd-hpa" "tftp")
NFS_SERVICES=("nfs-kernel-server" "nfs-server" "nfs")

# Find available service name
find_service() {
    local services=("$@")
    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}.service" &>/dev/null; then
            echo "$service"
            return 0
        fi
    done
    return 1
}

# Get service status
get_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo "active"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        echo "inactive"
    else
        echo "disabled"
    fi
}

# Start service
start_service() {
    local service="$1"
    log_info "Starting service: $service"
    
    if systemctl start "$service"; then
        log_success "Started: $service"
        return 0
    else
        log_error "Failed to start: $service"
        return 1
    fi
}

# Stop service
stop_service() {
    local service="$1"
    log_info "Stopping service: $service"
    
    if systemctl stop "$service"; then
        log_success "Stopped: $service"
        return 0
    else
        log_error "Failed to stop: $service"
        return 1
    fi
}

# Restart service
restart_service() {
    local service="$1"
    log_info "Restarting service: $service"
    
    if systemctl restart "$service"; then
        log_success "Restarted: $service"
        return 0
    else
        log_error "Failed to restart: $service"
        return 1
    fi
}

# Enable service
enable_service() {
    local service="$1"
    log_info "Enabling service: $service"
    
    if systemctl enable "$service"; then
        log_success "Enabled: $service"
        return 0
    else
        log_error "Failed to enable: $service"
        return 1
    fi
}

# Disable service
disable_service() {
    local service="$1"
    log_info "Disabling service: $service"
    
    if systemctl disable "$service"; then
        log_success "Disabled: $service"
        return 0
    else
        log_error "Failed to disable: $service"
        return 1
    fi
}

# Get service logs
get_service_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    log_info "Getting logs for service: $service"
    journalctl -u "$service" --no-pager -n "$lines"
}

# Status of all PXE services
status_all() {
    log_info "PXE Server Service Status"
    echo "=========================="
    
    # DHCP Service
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        local dhcp_status=$(get_service_status "$dhcp_service")
        printf "DHCP (%s): %s\n" "$dhcp_service" "$dhcp_status"
    else
        log_warn "DHCP service not found"
    fi
    
    # TFTP Service
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        local tftp_status=$(get_service_status "$tftp_service")
        printf "TFTP (%s): %s\n" "$tftp_service" "$tftp_status"
    else
        log_warn "TFTP service not found"
    fi
    
    # NFS Service
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        local nfs_status=$(get_service_status "$nfs_service")
        printf "NFS  (%s): %s\n" "$nfs_service" "$nfs_status"
    else
        log_warn "NFS service not found"
    fi
}

# Start all PXE services
start_all() {
    log_info "Starting all PXE services..."
    
    local errors=0
    
    # Start DHCP
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        start_service "$dhcp_service" || ((errors++))
    else
        log_error "DHCP service not found"
        ((errors++))
    fi
    
    # Start TFTP
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        start_service "$tftp_service" || ((errors++))
    else
        log_error "TFTP service not found"
        ((errors++))
    fi
    
    # Start NFS
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        start_service "$nfs_service" || ((errors++))
    else
        log_error "NFS service not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All services started successfully"
    else
        log_error "Failed to start $errors service(s)"
        return 1
    fi
}

# Stop all PXE services
stop_all() {
    log_info "Stopping all PXE services..."
    
    local errors=0
    
    # Stop DHCP
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        stop_service "$dhcp_service" || ((errors++))
    fi
    
    # Stop TFTP
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        stop_service "$tftp_service" || ((errors++))
    fi
    
    # Stop NFS
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        stop_service "$nfs_service" || ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All services stopped successfully"
    else
        log_error "Failed to stop $errors service(s)"
        return 1
    fi
}

# Restart all PXE services
restart_all() {
    log_info "Restarting all PXE services..."
    
    local errors=0
    
    # Restart DHCP
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        restart_service "$dhcp_service" || ((errors++))
    fi
    
    # Restart TFTP
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        restart_service "$tftp_service" || ((errors++))
    fi
    
    # Restart NFS
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        restart_service "$nfs_service" || ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All services restarted successfully"
    else
        log_error "Failed to restart $errors service(s)"
        return 1
    fi
}

# Enable all PXE services
enable_all() {
    log_info "Enabling all PXE services..."
    
    local errors=0
    
    # Enable DHCP
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        enable_service "$dhcp_service" || ((errors++))
    fi
    
    # Enable TFTP
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        enable_service "$tftp_service" || ((errors++))
    fi
    
    # Enable NFS
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        enable_service "$nfs_service" || ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All services enabled successfully"
    else
        log_error "Failed to enable $errors service(s)"
        return 1
    fi
}

# Show logs for all services
logs_all() {
    local lines="${1:-50}"
    
    log_info "PXE Server Service Logs (last $lines lines)"
    echo "==========================================="
    
    # DHCP logs
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        echo
        log_info "DHCP Service Logs ($dhcp_service):"
        get_service_logs "$dhcp_service" "$lines"
    fi
    
    # TFTP logs
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        echo
        log_info "TFTP Service Logs ($tftp_service):"
        get_service_logs "$tftp_service" "$lines"
    fi
    
    # NFS logs
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        echo
        log_info "NFS Service Logs ($nfs_service):"
        get_service_logs "$nfs_service" "$lines"
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    status              Show status of all PXE services
    start               Start all PXE services
    stop                Stop all PXE services
    restart             Restart all PXE services
    enable              Enable all PXE services for startup
    disable             Disable all PXE services from startup
    logs [LINES]        Show service logs (default: 50 lines)
    
Examples:
    $0 status           # Show service status
    $0 restart          # Restart all services
    $0 logs 100         # Show last 100 log lines
    
EOF
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        status)
            status_all
            ;;
        start)
            start_all
            ;;
        stop)
            stop_all
            ;;
        restart)
            restart_all
            ;;
        enable)
            enable_all
            ;;
        disable)
            # Similar to enable_all but with disable
            log_info "Disabling all PXE services..."
            local errors=0
            
            for services in "DHCP_SERVICES[@]" "TFTP_SERVICES[@]" "NFS_SERVICES[@]"; do
                declare -n service_array="$services"
                local service
                if service=$(find_service "${service_array[@]}"); then
                    disable_service "$service" || ((errors++))
                fi
            done
            
            if [[ $errors -eq 0 ]]; then
                log_success "All services disabled successfully"
            else
                log_error "Failed to disable $errors service(s)"
                exit 1
            fi
            ;;
        logs)
            local lines="${1:-50}"
            logs_all "$lines"
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