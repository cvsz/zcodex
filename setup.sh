#!/usr/bin/env bash
# Codex-Max setup script for Codex Cloud / Ubuntu runners.
# Installs baseline tools safely and avoids unnecessary runtime mutation.

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

LOG_PREFIX="[Codex-Max Setup]"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
INSTALL_SECURITY_TOOLS="${INSTALL_SECURITY_TOOLS:-false}"
UPGRADE_NPM="${UPGRADE_NPM:-false}"

log() {
  printf '%s %s\n' "${LOG_PREFIX}" "$*"
}

warn() {
  printf '%s WARN: %s\n' "${LOG_PREFIX}" "$*" >&2
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

apt_install_baseline() {
  if [[ "${EUID}" -ne 0 ]]; then
    warn "Skipping apt install because script is not running as root."
    return 0
  fi

  log "Updating apt metadata..."
  apt-get update -y

  log "Installing baseline packages..."
  apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    build-essential \
    python3 \
    python3-pip

  apt-get clean
  rm -rf /var/lib/apt/lists/*
}

configure_git() {
  log "Configuring git safety defaults..."
  git config --global init.defaultBranch main || true
  git config --global pull.rebase false || true
  git config --global --add safe.directory "${WORKSPACE_DIR}" || true
}

configure_npm() {
  if ! have_cmd npm; then
    warn "npm not found; skipping npm configuration."
    return 0
  fi

  log "Configuring npm for CI-friendly output..."
  npm config set fund false --location=global || true
  npm config set audit false --location=global || true
  npm config set progress false --location=global || true

  # Some Codex/CI images expose uppercase/lowercase proxy env vars that npm warns about.
  # Preserve proxy functionality while normalizing npm config keys when present.
  if [[ -n "${HTTP_PROXY:-}" ]]; then
    npm config set proxy "${HTTP_PROXY}" --location=global || true
  elif [[ -n "${http_proxy:-}" ]]; then
    npm config set proxy "${http_proxy}" --location=global || true
  fi

  if [[ -n "${HTTPS_PROXY:-}" ]]; then
    npm config set https-proxy "${HTTPS_PROXY}" --location=global || true
  elif [[ -n "${https_proxy:-}" ]]; then
    npm config set https-proxy "${https_proxy}" --location=global || true
  fi

  if [[ "${UPGRADE_NPM}" == "true" ]]; then
    log "UPGRADE_NPM=true; upgrading npm explicitly..."
    npm install -g npm@latest
  else
    log "Skipping npm self-upgrade. Set UPGRADE_NPM=true to enable."
  fi
}

install_security_tools() {
  if [[ "${INSTALL_SECURITY_TOOLS}" != "true" ]]; then
    log "Skipping optional security tools. Set INSTALL_SECURITY_TOOLS=true to enable."
    return 0
  fi

  log "Installing optional Python-based security tooling..."
  if have_cmd python3; then
    python3 -m pip install --user --upgrade pip || true
    python3 -m pip install --user semgrep pip-audit || true
  else
    warn "python3 missing; cannot install Python security tools."
  fi
}

print_versions() {
  log "Runtime versions:"
  for cmd in bash git curl jq python3 pip3 node npm; do
    if have_cmd "${cmd}"; then
      printf '  - %s: ' "${cmd}"
      case "${cmd}" in
        bash) bash --version | head -n 1 ;;
        python3) python3 --version ;;
        pip3) pip3 --version ;;
        *) "${cmd}" --version 2>/dev/null | head -n 1 || true ;;
      esac
    else
      printf '  - %s: missing\n' "${cmd}"
    fi
  done
}

main() {
  log "Initializing environment..."

  apt_install_baseline

  if ! have_cmd node; then
    warn "Node.js not found in image. Install through Codex language runtime settings if Node is required."
  fi

  if ! have_cmd python3; then
    warn "Python 3 not found after setup. Check base image/runtime settings."
  fi

  configure_npm
  configure_git
  install_security_tools

  export SHELL=/bin/bash
  mkdir -p "${WORKSPACE_DIR}"
  cd "${WORKSPACE_DIR}"

  print_versions
  log "Environment ready at ${WORKSPACE_DIR}"
}

main "$@"
