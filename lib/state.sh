#!/bin/bash
# ==============================================================================
# RABBITHOLE - State Management Module
# ==============================================================================
# Manages installation state via ~/.rabbithole/state.json. Tracks roles, tools,
# versions, install dates, and provides query/resume/rollback capabilities.
# ==============================================================================

RABBIT_STATE_DIR="${RABBIT_STATE_DIR:-${HOME}/.rabbithole}"
RABBIT_STATE_FILE="${RABBIT_STATE_FILE:-${RABBIT_STATE_DIR}/state.json}"
RABBIT_PROJECT_VERSION="${RABBIT_PROJECT_VERSION:-2.0.0}"

rabbit_state_init() {
    mkdir -p "${RABBIT_STATE_DIR}" 2>/dev/null || true
    if [[ ! -f "${RABBIT_STATE_FILE}" ]]; then
        echo '{
  "version": "'"${RABBIT_PROJECT_VERSION}"'",
  "created_at": "'"$(_rabbit_timestamp)"'",
  "updated_at": "'"$(_rabbit_timestamp)"'",
  "roles": {},
  "tools": {},
  "docker": {}
}' > "${RABBIT_STATE_FILE}"
        log_debug "State file initialized at ${RABBIT_STATE_FILE}"
    fi
}

rabbit_state_read() {
    if [[ ! -f "${RABBIT_STATE_FILE}" ]]; then
        echo "{}"
        return 0
    fi
    cat "${RABBIT_STATE_FILE}"
}

rabbit_state_write() {
    local json="$1"
    echo "${json}" > "${RABBIT_STATE_FILE}"
}

rabbit_state_get() {
    local key="$1"
    rabbit_state_read | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('${key}', ''))" 2>/dev/null || echo ""
}

rabbit_state_record_role() {
    local role_name="$1"
    local status="$2"

    local current
    current="$(rabbit_state_read)"

    local updated
    updated="$(echo "${current}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'roles' not in d:
    d['roles'] = {}
d['roles']['${role_name}'] = {
    'status': '${status}',
    'installed_at': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
}
d['updated_at'] = '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
print(json.dumps(d, indent=2))
" 2>/dev/null)" || return 1

    rabbit_state_write "${updated}"
}

rabbit_state_record_tool() {
    local method="$1"
    local tool="$2"
    local source="$3"
    local start_time="$4"
    local end_time="$5"
    local exit_code="$6"

    local current
    current="$(rabbit_state_read)"

    local updated
    updated="$(echo "${current}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'tools' not in d:
    d['tools'] = {}
d['tools']['${tool}'] = {
    'method': '${method}',
    'source': '${source}',
    'installed_at': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")',
    'exit_code': ${exit_code},
    'version': 'unknown'
}
d['updated_at'] = '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
print(json.dumps(d, indent=2))
" 2>/dev/null)" || return 1

    rabbit_state_write "${updated}"
}

rabbit_state_tool_is_installed() {
    local tool="$1"
    rabbit_state_read | python3 -c "
import sys, json
d = json.load(sys.stdin)
tools = d.get('tools', {})
if '${tool}' in tools:
    sys.exit(0)
else:
    sys.exit(1)
" 2>/dev/null && return 0 || return 1
}

rabbit_state_role_is_installed() {
    local role_name="$1"
    rabbit_state_read | python3 -c "
import sys, json
d = json.load(sys.stdin)
roles = d.get('roles', {})
if '${role_name}' in roles:
    sys.exit(0)
else:
    sys.exit(1)
" 2>/dev/null && return 0 || return 1
}

rabbit_state_remove_tool() {
    local tool="$1"

    local current
    current="$(rabbit_state_read)"

    local updated
    updated="$(echo "${current}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'tools' in d and '${tool}' in d['tools']:
    del d['tools']['${tool}']
d['updated_at'] = '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
print(json.dumps(d, indent=2))
" 2>/dev/null)" || return 1

    rabbit_state_write "${updated}"
}

rabbit_state_remove_role() {
    local role_name="$1"

    local current
    current="$(rabbit_state_read)"

    local updated
    updated="$(echo "${current}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'roles' in d and '${role_name}' in d['roles']:
    del d['roles']['${role_name}']
d['updated_at'] = '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
print(json.dumps(d, indent=2))
" 2>/dev/null)" || return 1

    rabbit_state_write "${updated}"
}

rabbit_state_get_installed_roles() {
    rabbit_state_read | python3 -c "
import sys, json
d = json.load(sys.stdin)
roles = d.get('roles', {})
for r in sorted(roles.keys()):
    print(r)
" 2>/dev/null
}

rabbit_state_get_installed_tools() {
    rabbit_state_read | python3 -c "
import sys, json
d = json.load(sys.stdin)
tools = d.get('tools', {})
for t in sorted(tools.keys()):
    print(t)
" 2>/dev/null
}

rabbit_state_snapshot() {
    local output_file="${1:-/dev/stdout}"
    rabbit_state_read | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(json.dumps({
    'version': d.get('version', 'unknown'),
    'created_at': d.get('created_at', ''),
    'roles': d.get('roles', {}),
    'tools': d.get('tools', {}),
    'docker': d.get('docker', {})
}, indent=2))
" > "${output_file}" 2>/dev/null || log_error "Failed to generate snapshot."
    log_ok "Snapshot written to ${output_file}"
}

rabbit_state_restore() {
    local snapshot_file="$1"

    if [[ ! -f "${snapshot_file}" ]]; then
        log_error "Snapshot file not found: ${snapshot_file}"
    fi

    if ! python3 -c "import json; json.load(open('${snapshot_file}'))" 2>/dev/null; then
        log_error "Invalid JSON in snapshot file."
    fi

    cp "${snapshot_file}" "${RABBIT_STATE_FILE}"
    log_ok "State restored from ${snapshot_file}"
}

rabbit_state_clear() {
    if [[ -f "${RABBIT_STATE_FILE}" ]]; then
        rm -f "${RABBIT_STATE_FILE}"
        log_info "State file cleared."
    fi
    rabbit_state_init
}





