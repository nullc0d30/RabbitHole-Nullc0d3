#!/bin/bash
# Red Team Operator role custom install logic
# WARNING: This installs weapons-grade offensive security tools.

REDTEAM_BANNER() {
    echo ""
    echo "██████╗ ███████╗██████╗     ████████╗███████╗ █████╗ ███╗   ███╗"
    echo "██╔══██╗██╔════╝██╔══██╗    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║"
    echo "██████╔╝█████╗  ██║  ██║       ██║   █████╗  ███████║██╔████╔██║"
    echo "██╔══██╗██╔══╝  ██║  ██║       ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║"
    echo "██║  ██║███████╗██████╔╝       ██║   ███████╗██║  ██║██║ ╚═╝ ██║"
    echo "╚═╝  ╚═╝╚══════╝╚═════╝        ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝"
    echo ""
}
REDTEAM_BANNER

log_warn "Red Team tools are for AUTHORIZED TESTING ONLY."
log_warn "Do not use these tools on networks you do not own or have explicit permission to test."

# HunterX post-install verification
if [[ -d "/opt/HunterX" ]]; then
    log_ok "HunterX cloned to /opt/HunterX"
    if [[ -f "/opt/HunterX/requirements.txt" ]]; then
        log_task "Installing HunterX Python dependencies..."
        pip3 install -r /opt/HunterX/requirements.txt >> "${RABBIT_LOG_FILE}" 2>&1 || log_warn "HunterX dependency installation encountered issues."
    fi
    # Create executable launcher if not present
    if [[ ! -f "/usr/local/bin/HunterX" ]] && [[ -f "/opt/HunterX/HunterX.py" ]]; then
        cat > /usr/local/bin/HunterX << 'LAUNCHER'
#!/bin/bash
cd /opt/HunterX && python3 HunterX.py "$@"
LAUNCHER
        chmod +x /usr/local/bin/HunterX
        log_ok "HunterX launcher created at /usr/local/bin/HunterX"
    fi
fi

log_info "Red Team installation complete. Exercise extreme caution."
