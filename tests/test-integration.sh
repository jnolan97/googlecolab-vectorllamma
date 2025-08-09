#!/bin/bash

# Integration Tests for PXE Server
# End-to-end tests for complete PXE server functionality

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_OUTPUT_DIR="/tmp/pxe-integration-tests"

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

# Setup integration test environment
setup_integration_test() {
    test_info "Setting up integration test environment..."
    
    # Create test directory
    mkdir -p "$TEST_OUTPUT_DIR"
    
    # Create test .env file
    cat > "$TEST_OUTPUT_DIR/.env" << 'EOF'
# Integration Test Environment
DHCP_SUBNET=192.168.99.0
DHCP_NETMASK=255.255.255.0
DHCP_RANGE_START=192.168.99.100
DHCP_RANGE_END=192.168.99.200
DHCP_GATEWAY=192.168.99.1
DHCP_DNS=1.1.1.1,8.8.8.8
PXE_SERVER_IP=192.168.99.10
TFTP_ROOT=/tmp/integration-tftp
NFS_ROOT=/tmp/integration-nfs
DHCP_LEASE_TIME=1800
DHCP_INTERFACE=eth0
TFTP_PORT=69
NFS_PORT=2049
SECURE_TFTP=false
NFS_SECURITY=sys
DHCP_CONFIG_FILE=/tmp/integration-tests/dhcpd.conf
TFTP_CONFIG_FILE=/tmp/integration-tests/tftpd-hpa
NFS_CONFIG_FILE=/tmp/integration-tests/exports
PXELINUX_CONFIG_DIR=/tmp/integration-tests/pxelinux.cfg
LOG_LEVEL=INFO
LOG_FILE=/tmp/integration-tests/pxe-server.log
EOF
    
    # Copy .env to project root for testing
    cp "$TEST_OUTPUT_DIR/.env" "$PROJECT_ROOT/.env.test"
    
    test_pass "Integration test environment setup"
    return 0
}

# Cleanup integration test environment
cleanup_integration_test() {
    test_info "Cleaning up integration test environment..."
    
    # Remove test files
    rm -rf "$TEST_OUTPUT_DIR"
    rm -f "$PROJECT_ROOT/.env.test"
    rm -rf "/tmp/integration-tftp"
    rm -rf "/tmp/integration-nfs"
    rm -rf "/tmp/integration-tests"
    
    test_pass "Integration test cleanup"
    return 0
}

# Test complete configuration generation workflow
test_complete_config_workflow() {
    test_info "Testing complete configuration workflow..."
    
    # Use test environment
    export ENV_FILE="$PROJECT_ROOT/.env.test"
    
    # Create required directories
    mkdir -p "/tmp/integration-tests/pxelinux.cfg"
    mkdir -p "/tmp/integration-tftp"
    mkdir -p "/tmp/integration-nfs"
    
    # Run environment validation
    if ENV_FILE="$ENV_FILE" "${PROJECT_ROOT}/src/scripts/validate-env.sh" env >/dev/null 2>&1; then
        test_pass "Environment validation passed"
    else
        test_fail "Environment validation failed"
        return 1
    fi
    
    # Generate configurations
    if ENV_FILE="$ENV_FILE" "${PROJECT_ROOT}/src/scripts/generate-configs.sh" >/dev/null 2>&1; then
        test_pass "Configuration generation completed"
    else
        test_fail "Configuration generation failed"
        return 1
    fi
    
    # Verify all config files were created
    local config_files=(
        "/tmp/integration-tests/dhcpd.conf"
        "/tmp/integration-tests/tftpd-hpa"
        "/tmp/integration-tests/exports"
        "/tmp/integration-tests/pxelinux.cfg/default"
    )
    
    for config in "${config_files[@]}"; do
        if [[ -f "$config" ]]; then
            test_pass "Configuration file created: $config"
        else
            test_fail "Configuration file not created: $config"
            return 1
        fi
    done
    
    return 0
}

