#!/bin/bash
# ==============================================================================
# RabbitHole - Comprehensive Test Suite
# ==============================================================================
# Exercises the full framework to catch real issues:
#   1. Shell syntax validation (bash -n) on every script
#   2. Library load integrity (no side effects when lib/*.sh are sourced)
#   3. Plugin manifest validation (parse, required fields, install.sh present)
#   4. State management round-trip (init/record/get/remove/snapshot/restore)
#   5. Security module behavior (random, uuid, sha256, env generation)
#   6. Install helpers in dry-run mode (no-op + safe)
#   7. CLI surface smoke tests (version/help/status/verify/doctor/cache/snapshot)
#   8. Install-source validator (network reachable, informational)
#
# Usage: bash tests/full_test.sh [-v]
# Exit code: number of failed assertions (0 = all pass)
# ==============================================================================

set -o pipefail

RABBIT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
export RABBIT_ROOT

# Isolated runtime directories so the test never touches the real system state.
export RABBIT_STATE_DIR="$(mktemp -d /tmp/rabbithole_fulltest.XXXXXX)"
export RABBIT_LOG_FILE="${RABBIT_STATE_DIR}/rabbithole.log"
export RABBIT_QUIET="false"
export RABBIT_STATE_FILE="${RABBIT_STATE_DIR}/state.json"

PASS='\033[0;32m'
FAIL='\033[0;31m'
INFO='\033[0;34m'
WARN='\033[0;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=false

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${expected}" == "${actual}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${msg}"
        echo "    expected: '${expected}'"
        echo "    actual:   '${actual}'"
    fi
}

assert_true() {
    local cond="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "${cond}"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${msg}"
    fi
}

assert_output_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "${haystack}" | grep -Fq "${needle}"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${msg}"
        echo "    expected to contain: '${needle}'"
    fi
}

assert_output_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "${haystack}" | grep -Fq "${needle}"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${msg}"
        echo "    expected NOT to contain: '${needle}'"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} ${msg}"
    fi
}

assert_file_exists() {
    local p="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "${p}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${msg} (missing: ${p})"
    fi
}

assert_dir_exists() {
    local p="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -d "${p}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        [[ "${VERBOSE}" == "true" ]] && echo -e "${PASS}[PASS]${NC} ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${FAIL}[FAIL]${NC} ${msg} (missing dir: ${p})"
    fi
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
# SUITE 1: Shell syntax validation
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 1]${NC} Shell syntax validation (bash -n)"
syntax_fail=0
while IFS= read -r f; do
    if ! bash -n "${f}" 2>/tmp/syntax_err; then
        syntax_fail=$((syntax_fail + 1))
        echo -e "${FAIL}[FAIL]${NC} syntax error in ${f}"
        cat /tmp/syntax_err
    fi
done < <(find "${RABBIT_ROOT}" -name '*.sh' -not -path '*/.git/*')
if [[ ${syntax_fail} -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))
assert_true "[[ ${syntax_fail} -eq 0 ]]" "All shell scripts parse without syntax errors"

# ------------------------------------------------------------------------------
# SUITE 2: Library load integrity
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 2]${NC} Library module load integrity"
# Snapshot lib dir state (command substitution avoids unreliable /tmp writes).
pre_cwd="$(pwd)"
before_md5="$(cd "${RABBIT_ROOT}"; find lib -name '*.sh' | sort | xargs md5sum 2>/dev/null)"

# Source every lib module exactly like bin/rabbithole's _source_lib does.
load_out="$(cd "${RABBIT_ROOT}"; for m in lib/*.sh; do source "${m}"; done 2>&1)"
load_rc=$?
post_cwd="$(pwd)"
after_md5="$(cd "${RABBIT_ROOT}"; find lib -name '*.sh' | sort | xargs md5sum 2>/dev/null)"

assert_eq "0" "${load_rc}" "Library modules source cleanly (exit 0)"
assert_eq "${pre_cwd}" "${post_cwd}" "Sourcing lib modules must not change working directory"
assert_eq "${before_md5}" "${after_md5}" "Sourcing lib modules must not modify lib files"
assert_eq "" "${load_out}" "Sourcing lib modules produces no unexpected output"

# A stray non-module (like the old fix.sh) would print/execute on source.
assert_output_not_contains "${load_out}" "Fixing" "lib/ contains only passive modules (no auto-executing scripts)"

# ------------------------------------------------------------------------------
# SUITE 3: Plugin manifest validation
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 3]${NC} Plugin manifest validation"
source "${RABBIT_ROOT}/lib/logging.sh" 2>/dev/null || true
source "${RABBIT_ROOT}/lib/plugins.sh" 2>/dev/null || true

count="$(plugin_count 2>/dev/null || echo 0)"
assert_eq "7" "${count}" "Exactly 7 roles discovered"

