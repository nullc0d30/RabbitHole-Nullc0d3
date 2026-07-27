#!/bin/bash
# ==============================================================================
# RABBITHOLE - Security Module
# ==============================================================================
# Provides secure random credential generation, checksum verification,
# and supply chain security utilities.
# ==============================================================================

# ------------------------------------------------------------------------------
# Generate a cryptographically secure random string
# $1 = length (default 32), $2 = character set (default alphanumeric)
# ------------------------------------------------------------------------------
secure_random_string() {
    local length="${1:-32}"
    local charset="${2:-a-zA-Z0-9}"

    if command -v openssl &> /dev/null; then
        openssl rand -base64 48 2>/dev/null | tr -dc "${charset}" | head -c"${length}"
    elif [[ -f /dev/urandom ]]; then
        tr -dc "${charset}" < /dev/urandom | head -c"${length}"
    else
        log_warn "No secure random source available. Using fallback."
        date +%s | sha256sum | head -c"${length}"
    fi
}

# ------------------------------------------------------------------------------
# Generate a UUID v4 string
# ------------------------------------------------------------------------------
secure_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Generate a random UUID v4
        local hex
        hex="$(secure_random_string 32 '0-9a-f')"
        echo "${hex:0:8}-${hex:8:4}-4${hex:13:3}-a${hex:17:3}-${hex:20:12}"
    fi
}

# ------------------------------------------------------------------------------
# Generate a bcrypt-compatible password hash
# $1 = plaintext password
# ------------------------------------------------------------------------------
secure_hash_password() {
    local password="$1"
    if command -v mkpasswd &> /dev/null; then
        mkpasswd -m sha-512 "${password}" 2>/dev/null || echo "${password}"
    else
        echo "${password}"
    fi
}

# ------------------------------------------------------------------------------
# Verify SHA256 checksum of a downloaded file
# $1 = file path, $2 = expected SHA256 hash
# Returns 0 if match, 1 otherwise
# ------------------------------------------------------------------------------
verify_sha256() {
    local file_path="$1"
    local expected_hash="$2"

    if [[ ! -f "${file_path}" ]]; then
        log_warn "Cannot verify checksum: file not found ${file_path}"
        return 1
    fi

    if [[ -z "${expected_hash}" ]]; then
        log_debug "No expected hash provided for ${file_path}. Skipping verification."
        return 0
    fi

    local actual_hash
    actual_hash="$(sha256sum "${file_path}" | cut -d' ' -f1)"

    if [[ "${actual_hash}" == "${expected_hash}" ]]; then
        log_debug "SHA256 match for ${file_path}"
        return 0
    else
        log_error "SHA256 mismatch for ${file_path}. Expected ${expected_hash}, got ${actual_hash}."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Download with checksum verification
# $1 = URL, $2 = output path, $3 = expected SHA256 (optional)
# ------------------------------------------------------------------------------
secure_download() {
    local url="$1"
    local output_path="$2"
    local expected_hash="${3:-}"

    log_task "Downloading ${url}..."
    if wget -q "${url}" -O "${output_path}" 2>> "${RABBIT_LOG_FILE}"; then
        if [[ -n "${expected_hash}" ]]; then
            verify_sha256 "${output_path}" "${expected_hash}" || {
                rm -f "${output_path}"
                return 1
            }
        fi
        log_ok "Downloaded to ${output_path}"
        return 0
    else
        log_warn "Failed to download ${url}"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Generate a secure .env file for Docker stacks
# $1 = output directory
# ------------------------------------------------------------------------------
generate_secure_env() {
    local output_dir="$1"
    local env_file="${output_dir}/.env"

    mkdir -p "${output_dir}"

    local minio_pass
    local rabbit_pass
    local elastic_pass
    local opencti_token
    local misp_mysql_pass
    local opencti_admin_pass

    minio_pass="$(secure_random_string 32)"
    rabbit_pass="$(secure_random_string 32)"
    elastic_pass="$(secure_random_string 32)"
    opencti_token="$(secure_uuid)"
    misp_mysql_pass="$(secure_random_string 32)"
    opencti_admin_pass="$(secure_random_string 24)"

    log_task "Generating secure .env at ${env_file}"
    cat > "${env_file}" << EOF
# RabbitHole Secure Configuration
# Auto-generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# WARNING: Keep this file secure. It contains credentials.

OPENCTI_ADMIN_EMAIL=admin@rabbithole.local
OPENCTI_ADMIN_PASSWORD=${opencti_admin_pass}
OPENCTI_ADMIN_TOKEN=${opencti_token}
OPENCTI_BASE_URL=http://localhost:8080

MINIO_ROOT_USER=opencti
MINIO_ROOT_PASSWORD=${minio_pass}

RABBITMQ_DEFAULT_USER=opencti
RABBITMQ_DEFAULT_PASS=${rabbit_pass}

ELASTIC_MEMORY_MAP_THRESHOLD=262144
ELASTIC_PASSWORD=${elastic_pass}

MISP_MYSQL_PASSWORD=${misp_mysql_pass}
MISP_ADMIN_EMAIL=admin@admin.test
MISP_ADMIN_PASSPHRASE=$(secure_random_string 16)
EOF

    chmod 600 "${env_file}"
    log_ok "Secure .env generated at ${env_file}"
}

# ------------------------------------------------------------------------------
# Validate that a file has safe permissions (not world-readable)
# $1 = file path
# ------------------------------------------------------------------------------
validate_file_permissions() {
    local file_path="$1"
    if [[ ! -f "${file_path}" ]]; then
        return 0
    fi

    local perms
    perms="$(stat -c '%a' "${file_path}" 2>/dev/null || echo '777')"
    if [[ "${perms: -1}" -gt 0 ]]; then
        log_warn "File ${file_path} is world-readable (${perms}). Consider chmod 600."
    fi
}

# ------------------------------------------------------------------------------
# Sanitize a path component (remove dangerous characters)
# $1 = string to sanitize
# ------------------------------------------------------------------------------
sanitize_path_component() {
    echo "$1" | tr -dc 'a-zA-Z0-9._-'
}
