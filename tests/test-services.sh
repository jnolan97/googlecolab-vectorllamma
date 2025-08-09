#!/bin/bash

# Service Status Tests
# Tests for PXE server service status and functionality

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test utilities
test_info() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

test_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    test_info "Running: $test_name"
    
    if $test_function; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name"
        return 1
    fi
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

# Test DHCP service status
test_dhcp_service() {
    test_info "Testing DHCP service status..."
    
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        test_pass "DHCP service found: $dhcp_service"
        
        # Check if service is installed
        if systemctl list-unit-files "${dhcp_service}.service" >/dev/null 2>&1; then
            test_pass "DHCP service is installed: $dhcp_service"
            
            # Check service status
            local status
            if systemctl is-active --quiet "$dhcp_service"; then
                status="active"
                test_pass "DHCP service is active: $dhcp_service"
            elif systemctl is-enabled --quiet "$dhcp_service" 2>/dev/null; then
                status="inactive"
                test_warn "DHCP service is enabled but not active: $dhcp_service"
            else
                status="disabled"
                test_warn "DHCP service is not enabled: $dhcp_service"
            fi
            
            # Check for errors in service logs
            if journalctl -u "$dhcp_service" --since="1 hour ago" --no-pager -q | grep -i error >/dev/null 2>&1; then
                test_warn "DHCP service has errors in logs (check: journalctl -u $dhcp_service)"
            else
                test_pass "DHCP service logs appear clean"
            fi
            
            return 0
        else
            test_fail "DHCP service is not installed: $dhcp_service"
            return 1
        fi
    else
        test_fail "No DHCP service found"
        return 1
    fi
}

# Test TFTP service status
test_tftp_service() {
    test_info "Testing TFTP service status..."
    
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        test_pass "TFTP service found: $tftp_service"
        
        # Check if service is installed
        if systemctl list-unit-files "${tftp_service}.service" >/dev/null 2>&1; then
            test_pass "TFTP service is installed: $tftp_service"
            
            # Check service status
            local status
            if systemctl is-active --quiet "$tftp_service"; then
                status="active"
                test_pass "TFTP service is active: $tftp_service"
            elif systemctl is-enabled --quiet "$tftp_service" 2>/dev/null; then
                status="inactive"
                test_warn "TFTP service is enabled but not active: $tftp_service"
            else
                status="disabled"
                test_warn "TFTP service is not enabled: $tftp_service"
            fi
            
            # Check for errors in service logs
            if journalctl -u "$tftp_service" --since="1 hour ago" --no-pager -q | grep -i error >/dev/null 2>&1; then
                test_warn "TFTP service has errors in logs (check: journalctl -u $tftp_service)"
            else
                test_pass "TFTP service logs appear clean"
            fi
            
            return 0
        else
            test_fail "TFTP service is not installed: $tftp_service"
            return 1
        fi
    else
        test_fail "No TFTP service found"
        return 1
    fi
}

# Test NFS service status
test_nfs_service() {
    test_info "Testing NFS service status..."
    
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        test_pass "NFS service found: $nfs_service"
        
        # Check if service is installed
        if systemctl list-unit-files "${nfs_service}.service" >/dev/null 2>&1; then
            test_pass "NFS service is installed: $nfs_service"
            
            # Check service status
            local status
            if systemctl is-active --quiet "$nfs_service"; then
                status="active"
                test_pass "NFS service is active: $nfs_service"
            elif systemctl is-enabled --quiet "$nfs_service" 2>/dev/null; then
                status="inactive"
                test_warn "NFS service is enabled but not active: $nfs_service"
            else
                status="disabled"
                test_warn "NFS service is not enabled: $nfs_service"
            fi
            
            # Check for errors in service logs
            if journalctl -u "$nfs_service" --since="1 hour ago" --no-pager -q | grep -i error >/dev/null 2>&1; then
                test_warn "NFS service has errors in logs (check: journalctl -u $nfs_service)"
            else
                test_pass "NFS service logs appear clean"
            fi
            
            # Test NFS exports if service is active
            if [[ "$status" == "active" ]] && command -v showmount >/dev/null 2>&1; then
                if showmount -e localhost >/dev/null 2>&1; then
                    test_pass "NFS exports are accessible"
                else
                    test_warn "NFS exports may not be configured or accessible"
                fi
            fi
            
            return 0
        else
            test_fail "NFS service is not installed: $nfs_service"
            return 1
        fi
    else
        test_fail "No NFS service found"
        return 1
    fi
}

