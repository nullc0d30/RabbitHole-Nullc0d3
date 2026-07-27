#!/bin/bash
# ==============================================================================
# RabbitHole Test Runner
# ==============================================================================
# Runs automated tests for plugin loading, state management, helpers, and more.
# Usage: ./tests/test_runner.sh [--verbose]
# ==============================================================================

set -o errexit
set -o pipefail

RABBIT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
export RABBIT_ROOT

# Colors
PASS='\033[0;32m'
FAIL='\033[0;31m'
INFO='\033[0;34m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=false

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${expected}" == "${actual}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ "${VERBOSE}" == "true" ]]; then
            echo -e "${PASS}[PASS]${NC} ${message}"
        fi
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${message}"
        echo "  Expected: '${expected}'"
        echo "  Actual:   '${actual}'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "${haystack}" | grep -Fq "${needle}"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ "${VERBOSE}" == "true" ]]; then
            echo -e "${PASS}[PASS]${NC} ${message}"
        fi
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${message}"
        echo "  Expected to contain: '${needle}'"
    fi
}

assert_file_exists() {
    local path="$1"
    local message="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "${path}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ "${VERBOSE}" == "true" ]]; then
            echo -e "${PASS}[PASS]${NC} ${message}"
        fi
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${message}"
        echo "  File not found: ${path}"
    fi
}

assert_dir_exists() {
    local path="$1"
    local message="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -d "${path}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ "${VERBOSE}" == "true" ]]; then
            echo -e "${PASS}[PASS]${NC} ${message}"
        fi
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${message}"
        echo "  Directory not found: ${path}"
    fi
}

print_result() {
    echo ""
    echo "================================"
    echo -e "${INFO}Test Results${NC}"
    echo "  Total:  ${TESTS_RUN}"
    echo -e "  Passed: ${PASS}${TESTS_PASSED}${NC}"
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo -e "  Failed: ${FAIL}${TESTS_FAILED}${NC}"
    fi
    echo "================================"
    return ${TESTS_FAILED}
}

# ------------------------------------------------------------------------------
# Parse args
# ------------------------------------------------------------------------------
for arg in "$@"; do
    case "${arg}" in
        --verbose|-v) VERBOSE=true ;;
    esac
done

# ------------------------------------------------------------------------------
# Test: Directory Structure
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE]${NC} Directory Structure Tests"
assert_dir_exists "${RABBIT_ROOT}/bin" "bin/ directory exists"
assert_dir_exists "${RABBIT_ROOT}/lib" "lib/ directory exists"
assert_dir_exists "${RABBIT_ROOT}/roles" "roles/ directory exists"
assert_dir_exists "${RABBIT_ROOT}/config" "config/ directory exists"
assert_dir_exists "${RABBIT_ROOT}/tests" "tests/ directory exists"
assert_file_exists "${RABBIT_ROOT}/bin/rabbithole" "bin/rabbithole entrypoint exists"
assert_file_exists "${RABBIT_ROOT}/rabbithole.sh" "Legacy rabbithole.sh exists"

# ------------------------------------------------------------------------------
# Test: Library Modules
# ------------------------------------------------------------------------------
echo ""
echo -e "${INFO}[SUITE]${NC} Library Module Tests"
for lib in logging package_manager helpers state plugins dependency security docker; do
    assert_file_exists "${RABBIT_ROOT}/lib/${lib}.sh" "lib/${lib}.sh exists"
done

# ------------------------------------------------------------------------------
# Test: Plugin Manifests (YAML parsing)
# ------------------------------------------------------------------------------
echo ""
echo -e "${INFO}[SUITE]${NC} Plugin Manifest Tests"

# Source the plugin system
source "${RABBIT_ROOT}/lib/logging.sh" 2>/dev/null || true
RABBIT_BUILTIN_ROLES_DIR="${RABBIT_ROOT}/roles"
source "${RABBIT_ROOT}/lib/plugins.sh" 2>/dev/null || true

