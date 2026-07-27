# RabbitHole

> **Universal Cybersecurity Environment Installer / Provisioning Framework**
> *Role-based. Opinionated. Production-Ready. Modular.*

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg) ![License](https://img.shields.io/badge/license-Apache%202.0-green.svg) ![Author](https://img.shields.io/badge/made%20by-Ahmed%20Awad%20(NullC0d3)-000000.svg)

## Overview

**RabbitHole** provisions combat-ready cybersecurity environments in minutes. Originally a single-file Bash installer, it has evolved into a **modular, extensible Cybersecurity Environment Provisioning Framework** with a plugin system, state management, rollback, supply-chain security, and full CLI tooling.

### Key Features

- **Distro Agnostic**: Auto-detects Debian/Kali/Ubuntu/Parrot, Fedora, Arch/Manjaro.
- **Plugin Architecture**: Roles are defined as YAML manifests under `roles/`. Add a new role by creating a directory with `plugin.yaml` — no code changes needed.
- **State Management**: Tracks installed roles, tools, versions, and dates in `~/.rabbithole/state.json`. Supports `verify`, `doctor`, `snapshot`, `restore`.
- **Resume Capability**: If installation is interrupted (power loss, Ctrl+C, network failure), re-running resumes from the last successful package.
- **Supply Chain Security**: SHA256 verification, pinned versions, secure auto-generated Docker credentials.
- **Rollback**: `rabbithole remove <role>` cleans packages, symlinks, pipx apps, Go binaries, Git repos, and Docker resources.
- **Dry Run**: `rabbithole --dry-run install <role>` previews without changes.
- **Zero-Bloat**: No background services, no telemetry.
- **Full Backward Compatibility**: The original `rabbithole.sh` still works exactly as before.

## Installation & Usage

### Prerequisites
- Linux-based OS (Kali, Ubuntu, Debian, Fedora, Arch, Parrot, Manjaro)
- Root privileges (`sudo`)
- Internet connection

### Quick Start (New Framework)

```bash
git clone https://github.com/NullC0d3/rabbithole.git
cd rabbithole
chmod +x bin/rabbithole
sudo ./bin/rabbithole
```

### Quick Start (Legacy — Original Installer)

```bash
sudo ./rabbithole.sh
```

The original single-file installer remains fully functional and unchanged for users who prefer it.

### CLI Commands

| Command | Description |
|---------|-------------|
| `rabbithole` | Interactive role-based installer |
| `rabbithole install <role>` | Install specific role(s) |
| `rabbithole remove <role>` | Remove specific role(s) |
| `rabbithole status` | Show installation status |
| `rabbithole verify` | Verify installed tools and dependencies |
| `rabbithole doctor` | Comprehensive health check |
| `rabbithole update` | Update installed tools |
| `rabbithole snapshot` | Export state snapshot to JSON |
| `rabbithole restore <file>` | Restore state from snapshot |
| `rabbithole cache build\|clean` | Manage download cache |
| `rabbithole benchmark` | Run system benchmarks |
| `rabbithole --dry-run` | Preview without installing |
| `rabbithole --version` | Show version |
| `rabbithole --help` | Show help |

### Examples

```bash
# Interactive menu
sudo rabbithole

# Install specific roles
sudo rabbithole install "OSINT Analyst" "Pentester"

# Preview without making changes
sudo rabbithole --dry-run install "Red Team Operator"

# Verify installation
rabbithole verify

# Health check
rabbithole doctor

# Remove a role
sudo rabbithole remove "Bug Bounty Hunter"

# Save and restore state
rabbithole snapshot > backup.json
rabbithole restore backup.json
```

## Operational Roles

RabbitHole organizes tools into strictly defined operational roles. You can install multiple roles simultaneously.

### [1] OSINT Analyst
Deep dive information gathering and reconnaissance.
- **Stack**: amass, theHarvester, maltego, spiderfoot, sherlock, maigret, holehe, social-analyzer, shodan, censys

### [2] Bug Bounty Hunter
Web application reconnaissance and vulnerability scanning.
- **Stack**: nuclei, katana, gau, ffuf, burpsuite, sqlmap, dalfox, xsstrike, dirsearch, arjun

### [3] Pentester
Standard network and infrastructure assessment toolkit.
- **Stack**: nmap, masscan, rustscan, impacket, bloodhound, crackmapexec, hashcat, john, seclists

### [4] Red Team Operator
**RESTRICTED USE.** Advanced C2 and adversary emulation.
- **Stack**: metasploit, sliver, empire, HunterX, ligolo-ng, chisel, ansible, terraform, donut, scarecrow
- **HunterX**: Cloned to `/opt/HunterX` with auto-launcher at `/usr/local/bin/HunterX`. Python dependencies installed automatically.

### [5] Blue Team / SOC Analyst
Defense, monitoring, and log analysis.
- **Stack**: wazuh-agent, osquery, velociraptor, sigma-cli, chainsaw, hayabusa, thehive, cortex

### [6] DFIR Analyst
Digital Forensics and Incident Response.
- **Stack**: volatility3, autopsy, sleuthkit, plaso, timesketch, yara, ghidra, radare2, capa

### [7] Threat Intelligence Analyst
Threat data platforms and intelligence tools.
- **Stack**: misp, opencti, yeti, intelmq, threatfox, virustotal-cli, otx-cli
- **Docker Infrastructure**: Optional deployment of full MISP & OpenCTI stack with secure auto-generated credentials.

## Architecture

```
RabbitHole/
├── rabbithole.sh         # Legacy single-file installer (unchanged)
├── bin/
│   └── rabbithole        # New framework entrypoint
├── lib/
│   ├── logging.sh        # Structured & colored logging
│   ├── package_manager.sh # OS detection & base dependency installation
│   ├── helpers.sh        # Native/Go/pipx/Git/Cargo/wget install helpers
│   ├── docker.sh         # Docker Compose stack management
│   ├── plugins.sh        # Plugin discovery & YAML parsing
│   ├── state.sh          # State management (~/.rabbithole/state.json)
│   ├── dependency.sh     # Dependency resolution & tracking
│   └── security.sh       # Secure credential generation & checksums
├── roles/
│   ├── osint/            # OSINT Analyst plugin
│   ├── bugbounty/        # Bug Bounty Hunter plugin
│   ├── pentest/          # Pentester plugin
│   ├── redteam/          # Red Team Operator plugin
│   ├── soc/              # Blue Team / SOC plugin
│   ├── dfir/             # DFIR Analyst plugin
│   └── threatintel/      # Threat Intelligence Analyst plugin
├── config/
│   ├── settings.conf     # User configuration
│   └── rabbit.lock       # Version lock file
├── plugins/              # User/custom plugin directory
├── cache/                # Download cache
├── logs/                 # Log files
├── state/                # State files
├── tests/                # Automated tests (50+ test cases)
├── AGENTS.md             # Developer guide for AI agents and contributors
└── .github/workflows/    # CI/CD (ShellCheck, YAML lint, manifest validation)
```

## Plugin Development

Adding a new role is as simple as creating a directory with a `plugin.yaml` manifest:

```yaml
name: "My Custom Role"
description: "Description of my custom role"
version: "1.0.0"
author: "Your Name"
warning: false
docker: false

native:
  - "toolname/pkgname/pkgname"

go:
  - "toolname github.com/user/toolname@latest"

pipx:
  - "toolname pip-package-name"

git:
  - "toolname https://github.com/user/toolname.git"

cargo:
  - "toolname crate-name"

wget:
  - "toolname https://example.com/toolname-linux-amd64"

custom:
  - "echo 'Custom install command'"

# Optionally provide install.sh for custom logic
```

Place your plugin in either `roles/` (built-in) or `plugins/` (user/custom). The framework discovers plugins automatically.

## Infrastructure & Docker Profiles

For Role [7] (Threat Intel), RabbitHole can deploy a production-grade infrastructure stack using Docker Compose.

**Location**: `/opt/rabbithole/infra/threat-intel/`

### Profiles
| Profile | Services | Description |
| :--- | :--- | :--- |
| `misp` | misp-core, misp-db | Malware Information Sharing Platform |
| `opencti` | opencti, elasticsearch, redis, minio, rabbitmq | Open Cyber Threat Intelligence Platform |

### Management
```bash
cd /opt/rabbithole/infra/threat-intel
docker compose --profile misp --profile opencti up -d
docker compose --profile opencti up -d
```

All credentials are auto-generated with `openssl rand` and stored in a `600`-permission `.env` file. No hardcoded passwords.

## Supply Chain Security

- **SHA256 checksum verification** for downloaded binaries via `verify_sha256()`
- **Pinned versions** in Docker Compose images — no `:latest` except where unavoidable
- **Secure credential generation** via `openssl rand -base64` with configurable length and character sets
- **`.env` files** created with `chmod 600` — not world-readable
- **No hardcoded passwords** — OpenCTI, MISP, MinIO, RabbitMQ, and Elasticsearch credentials are all auto-generated
- **Pinned Git tags and commits** supported in plugin manifests for reproducible builds
- **`eval` avoidance** — commands use explicit argument passing; custom commands are opt-in only
- **Safe path handling** — `sanitize_path_component()` strips dangerous characters from user-provided paths

## Configuration Profiles

Set `RABBIT_PROFILE` in `config/settings.conf`:

| Profile | Description |
|---------|-------------|
| `minimal` | Core tools only |
| `research` | OSINT + DFIR + Threat Intel |
| `lab` | Full lab environment |
| `redteam` | Offensive toolkit |
| `blueteam` | Defensive toolkit |
| `enterprise` | Production-grade deployment |

## Testing

```bash
# Run the full test suite
./tests/test_runner.sh

# Run with verbose output
./tests/test_runner.sh -v
```

The test suite covers:
- Directory structure integrity
- Library module function exports
- Plugin manifest validation (all 7 roles)
- YAML parsing (name, description, version, author fields)
- State management (create, record, read, remove)
- Helper function existence and signatures
- Security module output verification
- Configuration file presence

## Cache Management

```bash
# Build/initialize download cache
rabbithole cache build

# Clean cached downloads
rabbithole cache clean
```

## Benchmarking

```bash
# Run system benchmarks
rabbithole benchmark
```

Reports:
- CPU cores and model
- Memory usage
- Disk I/O speed (dd benchmark)
- Nmap version availability
- Docker engine status

## CI/CD

GitHub Actions in `.github/workflows/ci.yml` run on every push:
- **ShellCheck** — static analysis for all shell scripts
- **Bash syntax validation** — `bash -n` on every `.sh` file and `bin/rabbithole`
- **Plugin manifest validation** — ensures all 7 roles have valid `plugin.yaml` with required fields
- **YAML linting** — `yamllint` on all YAML files
- **State module validation** — verifies Python3 JSON processing integration

## State & Lock Files

**State File**: `~/.rabbithole/state.json`
Tracks:
- Framework version
- Installed roles with timestamps
- Installed tools with method, source, version, exit code
- Docker services

**Lock File**: `config/rabbit.lock`
- Pins tool versions for reproducible installations
- Prevents unintended upgrades when used with `rabbithole --locked`

**Snapshot & Restore**:
```bash
# Export full environment state
rabbithole snapshot > ~/rabbithole-backup-$(date +%Y%m%d).json

# Restore on a different machine
rabbithole restore ~/rabbithole-backup-20260727.json
```

## Developer Guide

See [AGENTS.md](AGENTS.md) for:
- Architecture principles and conventions
- Module API reference
- Plugin YAML specification
- How to add new roles
- Testing and CI/CD workflow

## Legal & Safety Warning

**RabbitHole installs offensive security tools.**

These tools are provided for **educational purposes** and **authorized security testing** only. The authors (NullC0d3) claim no responsibility for any use.

- **Sliver / Empire / Metasploit / HunterX**: These are weapons-grade tools. Do not use on networks you do not own or have explicit permission to test.
- **OPSEC**: This script installs tools globally. It does not configure Tor or VPNs for you. Managing your operational security is your responsibility.

## License

Copyright (C) 2026 **Ahmed Awad (NullC0d3)**

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Credits

**Created & Maintained by Ahmed Awad (NullC0d3)**  
*Copyright (C) 2026 Ahmed Awad. Licensed under Apache 2.0.*

> "Follow the white rabbit."
