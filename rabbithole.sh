#!/bin/bash
# ==============================================================================
# RABBITHOLE
# Universal Cybersecurity Environment Installer
# 
# Author: NullC0d3
# Copyright (C) 2026 NullC0d3. All Rights Reserved.
#
# DESCRIPTION:
# Role-based, opinionated, fast provisioning for Cybersecurity professionals.
# Supports: Debian/Kali/Ubuntu, Fedora, Arch Linux.
#
# ==============================================================================

# ------------------------------------------------------------------------------
# CONFIGURATION & CONSTANTS
# ------------------------------------------------------------------------------
VERSION="1.0.0"
INSTALL_DIR="/opt/rabbithole"
BIN_DIR="/usr/local/bin"
LOG_FILE="./rabbithole_install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# CORE UTILITIES
# ------------------------------------------------------------------------------
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_task() { echo -e "${CYAN}[TASK]${NC} $1"; }

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
    fi
}

function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        VERSION_ID=$VERSION_ID
    else
        log_error "Cannot detect OS. /etc/os-release not found."
    fi

    ARCH=$(uname -m)
    log_info "Detected OS: $OS_NAME ($ARCH)"
    
    case $OS_NAME in
        debian|ubuntu|kali|parrot)
            PKG_MGR="apt"
            INSTALL_CMD="apt-get install -y"
            UPDATE_CMD="apt-get update"
            ;;
        fedora)
            PKG_MGR="dnf"
            INSTALL_CMD="dnf install -y"
            UPDATE_CMD="dnf check-update" # dnf doesn't strictly need explicit update usually but good for cache
            ;;
        arch|manjaro)
            PKG_MGR="pacman"
            INSTALL_CMD="pacman -S --noconfirm --needed"
            UPDATE_CMD="pacman -Sy"
            ;;
        *)
            log_error "Unsupported Distribution: $OS_NAME"
            ;;
    esac
}

function check_connectivity() {
    log_task "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connection detected."
    fi
}

# ------------------------------------------------------------------------------
# INSTALLATION HELPERS
# ------------------------------------------------------------------------------

# $1 = tool name, $2 = deb_pkg, $3 = rpm_pkg, $4 = arch_pkg
function install_native() {
    local tool=$1
    local pkg=""
    
    case $PKG_MGR in
        apt) pkg=$2 ;;
        dnf) pkg=$3 ;;
        pacman) pkg=$4 ;;
    esac

    if [[ -z "$pkg" ]]; then
        log_warn "No native package mapping for $tool on $OS_NAME. Skipping native install."
        return 1
    fi

    log_task "Installing $tool via $PKG_MGR ($pkg)..."
    # Capture output to log, silence stdout unless error
    if $INSTALL_CMD "$pkg" >> "$LOG_FILE" 2>&1; then
        log_ok "$tool installed."
        return 0
    else
        log_warn "Failed to install $tool via native package."
        return 1
    fi
}

function install_go() {
    local tool=$1
    local path=$2
    
    log_task "Installing $tool via Go..."
    # Ensure go bin is in path for the script session
    export PATH=$PATH:/usr/local/go/bin:$(go env GOPATH)/bin:/root/go/bin

    if go install -v "$path" >> "$LOG_FILE" 2>&1; then
        log_ok "$tool installed (Go)."
        # Symlink to global bin if needed
        local gobina=$(go env GOPATH)/bin/$tool
        if [ -f "$gobina" ]; then
            ln -sf "$gobina" "$BIN_DIR/$tool"
        fi
    else
        log_error "Failed to install $tool via Go."
    fi
}

function install_pipx() {
    local tool=$1
    local pkg_name=${2:-$1} # Default to tool name if no pkg name provided
    
    log_task "Installing $tool via pipx..."
    export PATH=$PATH:/root/.local/bin
    if pipx install "$pkg_name" --include-deps --force >> "$LOG_FILE" 2>&1; then
        log_ok "$tool installed (pipx)."
        pipx ensurepath >> "$LOG_FILE" 2>&1
    else
        log_warn "Failed to install $tool via pipx. Trying fallback pip..."
        pip3 install "$pkg_name" >> "$LOG_FILE" 2>&1
    fi
}

