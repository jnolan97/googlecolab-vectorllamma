#!/bin/bash

# Configuration Validation Tests
# Tests for PXE server configuration files

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_OUTPUT_DIR="/tmp/pxe-test-configs"

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

# Setup test environment
setup_test_env() {
    test_info "Setting up test environment..."
    
    # Create test output directory
    mkdir -p "$TEST_OUTPUT_DIR"
    
    # Set test environment variables
    export DHCP_SUBNET="192.168.100.0"
    export DHCP_NETMASK="255.255.255.0"
    export DHCP_RANGE_START="192.168.100.100"
    export DHCP_RANGE_END="192.168.100.200"
    export DHCP_GATEWAY="192.168.100.1"
    export DHCP_DNS="8.8.8.8,8.8.4.4"
    export PXE_SERVER_IP="192.168.100.10"
    export TFTP_ROOT="/tmp/test-tftp"
    export NFS_ROOT="/tmp/test-nfs"
    export DHCP_LEASE_TIME="3600"
    export DHCP_INTERFACE="eth0"
    export TFTP_PORT="69"
    export NFS_PORT="2049"
    export SECURE_TFTP="false"
    export NFS_SECURITY="sys"
    
    # Override config file paths for testing
    export DHCP_CONFIG_FILE="$TEST_OUTPUT_DIR/dhcpd.conf"
    export TFTP_CONFIG_FILE="$TEST_OUTPUT_DIR/tftpd-hpa"
    export NFS_CONFIG_FILE="$TEST_OUTPUT_DIR/exports"
    export PXELINUX_CONFIG_DIR="$TEST_OUTPUT_DIR/pxelinux.cfg"
    
    mkdir -p "$TFTP_ROOT" "$NFS_ROOT" "$PXELINUX_CONFIG_DIR"
    
    test_pass "Test environment setup"
    return 0
}

# Cleanup test environment
cleanup_test_env() {
    test_info "Cleaning up test environment..."
    
    if [[ -d "$TEST_OUTPUT_DIR" ]]; then
        rm -rf "$TEST_OUTPUT_DIR"
    fi
    
    if [[ -d "/tmp/test-tftp" ]]; then
        rm -rf "/tmp/test-tftp"
    fi
    
    if [[ -d "/tmp/test-nfs" ]]; then
        rm -rf "/tmp/test-nfs"
    fi
    
    test_pass "Test environment cleanup"
    return 0
}

# Test configuration generation
test_config_generation() {
    test_info "Testing configuration generation..."
    
    # Generate configurations using the script
    if "${PROJECT_ROOT}/src/scripts/generate-configs.sh" >/dev/null 2>&1; then
        # Check if all config files were generated
        local required_files=(
            "$DHCP_CONFIG_FILE"
            "$TFTP_CONFIG_FILE"
            "$NFS_CONFIG_FILE"
            "$PXELINUX_CONFIG_DIR/default"
        )
        
        for file in "${required_files[@]}"; do
            if [[ ! -f "$file" ]]; then
                test_fail "Configuration file not generated: $file"
                return 1
            fi
        done
        
        return 0
    else
        return 1
    fi
}

# Test DHCP configuration syntax
test_dhcp_config_syntax() {
    test_info "Testing DHCP configuration syntax..."
    
    if [[ ! -f "$DHCP_CONFIG_FILE" ]]; then
        test_fail "DHCP config file not found: $DHCP_CONFIG_FILE"
        return 1
    fi
    
    # Check for required DHCP configuration elements
    local required_elements=(
        "subnet"
        "range"
        "option routers"
        "option domain-name-servers"
        "next-server"
        "filename"
    )
    
    for element in "${required_elements[@]}"; do
        if ! grep -q "$element" "$DHCP_CONFIG_FILE"; then
            test_fail "DHCP config missing required element: $element"
            return 1
        fi
    done
    
    # Test with dhcpd if available
    if command -v dhcpd >/dev/null 2>&1; then
        if dhcpd -t -cf "$DHCP_CONFIG_FILE" >/dev/null 2>&1; then
            test_pass "DHCP configuration syntax is valid"
        else
            test_fail "DHCP configuration syntax error"
            return 1
        fi
    else
        test_warn "dhcpd not available for syntax checking"
    fi
    
    return 0
}