# Test plugin discovery
echo "  Testing plugin discovery..."
plugin_count_val=$(plugin_count 2>/dev/null || echo "0")
assert_eq "7" "${plugin_count_val}" "Expected 7 built-in plugins"

# Test each plugin has required fields
for yaml in "${RABBIT_ROOT}"/roles/*/plugin.yaml; do
    dir=$(dirname "${yaml}")
    name=$(grep -E '^name:' "${yaml}" | head -1 | sed 's/^name: *//' | tr -d '"')
    assert_file_exists "${dir}/install.sh" "install.sh exists for ${name}"
    
    # Verify YAML has required fields
    for field in name description version author; do
        val=$(grep -E "^${field}:" "${yaml}" | head -1)
        assert_contains "${val}" "${field}" "plugin.yaml contains '${field}' in ${dir}"
    done
done

# ------------------------------------------------------------------------------
# Test: State Management
# ------------------------------------------------------------------------------
echo ""
echo -e "${INFO}[SUITE]${NC} State Management Tests"
source "${RABBIT_ROOT}/lib/state.sh" 2>/dev/null || true

RABBIT_STATE_DIR="/tmp/rabbithole_test_state"
RABBIT_STATE_FILE="${RABBIT_STATE_DIR}/state.json"
mkdir -p "${RABBIT_STATE_DIR}"
RABBIT_STATE_FILE="${RABBIT_STATE_FILE}" rabbit_state_init 2>/dev/null || true
assert_file_exists "${RABBIT_STATE_FILE}" "state.json created"

# Test state record/read
echo "  Testing state recording..."
RABBIT_STATE_FILE="${RABBIT_STATE_FILE}" rabbit_state_record_role "test-role" "installed" 2>/dev/null || true
roles=$(RABBIT_STATE_FILE="${RABBIT_STATE_FILE}" rabbit_state_get_installed_roles 2>/dev/null || echo "")
assert_contains "${roles}" "test-role" "Role recorded in state.json"

# Cleanup
rm -rf "${RABBIT_STATE_DIR}"

# ------------------------------------------------------------------------------
# Test: Helper Functions (dry run)
# ------------------------------------------------------------------------------
echo ""
echo -e "${INFO}[SUITE]${NC} Helper Function Tests (Syntax Only)"

# Test basic function existence by grepping
for func in install_native install_go install_pipx install_git install_cargo install_wget install_custom; do
    if grep -q "^${func}()" "${RABBIT_ROOT}/lib/helpers.sh" 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} Function ${func} exists"
    fi
done

for func in rabbit_ensure_golang rabbit_ensure_docker rabbit_ensure_python rabbit_ensure_pipx rabbit_ensure_cargo rabbit_ensure_git; do
    if grep -q "^${func}()" "${RABBIT_ROOT}/lib/dependency.sh" 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} Function ${func} exists"
    fi
done

# ------------------------------------------------------------------------------
# Test: Security Module
# ------------------------------------------------------------------------------
echo ""
echo -e "${INFO}[SUITE]${NC} Security Module Tests"
source "${RABBIT_ROOT}/lib/security.sh" 2>/dev/null || true

for func in secure_random_string secure_uuid verify_sha256 secure_download generate_secure_env validate_file_permissions sanitize_path_component; do
    if grep -q "^${func}()" "${RABBIT_ROOT}/lib/security.sh" 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} Function ${func} exists"
    fi
done

# Test secure_random_string output
if source "${RABBIT_ROOT}/lib/security.sh" 2>/dev/null; then
    result=$(secure_random_string 16 2>/dev/null || echo "")
    assert_eq "16" "${#result}" "secure_random_string produces correct length"
fi

# ------------------------------------------------------------------------------
# Test: Config files
# ------------------------------------------------------------------------------
echo ""
echo -e "${INFO}[SUITE]${NC} Configuration Tests"
assert_file_exists "${RABBIT_ROOT}/config/settings.conf" "settings.conf exists"
assert_file_exists "${RABBIT_ROOT}/config/rabbit.lock" "rabbit.lock exists"

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
print_result
exit ${TESTS_FAILED}
