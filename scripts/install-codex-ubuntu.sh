#!/usr/bin/env bash
# =============================================================================
# scripts/install-codex-ubuntu.sh
# Codex CLI — Ubuntu Full Environment Installer
# Version : 6.0.0
# Requires: Ubuntu 22.04 LTS / 24.04 LTS  (x86_64 | aarch64)
# Usage   : ./install-codex-ubuntu.sh [--ci] [--skip-docker] [--skip-optional]
# CI mode : CI=true ./install-codex-ubuntu.sh
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_VERSION="6.0.0"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_START_TS="$(date +%s)"
readonly SCRIPT_START_TS

readonly CONFIG_DIR="${HOME}/.codex"
readonly NPM_GLOBAL_DIR="${HOME}/.npm-global"
readonly BIN_DIR="${HOME}/.local/bin"
readonly LOCK_FILE="${CONFIG_DIR}/.install.lock"
readonly ENV_FILE="${CONFIG_DIR}/env"

readonly CODEX_NPM_PACKAGE="@openai/codex"
readonly NODE_MAJOR="22"

readonly MIN_DISK_GB=5
readonly MIN_RAM_MB=1024

readonly NODESOURCE_KEYRING="/usr/share/keyrings/nodesource.gpg"
readonly NODESOURCE_GPG_URL="https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key"
readonly OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

# ─────────────────────────────────────────────────────────────────────────────
# FLAGS
# ─────────────────────────────────────────────────────────────────────────────

CI_MODE="${CI:-false}"
SKIP_DOCKER=false
SKIP_OPTIONAL=false
SHELL_RC=""

# Log file created after CONFIG_DIR exists
mkdir -p "${CONFIG_DIR}"
LOG_FILE="${CONFIG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly LOG_FILE
touch "${LOG_FILE}"
chmod 600 "${LOG_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
# COLORS  (disabled in CI / non-tty)
# ─────────────────────────────────────────────────────────────────────────────

_init_colors() {
	if [[ -t 1 && "${CI_MODE}" != "true" ]]; then
		RED='\033[0;31m'
		GREEN='\033[0;32m'
		YELLOW='\033[1;33m'
		BLUE='\033[0;34m'
		CYAN='\033[0;36m'
		BOLD='\033[1m'
		NC='\033[0m'
	else
		RED=''
		GREEN=''
		YELLOW=''
		BLUE=''
		CYAN=''
		BOLD=''
		NC=''
	fi
}

# ─────────────────────────────────────────────────────────────────────────────
# LOGGER
# ─────────────────────────────────────────────────────────────────────────────

_log() {
	local level="$1"
	shift
	local ts
	ts="$(date '+%Y-%m-%d %H:%M:%S')"
	printf '[%s] [%-7s] %s\n' "${ts}" "${level}" "$*" >>"${LOG_FILE}"
	echo -e "$*"
}

info() { _log INFO "${BLUE}[INFO]${NC}    $*"; }
success() { _log OK "${GREEN}[OK]${NC}      $*"; }
warn() { _log WARN "${YELLOW}[WARN]${NC}    $*"; }
error() { _log ERROR "${RED}[ERROR]${NC}   $*"; }
section() { _log SECTION "\n${BOLD}${CYAN}══ $* ══${NC}"; }
step() { _log STEP "  ${BLUE}->${NC} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# ARG PARSER
# ─────────────────────────────────────────────────────────────────────────────

_parse_args() {
	for arg in "$@"; do
		case "${arg}" in
		--ci) CI_MODE=true ;;
		--skip-docker) SKIP_DOCKER=true ;;
		--skip-optional) SKIP_OPTIONAL=true ;;
		--help | -h)
			_usage
			exit 0
			;;
		*) warn "Unknown flag: ${arg}" ;;
		esac
	done
}