# Test service dependencies
test_service_dependencies() {
    test_info "Testing service dependencies..."
    
    local errors=0
    
    # Check if systemd is running
    if systemctl --version >/dev/null 2>&1; then
        test_pass "Systemd is available"
    else
        test_fail "Systemd is not available"
        ((errors++))
    fi
    
    # Check if journalctl is available for log checking
    if command -v journalctl >/dev/null 2>&1; then
        test_pass "Journalctl is available for log analysis"
    else
        test_warn "Journalctl is not available"
    fi
    
    # Check if required network tools are available
    local network_tools=("ip" "ping")
    for tool in "${network_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            test_pass "Network tool available: $tool"
        else
            test_warn "Network tool not available: $tool"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test configuration files exist and are readable
test_configuration_files() {
    test_info "Testing configuration file accessibility..."
    
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        set -a
        source "${env_file}"
        set +a
    else
        # Load defaults from .env.example
        if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
            set -a
            source "${PROJECT_ROOT}/.env.example"
            set +a
        fi
    fi
    
    local config_files=(
        "${DHCP_CONFIG_FILE:-/etc/dhcp/dhcpd.conf}:DHCP"
        "${TFTP_CONFIG_FILE:-/etc/default/tftpd-hpa}:TFTP"
        "${NFS_CONFIG_FILE:-/etc/exports}:NFS"
    )
    
    local errors=0
    
    for config_info in "${config_files[@]}"; do
        IFS=':' read -ra config_data <<< "$config_info"
        local config_file="${config_data[0]}"
        local service_name="${config_data[1]}"
        
        if [[ -f "$config_file" ]]; then
            if [[ -r "$config_file" ]]; then
                test_pass "$service_name configuration file is readable: $config_file"
            else
                test_fail "$service_name configuration file is not readable: $config_file"
                ((errors++))
            fi
        else
            test_warn "$service_name configuration file does not exist: $config_file"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test service performance and resource usage
test_service_performance() {
    test_info "Testing service performance and resource usage..."
    
    # Get system load
    local load_avg
    if load_avg=$(uptime | grep -oP '(?<=load average: )\S+'); then
        # Convert to number and compare (basic check)
        local load_num
        load_num=$(echo "$load_avg" | cut -d',' -f1)
        if (( $(echo "$load_num < 5.0" | bc -l 2>/dev/null || echo "1") )); then
            test_pass "System load is acceptable: $load_avg"
        else
            test_warn "System load is high: $load_avg"
        fi
    else
        test_warn "Cannot determine system load"
    fi
    
    # Check memory usage
    if command -v free >/dev/null 2>&1; then
        local memory_info
        memory_info=$(free -m | grep '^Mem:')
        local total_mem
        local used_mem
        total_mem=$(echo "$memory_info" | awk '{print $2}')
        used_mem=$(echo "$memory_info" | awk '{print $3}')
        
        if [[ -n "$total_mem" && -n "$used_mem" && "$total_mem" -gt 0 ]]; then
            local usage_percent
            usage_percent=$((used_mem * 100 / total_mem))
            if [[ $usage_percent -lt 90 ]]; then
                test_pass "Memory usage is acceptable: ${usage_percent}%"
            else
                test_warn "Memory usage is high: ${usage_percent}%"
            fi
        else
            test_warn "Cannot determine memory usage"
        fi
    else
        test_warn "Cannot check memory usage (free command not available)"
    fi
    
    # Check disk space for TFTP and NFS roots
    local tftp_root="${TFTP_ROOT:-/var/lib/tftpboot}"
    local nfs_root="${NFS_ROOT:-/var/lib/nfs}"
    
    for root_dir in "$tftp_root" "$nfs_root"; do
        if [[ -d "$root_dir" ]]; then
            local disk_usage
            if disk_usage=$(df -h "$root_dir" 2>/dev/null | tail -n1 | awk '{print $5}' | sed 's/%//'); then
                if [[ $disk_usage -lt 90 ]]; then
                    test_pass "Disk usage acceptable for $root_dir: ${disk_usage}%"
                else
                    test_warn "Disk usage high for $root_dir: ${disk_usage}%"
                fi
            else
                test_warn "Cannot check disk usage for $root_dir"
            fi
        fi
    done
    
    return 0
}

# Test service autostart configuration
test_service_autostart() {
    test_info "Testing service autostart configuration..."
    
    local services_to_check=()
    
    # Find available services
    local dhcp_service
    if dhcp_service=$(find_service "${DHCP_SERVICES[@]}"); then
        services_to_check+=("$dhcp_service:DHCP")
    fi
    
    local tftp_service
    if tftp_service=$(find_service "${TFTP_SERVICES[@]}"); then
        services_to_check+=("$tftp_service:TFTP")
    fi
    
    local nfs_service
    if nfs_service=$(find_service "${NFS_SERVICES[@]}"); then
        services_to_check+=("$nfs_service:NFS")
    fi
    
    for service_info in "${services_to_check[@]}"; do
        IFS=':' read -ra service_data <<< "$service_info"
        local service="${service_data[0]}"
        local service_name="${service_data[1]}"
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            test_pass "$service_name service is enabled for autostart: $service"
        else
            test_warn "$service_name service is not enabled for autostart: $service"
        fi
    done
    
    return 0
}

# Main test runner
run_all_tests() {
    echo "PXE Server Service Status Tests"
    echo "==============================="
    
    # Run all service tests
    run_test "Service Dependencies" test_service_dependencies
    run_test "DHCP Service" test_dhcp_service
    run_test "TFTP Service" test_tftp_service
    run_test "NFS Service" test_nfs_service
    run_test "Configuration Files" test_configuration_files
    run_test "Service Performance" test_service_performance
    run_test "Service Autostart" test_service_autostart
    
    # Print summary
    echo
    echo "==============================="
    echo "Test Summary:"
    echo "  Total Tests: $TESTS_RUN"
    echo "  Passed:      $TESTS_PASSED"
    echo "  Failed:      $TESTS_FAILED"
    echo "==============================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        test_info "All service tests passed!"
        return 0
    else
        test_info "$TESTS_FAILED service test(s) failed."
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    all                 Run all service tests (default)
    dependencies        Test service dependencies
    dhcp                Test DHCP service only
    tftp                Test TFTP service only
    nfs                 Test NFS service only
    configs             Test configuration file accessibility
    performance         Test service performance
    autostart           Test service autostart configuration
    
Examples:
    $0                  # Run all service tests
    $0 dhcp             # Test only DHCP service
    $0 performance      # Test only performance metrics
    
EOF
}

# Main function
main() {
    local command="${1:-all}"
    
    case "$command" in
        all)
            run_all_tests
            ;;
        dependencies)
            run_test "Service Dependencies" test_service_dependencies
            ;;
        dhcp)
            run_test "DHCP Service" test_dhcp_service
            ;;
        tftp)
            run_test "TFTP Service" test_tftp_service
            ;;
        nfs)
            run_test "NFS Service" test_nfs_service
            ;;
        configs)
            run_test "Configuration Files" test_configuration_files
            ;;
        performance)
            run_test "Service Performance" test_service_performance
            ;;
        autostart)
            run_test "Service Autostart" test_service_autostart
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi