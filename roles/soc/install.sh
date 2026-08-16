#!/bin/bash
# Blue Team / SOC Analyst role custom install logic

log_info "Blue Team: Wazuh Agent typically requires repository setup."
log_info "Please add the Wazuh repository manually if the agent is not found."
log_info "See: https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html"

log_info "Blue Team: Velociraptor downloaded via wget to /usr/local/bin"
if command -v velociraptor &> /dev/null; then
    log_ok "Velociraptor available: $(velociraptor --version 2>/dev/null || echo 'version unknown')"
fi





