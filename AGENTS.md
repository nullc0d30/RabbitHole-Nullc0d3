# AGENTS.md — RabbitHole Developer Guide

## Architecture Principles

1. **Backward Compatibility First**: The original `rabbithole.sh` must NEVER be modified. New features are built as separate modules under `lib/` and accessed via `bin/rabbithole`.

2. **Plugin Over Code**: Roles are YAML manifests, not hardcoded functions. Adding a new role means creating `roles/<name>/plugin.yaml` — no shell code required.

3. **Defensive Bash**: Every variable is quoted. Every `cd` has `|| return`. Every function validates its inputs. ShellCheck compliance is the goal.

4. **State-Driven**: All operations record to `~/.rabbithole/state.json`. The framework knows what's installed, when, and how.

5. **No Duplicated Code**: Shared logic lives in `lib/`. Role-specific logic lives in `roles/<name>/install.sh`.

## Module Reference

### `lib/logging.sh`
- `log_info`, `log_ok`, `log_warn`, `log_error`, `log_task`, `log_debug`, `log_step`
- Writes to both stdout and `$RABBIT_LOG_FILE`
- Structured JSON logging when `RABBIT_STRUCTURED=true`

### `lib/package_manager.sh`
- `check_root`, `detect_os`, `check_connectivity`, `package_is_installed`, `install_base_deps`
- Sets `$OS_NAME`, `$PKG_MGR`, `$PKG_INSTALL_CMD`, etc.

### `lib/helpers.sh`
- `install_native`, `install_go`, `install_pipx`, `install_git`, `install_cargo`, `install_wget`, `install_custom`
- Each respects `$RABBIT_DRY_RUN` and records installs via `_record_install`

### `lib/plugins.sh`
- `plugin_discover_all`, `plugin_load`, `plugin_find_by_name`, `plugin_list_names`, `plugin_get_by_index`, `plugin_count`
- Parses `plugin.yaml` with grep/sed (no external YAML deps)
- `plugin_yaml_value`, `plugin_yaml_list`, `plugin_yaml_map` — low-level YAML access

### `lib/state.sh`
- `rabbit_state_init`, `rabbit_state_record_role`, `rabbit_state_record_tool`, `rabbit_state_remove_tool`, `rabbit_state_remove_role`
- `rabbit_state_get_installed_roles`, `rabbit_state_get_installed_tools`
- `rabbit_state_snapshot`, `rabbit_state_restore`, `rabbit_state_clear`

### `lib/dependency.sh`
- `rabbit_ensure_golang`, `rabbit_ensure_docker`, `rabbit_ensure_python`, `rabbit_ensure_pipx`, `rabbit_ensure_cargo`, `rabbit_ensure_git`
- Tracks satisfied deps to avoid redundant installs

### `lib/security.sh`
- `secure_random_string`, `secure_uuid`, `secure_hash_password`
- `verify_sha256`, `secure_download`, `generate_secure_env`, `validate_file_permissions`

### `lib/docker.sh`
- `docker_check_available`, `docker_compose_cmd`, `docker_deploy_threat_stack`, `docker_teardown_stack`, `docker_stack_status`

## Plugin YAML Specification

```yaml
name: "Role Display Name"         # Required
description: "What this role does" # Required
version: "1.0.0"                  # Required
author: "Your Name"               # Required
warning: false                    # If true, requires user confirmation
docker: false                     # If true, ensures Docker is installed
docker_stack: ""                  # "threat-intel" for Docker Compose deployment

native:    # List of "apt/rpm/pacman" package names
  - "tool/pkg/pkg"
go:        # List of "name import_path" pairs
  - "tool github.com/user/repo@latest"
pipx:      # List of "name package" pairs
  - "tool pip-package"
git:       # List of "name url [post_clone_command]" pairs
  - "tool https://github.com/user/repo.git make"
cargo:     # List of "name crate" pairs
  - "tool crate-name"
wget:      # List of "name url" pairs
  - "tool https://example.com/binary"
custom:    # List of raw shell commands
  - "echo 'custom step'"
```

## Adding a New Role

1. Create `roles/<rolename>/plugin.yaml`
2. Optionally create `roles/<rolename>/install.sh` for custom logic
3. The framework discovers it automatically — no registration needed

## Running Tests

```bash
./tests/test_runner.sh          # Standard run
./tests/test_runner.sh -v       # Verbose
```

## CI/CD

GitHub Actions in `.github/workflows/ci.yml`:
- ShellCheck linting
- Bash syntax validation
- Plugin manifest validation
- YAML linting

## Commands for Reproducible Work

```bash
# Create a lock file of current state
rabbithole snapshot > /backup/rabbithole-$(date +%Y%m%d).json

# Restore on a different machine
rabbithole restore /backup/rabbithole-20260101.json
```