function install_git() {
    local tool=$1
    local repo_url=$2
    local install_script=$3 # Optional: command to run after clone

    log_task "Installing $tool via Git..."
    local target_dir="/opt/$tool"
    
    if [ -d "$target_dir" ]; then
        log_warn "$target_dir exists. Pulling latest..."
        cd "$target_dir" && git pull >> "$LOG_FILE" 2>&1
    else
        git clone "$repo_url" "$target_dir" >> "$LOG_FILE" 2>&1
    fi

    if [ -n "$install_script" ]; then
        log_task "Running setup for $tool..."
        cd "$target_dir" || return
        eval "$install_script" >> "$LOG_FILE" 2>&1
    fi
    log_ok "$tool installed (Git)."

    # Make the cloned tool callable from anywhere by symlinking its binary
    rabbit_link_git_bin "$tool"
}

# ------------------------------------------------------------------------------
# PATH RESOLUTION HELPERS (git / cargo / global)
# ------------------------------------------------------------------------------

# Link a binary named $1 found in any of the given directories into $BIN_DIR.
# Returns 0 on success, 1 if no binary was found.
function rabbit_link_bin() {
    local tool=$1
    shift
    local dir
    for dir in "$@"; do
        if [[ -n "$dir" && -f "$dir/$tool" && -x "$dir/$tool" ]]; then
            ln -sf "$dir/$tool" "$BIN_DIR/$tool"
            log_ok "$tool linked into $BIN_DIR"
            return 0
        fi
    done
    return 1
}

# Locate and symlink a Git-cloned tool's executable into $BIN_DIR.
function rabbit_link_git_bin() {
    local tool=$1
    local target_dir="/opt/$tool"

    # 1) Common binary locations
    rabbit_link_bin "$tool" \
        "$target_dir" \
        "$target_dir/bin" \
        "$target_dir/dist" \
        "$target_dir/build" \
        "$target_dir/target/release" \
        "$target_dir/target/debug" \
        "$target_dir/.bin" && return 0

    # 2) Fallback: any executable file named exactly $tool under the repo
    local found
    found=$(find "$target_dir" -type f -name "$tool" -perm -u+x 2>/dev/null | head -n1)
    if [[ -n "$found" ]]; then
        ln -sf "$found" "$BIN_DIR/$tool"
        log_ok "$tool linked into $BIN_DIR"
        return 0
    fi

    log_warn "$tool installed at $target_dir but no binary auto-linked; add its bin dir to PATH manually if needed."
    return 1
}

# Install a Rust/Cargo tool and symlink its binary into $BIN_DIR.
# $1 = tool name, remaining args = cargo install arguments (defaults to $1).
function install_cargo() {
    local tool=$1
    shift
    local cargo_args="${*:-$tool}"

    if ! command -v cargo &> /dev/null; then
        log_warn "Cargo not available. Skipping $tool."
        return 1
    fi

    log_task "Installing $tool via Cargo..."
    if cargo install $cargo_args >> "$LOG_FILE" 2>&1; then
        rabbit_link_bin "$tool" "/root/.cargo/bin" "$HOME/.cargo/bin" && \
            log_ok "$tool installed (Cargo)." || \
            log_warn "$tool built but not auto-linked; ensure ~/.cargo/bin is on PATH."
        return 0
    else
        log_warn "Failed to install $tool via Cargo."
        return 1
    fi
}

# Persist RabbitHole tool directories on PATH for the current session and for
# all future login shells (via /etc/profile.d), so installed tools are callable
# from anywhere regardless of install method.
function rabbit_ensure_path() {
    export PATH="$PATH:$BIN_DIR:/root/.cargo/bin:$HOME/.cargo/bin:/root/.local/bin:$HOME/.local/bin"

    local prof="/etc/profile.d/rabbithole.sh"
    if [[ ! -f "$prof" ]]; then
        cat > "$prof" <<'EOF'
# RabbitHole PATH additions
export PATH="$PATH:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin"
EOF
        chmod 644 "$prof"
        log_ok "Persisted RabbitHole PATH in $prof"
    fi
}

# ------------------------------------------------------------------------------
# BASE DEPENDENCIES
# ------------------------------------------------------------------------------
function install_base_deps() {
    log_info "Installing Base Dependencies..."
    
    # Update Repos
    $UPDATE_CMD >> "$LOG_FILE" 2>&1

    # Generic map: tool apt dnf pacman
    install_native "git" "git" "git" "git"
    install_native "curl" "curl" "curl" "curl"
    install_native "wget" "wget" "wget" "wget"
    
    # Python
    install_native "python3" "python3" "python3" "python"
    install_native "pip" "python3-pip" "python3-pip" "python-pip"
    install_native "pipx" "pipx" "pipx" "python-pipx" # Arch often needs python-pipx

    # Golang
    install_native "golang" "golang-go" "golang" "go"

    # Docker (Optional but required by some tools)
    install_native "docker" "docker.io" "docker" "docker"
    
    # Ensure pipx works
    pipx ensurepath >> "$LOG_FILE" 2>&1
    export PATH=$PATH:/root/.local/bin
}

