# scripts/codex-installer-final.sh
#!/usr/bin/env bash
# FINAL RELEASE (installer + runtime auto-heal)
# - Works when run via `bash` (persists PATH) and `source` (immediate PATH)
# - No npm global to /usr (fixes EACCES)
# - nvm strict-safe (handles set -u)
# - Deterministic PATH (no `npm bin -g`)
# - Creates stable shim: ~/.local/bin/codex (no need to source nvm)
# - Idempotent + retry + verbose-safe

set -Eeuo pipefail

LOG_FILE="${HOME}/codex-installer-final.log"
exec > >(tee -a "$LOG_FILE") 2>&1

########################################
# CONFIG
########################################
NVM_VERSION="v0.39.7"
NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
NVM_DIR="${HOME}/.nvm"
TMP_NVM="/tmp/nvm-install.sh"
PACKAGES=("@openai/codex" "pm2" "pnpm")
LOCAL_BIN="${HOME}/.local/bin"

########################################
# UTILS
########################################
log(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERROR] $*" >&2; }

retry(){
  local n=0 max=3 delay=2
  until "$@"; do
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      err "Failed: $*"
      return 1
    fi
    warn "Retry $n/$max..."
    sleep "$delay"
  done
}

########################################
# PRECHECK
########################################
precheck(){
  log "Preflight..."
  for p in curl git; do
    command -v "$p" >/dev/null || {
      warn "$p missing → installing"
      sudo apt-get update -y
      sudo apt-get install -y "$p"
    }
  done
}

########################################
# INSTALL / HEAL NVM
########################################
install_nvm(){
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    log "NVM OK"
    return
  fi
  warn "Installing NVM..."
  retry curl -fsSL "$NVM_URL" -o "$TMP_NVM"
  bash "$TMP_NVM"
}

########################################
# LOAD NVM (STRICT-SAFE)
########################################
load_nvm(){
  export NVM_DIR
  set +u
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  set -u

  command -v nvm >/dev/null || {
    err "nvm load failed"
    exit 1
  }
}

########################################
# INSTALL NODE (LTS)
########################################
install_node(){
  log "Ensuring Node LTS..."
  set +u
  nvm install --lts >/dev/null 2>&1 || nvm install --lts
  nvm use --lts
  nvm alias default lts/*
  set -u
}

########################################
# FIX NPM PREFIX (no /usr)
########################################
fix_prefix(){
  local p
  p="$(npm config get prefix || true)"
  if [[ "$p" == "/usr"* ]] || [[ "$p" == "undefined" ]]; then
    warn "Fixing npm prefix"
    npm config delete prefix || true
  fi
}

########################################
# FIX PERMISSIONS
########################################
fix_permissions(){
  local dir
  dir="$(npm root -g)"
  if [ ! -w "$dir" ]; then
    warn "Fixing permission on $dir"
    sudo chown -R "$(whoami)":"$(whoami)" "$dir"
  fi
  mkdir -p "$HOME/.npm"
  sudo chown -R "$(whoami)":"$(whoami)" "$HOME/.npm"
}

########################################
# INSTALL GLOBAL PACKAGES (user-space)
########################################
install_packages(){
  log "Installing global packages..."
  for pkg in "${PACKAGES[@]}"; do
    log "→ $pkg"
    retry npm i -g "$pkg"
  done
}

########################################
# PATH + SHIM (CRITICAL)
########################################
ensure_local_bin_in_path(){
  mkdir -p "$LOCAL_BIN"

  # Persist ~/.local/bin in PATH (idempotent)
  if ! grep -q 'export PATH=$HOME/.local/bin:$PATH' "$HOME/.bashrc"; then
    echo 'export PATH=$HOME/.local/bin:$PATH' >> "$HOME/.bashrc"
  fi

  # Apply to current shell as well
  export PATH="$LOCAL_BIN:$PATH"
}

create_codex_shim(){
  log "Creating stable codex shim..."

  local node_bin="$NVM_DIR/versions/node/$(node -v)/bin"
  local target="$node_bin/codex"
  local shim="$LOCAL_BIN/codex"

  if [ ! -x "$target" ]; then
    err "codex binary not found at $target"
    return 1
  fi

  ln -sf "$target" "$shim"
  chmod +x "$shim"

  log "Shim → $shim -> $target"
}

########################################
# OPTIONAL: ALSO EXPORT NODE BIN FOR CURRENT SHELL
########################################
export_node_bin_now(){
  local node_bin="$NVM_DIR/versions/node/$(node -v)/bin"
  export PATH="$node_bin:$PATH"
}

########################################
# VERIFY
########################################
verify(){
  log "Verifying..."
  echo "Node : $(node -v)"
  echo "NPM  : $(npm -v)"

  if ! command -v codex >/dev/null; then
    warn "codex not in PATH → attempting heal via shim"
    ensure_local_bin_in_path
  fi

  command -v codex >/dev/null || {
    err "codex not found after heal"
    return 1
  }

  echo "Codex: $(codex --version)"
  echo "Path : $(which codex)"
}

########################################
# SHELL MODE NOTICE
########################################
shell_notice(){
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log "Detected: sourced → PATH applied to current shell"
  else
    warn "Executed via bash → current shell PATH unchanged"
    echo "👉 Open a new shell OR run:"
    echo "   source ~/.bashrc"
    echo "👉 Or run installer as:"
    echo "   source scripts/codex-installer-final.sh"
  fi
}

########################################
# MAIN
########################################
main(){
  log "===== FINAL INSTALLER START ====="

  precheck
  install_nvm
  load_nvm
  install_node
  fix_prefix
  fix_permissions
  install_packages

  ensure_local_bin_in_path
  export_node_bin_now
  create_codex_shim

  if ! verify; then
    warn "Healing retry..."
    fix_prefix
    fix_permissions
    install_packages
    create_codex_shim
    verify || exit 1
  fi

  shell_notice
  log "===== SUCCESS ====="
}

main "$@"
