#!/bin/bash
# ==============================================================================
# RABBITHOLE - Logging Module
# ==============================================================================
# Provides structured and colored logging for the RabbitHole framework.
# All log entries include timestamps and are written to both stdout and the
# configured log file when available.
# ==============================================================================

RABBIT_LOG_FILE="${RABBIT_LOG_FILE:-./rabbithole.log}"
RABBIT_QUIET="${RABBIT_QUIET:-false}"
RABBIT_STRUCTURED="${RABBIT_STRUCTURED:-false}"

# Colors
RABBIT_RED='\033[0;31m'
RABBIT_GREEN='\033[0;32m'
RABBIT_YELLOW='\033[0;33m'
RABBIT_BLUE='\033[0;34m'
RABBIT_CYAN='\033[0;36m'
RABBIT_BOLD='\033[1m'
RABBIT_NC='\033[0m'

_rabbit_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

_rabbit_log_entry() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(_rabbit_timestamp)"
    local entry="${timestamp} [${level}] ${message}"
    echo "${entry}" >> "${RABBIT_LOG_FILE}" 2>/dev/null || true
    if [[ "${RABBIT_STRUCTURED}" == "true" ]]; then
        echo "{\"timestamp\":\"${timestamp}\",\"level\":\"${level}\",\"message\":\"${message}\"}" >> "${RABBIT_LOG_FILE}.json" 2>/dev/null || true
    fi
}

log_info() {
    _rabbit_log_entry "INFO" "$*"
    if [[ "${RABBIT_QUIET}" != "true" ]]; then
        echo -e "${RABBIT_BLUE}[INFO]${RABBIT_NC} $*"
    fi
}

log_ok() {
    _rabbit_log_entry "OK" "$*"
    if [[ "${RABBIT_QUIET}" != "true" ]]; then
        echo -e "${RABBIT_GREEN}[OK]${RABBIT_NC} $*"
    fi
}

log_warn() {
    _rabbit_log_entry "WARN" "$*"
    if [[ "${RABBIT_QUIET}" != "true" ]]; then
        echo -e "${RABBIT_YELLOW}[WARN]${RABBIT_NC} $*"
    fi
}

log_error() {
    _rabbit_log_entry "ERROR" "$*"
    echo -e "${RABBIT_RED}[ERROR]${RABBIT_NC} $*" >&2
    exit 1
}

log_task() {
    _rabbit_log_entry "TASK" "$*"
    if [[ "${RABBIT_QUIET}" != "true" ]]; then
        echo -e "${RABBIT_CYAN}[TASK]${RABBIT_NC} $*"
    fi
}

log_debug() {
    if [[ "${RABBIT_DEBUG:-false}" == "true" ]]; then
        _rabbit_log_entry "DEBUG" "$*"
        echo -e "${RABBIT_BOLD}[DEBUG]${RABBIT_NC} $*"
    fi
}

log_step() {
    local current="$1"
    local total="$2"
    local label="$3"
    echo -e "${RABBIT_CYAN}[${current}/${total}]${RABBIT_NC} ${label}"
}
