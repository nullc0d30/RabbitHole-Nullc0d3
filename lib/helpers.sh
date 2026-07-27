#!/bin/bash
# ==============================================================================
# RABBITHOLE - Installation Helpers Module
# ==============================================================================
# Provides standardized install functions for native packages, Go, pipx, Git,
# Cargo, wget downloads, and custom commands. Each function logs structured
# metadata and supports dry-run and skip-if-installed modes.
# ==============================================================================

RABBIT_BIN_DIR="${RABBIT_BIN_DIR:-/usr/local/bin}"
RABBIT_INSTALL_DIR="${RABBIT_INSTALL_DIR:-/opt/rabbithole}"
RABBIT_DRY_RUN="${RABBIT_DRY_RUN:-false}"

# ------------------------------------------------------------------------------
# Native package install (multi-distro)
# $1 = tool name, $2 = deb_pkg, $3 = rpm_pkg, $4 = arch_pkg
# ------------------------------------------------------------------------------
install_native() {
    local tool="$1"
    local pkg=""

    case "${PKG_MGR}" in
        apt) pkg="$2" ;;
        dnf) pkg="$3" ;;
        pacman) pkg="$4" ;;
    esac

    if [[ -z "${pkg}" ]]; then
        log_warn "No native package mapping for '${tool}' on ${OS_NAME}. Skipping native install."
        return 1
    fi

    if package_is_installed "${pkg}"; then
        log_ok "${tool} already installed (native)."
        return 0
    fi

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would install ${tool} via ${PKG_MGR} (${pkg})"
        return 0
    fi

    log_task "Installing ${tool} via ${PKG_MGR} (${pkg})..."
    local start_time
    start_time="$(_rabbit_timestamp)"
    if ${PKG_INSTALL_CMD} "${pkg}" >> "${RABBIT_LOG_FILE}" 2>&1; then
        log_ok "${tool} installed."
        _record_install "native" "${tool}" "${pkg}" "${start_time}" "$(_rabbit_timestamp)" 0
        return 0
    else
        log_warn "Failed to install ${tool} via native package."
        _record_install "native" "${tool}" "${pkg}" "${start_time}" "$(_rabbit_timestamp)" 1
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Go install
# $1 = tool name, $2 = go import path
# ------------------------------------------------------------------------------
install_go() {
    local tool="$1"
    local path="$2"

    export PATH="${PATH}:/usr/local/go/bin:$(go env GOPATH 2>/dev/null || echo '/root/go')/bin:/root/go/bin"

    if command -v "${tool}" &> /dev/null; then
        log_ok "${tool} already installed (Go)."
        return 0
    fi

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would install ${tool} via Go (${path})"
        return 0
    fi

    log_task "Installing ${tool} via Go..."
    local start_time
    start_time="$(_rabbit_timestamp)"

    if go install -v "${path}" >> "${RABBIT_LOG_FILE}" 2>&1; then
        log_ok "${tool} installed (Go)."
        local gobin
        gobin="$(go env GOPATH 2>/dev/null || echo '/root/go')/bin/${tool}"
        if [[ -f "${gobin}" ]]; then
            ln -sf "${gobin}" "${RABBIT_BIN_DIR}/${tool}" 2>/dev/null || true
        fi
        _record_install "go" "${tool}" "${path}" "${start_time}" "$(_rabbit_timestamp)" 0
        return 0
    else
        log_warn "Failed to install ${tool} via Go."
        _record_install "go" "${tool}" "${path}" "${start_time}" "$(_rabbit_timestamp)" 1
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Pipx install (with pip fallback)
# $1 = tool name, $2 = pip package name (defaults to tool name)
# ------------------------------------------------------------------------------
install_pipx() {
    local tool="$1"
    local pkg_name="${2:-${tool}}"

    export PATH="${PATH}:/root/.local/bin"

    if command -v "${tool}" &> /dev/null; then
        log_ok "${tool} already installed (pipx)."
        return 0
    fi

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would install ${tool} via pipx (${pkg_name})"
        return 0
    fi

    log_task "Installing ${tool} via pipx..."
    local start_time
    start_time="$(_rabbit_timestamp)"

    if pipx install "${pkg_name}" --include-deps --force >> "${RABBIT_LOG_FILE}" 2>&1; then
        log_ok "${tool} installed (pipx)."
        pipx ensurepath >> "${RABBIT_LOG_FILE}" 2>&1 || true
        _record_install "pipx" "${tool}" "${pkg_name}" "${start_time}" "$(_rabbit_timestamp)" 0
        return 0
    else
        log_warn "Failed to install ${tool} via pipx. Trying fallback pip..."
        if pip3 install "${pkg_name}" >> "${RABBIT_LOG_FILE}" 2>&1; then
            log_ok "${tool} installed (pip fallback)."
            _record_install "pip" "${tool}" "${pkg_name}" "${start_time}" "$(_rabbit_timestamp)" 0
            return 0
        else
            log_warn "Failed to install ${tool} via pip fallback."
            _record_install "pip" "${tool}" "${pkg_name}" "${start_time}" "$(_rabbit_timestamp)" 1
            return 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# Git clone install
# $1 = tool name, $2 = repo URL, $3 = optional post-clone command
# ------------------------------------------------------------------------------
install_git() {
    local tool="$1"
    local repo_url="$2"
    local install_script="${3:-}"
    local target_dir="/opt/${tool}"

    if [[ -d "${target_dir}" ]]; then
        log_ok "${tool} already cloned at ${target_dir}."
        if [[ -n "${install_script}" ]]; then
            log_task "Running update for ${tool}..."
            (cd "${target_dir}" || return; git pull >> "${RABBIT_LOG_FILE}" 2>&1) || true
        fi
        return 0
    fi

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would clone ${repo_url} to ${target_dir}"
        return 0
    fi

    log_task "Installing ${tool} via Git..."
    local start_time
    start_time="$(_rabbit_timestamp)"

    if git clone "${repo_url}" "${target_dir}" >> "${RABBIT_LOG_FILE}" 2>&1; then
        if [[ -n "${install_script}" ]]; then
            log_task "Running setup for ${tool}..."
            (cd "${target_dir}" || return; eval "${install_script}" >> "${RABBIT_LOG_FILE}" 2>&1) || log_warn "Setup script for ${tool} encountered issues."
        fi
        log_ok "${tool} installed (Git)."
        _record_install "git" "${tool}" "${repo_url}" "${start_time}" "$(_rabbit_timestamp)" 0
        return 0
    else
        log_error "Failed to clone ${repo_url}."
        _record_install "git" "${tool}" "${repo_url}" "${start_time}" "$(_rabbit_timestamp)" 1
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Cargo install
# $1 = tool name, $2 = crate name (defaults to tool name)
# ------------------------------------------------------------------------------
install_cargo() {
    local tool="$1"
    local crate="${2:-${tool}}"

    if ! command -v cargo &> /dev/null; then
        log_warn "Cargo not available. Skipping ${tool}."
        return 1
    fi

    if command -v "${tool}" &> /dev/null; then
        log_ok "${tool} already installed (Cargo)."
        return 0
    fi

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would install ${tool} via cargo (${crate})"
        return 0
    fi

    log_task "Installing ${tool} via Cargo..."
    local start_time
    start_time="$(_rabbit_timestamp)"

    if cargo install "${crate}" >> "${RABBIT_LOG_FILE}" 2>&1; then
        log_ok "${tool} installed (Cargo)."
        _record_install "cargo" "${tool}" "${crate}" "${start_time}" "$(_rabbit_timestamp)" 0
        return 0
    else
        log_warn "Failed to install ${tool} via Cargo."
        _record_install "cargo" "${tool}" "${crate}" "${start_time}" "$(_rabbit_timestamp)" 1
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Wget binary download
# $1 = tool name, $2 = download URL, $3 = optional binary name (defaults to tool name)
# ------------------------------------------------------------------------------
install_wget() {
    local tool="$1"
    local url="$2"
    local binary_name="${3:-${tool}}"
    local target="${RABBIT_BIN_DIR}/${binary_name}"

    if [[ -f "${target}" ]] && [[ -x "${target}" ]]; then
        log_ok "${tool} already installed at ${target}."
        return 0
    fi

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would download ${url} to ${target}"
        return 0
    fi

    log_task "Downloading ${tool}..."
    local start_time
    start_time="$(_rabbit_timestamp)"

    if wget -q "${url}" -O "${target}" 2>> "${RABBIT_LOG_FILE}"; then
        chmod +x "${target}"
        log_ok "${tool} downloaded and installed."
        _record_install "wget" "${tool}" "${url}" "${start_time}" "$(_rabbit_timestamp)" 0
        return 0
    else
        log_warn "Failed to download ${tool}."
        _record_install "wget" "${tool}" "${url}" "${start_time}" "$(_rabbit_timestamp)" 1
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Custom command execution
# $1 = tool name, $2 = command string, $3 = cwd (optional)
# ------------------------------------------------------------------------------
install_custom() {
    local tool="$1"
    local command_str="$2"
    local cwd="${3:-}"

    if [[ "${RABBIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute custom command for ${tool}: ${command_str}"
        return 0
    fi

    log_task "Running custom install for ${tool}..."
    local start_time
    start_time="$(_rabbit_timestamp)"

    local rc=0
    if [[ -n "${cwd}" ]]; then
        (cd "${cwd}" || return; eval "${command_str}" >> "${RABBIT_LOG_FILE}" 2>&1) || rc=1
    else
        eval "${command_str}" >> "${RABBIT_LOG_FILE}" 2>&1 || rc=1
    fi

    if [[ ${rc} -eq 0 ]]; then
        log_ok "${tool} custom install succeeded."
        _record_install "custom" "${tool}" "${command_str}" "${start_time}" "$(_rabbit_timestamp)" 0
    else
        log_warn "${tool} custom install failed."
        _record_install "custom" "${tool}" "${command_str}" "${start_time}" "$(_rabbit_timestamp)" 1
    fi
    return ${rc}
}

# ------------------------------------------------------------------------------
# Internal: record install metadata to state
# ------------------------------------------------------------------------------
_record_install() {
    local method="$1"
    local tool="$2"
    local source="$3"
    local start_time="$4"
    local end_time="$5"
    local exit_code="$6"

    if [[ -z "${RABBIT_STATE_FILE:-}" ]]; then
        return 0
    fi
    rabbit_state_record_tool "${method}" "${tool}" "${source}" "${start_time}" "${end_time}" "${exit_code}" 2>/dev/null || true
}