# ------------------------------------------------------------------------------
# ROLE INSTALLERS
# ------------------------------------------------------------------------------

function install_osint() {
    log_info ">>> Installing OSINT Analyst Tools..."
    
    # Go Tools
    install_go "amass" "github.com/owasp-amass/amass/v4/...@master"
    install_go "subfinder" "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    install_go "assetfinder" "github.com/tomnomnom/assetfinder@latest"
    install_go "dnsx" "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    install_go "httpx" "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    
    # Python/Pipx
    install_pipx "theHarvester" "git+https://github.com/laramies/theHarvester.git"
    install_pipx "shodan" "shodan"
    install_pipx "censys" "censys"
    install_pipx "sherlock" "sherlock-project"
    install_pipx "maigret" "maigret"
    install_pipx "holehe" "holehe"
    install_pipx "social-analyzer" "social-analyzer"
    install_pipx "spiderfoot" "spiderfoot"

    # Native/Manual
    install_native "tor" "tor" "tor" "tor"

    # Maltego (Complex)
    if [[ "$PKG_MGR" == "apt" ]]; then
        install_native "maltego" "maltego" "" "" || log_task "Maltego not in repo. Please install manually from Website."
    else
        log_warn "Maltego requires manual installation on this OS."
    fi
}

function install_bugbounty() {
    log_info ">>> Installing Bug Bounty Hunter Tools..."
    
    # Overlaps from OSINT
    install_go "amass" "github.com/owasp-amass/amass/v4/...@master"
    install_go "subfinder" "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    install_go "assetfinder" "github.com/tomnomnom/assetfinder@latest"
    install_go "httpx" "github.com/projectdiscovery/httpx/cmd/httpx@latest"

    # BB Specific
    install_go "nuclei" "github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest"
    install_go "katana" "github.com/projectdiscovery/katana/cmd/katana@latest"
    install_go "gau" "github.com/lc/gau/v2/cmd/gau@latest"
    install_go "waybackurls" "github.com/tomnomnom/waybackurls@latest"
    install_go "ffuf" "github.com/ffuf/ffuf/v2@latest"
    install_go "dalfox" "github.com/hahwul/dalfox/v2@latest"
    
    # Python
    install_pipx "dirsearch" "dirsearch"
    install_pipx "xsstrike" "git+https://github.com/s0md3v/XSStrike.git"
    install_pipx "arjun" "arjun"
    
    # Native
    install_native "sqlmap" "sqlmap" "sqlmap" "sqlmap"
    
    # Burp Suite (Community)
    if [[ "$OS_NAME" == "kali" ]]; then
        install_native "burpsuite" "burpsuite" "" ""
    else 
        log_warn "Burp Suite Community: Manual download required for $OS_NAME."
    fi
}

function install_pentester() {
    log_info ">>> Installing Pentester Tools..."
    
    install_native "nmap" "nmap" "nmap" "nmap"
    install_native "masscan" "masscan" "masscan" "masscan"
    
    # Rustscan via cargo (symlinked to PATH) or native fallback
    if command -v cargo &> /dev/null; then
        install_cargo "rustscan" "rustscan"
    else
        # Try native (kali has it)
        install_native "rustscan" "rustscan" "rustscan" "rustscan" || log_warn "Install Rust/Cargo for rustscan."
    fi

    install_native "netcat" "netcat-traditional" "nmap-ncat" "gnu-netcat"
    install_pipx "impacket" "impacket"
    install_pipx "crackmapexec" "git+https://github.com/Pennyw0rth/NetExec.git"
    
    # Bloodhound (Ingestors usually via method, GUI via apt)
    install_native "bloodhound" "bloodhound" "bloodhound" "bloodhound"
    
    install_native "aircrack-ng" "aircrack-ng" "aircrack-ng" "aircrack-ng"
    install_native "kismet" "kismet" "kismet" "kismet"
    install_native "hashcat" "hashcat" "hashcat" "hashcat"
    install_native "john" "john" "john" "john"
    
    # Seclists
    install_native "seclists" "seclists" "seclists" "seclists" || \
    install_git "seclists" "https://github.com/danielmiessler/SecLists.git"
}