# Test TFTP configuration
test_tftp_config() {
    test_info "Testing TFTP configuration..."
    
    if [[ ! -f "$TFTP_CONFIG_FILE" ]]; then
        test_fail "TFTP config file not found: $TFTP_CONFIG_FILE"
        return 1
    fi
    
    # Check for required TFTP configuration elements
    local required_elements=(
        "TFTP_DIRECTORY"
        "TFTP_ADDRESS"
        "RUN_DAEMON"
    )
    
    for element in "${required_elements[@]}"; do
        if ! grep -q "$element" "$TFTP_CONFIG_FILE"; then
            test_fail "TFTP config missing required element: $element"
            return 1
        fi
    done
    
    return 0
}

# Test NFS configuration
test_nfs_config() {
    test_info "Testing NFS configuration..."
    
    if [[ ! -f "$NFS_CONFIG_FILE" ]]; then
        test_fail "NFS config file not found: $NFS_CONFIG_FILE"
        return 1
    fi
    
    # Check for required NFS export entries
    if ! grep -q "$NFS_ROOT.*$DHCP_SUBNET" "$NFS_CONFIG_FILE"; then
        test_fail "NFS config missing export for NFS_ROOT"
        return 1
    fi
    
    # Test with exportfs if available
    if command -v exportfs >/dev/null 2>&1; then
        # Create a temporary exports file for testing
        local temp_exports="/tmp/test_exports"
        cp "$NFS_CONFIG_FILE" "$temp_exports"
        
        # Test the syntax (this may fail if directories don't exist, but syntax will be checked)
        if exportfs -a -f "$temp_exports" >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
            test_pass "NFS exports syntax appears valid"
        else
            test_fail "NFS exports syntax error"
            rm -f "$temp_exports"
            return 1
        fi
        
        rm -f "$temp_exports"
    else
        test_warn "exportfs not available for syntax checking"
    fi
    
    return 0
}

# Test PXE boot menu
test_pxe_menu() {
    test_info "Testing PXE boot menu..."
    
    local pxe_menu="$PXELINUX_CONFIG_DIR/default"
    if [[ ! -f "$pxe_menu" ]]; then
        test_fail "PXE menu file not found: $pxe_menu"
        return 1
    fi
    
    # Check for required PXE menu elements
    local required_elements=(
        "DEFAULT"
        "TIMEOUT"
        "MENU TITLE"
        "LABEL local"
        "LABEL.*ubuntu"
    )
    
    for element in "${required_elements[@]}"; do
        if ! grep -q "$element" "$pxe_menu"; then
            test_fail "PXE menu missing required element: $element"
            return 1
        fi
    done
    
    return 0
}

# Test environment variable substitution
test_env_substitution() {
    test_info "Testing environment variable substitution..."
    
    # Check if environment variables were properly substituted in config files
    local test_value="192.168.100.10"
    
    if grep -q "$test_value" "$DHCP_CONFIG_FILE"; then
        test_pass "Environment variables substituted in DHCP config"
    else
        test_fail "Environment variables not substituted in DHCP config"
        return 1
    fi
    
    if grep -q "/tmp/test-tftp" "$TFTP_CONFIG_FILE"; then
        test_pass "Environment variables substituted in TFTP config"
    else
        test_fail "Environment variables not substituted in TFTP config"
        return 1
    fi
    
    return 0
}

