#!/bin/bash
# DFIR Analyst role custom install logic

log_info "DFIR: Volatility3 installed via pipx from GitHub source."
log_info "DFIR: Capa downloaded via wget to /usr/local/bin/capa"

if command -v capa &> /dev/null; then
    log_ok "Capa available: $(capa --version 2>/dev/null || echo 'version unknown')"
fi

log_info "DFIR: Autopsy may require additional Java dependencies on some distributions."





