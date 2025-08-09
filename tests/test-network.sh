#!/bin/bash

# Network Connectivity Tests
# Tests network connectivity and port accessibility for PXE server

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

# Load environment variables
load_environment() {
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
}

# Test network interface availability
test_network_interface() {
    test_info "Testing network interface availability..."
    
    local interface="${DHCP_INTERFACE:-eth0}"
    
    # Check if interface exists
    if ip link show "$interface" >/dev/null 2>&1; then
        test_pass "Network interface exists: $interface"
        
        # Check if interface is up
        if ip link show "$interface" | grep -q "state UP"; then
            test_pass "Network interface is UP: $interface"
        else
            test_warn "Network interface is DOWN: $interface"
        fi
        
        # Get interface information
        local ip_addr
        ip_addr=$(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | head -n1)
        if [[ -n "$ip_addr" ]]; then
            test_pass "Network interface has IP address: $interface ($ip_addr)"
        else
            test_warn "Network interface has no IP address: $interface"
        fi
        
        return 0
    else
        test_fail "Network interface not found: $interface"
        return 1
    fi
}

# Test PXE server IP connectivity
test_pxe_server_ip() {
    test_info "Testing PXE server IP connectivity..."
    
    local pxe_ip="${PXE_SERVER_IP:-192.168.1.10}"
    
    # Check if IP is assigned to any interface
    if ip addr show | grep -q "$pxe_ip"; then
        test_pass "PXE server IP is assigned: $pxe_ip"
    else
        test_warn "PXE server IP is not assigned to any interface: $pxe_ip"
    fi
    
    # Test ping to PXE server IP
    if ping -c 1 -W 2 "$pxe_ip" >/dev/null 2>&1; then
        test_pass "PXE server IP is reachable: $pxe_ip"
        return 0
    else
        test_warn "PXE server IP is not reachable: $pxe_ip (may be normal if not configured yet)"
        return 0  # Not a failure, just a warning
    fi
}

# Test gateway connectivity
test_gateway_connectivity() {
    test_info "Testing gateway connectivity..."
    
    local gateway="${DHCP_GATEWAY:-192.168.1.1}"
    
    # Test ping to gateway
    if ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
        test_pass "Gateway is reachable: $gateway"
        return 0
    else
        test_warn "Gateway is not reachable: $gateway (may affect client connectivity)"
        return 0  # Not a failure for PXE server setup
    fi
}

# Test DNS connectivity
test_dns_connectivity() {
    test_info "Testing DNS connectivity..."
    
    local dns_servers="${DHCP_DNS:-8.8.8.8,8.8.4.4}"
    IFS=',' read -ra dns_list <<< "$dns_servers"
    
    local dns_working=false
    
    for dns in "${dns_list[@]}"; do
        dns=$(echo "$dns" | xargs)  # trim whitespace
        if ping -c 1 -W 2 "$dns" >/dev/null 2>&1; then
            test_pass "DNS server is reachable: $dns"
            dns_working=true
        else
            test_warn "DNS server is not reachable: $dns"
        fi
    done
    
    if $dns_working; then
        # Test actual DNS resolution
        if nslookup google.com "${dns_list[0]// /}" >/dev/null 2>&1; then
            test_pass "DNS resolution is working"
        else
            test_warn "DNS resolution may have issues"
        fi
        return 0
    else
        test_warn "No DNS servers are reachable (may affect client functionality)"
        return 0  # Not a critical failure
    fi
}

# Test DHCP port (67) availability
test_dhcp_port() {
    test_info "Testing DHCP port availability..."
    
    local port="67"
    
    # Check if port 67 is available or in use by DHCP server
    if command -v netstat >/dev/null 2>&1; then
        if netstat -ulpn 2>/dev/null | grep -q ":$port "; then
            local process
            process=$(netstat -ulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -n1)
            if echo "$process" | grep -q -E "(dhcp|dhcpd)"; then
                test_pass "DHCP port is in use by DHCP server: $port/UDP"
            else
                test_warn "DHCP port is in use by other process: $port/UDP ($process)"
            fi
        else
            test_pass "DHCP port is available: $port/UDP"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -ulpn | grep -q ":$port "; then
            local process
            process=$(ss -ulpn | grep ":$port " | awk '{print $7}' | head -n1)
            if echo "$process" | grep -q -E "(dhcp|dhcpd)"; then
                test_pass "DHCP port is in use by DHCP server: $port/UDP"
            else
                test_warn "DHCP port is in use by other process: $port/UDP ($process)"
            fi
        else
            test_pass "DHCP port is available: $port/UDP"
        fi
    else
        test_warn "Cannot check DHCP port status (netstat/ss not available)"
    fi
    
    return 0
}

