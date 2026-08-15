#!/bin/bash
# ==============================================================================
# RABBITHOLE - Dependency Resolution Module
# ==============================================================================
# Ensures that shared dependencies (Go, Docker, Python, pipx, Cargo) are
# installed before role-specific tools that require them. Tracks which
# dependencies have been satisfied to avoid redundant installs.
# ==============================================================================

declare -A RABBIT_DEPS_SATISFIED

rabbit_dep_mark() {
    RABBIT_DEPS_SATISFIED["$1"]=true
}

rabbit_dep_is_satisfied() {
    [[ "${RABBIT_DEPS_SATISFIED[$1]:-false}" == "true" ]]
}

rabbit_ensure_golang() {
    if rabbit_dep_is_satisfied "golang"; then
        log_debug "Golang dependency already satisfied."
        return 0
    fi

    if ! command -v go &> /dev/null; then
        log_task "Go not found. Installing Go..."
        install_native "golang" "golang-go" "golang" "go" || {
            log_error "Failed to install Go. Cannot proceed with Go-based tools."
            return 1
        }
    else
        log_debug "Go is available: $(go version 2>/dev/null | head -1)"
    fi

    export PATH="${PATH}:/usr/local/go/bin:$(go env GOPATH 2>/dev/null || echo '/root/go')/bin:/root/go/bin"
    rabbit_dep_mark "golang"
}

rabbit_ensure_docker() {
    if rabbit_dep_is_satisfied "docker"; then
        log_debug "Docker dependency already satisfied."
        return 0
    fi

    if ! command -v docker &> /dev/null; then
        log_task "Docker not found. Installing Docker..."
        install_native "docker" "docker.io" "docker" "docker" || {
            log_warn "Failed to install Docker via package manager."
            log_warn "Docker-dependent features (Threat Intel stack) will be unavailable."
            return 1
        }
    else
        log_debug "Docker is available: $(docker --version 2>/dev/null | head -1)"
    fi

    rabbit_dep_mark "docker"
}

rabbit_ensure_python() {
    if rabbit_dep_is_satisfied "python"; then
        return 0
    fi

    if ! command -v python3 &> /dev/null; then
        log_task "Python3 not found. Installing..."
        install_native "python3" "python3" "python3" "python" || {
            log_error "Failed to install Python3."
            return 1
        }
    fi

    if ! command -v pip3 &> /dev/null; then
        log_task "pip3 not found. Installing..."
        install_native "pip" "python3-pip" "python3-pip" "python-pip" || {
            log_warn "Failed to install pip3."
            return 1
        }
    fi

    rabbit_dep_mark "python"
}

rabbit_ensure_pipx() {
    if rabbit_dep_is_satisfied "pipx"; then
        return 0
    fi

    rabbit_ensure_python

    if ! command -v pipx &> /dev/null; then
        log_task "pipx not found. Installing..."
        install_native "pipx" "pipx" "pipx" "python-pipx" || {
            pip3 install pipx >> "${RABBIT_LOG_FILE}" 2>&1 || {
                log_warn "Failed to install pipx."
                return 1
            }
        }
    fi

    export PATH="${PATH}:/root/.local/bin"
    pipx ensurepath >> "${RABBIT_LOG_FILE}" 2>&1 || true
    rabbit_dep_mark "pipx"
}

rabbit_ensure_cargo() {
    if rabbit_dep_is_satisfied "cargo"; then
        return 0
    fi

    if ! command -v cargo &> /dev/null; then
        log_task "Cargo not found. Installing Rust/Cargo..."
        if command -v rustup &> /dev/null; then
            rustup install stable >> "${RABBIT_LOG_FILE}" 2>&1 || log_warn "rustup install failed."
        else
            install_native "cargo" "cargo" "cargo" "rust" || {
                log_warn "Failed to install Cargo. Rust-based tools will be skipped."
                return 1
            }
        fi
    else
        log_debug "Cargo is available: $(cargo --version 2>/dev/null | head -1)"
    fi

    rabbit_dep_mark "cargo"
}

rabbit_ensure_git() {
    if rabbit_dep_is_satisfied "git"; then
        return 0
    fi

    if ! command -v git &> /dev/null; then
        log_task "Git not found. Installing..."
        install_native "git" "git" "git" "git" || {
            log_error "Failed to install Git."
            return 1
        }
    fi

    rabbit_dep_mark "git"
}

rabbit_ensure_all_base() {
    rabbit_ensure_git
    rabbit_ensure_python
    rabbit_ensure_pipx
    rabbit_ensure_golang
    rabbit_ensure_docker
}