function install_redteam() {
    log_info ">>> Installing Red Team Operator Tools..."
    
    # Metasploit
    install_native "metasploit-framework" "metasploit-framework" "metasploit" "metasploit" || \
    (curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod 755 msfinstall && ./msfinstall)

    # C2 Frameworks & Tools
    install_git "sliver" "https://github.com/BishopFox/sliver.git" "make"
    install_git "empire" "https://github.com/BC-SECURITY/Empire.git" "./setup/install.sh"
    install_go "donut" "github.com/TheWover/donut@latest" # Sometimes fails, binary preferred
    install_go "scarecrow" "github.com/optiv/ScareCrow@latest"
    install_go "ligolo-ng" "github.com/nicocha30/ligolo-ng@latest"
    install_go "chisel" "github.com/jpillora/chisel@latest"
    
    install_git "HunterX" "https://github.com/nullc0d30/HunterX.git" "pip3 install -r requirements.txt"

    install_native "ansible" "ansible" "ansible" "ansible"
    install_native "terraform" "terraform" "terraform" "terraform"
}

function install_blueteam() {
    log_info ">>> Installing Blue Team / SOC Analyst Tools..."
    
    # Agents/Analysers
    # Wazuh usually requires adding repo. Just installing dependencies if no repo.
    install_native "wazuh-agent" "wazuh-agent" "wazuh-agent" "wazuh-agent" || log_warn "Wazuh Agent: Repo setup skipped. Please add Wazuh repo."

    install_native "osquery" "osquery" "osquery" "osquery"
    
    # Velociraptor (Just binary)
    if [ ! -f "$BIN_DIR/velociraptor" ]; then
        log_task "Downloading Velociraptor..."
        wget https://github.com/Velocidex/velociraptor/releases/latest/download/velociraptor-v0.77.2-linux-amd64 -O "$BIN_DIR/velociraptor"
        chmod +x "$BIN_DIR/velociraptor"
    fi

    install_pipx "sigma-cli" "sigma-cli"
    
    # Chainsaw (Rust) — git-based cargo install, then symlinked to PATH
    if command -v cargo &> /dev/null; then
        install_cargo "chainsaw" "--git https://github.com/WithSecureLabs/chainsaw"
    fi

    # TheHive/Cortex/Hayabusa: Often simpler to just Git Clone for analysis
    install_git "hayabusa" "https://github.com/Yamato-Security/hayabusa.git"
    install_git "thehive" "https://github.com/TheHive-Project/TheHive.git" # Source only
    install_git "cortex" "https://github.com/TheHive-Project/Cortex.git" # Source only

    install_native "jq" "jq" "jq" "jq"
    install_native "yq" "yq" "yq" "yq"
}

function install_dfir() {
    log_info ">>> Installing DFIR Analyst Tools..."
    install_pipx "volatility3" "git+https://github.com/volatilityfoundation/volatility3.git"
    install_pipx "rekall" "rekall-agent"
    install_native "autopsy" "autopsy" "autopsy" "autopsy"
    install_native "sleuthkit" "sleuthkit" "sleuthkit" "sleuthkit"
    install_native "plaso" "plaso-tools" "plaso" "plaso"
    install_pipx "timesketch" "timesketch"
    install_native "yara" "yara" "yara" "yara"
    
    install_pipx "capa" "capa"

    install_native "ghidra" "ghidra" "ghidra" "ghidra"
    install_native "radare2" "radare2" "radare2" "radare2"
    install_pipx "aleapp" "aleapp"
    install_git "ileapp" "https://github.com/abrignoni/iLEAPP.git" "pip install -r requirements.txt"
}