# Test TFTP port availability
test_tftp_port() {
    test_info "Testing TFTP port availability..."
    
    local port="${TFTP_PORT:-69}"
    
    # Check if TFTP port is available or in use
    if command -v netstat >/dev/null 2>&1; then
        if netstat -ulpn 2>/dev/null | grep -q ":$port "; then
            local process
            process=$(netstat -ulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -n1)
            if echo "$process" | grep -q -E "(tftp|tftpd)"; then
                test_pass "TFTP port is in use by TFTP server: $port/UDP"
            else
                test_warn "TFTP port is in use by other process: $port/UDP ($process)"
            fi
        else
            test_pass "TFTP port is available: $port/UDP"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -ulpn | grep -q ":$port "; then
            local process
            process=$(ss -ulpn | grep ":$port " | awk '{print $7}' | head -n1)
            if echo "$process" | grep -q -E "(tftp|tftpd)"; then
                test_pass "TFTP port is in use by TFTP server: $port/UDP"
            else
                test_warn "TFTP port is in use by other process: $port/UDP ($process)"
            fi
        else
            test_pass "TFTP port is available: $port/UDP"
        fi
    else
        test_warn "Cannot check TFTP port status (netstat/ss not available)"
    fi
    
    return 0
}

# Test NFS port availability
test_nfs_port() {
    test_info "Testing NFS port availability..."
    
    local port="${NFS_PORT:-2049}"
    
    # Check if NFS port is available or in use
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlpn 2>/dev/null | grep -q ":$port "; then
            local process
            process=$(netstat -tlpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -n1)
            if echo "$process" | grep -q -E "(nfs|nfsd)"; then
                test_pass "NFS port is in use by NFS server: $port/TCP"
            else
                test_warn "NFS port is in use by other process: $port/TCP ($process)"
            fi
        else
            test_pass "NFS port is available: $port/TCP"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlpn | grep -q ":$port "; then
            local process
            process=$(ss -tlpn | grep ":$port " | awk '{print $7}' | head -n1)
            if echo "$process" | grep -q -E "(nfs|nfsd)"; then
                test_pass "NFS port is in use by NFS server: $port/TCP"
            else
                test_warn "NFS port is in use by other process: $port/TCP ($process)"
            fi
        else
            test_pass "NFS port is available: $port/TCP"
        fi
    else
        test_warn "Cannot check NFS port status (netstat/ss not available)"
    fi
    
    return 0
}

# Test subnet connectivity
test_subnet_connectivity() {
    test_info "Testing subnet connectivity..."
    
    local subnet="${DHCP_SUBNET:-192.168.1.0}"
    local netmask="${DHCP_NETMASK:-255.255.255.0}"
    
    # Calculate network range if ipcalc is available
    if command -v ipcalc >/dev/null 2>&1; then
        local network_info
        if network_info=$(ipcalc -n "$subnet/$netmask" 2>/dev/null); then
            test_pass "Subnet calculation successful: $subnet/$netmask"
            
            # Check if current system is in the subnet
            local current_ips
            current_ips=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
            
            local in_subnet=false
            for ip in $current_ips; do
                if ipcalc -c "$ip" "$subnet/$netmask" >/dev/null 2>&1; then
                    test_pass "System IP is in target subnet: $ip"
                    in_subnet=true
                    break
                fi
            done
            
            if ! $in_subnet; then
                test_warn "System is not currently configured for target subnet"
            fi
        else
            test_fail "Invalid subnet configuration: $subnet/$netmask"
            return 1
        fi
    else
        test_warn "Cannot validate subnet (ipcalc not available)"
    fi
    
    return 0
}

