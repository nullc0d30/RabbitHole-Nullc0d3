#!/bin/bash
# ==============================================================================
# RABBITHOLE - Package Manager Module
# ==============================================================================
# Detects the Linux distribution and configures the appropriate package manager.
# Supports: apt (Debian/Kali/Ubuntu/Parrot), dnf (Fedora), pacman (Arch/Manjaro).
# ==============================================================================

RABBIT_RED='\033[0;31m'
RABBIT_NC='\033[0m'

# Detection results ? set by detect_os()
OS_NAME=""
OS_VERSION_ID=""
OS_ARCH=""
PKG_MGR=""
PKG_INSTALL_CMD=""
PKG_UPDATE_CMD=""
PKG_QUERY_CMD=""

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo -e "${RABBIT_RED}[ERROR]${RABBIT_NC} This script must be run as root." >&2
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RABBIT_RED}[ERROR]${RABBIT_NC} Cannot detect OS. /etc/os-release not found." >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    OS_NAME="${ID}"
    OS_VERSION_ID="${VERSION_ID}"
    OS_ARCH="$(uname -m)"

    log_debug "Detected OS: ${OS_NAME} ${OS_VERSION_ID} (${OS_ARCH})"

    case "${OS_NAME}" in
        debian|ubuntu|kali|parrot)
            PKG_MGR="apt"
            PKG_INSTALL_CMD="apt-get install -y"
            PKG_UPDATE_CMD="apt-get update"
            PKG_QUERY_CMD="dpkg -l"
            ;;
        fedora)
            PKG_MGR="dnf"
            PKG_INSTALL_CMD="dnf install -y"
            PKG_UPDATE_CMD="dnf check-update"
            PKG_QUERY_CMD="rpm -q"
            ;;
        arch|manjaro)
            PKG_MGR="pacman"
            PKG_INSTALL_CMD="pacman -S --noconfirm --needed"
            PKG_UPDATE_CMD="pacman -Sy"
            PKG_QUERY_CMD="pacman -Qi"
            ;;
        *)
            echo -e "${RABBIT_RED}[ERROR]${RABBIT_NC} Unsupported Distribution: ${OS_NAME}" >&2
            exit 1
            ;;
    esac

    log_info "Detected OS: ${OS_NAME} (${OS_ARCH}) ? using ${PKG_MGR}"
}

check_connectivity() {
    log_task "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connection detected."
    fi
    log_ok "Connectivity confirmed."
}

package_is_installed() {
    local pkg_name="$1"
    case "${PKG_MGR}" in
        apt)
            dpkg -l "${pkg_name}" 2>/dev/null | grep -q '^ii' || return 1
            ;;
        dnf)
            rpm -q "${pkg_name}" &>/dev/null || return 1
            ;;
        pacman)
            pacman -Qi "${pkg_name}" &>/dev/null || return 1
            ;;
    esac
    return 0
}

install_base_deps() {
    log_info "Installing Base Dependencies..."

    # Update repositories
    log_task "Updating package repositories..."
    ${PKG_UPDATE_CMD} >> "${RABBIT_LOG_FILE}" 2>&1 || log_warn "Repository update encountered issues."

    # Core utilities
    install_native "git" "git" "git" "git"
    install_native "curl" "curl" "curl" "curl"
    install_native "wget" "wget" "wget" "wget"

    # Python ecosystem
    install_native "python3" "python3" "python3" "python"
    install_native "pip" "python3-pip" "python3-pip" "python-pip"
    install_native "pipx" "pipx" "pipx" "python-pipx"

    # Go
    install_native "golang" "golang-go" "golang" "go"

    # Docker (optional but required by some tools)
    install_native "docker" "docker.io" "docker" "docker" || log_warn "Docker installation skipped or failed."

    # Ensure pipx is functional
    if command -v pipx &> /dev/null; then
        pipx ensurepath >> "${RABBIT_LOG_FILE}" 2>&1 || true
    fi
    export PATH="${PATH}:/root/.local/bin"
}





