#!/bin/bash
# ==============================================================================
# RABBITHOLE - Plugin Discovery & Loading Module
# ==============================================================================
# Discovers role plugins from roles/ and plugins/ directories by reading
# plugin.yaml manifests. Provides functions to list, query, and load plugins.
# ==============================================================================

RABBIT_ROLES_DIR="${RABBIT_ROLES_DIR:-${RABBIT_INSTALL_DIR}/roles}"
RABBIT_PLUGINS_DIR="${RABBIT_PLUGINS_DIR:-${RABBIT_INSTALL_DIR}/plugins}"
RABBIT_BUILTIN_ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../roles" && pwd 2>/dev/null || echo '/opt/rabbithole/roles')"

declare -a RABBIT_LOADED_PLUGINS=()

# ------------------------------------------------------------------------------
# Parse a YAML value by key from plugin.yaml
# Uses grep + sed ? no external YAML parser dependency
# ------------------------------------------------------------------------------
plugin_yaml_value() {
    local yaml_file="$1"
    local key="$2"

    if [[ ! -f "${yaml_file}" ]]; then
        echo ""
        return 1
    fi

    # Extract value, handling quoted and unquoted strings
    grep -E "^${key}:" "${yaml_file}" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?/\1/' | xargs
}

# ------------------------------------------------------------------------------
# Parse a list value from plugin.yaml (lines starting with "  - ")
# ------------------------------------------------------------------------------
plugin_yaml_list() {
    local yaml_file="$1"
    local key="$2"

    if [[ ! -f "${yaml_file}" ]]; then
        return 0
    fi

    # Find the section, then read list items until next top-level key
    awk -v section="${key}:" '
        $0 ~ "^" section { found=1; next }
        found && /^[a-zA-Z]/ && !/^  / { found=0; next }
        found && /^  - / {
            gsub(/^  - /, "")
            print
        }
    ' "${yaml_file}" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Parse a mapped list (sub-key with values) from plugin.yaml
# e.g., native: { apt: git, dnf: git, pacman: git }
# ------------------------------------------------------------------------------
plugin_yaml_map() {
    local yaml_file="$1"
    local section="$2"
    local subkey="$3"

    if [[ ! -f "${yaml_file}" ]]; then
        return 0
    fi

    awk -v section="${section}:" -v subkey="${subkey}" '
        $0 ~ "^" section { in_section=1; next }
        in_section && /^[a-zA-Z]/ && !/^  / { in_section=0; next }
        in_section && $0 ~ "^  " subkey ":" {
            gsub(/^  [^:]+:[[:space:]]*/, "")
            print
        }
    ' "${yaml_file}" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Discover all available plugins
# Returns paths to all plugin.yaml files found
# ------------------------------------------------------------------------------
plugin_discover_all() {
    local -a search_dirs=()
    local -a results=()

    if [[ -d "${RABBIT_BUILTIN_ROLES_DIR}" ]]; then
        search_dirs+=("${RABBIT_BUILTIN_ROLES_DIR}")
    fi

    if [[ -d "${RABBIT_PLUGINS_DIR}" ]]; then
        search_dirs+=("${RABBIT_PLUGINS_DIR}")
    fi

    for dir in "${search_dirs[@]}"; do
        while IFS= read -r -d '' yaml; do
            results+=("${yaml}")
        done < <(find "${dir}" -maxdepth 2 -name 'plugin.yaml' -print0 2>/dev/null)
    done

    printf '%s\n' "${results[@]}"
}

# ------------------------------------------------------------------------------
# Load a specific plugin by directory path
# Sets plugin metadata as global variables
# ------------------------------------------------------------------------------
plugin_load() {
    local plugin_dir="$1"
    local yaml_file="${plugin_dir}/plugin.yaml"

    if [[ ! -f "${yaml_file}" ]]; then
        log_warn "No plugin.yaml found in ${plugin_dir}"
        return 1
    fi

    local plugin_name
    plugin_name="$(plugin_yaml_value "${yaml_file}" "name")"
    if [[ -z "${plugin_name}" ]]; then
        log_warn "Plugin in ${plugin_dir} has no name. Skipping."
        return 1
    fi

    RABBIT_CURRENT_PLUGIN_NAME="${plugin_name}"
    RABBIT_CURRENT_PLUGIN_DIR="${plugin_dir}"
    RABBIT_CURRENT_PLUGIN_DESC="$(plugin_yaml_value "${yaml_file}" "description")"
    RABBIT_CURRENT_PLUGIN_VERSION="$(plugin_yaml_value "${yaml_file}" "version")"
    RABBIT_CURRENT_PLUGIN_AUTHOR="$(plugin_yaml_value "${yaml_file}" "author")"

    RABBIT_LOADED_PLUGINS+=("${plugin_name}")
    log_debug "Loaded plugin: ${plugin_name} v${RABBIT_CURRENT_PLUGIN_VERSION}"
    return 0
}

# ------------------------------------------------------------------------------
# Get the install script path for a plugin
# ------------------------------------------------------------------------------
plugin_install_script() {
    local plugin_dir="$1"
    if [[ -f "${plugin_dir}/install.sh" ]]; then
        echo "${plugin_dir}/install.sh"
        return 0
    fi
    echo ""
    return 1
}

# ------------------------------------------------------------------------------
# List all discovered plugin names
# ------------------------------------------------------------------------------
plugin_list_names() {
    local yaml
    local name
    while IFS= read -r yaml; do
        name="$(plugin_yaml_value "${yaml}" "name")"
        if [[ -n "${name}" ]]; then
            echo "${name}"
        fi
    done < <(plugin_discover_all)
}

# ------------------------------------------------------------------------------
# Find plugin directory by name
# ------------------------------------------------------------------------------
plugin_find_by_name() {
    local target_name="$1"
    local yaml
    local name
    local dir

    while IFS= read -r yaml; do
        name="$(plugin_yaml_value "${yaml}" "name")"
        if [[ "${name}" == "${target_name}" ]]; then
            dir="$(dirname "${yaml}")"
            echo "${dir}"
            return 0
        fi
    done < <(plugin_discover_all)

    return 1
}

# ------------------------------------------------------------------------------
# Get plugin directory by index (1-based, matching menu order)
# ------------------------------------------------------------------------------
plugin_get_by_index() {
    local index="$1"
    local count=0
    local yaml

    while IFS= read -r yaml; do
        count=$((count + 1))
        if [[ ${count} -eq ${index} ]]; then
            dirname "${yaml}"
            return 0
        fi
    done < <(plugin_discover_all)

    return 1
}

# ------------------------------------------------------------------------------
# Count total plugins
# ------------------------------------------------------------------------------
plugin_count() {
    plugin_discover_all | wc -l
}