# Test TFTP directory accessibility
test_tftp_directory() {
    test_info "Testing TFTP directory accessibility..."
    
    local tftp_root="${TFTP_ROOT:-/var/lib/tftpboot}"
    
    if [[ -d "$tftp_root" ]]; then
        test_pass "TFTP directory exists: $tftp_root"
        
        if [[ -r "$tftp_root" ]]; then
            test_pass "TFTP directory is readable: $tftp_root"
        else
            test_fail "TFTP directory is not readable: $tftp_root"
            return 1
        fi
        
        if [[ -w "$tftp_root" ]]; then
            test_pass "TFTP directory is writable: $tftp_root"
        else
            test_warn "TFTP directory is not writable: $tftp_root"
        fi
    else
        test_warn "TFTP directory does not exist: $tftp_root (will be created during setup)"
    fi
    
    return 0
}

# Test NFS directory accessibility
test_nfs_directory() {
    test_info "Testing NFS directory accessibility..."
    
    local nfs_root="${NFS_ROOT:-/var/lib/nfs}"
    
    if [[ -d "$nfs_root" ]]; then
        test_pass "NFS directory exists: $nfs_root"
        
        if [[ -r "$nfs_root" ]]; then
            test_pass "NFS directory is readable: $nfs_root"
        else
            test_fail "NFS directory is not readable: $nfs_root"
            return 1
        fi
        
        if [[ -w "$nfs_root" ]]; then
            test_pass "NFS directory is writable: $nfs_root"
        else
            test_warn "NFS directory is not writable: $nfs_root"
        fi
    else
        test_warn "NFS directory does not exist: $nfs_root (will be created during setup)"
    fi
    
    return 0
}

# Main test runner
run_all_tests() {
    echo "PXE Server Network Connectivity Tests"
    echo "===================================="
    
    load_environment
    
    # Run all network tests
    run_test "Network Interface" test_network_interface
    run_test "PXE Server IP" test_pxe_server_ip
    run_test "Gateway Connectivity" test_gateway_connectivity
    run_test "DNS Connectivity" test_dns_connectivity
    run_test "DHCP Port" test_dhcp_port
    run_test "TFTP Port" test_tftp_port
    run_test "NFS Port" test_nfs_port
    run_test "Subnet Connectivity" test_subnet_connectivity
    run_test "TFTP Directory" test_tftp_directory
    run_test "NFS Directory" test_nfs_directory
    
    # Print summary
    echo
    echo "===================================="
    echo "Test Summary:"
    echo "  Total Tests: $TESTS_RUN"
    echo "  Passed:      $TESTS_PASSED"
    echo "  Failed:      $TESTS_FAILED"
    echo "===================================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        test_info "All network tests passed!"
        return 0
    else
        test_info "$TESTS_FAILED network test(s) failed."
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    all                 Run all network tests (default)
    interface           Test network interface
    ip                  Test PXE server IP
    gateway             Test gateway connectivity
    dns                 Test DNS connectivity
    ports               Test all port availability
    dhcp-port           Test DHCP port only
    tftp-port           Test TFTP port only
    nfs-port            Test NFS port only
    subnet              Test subnet connectivity
    directories         Test directory accessibility
    
Examples:
    $0                  # Run all network tests
    $0 ports            # Test only port availability
    $0 dns              # Test only DNS connectivity
    
EOF
}

# Main function
main() {
    local command="${1:-all}"
    
    load_environment
    
    case "$command" in
        all)
            run_all_tests
            ;;
        interface)
            run_test "Network Interface" test_network_interface
            ;;
        ip)
            run_test "PXE Server IP" test_pxe_server_ip
            ;;
        gateway)
            run_test "Gateway Connectivity" test_gateway_connectivity
            ;;
        dns)
            run_test "DNS Connectivity" test_dns_connectivity
            ;;
        ports)
            run_test "DHCP Port" test_dhcp_port
            run_test "TFTP Port" test_tftp_port
            run_test "NFS Port" test_nfs_port
            ;;
        dhcp-port)
            run_test "DHCP Port" test_dhcp_port
            ;;
        tftp-port)
            run_test "TFTP Port" test_tftp_port
            ;;
        nfs-port)
            run_test "NFS Port" test_nfs_port
            ;;
        subnet)
            run_test "Subnet Connectivity" test_subnet_connectivity
            ;;
        directories)
            run_test "TFTP Directory" test_tftp_directory
            run_test "NFS Directory" test_nfs_directory
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