function deploy_threat_stack() {
    log_info ">>> Initiating Threat Intelligence Infrastructure Deployment..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is required for this stack but not found. Please install Docker first."
    fi

    local stack_dir="/opt/rabbithole/infra/threat-intel"
    mkdir -p "$stack_dir"
    
    # Generate Secrets
    local minio_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    local rabbit_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    local elastic_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    local opencti_token=$(cat /proc/sys/kernel/random/uuid)
    local misp_mysql_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

    log_task "Generating .env configuration at $stack_dir/.env"
    cat <<EOF > "$stack_dir/.env"
OPENCTI_ADMIN_EMAIL=admin@rabbithole.local
OPENCTI_ADMIN_PASSWORD=ChangeMePlease!
OPENCTI_ADMIN_TOKEN=${opencti_token}
OPENCTI_BASE_URL=http://localhost:8080
MINIO_ROOT_USER=opencti
MINIO_ROOT_PASSWORD=${minio_pass}
RABBITMQ_DEFAULT_USER=opencti
RABBITMQ_DEFAULT_PASS=${rabbit_pass}
ELASTIC_MEMORY_MAP_THRESHOLD=262144
ELASTIC_PASSWORD=${elastic_pass}
MISP_MYSQL_PASSWORD=${misp_mysql_pass}
EOF

    log_task "Writing Docker Compose Manifest..."
    cat <<EOF > "$stack_dir/docker-compose.yml"
version: '3'

profiles:
  - misp
  - opencti

services:
  # --------------------------------------------------------------------------
  # OPENCTI STACK (Profile: opencti)
  # --------------------------------------------------------------------------
  redis:
    image: redis:7.2.4
    restart: always
    profiles: ["opencti"]
    volumes:
      - redis_data:/data

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.3
    volumes:
      - es_data:/usr/share/elasticsearch/data
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=\${ELASTIC_PASSWORD}
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    restart: always
    profiles: ["opencti"]

  minio:
    image: minio/minio:RELEASE.2024-01-13T21-38-02Z
    volumes:
      - minio_data:/data
    environment:
      - MINIO_ROOT_USER=\${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=\${MINIO_ROOT_PASSWORD}
    command: server /data
    restart: always
    profiles: ["opencti"]

  rabbitmq:
    image: rabbitmq:3.12-management
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    environment:
      - RABBITMQ_DEFAULT_USER=\${RABBITMQ_DEFAULT_USER}
      - RABBITMQ_DEFAULT_PASS=\${RABBITMQ_DEFAULT_PASS}
    restart: always
    profiles: ["opencti"]

  opencti:
    image: opencti/platform:6.1.4
    environment:
      - NODE_OPTIONS=--max-old-space-size=8096
      - APP__ADMIN__EMAIL=\${OPENCTI_ADMIN_EMAIL}
      - APP__ADMIN__PASSWORD=\${OPENCTI_ADMIN_PASSWORD}
      - APP__ADMIN__TOKEN=\${OPENCTI_ADMIN_TOKEN}
      - REDIS__HOSTNAME=redis
      - REDIS__PORT=6379
      - ELASTICSEARCH__URL=http://elasticsearch:9200
      - ELASTICSEARCH__USERNAME=elastic
      - ELASTICSEARCH__PASSWORD=\${ELASTIC_PASSWORD}
      - MINIO__ENDPOINT=minio
      - MINIO__PORT=9000
      - MINIO__USE_SSL=false
      - MINIO__ACCESS_KEY=\${MINIO_ROOT_USER}
      - MINIO__SECRET_KEY=\${MINIO_ROOT_PASSWORD}
      - RABBITMQ__HOSTNAME=rabbitmq
      - RABBITMQ__PORT=5672
      - RABBITMQ__PORT_MANAGEMENT=15672
      - RABBITMQ__MANAGEMENT_SSL=false
      - RABBITMQ__USERNAME=\${RABBITMQ_DEFAULT_USER}
      - RABBITMQ__PASSWORD=\${RABBITMQ_DEFAULT_PASS}
    ports:
      - "8080:8080"
    depends_on:
      - redis
      - elasticsearch
      - minio
      - rabbitmq
    restart: always
    profiles: ["opencti"]

  # --------------------------------------------------------------------------
  # MISP STACK (Profile: misp)
  # --------------------------------------------------------------------------
  misp-db:
    image: mysql:8.0
    restart: always
    environment:
      - MYSQL_DATABASE=misp
      - MYSQL_USER=misp
      - MYSQL_PASSWORD=\${MISP_MYSQL_PASSWORD}
      - MYSQL_ROOT_PASSWORD=\${MISP_MYSQL_PASSWORD}
    volumes:
      - misp_db:/var/lib/mysql
    profiles: ["misp"]

  misp-core:
    image: ghcr.io/misp/misp-docker/misp-core:latest
    restart: always
    depends_on:
      - misp-db
    environment:
      - MYSQL_HOST=misp-db
      - MYSQL_USER=misp
      - MYSQL_PASSWORD=\${MISP_MYSQL_PASSWORD}
      - MISP_BASEURL=http://localhost:8443
      - MISP_ADMIN_EMAIL=admin@admin.test
      - MISP_ADMIN_PASSPHRASE=admin
    ports:
      - "8443:443"
      - "8081:80"
    volumes:
      - misp_web:/var/www/MISP
    profiles: ["misp"]

volumes:
  es_data:
  minio_data:
  redis_data:
  rabbitmq_data:
  misp_db:
  misp_web:

EOF
    
    log_ok "Docker Compose stack generated at $stack_dir"
    log_info "To launch OpenCTI:   cd $stack_dir && docker compose --profile opencti up -d"
    log_info "To launch MISP:      cd $stack_dir && docker compose --profile misp up -d"
    log_info "To launch ALL:       cd $stack_dir && docker compose --profile misp --profile opencti up -d"
    
    # Optional auto-launch
    read -p "Do you want to launch the FULL stack now? (y/N): " launch
    if [[ "$launch" =~ ^[Yy]$ ]]; then
        cd "$stack_dir" || return
        log_task "Starting services (this may take a while)..."
        docker compose --profile misp --profile opencti up -d
        log_ok "Services started."
    fi
}

function install_threatintel() {
    log_info ">>> Installing Threat Intelligence Analyst Tools..."
    
    # Specialized stack. Usually web apps. Installing repos/clients.
    install_git "misp-modules" "https://github.com/MISP/misp-modules.git"
    install_git "opencti" "https://github.com/OpenCTI-Platform/opencti.git" # Keep repo for reference tools
    install_native "intelmq" "intelmq" "intelmq" "intelmq"
    install_git "yeti" "https://github.com/yeti-platform/yeti.git"
    
    # Clients
    install_pipx "threatfox" "threatfox"
    install_pipx "otx-cli" "OTXv2"
    install_pipx "vt-cli" "vt-py"
    install_pipx "abuseipdb" "abuseipdb"
    
    echo ""
    log_info "[INFRASTRUCTURE]"
    read -p "Deploy MISP & OpenCTI Docker Cluster? (y/N): " want_docker
    if [[ "$want_docker" =~ ^[Yy]$ ]]; then
        deploy_threat_stack
    else
        log_info "Skipping Docker infra."
    fi
}

# ------------------------------------------------------------------------------
# MAIN LOGIC
# ------------------------------------------------------------------------------
clear
echo -e "${RED}"
echo "    █▀▀█ █▀▀█ █▀▀▄ █▀▀▄ ▀█▀ ▀▀█▀▀ █   █ █▀▀█ █   █▀▀"
echo "    █▄▄▀ █▄▄█ █▀▀▄ █▀▀▄  █    █   █▀▀▄█ █  █ █   █▀▀"
echo "    ▀  ▀ ▀  ▀ ▀▀▀  ▀▀▀  ▀▀▀   ▀   ▀   ▀ ▀▀▀▀ ▀▀▀ ▀▀▀"
echo "                  By NULLC0D3"
echo "         Universal Cybersecurity Environment Installer"
echo -e "${NC}"
echo "------------------------------------------------------------"

check_root
detect_os
check_connectivity
install_base_deps
rabbit_ensure_path

echo ""
echo "SELECT YOUR ROLE(S):"
echo "[1] OSINT Analyst"
echo "[2] Bug Bounty Hunter"
echo "[3] Pentester"
echo "[4] Red Team Operator (WARNING: OFFENSIVE)"
echo "[5] Blue Team / SOC Analyst"
echo "[6] DFIR Analyst"
echo "[7] Threat Intelligence Analyst"
echo ""
echo "Enter choices separated by space (e.g., '1 3 5') or 'A' for All:"
read -p "> " choices

if [[ "$choices" =~ "A" ]] || [[ "$choices" =~ "a" ]]; then
    choices="1 2 3 4 5 6 7"
fi

for choice in $choices; do
    case $choice in
        1) install_osint ;;
        2) install_bugbounty ;;
        3) install_pentester ;;
        4) 
            echo -e "${RED}!!! WARNING !!!${NC}"
            echo "You have selected RED TEAM OPERATOR."
            echo "These tools are for authorized testing only."
            read -p "Are you sure? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                install_redteam
            else
                log_info "Skipping Red Team Role."
            fi
            ;;
        5) install_blueteam ;;
        6) install_dfir ;;
        7) install_threatintel ;;
    esac
done

# ------------------------------------------------------------------------------
# FINALIZATION
# ------------------------------------------------------------------------------
echo ""
log_ok "Installation Procedure Complete."
log_info "Tools installed in: $INSTALL_DIR or System Path"
log_info "Please restart your terminal or source your profile."
log_info "Log file: $LOG_FILE"
echo ""
echo "NullC0d3 RabbitHole - Disengage."