# Every yaml: required fields + install.sh + parseable lists
bad_field=0
missing_install=0
for yaml in "${RABBIT_ROOT}"/roles/*/plugin.yaml; do
    dir="$(dirname "${yaml}")"
    name="$(plugin_yaml_value "${yaml}" "name")"
    [[ -z "${name}" ]] && bad_field=$((bad_field + 1))
    for field in name description version author; do
        val="$(plugin_yaml_value "${yaml}" "${field}")"
        [[ -z "${val}" ]] && bad_field=$((bad_field + 1))
    done
    [[ ! -f "${dir}/install.sh" ]] && missing_install=$((missing_install + 1))

    # Every declared list section returns at least its entries (sanity: not empty parse)
    for section in native go pipx git cargo wget custom; do
        # sections may legitimately be empty; just ensure the function does not error
        plugin_yaml_list "${yaml}" "${section}" >/dev/null 2>&1 || bad_field=$((bad_field + 1))
    done
done
assert_eq "0" "${bad_field}" "All plugin.yaml files have required fields and parse"
assert_eq "0" "${missing_install}" "Every role ships an install.sh"

# ------------------------------------------------------------------------------
# SUITE 4: State management round-trip
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 4]${NC} State management round-trip"
source "${RABBIT_ROOT}/lib/state.sh" 2>/dev/null || true
rabbit_state_init 2>/dev/null
assert_file_exists "${RABBIT_STATE_FILE}" "state.json initialized"

rabbit_state_record_role "TestRole" "installed" 2>/dev/null
assert_true "rabbit_state_role_is_installed 'TestRole' 2>/dev/null" "Role recorded and detected as installed"

rabbit_state_record_tool "go" "amass" "github.com/..." "t1" "t2" "0" 2>/dev/null
assert_true "rabbit_state_tool_is_installed 'amass' 2>/dev/null" "Tool recorded and detected as installed"

tools="$(rabbit_state_get_installed_tools 2>/dev/null)"
assert_output_contains "${tools}" "amass" "Tool listed in get_installed_tools"

rabbit_state_remove_tool "amass" 2>/dev/null
assert_true "! rabbit_state_tool_is_installed 'amass' 2>/dev/null" "Tool removed from state"

rabbit_state_remove_role "TestRole" 2>/dev/null
assert_true "! rabbit_state_role_is_installed 'TestRole' 2>/dev/null" "Role removed from state"

# snapshot / restore
snap="${RABBIT_STATE_DIR}/snap.json"
rabbit_state_record_role "SnapRole" "installed" 2>/dev/null
rabbit_state_snapshot "${snap}" 2>/dev/null
assert_file_exists "${snap}" "Snapshot file produced"
rabbit_state_remove_role "SnapRole" 2>/dev/null
assert_true "! rabbit_state_role_is_installed 'SnapRole' 2>/dev/null" "Role gone before restore"
rabbit_state_restore "${snap}" 2>/dev/null
assert_true "rabbit_state_role_is_installed 'SnapRole' 2>/dev/null" "Role restored from snapshot"

# ------------------------------------------------------------------------------
# SUITE 5: Security module
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 5]${NC} Security module"
source "${RABBIT_ROOT}/lib/security.sh" 2>/dev/null || true

s="$(secure_random_string 16 2>/dev/null)"
assert_eq "16" "${#s}" "secure_random_string respects length"
assert_true "[[ \"${s}\" =~ ^[a-zA-Z0-9]+$ ]]" "secure_random_string is alphanumeric"

uuid="$(secure_uuid 2>/dev/null)"
assert_true "[[ \"${uuid}\" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]" "secure_uuid v4 format"

# sha256 verify
# NOTE: verify_sha256 calls log_error -> exit 1 on mismatch. Run inside a command
# substitution (subshell) so the fatal exit cannot abort the test harness.
tf="${RABBIT_STATE_DIR}/sha_test.bin"
echo "rabbithole" > "${tf}"
good="$(sha256sum "${tf}" | cut -d' ' -f1)"
if ( verify_sha256 "${tf}" "${good}" ) 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${FAIL}[FAIL]${NC} verify_sha256 passes on matching hash"
fi
TESTS_RUN=$((TESTS_RUN + 1))
bad_out="$(verify_sha256 "${tf}" "deadbeef" 2>&1)"
assert_output_contains "${bad_out}" "SHA256 mismatch" "verify_sha256 reports mismatch on bad hash"

# generate_secure_env writes a 600 file
envdir="${RABBIT_STATE_DIR}/envtest"
generate_secure_env "${envdir}" 2>/dev/null
assert_file_exists "${envdir}/.env" "generate_secure_env produced .env"
perms="$(stat -c '%a' "${envdir}/.env" 2>/dev/null)"
assert_eq "600" "${perms}" ".env has restrictive 600 permissions"

# sanitize
san="$(sanitize_path_component 'a/../b;rm -rf' 2>/dev/null)"
assert_eq "a..brm-rf" "${san}" "sanitize_path_component strips dangerous chars"

# ------------------------------------------------------------------------------
# SUITE 6: Install helpers (dry-run must be no-op + safe)
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 6]${NC} Install helpers (dry-run)"
source "${RABBIT_ROOT}/lib/helpers.sh" 2>/dev/null || true
export RABBIT_DRY_RUN="true"
export RABBIT_BIN_DIR="${RABBIT_STATE_DIR}/bin"
export RABBIT_INSTALL_DIR="${RABBIT_STATE_DIR}/inst"
# install_native reaches its dry-run branch only once a package manager is known.
export PKG_MGR="apt"
export PKG_INSTALL_CMD="apt-get install -y"
export OS_NAME="debian"
mkdir -p "${RABBIT_BIN_DIR}"

# dry-run install_wget must NOT create the binary
dry_out="$(install_wget "fakebin" "https://example.com/fakebin" 2>&1)"
assert_output_contains "${dry_out}" "[DRY-RUN]" "install_wget reports dry-run"
assert_true "[[ ! -f '${RABBIT_BIN_DIR}/fakebin' ]]" "install_wget dry-run does not write binary"

# dry-run install_pipx must not actually pipx-install
dry_out="$(install_pipx "faketool" "faketoolpkg" 2>&1)"
assert_output_contains "${dry_out}" "[DRY-RUN]" "install_pipx reports dry-run"

# dry-run install_native (no PKG_MGR set) must not error/install
dry_out="$(install_native "fakenative" "pkg" "pkg" "pkg" 2>&1)"
assert_output_contains "${dry_out}" "[DRY-RUN]" "install_native reports dry-run"

# ------------------------------------------------------------------------------
# SUITE 7: CLI surface smoke tests
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 7]${NC} CLI surface smoke tests"
RH="${RABBIT_ROOT}/bin/rabbithole"

out="$(${RH} --version 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole --version exits 0"
assert_output_contains "${out}" "RabbitHole v" "version output present"

out="$(${RH} --help 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole --help exits 0"
assert_output_contains "${out}" "Usage:" "help output present"

out="$(${RH} status 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole status exits 0"
assert_output_contains "${out}" "Installed Roles" "status lists roles section"

out="$(${RH} verify 2>&1)"; rc=$?
assert_output_contains "${out}" "Verifying RabbitHole" "rabbithole verify runs and reports status"

out="$(${RH} doctor 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole doctor exits 0"

out="$(${RH} cache build 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole cache build exits 0"
out="$(${RH} cache clean 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole cache clean exits 0"

out="$(${RH} snapshot 2>&1)"; rc=$?
assert_eq "0" "${rc}" "rabbithole snapshot exits 0"
assert_file_exists "${RABBIT_STATE_DIR}/snapshot.json" "snapshot written to state dir"

# The entrypoint must NOT auto-execute the old fix.sh loader anymore.
out="$(${RH} --version 2>&1)"
assert_true "! echo \"${out}\" | grep -q 'Fixing '" "entrypoint no longer auto-runs stray fix.sh"

# ------------------------------------------------------------------------------
# SUITE 8: Install-source validator (network-dependent, informational)
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 8]${NC} Install-source validator (informational)"
if command -v python3 >/dev/null 2>&1; then
    val_out="$(cd "${RABBIT_ROOT}" && python3 tests/validate_install_sources.py 2>&1)"
    val_rc=$?
    echo "${val_out}" | tail -n 8
    if [[ ${val_rc} -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        echo -e "${PASS}[PASS]${NC} All install sources reachable"
    else
        # Network may be unavailable in the sandbox; surface as a warning, not a hard fail.
        TESTS_RUN=$((TESTS_RUN + 1))
        echo -e "${WARN}[WARN]${NC} Validator reported unreachable sources (may be network-limited)."
        echo "        Re-run 'python3 tests/validate_install_sources.py' with network access to confirm."
    fi
else
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${WARN}[WARN]${NC} python3 not available; skipping install-source validator."
fi

# ------------------------------------------------------------------------------
# Regression: run the original test_runner.sh too
# ------------------------------------------------------------------------------
echo -e "${INFO}[SUITE 9]${NC} Regression: original test_runner.sh"
if bash "${RABBIT_ROOT}/tests/test_runner.sh" >/tmp/regression.out 2>&1; then
    reg_clean="$(sed 's/\x1b\[[0-9;]*m//g' /tmp/regression.out)"
    reg_total="$(echo "${reg_clean}" | grep -E 'Total:' | awk '{print $2}')"
    reg_pass="$(echo "${reg_clean}" | grep -E 'Passed:' | awk '{print $2}')"
    assert_eq "${reg_total}" "${reg_pass}" "Original test_runner passes all (${reg_pass}/${reg_total})"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${FAIL}[FAIL]${NC} Original test_runner.sh failed"
    tail -n 15 /tmp/regression.out
fi

# ------------------------------------------------------------------------------
# Cleanup + summary
# ------------------------------------------------------------------------------
rm -rf "${RABBIT_STATE_DIR}" 2>/dev/null || true

echo ""
echo "================================"
echo -e "${INFO}Full Test Results${NC}"
echo "  Total:   ${TESTS_RUN}"
echo -e "  Passed:  ${PASS}${TESTS_PASSED}${NC}"
if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "  Failed:  ${FAIL}${TESTS_FAILED}${NC}"
fi
echo "================================"

exit ${TESTS_FAILED}
