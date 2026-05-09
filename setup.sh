#!/usr/bin/env bash
set -euo pipefail

# SETUP SCRIPT (ONE-TIME INIT)

log() { echo "[setup] $1"; }

log "Installing dependencies"
# npm install
# pip install -r requirements.txt

log "Configuring git"
# git config --global user.name "zcodex"
# git config --global user.email "dev@local"

log "GitHub authentication"
# gh auth login

log "Project initialization complete"