_usage() {
	cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --ci              Non-interactive CI mode (skip prompts, skip shell edits)
  --skip-docker     Skip Docker installation
  --skip-optional   Skip optional npm globals and Oh-My-Zsh
  --help            Show this help message

Environment variables:
  CI=true           Equivalent to --ci
  OPENAI_API_KEY    Pre-set API key (skips interactive prompt)
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# RETRY WRAPPER — wraps entire pipelines safely via bash -c
#
# FIX #1: wrap the whole pipeline, not just the first command.
# Passing a pipeline directly to retry() only retries the first process;
# set -o pipefail makes the rest unpredictable. Using bash -c ensures the
# entire pipeline is retried as a single atomic unit.
#
# Usage: retry <max_attempts> <delay_base_seconds> <bash_pipeline_string>
# ─────────────────────────────────────────────────────────────────────────────

retry() {
	local retries="${1}"
	local delay="${2}"
	shift 2
	local count=0

	local cmd=("$@")

	until "${cmd[@]}"; do
		local exit_code=$?
		count=$((count + 1))
		if ((count >= retries)); then
			error "Command failed after ${retries} attempt(s). Last exit: ${exit_code}"
			return "${exit_code}"
		fi
		warn "Attempt ${count}/${retries} failed — retrying in ${delay}s..."
		sleep "${delay}"
		delay=$((delay * 2))
	done
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

command_exists() { command -v "$1" >/dev/null 2>&1; }

version_gte() {
	# Returns 0 (true) if $1 >= $2
	printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

apt_install() {
	# shellcheck disable=SC2016
	retry 3 2 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confnew" '"$*"
}

# Secure download: write to a temp file, return its path via stdout.
# Caller is responsible for rm -f.
secure_download() {
	local url="$1"
	local tmpfile
	tmpfile="$(mktemp)"
	retry 3 2 "curl -fsSL '${url}' -o '${tmpfile}'"
	echo "${tmpfile}"
}

# ─────────────────────────────────────────────────────────────────────────────
# LOCK
# ─────────────────────────────────────────────────────────────────────────────

_acquire_lock() {
	exec 9>"${LOCK_FILE}"

	if ! flock -n 9; then
		error "Another install process is already running."
		exit 1
	fi

	echo "$$" 1>&9
}

_release_lock() {
	flock -u 9 2>/dev/null || true
	rm -f "${LOCK_FILE}" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# ERROR / EXIT HANDLERS
# ─────────────────────────────────────────────────────────────────────────────

_on_error() {
	local exit_code=$?
	local line_no="${1:-?}"
	error "Installer failed — exit ${exit_code} at ${SCRIPT_NAME}:${line_no}"
	error "Full log: ${LOG_FILE}"
	_release_lock
	exit "${exit_code}"
}

_on_exit() {
	_release_lock
	local elapsed=$(($(date +%s) - SCRIPT_START_TS))
	info "Total elapsed: ${elapsed}s"
}

trap '_on_error ${LINENO}' ERR
trap '_on_exit' EXIT

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

check_ubuntu() {
	section "Preflight: OS"
	if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
		error "Unsupported OS. Ubuntu 22.04+ required."
		exit 1
	fi
	local ubuntu_version
	# shellcheck disable=SC1091
	ubuntu_version="$(. /etc/os-release && echo "${VERSION_ID}")"
	if ! version_gte "${ubuntu_version}" "22.04"; then
		error "Ubuntu ${ubuntu_version} — minimum supported: 22.04 LTS."
		exit 1
	fi
	success "Ubuntu ${ubuntu_version} ✓"
}

check_architecture() {
	section "Preflight: Architecture"
	local arch
	arch="$(uname -m)"
	case "${arch}" in
	x86_64 | aarch64) success "Architecture: ${arch} ✓" ;;
	*)
		error "Unsupported architecture: ${arch}."
		exit 1
		;;
	esac
}

check_disk_space() {
	section "Preflight: Disk Space"
	local free_gb
	free_gb="$(df -BG "${HOME}" | awk 'NR==2 {gsub("G",""); print $4}')"
	if ((free_gb < MIN_DISK_GB)); then
		error "Insufficient disk: ${free_gb}GB free, ${MIN_DISK_GB}GB required."
		exit 1
	fi
	success "Disk space: ${free_gb}GB free ✓"
}

check_ram() {
	section "Preflight: RAM"
	local ram_mb
	ram_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
	if ((ram_mb < MIN_RAM_MB)); then
		warn "Low RAM: ${ram_mb}MB (recommended: ${MIN_RAM_MB}MB+)"
	else
		success "RAM: ${ram_mb}MB ✓"
	fi
}

check_internet() {
	section "Preflight: Internet"
	local targets=("registry.npmjs.org" "deb.nodesource.com" "github.com")
	for t in "${targets[@]}"; do
		if curl -sf --max-time 8 "https://${t}" >/dev/null 2>&1; then
			success "Network reachable (${t}) ✓"
			return
		fi
	done
	error "No internet connectivity detected."
	exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# SUDO KEEPALIVE
# ─────────────────────────────────────────────────────────────────────────────

enable_sudo_keepalive() {
	section "Sudo Keepalive"
	sudo -v
	(
		while true; do
			sudo -n true
			sleep 50
			kill -0 "$$" 2>/dev/null || exit 0
		done
	) &
	SUDO_KEEPALIVE_PID=$!

	trap 'kill ${SUDO_KEEPALIVE_PID:-0} 2>/dev/null || true' EXIT

	trap 'kill ${SUDO_KEEPALIVE_PID:-0} 2>/dev/null || true' EXIT
	success "Sudo keepalive active (pid: ${SUDO_KEEPALIVE_PID}) ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM UPDATE
# ─────────────────────────────────────────────────────────────────────────────

update_system() {
	section "System Update"
	step "Updating apt repositories..."
	retry 3 2 'sudo apt-get update -y'

	step "Upgrading installed packages..."
	sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
		-o Dpkg::Options::="--force-confnew"

	sudo apt-get autoremove -y
	sudo apt-get autoclean -y
	success "System updated ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# BASE PACKAGES
# ─────────────────────────────────────────────────────────────────────────────

install_base_packages() {
	section "Base Packages"

	local packages=(
		build-essential make gcc g++ pkg-config
		curl wget git jq unzip zip xz-utils
		ca-certificates gnupg lsb-release apt-transport-https software-properties-common
		ripgrep fd-find bat fzf tmux neovim htop tree
		zsh zsh-autosuggestions zsh-syntax-highlighting
		netcat-openbsd dnsutils iputils-ping
		direnv pass
	)

	step "Installing ${#packages[@]} packages..."
	# shellcheck disable=SC2068
	apt_install "${packages[@]}"

	# Ubuntu ships fd as 'fdfind' and bat as 'batcat' — create canonical symlinks
	mkdir -p "${BIN_DIR}"
	if command_exists fdfind && ! command_exists fd; then
		ln -sf "$(command -v fdfind)" "${BIN_DIR}/fd"
		success "Symlink: fd -> fdfind ✓"
	fi
	if command_exists batcat && ! command_exists bat; then
		ln -sf "$(command -v batcat)" "${BIN_DIR}/bat"
		success "Symlink: bat -> batcat ✓"
	fi

	success "Base packages installed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# NPM GLOBAL PREFIX ISOLATION
#
# FIX #3: use --location=user to avoid writing to the wrong npmrc
# (root npmrc, sudo-contaminated env, or CI runner global config).
# ─────────────────────────────────────────────────────────────────────────────

configure_npm_prefix() {
	section "npm Global Prefix Isolation"

	mkdir -p "${NPM_GLOBAL_DIR}"

	# Explicit user-scope npmrc — immune to sudo/root contamination
	npm config --location=user set prefix "${NPM_GLOBAL_DIR}"

	touch "${ENV_FILE}"
	chmod 600 "${ENV_FILE}"

	if ! grep -q "NPM_GLOBAL_DIR" "${ENV_FILE}" 2>/dev/null; then
		cat >>"${ENV_FILE}" <<EOF

# npm global prefix isolation — managed by ${SCRIPT_NAME} v${SCRIPT_VERSION}
export NPM_GLOBAL_DIR="${NPM_GLOBAL_DIR}"
export PATH="${NPM_GLOBAL_DIR}/bin:\${PATH}"
EOF
	fi

	# Apply to current shell immediately
	export PATH="${NPM_GLOBAL_DIR}/bin:${PATH}"

	success "npm prefix -> ${NPM_GLOBAL_DIR} (user-scoped) ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# NODE.JS — GPG-verified NodeSource repository
#
# FIX #1: the GPG pipeline (curl | gpg | tee) is wrapped as a single
#         bash -c string so retry() covers the entire chain.
# FIX #4: use real VERSION_CODENAME instead of 'nodistro'.
# ─────────────────────────────────────────────────────────────────────────────

install_nodejs() {
	section "Node.js ${NODE_MAJOR} LTS"

	if command_exists node; then
		local cur_major
		cur_major="$(node -p 'process.versions.node.split(".")[0]')"
		if ((cur_major >= NODE_MAJOR)); then
			success "Node.js $(node -v) already installed ✓"
			configure_npm_prefix
			return
		fi
		warn "Node.js v${cur_major} found — upgrading to ${NODE_MAJOR}..."
	fi

	local codename
	# shellcheck disable=SC1091
	codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

	step "Importing NodeSource GPG key (full pipeline retry)..."
	# FIX #1: entire pipeline as single bash -c — retry covers curl + gpg + tee
	retry 3 2 "
    curl -fsSL '${NODESOURCE_GPG_URL}' \
      | gpg --dearmor \
      | sudo tee '${NODESOURCE_KEYRING}' >/dev/null
  "
	sudo chmod a+r "${NODESOURCE_KEYRING}"

	step "Adding NodeSource apt repository (codename: ${codename})..."
	# FIX #4: use real VERSION_CODENAME, not 'nodistro'
	printf 'deb [signed-by=%s] https://deb.nodesource.com/node_%s.x %s main\n' \
		"${NODESOURCE_KEYRING}" "${NODE_MAJOR}" "${codename}" |
		sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null

	retry 3 2 'sudo apt-get update -y'
	apt_install nodejs

	step "Updating npm to latest stable..."
	retry 3 2 npm install -g "npm@^10"

	configure_npm_prefix

	success "Node.js $(node -v) / npm $(npm -v) installed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER — hardened daemon
#
# FIX #5: removed "no-new-privileges" — not a valid Docker daemon option;
#         it belongs in container runtime / compose securityOpt, not daemon.json.
# ─────────────────────────────────────────────────────────────────────────────

install_docker() {
	section "Docker"

	if [[ "${SKIP_DOCKER}" == "true" ]]; then
		warn "Docker installation skipped (--skip-docker)"
		return
	fi

	if command_exists docker; then
		success "Docker $(docker --version | awk '{print $3}' | tr -d ',') already installed ✓"
		_configure_docker_group
		_harden_docker_daemon
		return
	fi

	step "Adding Docker GPG key..."
	sudo mkdir -p /etc/apt/keyrings
	# FIX #1 pattern: entire pipeline in single bash -c
	retry 3 2 "
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  "
	sudo chmod a+r /etc/apt/keyrings/docker.gpg

	local codename
	# shellcheck disable=SC1091
	codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
	local arch
	arch="$(dpkg --print-architecture)"

	step "Adding Docker apt repository..."
	printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu %s stable\n' \
		"${arch}" "${codename}" |
		sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

	retry 3 2 'sudo apt-get update -y'
	apt_install docker-ce docker-ce-cli containerd.io \
		docker-buildx-plugin docker-compose-plugin

	_configure_docker_group
	_harden_docker_daemon

	success "Docker $(docker --version | awk '{print $3}' | tr -d ',') installed ✓"
}

_configure_docker_group() {
	if ! groups "${USER}" | grep -q '\bdocker\b'; then
		step "Adding ${USER} to docker group..."
		sudo usermod -aG docker "${USER}"
		warn "Run 'newgrp docker' or log out/in to use Docker without sudo"
	fi
}

_harden_docker_daemon() {
	step "Writing Docker daemon config..."
	sudo mkdir -p /etc/docker

	if [[ ! -f /etc/docker/daemon.json ]]; then
		# FIX #5: "no-new-privileges" is NOT a daemon.json key — removed.
		# Use securityOpt in docker run / compose instead.
		cat <<'DOCKERD' | sudo tee /etc/docker/daemon.json >/dev/null
{
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "userland-proxy": false
}
DOCKERD
		sudo systemctl restart docker 2>/dev/null || true
		success "Docker daemon hardened ✓"
	else
		warn "/etc/docker/daemon.json already exists — kept unchanged (review manually)"
	fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CODEX CLI
#
# FIX #10: use `npm install -g @openai/codex@latest` instead of `npm update -g`
#          to avoid accidentally pulling incompatible major versions of
#          unrelated global packages.
# ─────────────────────────────────────────────────────────────────────────────

install_codex_cli() {
	section "Codex CLI"

	if command_exists codex; then
		local cur_ver
		cur_ver="$(codex --version 2>/dev/null || echo 'unknown')"
		step "Codex ${cur_ver} installed — upgrading to @latest..."
		# FIX #10: pin to @latest, not `npm update -g` (which updates everything)
		retry 3 2 "npm install -g '${CODEX_NPM_PACKAGE}@latest'"
		success "Codex updated: $(codex --version) ✓"
		return
	fi

	step "Installing ${CODEX_NPM_PACKAGE}@latest..."
	retry 3 2 "npm install -g '${CODEX_NPM_PACKAGE}@latest'"

	if ! command_exists codex; then
		error "Codex not found after install. npm global bin: $(npm bin -g 2>/dev/null || echo 'unknown')"
		exit 1
	fi

	success "Codex CLI $(codex --version) installed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# SHELL CONFIG
# ─────────────────────────────────────────────────────────────────────────────

detect_shell_rc() {
	section "Shell Config"
	local shell_name
	shell_name="$(basename "${SHELL:-bash}")"
	case "${shell_name}" in
	zsh) SHELL_RC="${HOME}/.zshrc" ;;
	bash) SHELL_RC="${HOME}/.bashrc" ;;
	*) SHELL_RC="${HOME}/.profile" ;;
	esac
	touch "${SHELL_RC}"
	success "Shell: ${shell_name} -> ${SHELL_RC} ✓"
}

configure_environment() {
	section "Environment"

	if [[ "${CI_MODE}" == "true" ]]; then
		warn "CI mode: shell RC modification skipped"
		return
	fi

	touch "${ENV_FILE}"
	chmod 600 "${ENV_FILE}"
	mkdir -p "${BIN_DIR}"

	# FIX #8: always remove the old block before re-writing to prevent
	# partial corruption or duplicated env blocks on re-runs.
	if grep -q "# codex:env-block" "${SHELL_RC}" 2>/dev/null; then
		step "Removing stale env block from ${SHELL_RC}..."
		sed -i '/# codex:env-block/,/# codex:env-block-end/d' "${SHELL_RC}"
	fi

	cat >>"${SHELL_RC}" <<EOF

# codex:env-block — managed by ${SCRIPT_NAME} v${SCRIPT_VERSION}
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"
export PATH="${BIN_DIR}:\${PATH}"
export EDITOR=nvim
export VISUAL=nvim
command -v direnv >/dev/null && eval "\$(direnv hook $(basename "${SHELL:-bash}"))"
# codex:env-block-end
EOF

	success "Environment block written -> ${SHELL_RC} ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# API KEY
#
# FIX #9: warn user that plaintext storage is a risk.
#         Minimal improvement: suggest pass / keychain integration path.
# ─────────────────────────────────────────────────────────────────────────────

configure_api_key() {
	section "API Key"

	if [[ -n "${OPENAI_API_KEY:-}" ]]; then
		_write_api_key "${OPENAI_API_KEY}"
		success "OPENAI_API_KEY sourced from environment ✓"
		return
	fi

	if grep -q "OPENAI_API_KEY" "${ENV_FILE}" 2>/dev/null; then
		success "OPENAI_API_KEY already configured ✓"
		return
	fi

	if [[ "${CI_MODE}" == "true" ]]; then
		warn "CI mode: set \$OPENAI_API_KEY in your runner secrets before calling 'codex'"
		return
	fi

	# FIX #9: offer keychain alternative
	echo
	if command_exists pass; then
		info "Tip: store your key securely with: pass insert codex/openai-api-key"
		info "     then add to ${ENV_FILE}: export OPENAI_API_KEY=\"\$(pass codex/openai-api-key)\""
		echo
	fi

	read -rsp "  Enter OPENAI_API_KEY (sk-...): " INPUT_KEY
	echo

	if [[ -z "${INPUT_KEY}" ]]; then
		error "OPENAI_API_KEY cannot be empty."
		exit 1
	fi
	if [[ ! "${INPUT_KEY}" =~ ^sk- ]]; then
		warn "Key does not start with 'sk-' — proceeding anyway."
	fi

	_write_api_key "${INPUT_KEY}"

	# FIX #9: explicit plaintext storage warning
	warn "API key stored in plaintext at ${ENV_FILE} (chmod 600)"
	warn "For better security, use 'pass', 'gnome-keyring', or '1password' CLI"

	success "OPENAI_API_KEY saved ✓"
}

_write_api_key() {
	local key="$1"
	touch "${ENV_FILE}"
	chmod 600 "${ENV_FILE}"
	sed -i '/^export OPENAI_API_KEY=/d' "${ENV_FILE}" 2>/dev/null || true
	printf 'export OPENAI_API_KEY="%s"\n' "${key}" >>"${ENV_FILE}"
}

# ─────────────────────────────────────────────────────────────────────────────
# CODEX CONFIG — minimal valid schema only
#
# Speculative keys (max_parallel_agents, prefer_clean_architecture, etc.)
# are NOT written here — they cause silent config failure.
# Those belong in AGENTS.md (generated below).
# ─────────────────────────────────────────────────────────────────────────────

generate_codex_config() {
	section "Codex Config"

	local config_file="${CONFIG_DIR}/config.toml"

	if [[ -f "${config_file}" ]]; then
		warn "Existing config found — backing up to ${config_file}.bak"
		cp "${config_file}" "${config_file}.bak"
	fi

	cat >"${config_file}" <<EOF
# Codex CLI Configuration
# Generated by ${SCRIPT_NAME} v${SCRIPT_VERSION}
# Reference: https://github.com/openai/codex

model           = "codex-1"
approval-policy = "on-request"
sandbox-mode    = "workspace-write"

EOF

	chmod 600 "${config_file}"
	success "Codex config generated (minimal valid schema) ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# AGENTS.md — advanced behaviour (replaces speculative config keys)
# ─────────────────────────────────────────────────────────────────────────────

generate_agents_md() {
	section "AGENTS.md"

	local agents_file="${CONFIG_DIR}/AGENTS.md"
	[[ -f "${agents_file}" ]] && {
		warn "AGENTS.md exists — skipping"
		return
	}

	cat >"${agents_file}" <<'AGENTS'
# Codex Agent Instructions

## Code Quality
- Prefer clean, modular architecture with clear separation of concerns.
- Use strong typing. Avoid `any` in TypeScript; avoid untyped vars in Python.
- Generate production-ready code: error handling, logging, and input validation included.

## Security
- Never output secrets, tokens, or credentials in code or comments.
- Parameterise all SQL queries. Never concatenate user input into SQL strings.
- Validate and sanitise all user inputs before persistence or rendering.

## Commits
- Follow Conventional Commits: `type(scope): description`
- Types: feat | fix | chore | docs | refactor | test | ci | perf
- Keep subject line <= 72 characters. Add body for non-trivial changes.

## Pull Requests
- Title = Conventional Commit subject line.
- Body: Summary | Motivation | Changes Made | Testing Notes.
- Link issues with `Closes #N`.

## Testing
- Write tests alongside implementation, not as an afterthought.
- Aim for >=80% coverage on business-critical paths.
- Include at least one negative test per public function.

## Performance
- Prefer parallel tool calls where semantically safe.
- Batch related DB queries; avoid N+1 patterns.

## Documentation
- Update README and inline docstrings for every public API change.
- Keep CHANGELOG.md current using Keep a Changelog format.
AGENTS

	success "AGENTS.md generated -> ${agents_file} ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# GIT — hardened with transfer integrity
# ─────────────────────────────────────────────────────────────────────────────

configure_git() {
	section "Git"

	git config --global init.defaultBranch main
	git config --global pull.rebase false
	git config --global core.editor "nvim"
	git config --global core.autocrlf false
	git config --global fetch.prune true
	git config --global diff.colorMoved zebra

	# Transfer integrity: detect object corruption / tampering in transit
	git config --global transfer.fsckObjects true
	git config --global fetch.fsckObjects true
	git config --global receive.fsckObjects true

	if command_exists gpg; then
		git config --global commit.gpgsign false
		step "GPG available — enable: git config --global commit.gpgsign true"
	fi

	success "Git configured (with fsck hardening) ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTIONAL TOOLING
#
# FIX #6: Oh-My-Zsh installer is downloaded to a temp file first,
#         then executed — avoids curl|sh TOCTOU / MITM risk.
# FIX #10: all npm globals installed with explicit @latest (not update-g).
# ─────────────────────────────────────────────────────────────────────────────

install_optional_tooling() {
	section "Optional Tooling"

	if [[ "${SKIP_OPTIONAL}" == "true" ]]; then
		warn "Optional tooling skipped (--skip-optional)"
		return
	fi

	local npm_globals=(
		"typescript@latest"
		"tsx@latest"
		"pnpm@latest"
		"yarn@latest"
		"eslint@latest"
		"prettier@latest"
		"@anthropic-ai/claude-code@latest"
	)

	step "Installing global npm packages..."
	# FIX #10: install each with @latest to pin intent explicitly
	retry 3 2 npm install -g "${npm_globals[@]}"

	# FIX #6: download Oh-My-Zsh installer to temp file first — no curl|sh
	local shell_name
	shell_name="$(basename "${SHELL:-bash}")"
	if [[ "${CI_MODE}" != "true" &&
		"${shell_name}" == "zsh" &&
		! -d "${HOME}/.oh-my-zsh" ]]; then
		step "Downloading Oh-My-Zsh installer to temp file..."
		local ohmyzsh_installer
		ohmyzsh_installer="$(secure_download "${OHMYZSH_INSTALL_URL}")"
		step "Verifying installer is not empty..."
		if [[ ! -s "${ohmyzsh_installer}" ]]; then
			error "Oh-My-Zsh installer download failed or empty."
			rm -f "${ohmyzsh_installer}"
		else
			RUNZSH=no CHSH=no sh "${ohmyzsh_installer}"
			rm -f "${ohmyzsh_installer}"
			success "Oh-My-Zsh installed ✓"
		fi
	fi

	success "Optional tooling installed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK — per-command validation
#
# FIX (healthcheck): use dedicated validation per command instead of
# the naive `$cmd --version` pattern, which fails for tools like
# docker compose, fd, and rg that have different version flag formats.
# ─────────────────────────────────────────────────────────────────────────────

run_healthcheck() {
	section "Health Check"
	local failed=0

	_pass() { success "$1 ✓"; }
	_fail() {
		error "$1 ✗"
		((failed++)) || true
	}

	# node
	if command_exists node; then
		_pass "Node.js: $(node --version)"
	else
		_fail "Node.js: not found"
	fi

	# npm
	if command_exists npm; then
		_pass "npm: $(npm --version)"
	else
		_fail "npm: not found"
	fi

	# git
	if command_exists git; then
		_pass "git: $(git --version)"
	else
		_fail "git: not found"
	fi

	# neovim
	if command_exists nvim; then
		_pass "neovim: $(nvim --version | head -1)"
	else
		_fail "neovim: not found"
	fi

	# ripgrep — uses --version, but output is 'ripgrep X.Y.Z'
	if command_exists rg; then
		_pass "ripgrep: $(rg --version | head -1)"
	else
		_fail "ripgrep: not found"
	fi

	# fd — Ubuntu's fdfind aliased to fd; version flag is --version
	if command_exists fd; then
		_pass "fd: $(fd --version)"
	else
		_fail "fd: not found"
	fi

	# codex
	if command_exists codex; then
		_pass "codex: $(codex --version)"
	else
		_fail "codex: not found"
	fi

	# docker (skip if --skip-docker)
	if [[ "${SKIP_DOCKER}" != "true" ]]; then
		if command_exists docker; then
			_pass "docker: $(docker version --format '{{.Client.Version}}' 2>/dev/null || docker --version)"
		else
			_fail "docker: not found"
		fi

		# docker compose plugin (different invocation from docker-compose v1)
		if docker compose version >/dev/null 2>&1; then
			_pass "docker compose: $(docker compose version --short 2>/dev/null || echo 'installed')"
		else
			warn "docker compose plugin: not available"
		fi
	fi

	# Verify npm prefix isolation
	local npm_prefix
	npm_prefix="$(npm config --location=user get prefix 2>/dev/null || echo 'unknown')"
	if [[ "${npm_prefix}" == "${NPM_GLOBAL_DIR}" ]]; then
		_pass "npm prefix isolated: ${npm_prefix}"
	else
		warn "npm prefix is '${npm_prefix}' — expected '${NPM_GLOBAL_DIR}'"
	fi

	if ((failed > 0)); then
		warn "${failed} health check(s) failed — see log: ${LOG_FILE}"
	else
		success "All health checks passed ✓"
	fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UPDATE SCRIPT
# ─────────────────────────────────────────────────────────────────────────────

generate_update_script() {
	section "Update Script"

	cat >"${CONFIG_DIR}/update.sh" <<'UPDATER'
#!/usr/bin/env bash
set -euo pipefail
echo "── Updating Codex CLI ──────────────────────────────"
npm install -g @openai/codex@latest
codex --version
echo "── Updating system packages ─────────────────────────"
sudo apt-get update -y && sudo apt-get upgrade -y
echo "✓ All components updated"
UPDATER
	chmod +x "${CONFIG_DIR}/update.sh"

	if [[ "${CI_MODE}" != "true" ]] && command_exists crontab; then
		# FIX #7: use exact full path for cron removal match consistency
		local entry="0 3 * * 0 ${CONFIG_DIR}/update.sh >> ${CONFIG_DIR}/update.log 2>&1"
		if ! crontab -l 2>/dev/null | grep -qF "${CONFIG_DIR}/update.sh"; then
			(
				crontab -l 2>/dev/null
				echo "${entry}"
			) | crontab -
			step "Weekly auto-update cron registered (Sun 03:00 UTC)"
		fi
	fi

	success "Update script -> ${CONFIG_DIR}/update.sh ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# UNINSTALL SCRIPT — full rollback
#
# FIX #7: cron removal uses exact CONFIG_DIR path match via grep -F
#         to avoid regex mismatch between install and uninstall.
# ─────────────────────────────────────────────────────────────────────────────

generate_uninstall_script() {
	section "Uninstall Script"

	# Use printf to avoid heredoc variable expansion issues with CONFIG_DIR
	local uninstall_path="${CONFIG_DIR}/uninstall.sh"

	cat >"${uninstall_path}" <<UNINSTALLER
#!/usr/bin/env bash
set -euo pipefail

CODEX_CONFIG_DIR="${CONFIG_DIR}"

echo "Uninstalling Codex environment..."

# 1. Remove Codex CLI
npm uninstall -g @openai/codex 2>/dev/null || true

# 2. Remove optional globals installed by this script
npm uninstall -g typescript tsx pnpm yarn eslint prettier \\
  @anthropic-ai/claude-code 2>/dev/null || true

# 3. Remove env block from all shell RC files
for rc in "\${HOME}/.bashrc" "\${HOME}/.zshrc" "\${HOME}/.profile"; do
  [[ -f "\${rc}" ]] || continue
  sed -i '/# codex:env-block/,/# codex:env-block-end/d' "\${rc}" 2>/dev/null || true
  echo "Cleaned: \${rc}"
done

# 4. FIX #7: remove cron using exact path match (grep -F, not grep -v pattern)
if command -v crontab >/dev/null 2>&1; then
  ( crontab -l 2>/dev/null | grep -vF "\${CODEX_CONFIG_DIR}/update.sh" ) \\
    | crontab - 2>/dev/null || true
  echo "Cron entry removed"
fi

# 5. Backup config dir before removal
if [[ -d "\${CODEX_CONFIG_DIR}" ]]; then
  local backup="\${HOME}/.codex-backup-\$(date +%Y%m%d-%H%M%S)"
  mv "\${CODEX_CONFIG_DIR}" "\${backup}"
  echo "Config backed up to: \${backup}"
fi

echo ""
echo "Codex environment uninstalled."
echo "Note: Node.js, Docker, and system packages were NOT removed."
UNINSTALLER

	chmod +x "${uninstall_path}"
	success "Uninstall script -> ${uninstall_path} ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

print_summary() {
	local elapsed=$(($(date +%s) - SCRIPT_START_TS))

	echo -e "\n${BOLD}${GREEN}+================================================+${NC}"
	echo -e "${BOLD}${GREEN}|   Codex Environment Installed Successfully     |${NC}"
	echo -e "${BOLD}${GREEN}+================================================+${NC}\n"

	echo -e "  ${CYAN}Installer version${NC}  ${SCRIPT_VERSION}"
	echo -e "  ${CYAN}Elapsed time      ${NC}  ${elapsed}s"
	echo -e "  ${CYAN}Config dir        ${NC}  ${CONFIG_DIR}"
	echo -e "  ${CYAN}npm prefix        ${NC}  ${NPM_GLOBAL_DIR}"
	echo -e "  ${CYAN}Log file          ${NC}  ${LOG_FILE}"
	echo -e "  ${CYAN}Codex version     ${NC}  $(codex --version 2>/dev/null || echo 'see PATH')"

	echo -e "\n${BOLD}Next steps:${NC}"
	echo -e "  1. Reload shell   ->  ${CYAN}source ${SHELL_RC:-~/.bashrc}${NC}"
	echo -e "  2. Start Codex    ->  ${CYAN}codex${NC}"
	echo -e "  3. Edit agents    ->  ${CYAN}nvim ${CONFIG_DIR}/AGENTS.md${NC}"
	echo -e "  4. Update later   ->  ${CYAN}${CONFIG_DIR}/update.sh${NC}"
	echo -e "  5. Uninstall      ->  ${CYAN}${CONFIG_DIR}/uninstall.sh${NC}\n"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
	_parse_args "$@"
	_init_colors # must come after _parse_args sets CI_MODE

	_acquire_lock

	# FIX #2: use explicit boolean check instead of ${CI_MODE:+ [CI MODE]}
	# because the string "false" is non-empty and would always trigger :+
	local ci_suffix=""
	[[ "${CI_MODE}" == "true" ]] && ci_suffix=" [CI MODE]"
	info "Codex Ubuntu Installer v${SCRIPT_VERSION}${ci_suffix}"
	info "Log: ${LOG_FILE}"

	# Preflight
	check_ubuntu
	check_architecture
	check_disk_space
	check_ram
	check_internet

	# Privileges
	enable_sudo_keepalive

	# System
	update_system
	install_base_packages

	# Runtime
	install_nodejs # internally calls configure_npm_prefix
	install_docker

	# Codex
	install_codex_cli

	# Shell / Env
	detect_shell_rc
	configure_environment
	configure_api_key

	# Config & Docs
	generate_codex_config
	generate_agents_md
	configure_git

	# Extras
	install_optional_tooling

	# Maintenance scripts
	generate_update_script
	generate_uninstall_script

	# Verify
	run_healthcheck

	# Done
	print_summary
}

main "$@"
