# RabbitHole 🐇

> **Universal Cybersecurity Environment Installer**  
> *Role-based. Opinionated. Production-Ready.*

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg) ![License](https://img.shields.io/badge/license-Proprietary-red.svg) ![Author](https://img.shields.io/badge/made%20by-NullC0d3-000000.svg)

## 💀 Overview

**RabbitHole** is a single-file, specialized installer script designed for cybersecurity practitioners who need to provision a combat-ready environment in minutes, not hours. 

It is **NOT** a framework. It is **NOT** a package manager wrapper.  
It **IS** a tactical provisioning tool that installs curated toolsets based on your specific operational role.

### ⚡ Key Features
- **Distro Agnostic**: Auto-detects and adapts to Debian/Kali/Ubuntu, Fedora, and Arch Linux.
- **Role-Driven**: Select only the tools you need for your mission.
- **Zero-Bloat**: No background services, no telemetry, no Docker layers (unless a tool specifically demands it).
- **Fast**: Prioritizes native binary installs (`go install`, `pipx`) over source builds required.

---

## 🚀 Installation & Usage

### Prerequisites
- A Linux-based Operating System (Kali, Ubuntu, Debian, Fedora, Arch)
- Root privileges (`sudo`)
- Internet connection

### Quick Start

1. **Download** the script:
   ```bash
   wget https://github.com/NullC0d3/rabbithole/raw/main/rabbithole.sh
   # OR
   git clone https://github.com/NullC0d3/rabbithole.git
   cd rabbithole
   ```

2. **Make Executable**:
   ```bash
   chmod +x rabbithole.sh
   ```

3. **Execute**:
   ```bash
   sudo ./rabbithole.sh
   ```

4. **Follow the On-Screen Menu** to select your role(s).

---

## 🎭 Operational Roles

RabbitHole organizes tools into strictly defined operational roles. You can install multiple roles simultaneously.

### 🕵️ [1] OSINT Analyst
Deep dive information gathering and reconnaissance.
- **Stack**: `amass`, `theHarvester`, `maltego`, `spiderfoot`, `sherlock`, `maigret`, `holehe`, `social-analyzer`...

### 🐛 [2] Bug Bounty Hunter
Web application focuses reconnaissance and vulnerability scanning.
- **Stack**: `nuclei`, `katana`, `gau`, `ffuf`, `burpsuite`, `sqlmap`, `dalfox`, `xsstrike`...

### ⚔️ [3] Pentester
Standard network and infrastructure assessment toolkit.
- **Stack**: `nmap`, `masscan`, `rustscan`, `impacket`, `bloodhound`, `crackmapexec`, `hashcat`, `john`...

### 🚩 [4] Red Team Operator
**⚠️ RESTRICTED USE.** Advanced C2 and adversary emulation.  
*Requires explicit confirmation during install.*
- **Stack**: `metasploit`, `sliver`, `empire`, `starkiller`, `ligolo-ng`, `chisel`, `ansible`, `terraform`...

### 🛡️ [5] Blue Team / SOC Analyst
Defense, monitoring, and log analysis.
- **Stack**: `wazuh-agent`, `osquery`, `velociraptor`, `sigma-cli`, `chainsaw`, `hayabusa`...

### 🔎 [6] DFIR Analyst
Digital Forensics and Incident Response.
- **Stack**: `volatility3`, `autopsy`, `sleuthkit`, `plaso`, `timesketch`, `yara`, `ghidra`...

### 📡 [7] Threat Intelligence Analyst
Threat data visualizers and intelligence platforms.
- **Stack**: `misp`, `opencti`, `yeti`, `threatfox`, `virustotal-cli`, `otx-cli`...
- **Docker Infrastructure**: Optional deployment of full MISP & OpenCTI stack.

---

## 🏗️ Infrastructure & Docker Profiles

For Role [7] (Threat Intel), RabbitHole can deploy a production-grade infrastructure stack using Docker Compose.

**Location**: `/opt/rabbithole/infra/threat-intel/`

### Profiles
The stack uses Docker Profiles for modular resource management:

| Profile | Services | Description |
| :--- | :--- | :--- |
| `misp` | `misp-core`, `misp-db` | Malware Information Sharing Platform |
| `opencti` | `opencti`, `elasticsearch`, `redis`, `minio`, `rabbitmq` | Open Cyber Threat Intelligence Platform |

### Managing the Stack
```bash
cd /opt/rabbithole/infra/threat-intel

# Launch everything
docker compose --profile misp --profile opencti up -d

# Launch specific platform
docker compose --profile opencti up -d
```

**Note**: RabbitHole automatically generates secure secrets in `.env` during installation.

---

## ⚠️ Legal & Safety Warning

**RabbitHole installs offensive security tools.**  

These tools are provided for **educational purposes** and **authorized security testing** only. The authors (NullC0d3) claim no responsibility for any use.
- **Sliver / Empire / Metasploit**: These are weapons-grade tools. Do not use on networks you do not own or have explicit permission to test.
- **OPSEC**: This script installs tools globally. It does not configure Tor or VPNs for you. managing your operational security is your responsibility.

---

## 👨‍💻 Credits

**Created & Maintained by NullC0d3**  
*Copyright © 2026 NullC0d3. All Rights Reserved.*

> "Follow the white rabbit." 🐇