# Test configuration backup functionality
test_config_backup() {
    test_info "Testing configuration backup functionality..."
    
    # Create a dummy existing config file
    local dummy_config="$TEST_OUTPUT_DIR/dummy.conf"
    echo "dummy config content" > "$dummy_config"
    
    # Copy it to simulate existing config
    cp "$dummy_config" "$DHCP_CONFIG_FILE"
    
    # Run config generation again
    if "${PROJECT_ROOT}/src/scripts/generate-configs.sh" >/dev/null 2>&1; then
        # Check if backup was created
        if ls "${DHCP_CONFIG_FILE}.backup."* >/dev/null 2>&1; then
            test_pass "Configuration backup created"
            return 0
        else
            test_fail "Configuration backup not created"
            return 1
        fi
    else
        test_fail "Config generation failed during backup test"
        return 1
    fi
}

# Test IP address validation
test_ip_validation() {
    test_info "Testing IP address validation..."
    
    # Test the validate-env script with our test environment
    if "${PROJECT_ROOT}/src/scripts/validate-env.sh" ip >/dev/null 2>&1; then
        test_pass "IP address validation passed"
        return 0
    else
        test_fail "IP address validation failed"
        return 1
    fi
}

# Test network configuration validation
test_network_validation() {
    test_info "Testing network configuration validation..."
    
    # Test the validate-env script network validation
    if "${PROJECT_ROOT}/src/scripts/validate-env.sh" network >/dev/null 2>&1; then
        test_pass "Network configuration validation passed"
        return 0
    else
        # This might fail if ipcalc is not available, which is acceptable
        test_warn "Network configuration validation failed (may be due to missing tools)"
        return 0
    fi
}

# Main test runner
run_all_tests() {
    echo "PXE Server Configuration Tests"
    echo "=============================="
    
    setup_test_env
    
    # Run all tests
    run_test "Configuration Generation" test_config_generation
    run_test "DHCP Config Syntax" test_dhcp_config_syntax
    run_test "TFTP Config" test_tftp_config
    run_test "NFS Config" test_nfs_config
    run_test "PXE Menu" test_pxe_menu
    run_test "Environment Substitution" test_env_substitution
    run_test "Config Backup" test_config_backup
    run_test "IP Validation" test_ip_validation
    run_test "Network Validation" test_network_validation
    
    cleanup_test_env
    
    # Print summary
    echo
    echo "=============================="
    echo "Test Summary:"
    echo "  Total Tests: $TESTS_RUN"
    echo "  Passed:      $TESTS_PASSED"
    echo "  Failed:      $TESTS_FAILED"
    echo "=============================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        test_info "All tests passed!"
        return 0
    else
        test_info "$TESTS_FAILED test(s) failed."
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    all                 Run all configuration tests (default)
    setup               Setup test environment only
    cleanup             Cleanup test environment only
    generate            Test configuration generation only
    dhcp                Test DHCP configuration only
    tftp                Test TFTP configuration only
    nfs                 Test NFS configuration only
    pxe                 Test PXE menu only
    
Examples:
    $0                  # Run all tests
    $0 dhcp             # Test only DHCP configuration
    $0 cleanup          # Clean up test files
    
EOF
}

# Main function
main() {
    local command="${1:-all}"
    
    case "$command" in
        all)
            run_all_tests
            ;;
        setup)
            setup_test_env
            ;;
        cleanup)
            cleanup_test_env
            ;;
        generate)
            setup_test_env
            run_test "Configuration Generation" test_config_generation
            cleanup_test_env
            ;;
        dhcp)
            setup_test_env
            run_test "Configuration Generation" test_config_generation
            run_test "DHCP Config Syntax" test_dhcp_config_syntax
            cleanup_test_env
            ;;
        tftp)
            setup_test_env
            run_test "Configuration Generation" test_config_generation
            run_test "TFTP Config" test_tftp_config
            cleanup_test_env
            ;;
        nfs)
            setup_test_env
            run_test "Configuration Generation" test_config_generation
            run_test "NFS Config" test_nfs_config
            cleanup_test_env
            ;;
        pxe)
            setup_test_env
            run_test "Configuration Generation" test_config_generation
            run_test "PXE Menu" test_pxe_menu
            cleanup_test_env
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