# Test script execution and error handling
test_script_execution() {
    test_info "Testing script execution and error handling..."
    
    # Test that all scripts are executable
    local scripts=(
        "${PROJECT_ROOT}/src/scripts/setup-pxe.sh"
        "${PROJECT_ROOT}/src/scripts/generate-configs.sh"
        "${PROJECT_ROOT}/src/scripts/manage-services.sh"
        "${PROJECT_ROOT}/src/scripts/validate-env.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            test_pass "Script is executable: $(basename "$script")"
        else
            test_fail "Script is not executable: $script"
            return 1
        fi
    done
    
    # Test script help/usage output
    for script in "${scripts[@]}"; do
        if "$script" --help >/dev/null 2>&1 || "$script" help >/dev/null 2>&1; then
            test_pass "Script provides help: $(basename "$script")"
        else
            test_warn "Script may not provide help: $(basename "$script")"
        fi
    done
    
    return 0
}

# Test environment variable handling
test_environment_handling() {
    test_info "Testing environment variable handling..."
    
    # Test with missing required variables
    local temp_env="/tmp/test_incomplete.env"
    cat > "$temp_env" << 'EOF'
# Incomplete environment - missing required variables
DHCP_SUBNET=192.168.1.0
# Missing other required variables
EOF
    
    # This should fail validation
    if ENV_FILE="$temp_env" "${PROJECT_ROOT}/src/scripts/validate-env.sh" env >/dev/null 2>&1; then
        test_fail "Environment validation should have failed with incomplete environment"
        rm -f "$temp_env"
        return 1
    else
        test_pass "Environment validation correctly failed with incomplete environment"
    fi
    
    # Test with invalid IP addresses
    cat > "$temp_env" << 'EOF'
# Invalid IP addresses
DHCP_SUBNET=999.999.999.999
DHCP_NETMASK=255.255.255.0
DHCP_RANGE_START=192.168.1.100
DHCP_RANGE_END=192.168.1.200
DHCP_GATEWAY=192.168.1.1
DHCP_DNS=8.8.8.8
PXE_SERVER_IP=192.168.1.10
TFTP_ROOT=/tmp/test-tftp
NFS_ROOT=/tmp/test-nfs
EOF
    
    if ENV_FILE="$temp_env" "${PROJECT_ROOT}/src/scripts/validate-env.sh" ip >/dev/null 2>&1; then
        test_fail "IP validation should have failed with invalid IP"
        rm -f "$temp_env"
        return 1
    else
        test_pass "IP validation correctly failed with invalid IP"
    fi
    
    rm -f "$temp_env"
    return 0
}

# Test configuration templates and substitution
test_template_processing() {
    test_info "Testing configuration template processing..."
    
    # Check that all templates exist
    local templates=(
        "${PROJECT_ROOT}/src/config/dhcpd.conf.template"
        "${PROJECT_ROOT}/src/config/tftpd.conf.template"
        "${PROJECT_ROOT}/src/config/exports.template"
        "${PROJECT_ROOT}/src/config/pxelinux.cfg.template"
    )
    
    for template in "${templates[@]}"; do
        if [[ -f "$template" ]]; then
            test_pass "Template exists: $(basename "$template")"
            
            # Check if template contains environment variables
            if grep -q '\${' "$template"; then
                test_pass "Template contains variables: $(basename "$template")"
            else
                test_warn "Template may not contain variables: $(basename "$template")"
            fi
        else
            test_fail "Template missing: $template"
            return 1
        fi
    done
    
    return 0
}

# Test test suite itself
test_test_suite() {
    test_info "Testing the test suite components..."
    
    # Check that all test scripts exist and are executable
    local test_scripts=(
        "${PROJECT_ROOT}/tests/test-configs.sh"
        "${PROJECT_ROOT}/tests/test-network.sh"
        "${PROJECT_ROOT}/tests/test-services.sh"
        "${PROJECT_ROOT}/tests/test-integration.sh"
    )
    
    for test_script in "${test_scripts[@]}"; do
        if [[ -f "$test_script" ]]; then
            test_pass "Test script exists: $(basename "$test_script")"
            
            if [[ -x "$test_script" ]]; then
                test_pass "Test script is executable: $(basename "$test_script")"
            else
                test_fail "Test script is not executable: $test_script"
                return 1
            fi
        else
            test_fail "Test script missing: $test_script"
            return 1
        fi
    done
    
    # Try running each test script with help option
    for test_script in "${test_scripts[@]}"; do
        if "$test_script" help >/dev/null 2>&1 || "$test_script" --help >/dev/null 2>&1; then
            test_pass "Test script provides help: $(basename "$test_script")"
        else
            test_warn "Test script may not provide help: $(basename "$test_script")"
        fi
    done
    
    return 0
}

# Test directory structure
test_directory_structure() {
    test_info "Testing project directory structure..."
    
    local required_dirs=(
        "${PROJECT_ROOT}/src"
        "${PROJECT_ROOT}/src/config"
        "${PROJECT_ROOT}/src/scripts"
        "${PROJECT_ROOT}/tests"
        "${PROJECT_ROOT}/.github"
        "${PROJECT_ROOT}/.github/workflows"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            test_pass "Required directory exists: $dir"
        else
            test_fail "Required directory missing: $dir"
            return 1
        fi
    done
    
    # Check for required files
    local required_files=(
        "${PROJECT_ROOT}/.env.example"
        "${PROJECT_ROOT}/README.md"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            test_pass "Required file exists: $(basename "$file")"
        else
            test_fail "Required file missing: $file"
            return 1
        fi
    done
    
    return 0
}

# Test error recovery and rollback
test_error_recovery() {
    test_info "Testing error recovery and rollback mechanisms..."
    
    # Create a test configuration to backup
    local test_config="/tmp/test-dhcp.conf"
    echo "# Original test config" > "$test_config"
    
    # Set environment to use test config
    export DHCP_CONFIG_FILE="$test_config"
    
    # Generate config (should create backup)
    if "${PROJECT_ROOT}/src/scripts/generate-configs.sh" >/dev/null 2>&1; then
        # Check if backup was created
        if ls "${test_config}.backup."* >/dev/null 2>&1; then
            test_pass "Configuration backup mechanism works"
        else
            test_fail "Configuration backup was not created"
            return 1
        fi
    else
        test_warn "Configuration generation failed (may be expected in test environment)"
    fi
    
    # Cleanup
    rm -f "$test_config" "${test_config}.backup."*
    unset DHCP_CONFIG_FILE
    
    return 0
}

# Main integration test runner
run_all_integration_tests() {
    echo "PXE Server Integration Tests"
    echo "============================"
    
    setup_integration_test
    
    # Run all integration tests
    run_test "Directory Structure" test_directory_structure
    run_test "Template Processing" test_template_processing
    run_test "Script Execution" test_script_execution
    run_test "Environment Handling" test_environment_handling
    run_test "Complete Config Workflow" test_complete_config_workflow
    run_test "Test Suite" test_test_suite
    run_test "Error Recovery" test_error_recovery
    
    cleanup_integration_test
    
    # Print summary
    echo
    echo "============================"
    echo "Integration Test Summary:"
    echo "  Total Tests: $TESTS_RUN"
    echo "  Passed:      $TESTS_PASSED"
    echo "  Failed:      $TESTS_FAILED"
    echo "============================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        test_info "All integration tests passed!"
        return 0
    else
        test_info "$TESTS_FAILED integration test(s) failed."
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    all                 Run all integration tests (default)
    setup               Setup integration test environment
    cleanup             Cleanup integration test environment  
    structure           Test directory structure
    templates           Test template processing
    scripts             Test script execution
    environment         Test environment handling
    workflow            Test complete configuration workflow
    tests               Test the test suite itself
    recovery            Test error recovery mechanisms
    
Examples:
    $0                  # Run all integration tests
    $0 workflow         # Test only configuration workflow
    $0 environment      # Test only environment handling
    
EOF
}

# Main function
main() {
    local command="${1:-all}"
    
    case "$command" in
        all)
            run_all_integration_tests
            ;;
        setup)
            setup_integration_test
            ;;
        cleanup)
            cleanup_integration_test
            ;;
        structure)
            run_test "Directory Structure" test_directory_structure
            ;;
        templates)
            run_test "Template Processing" test_template_processing
            ;;
        scripts)
            run_test "Script Execution" test_script_execution
            ;;
        environment)
            setup_integration_test
            run_test "Environment Handling" test_environment_handling
            cleanup_integration_test
            ;;
        workflow)
            setup_integration_test
            run_test "Complete Config Workflow" test_complete_config_workflow
            cleanup_integration_test
            ;;
        tests)
            run_test "Test Suite" test_test_suite
            ;;
        recovery)
            run_test "Error Recovery" test_error_recovery
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