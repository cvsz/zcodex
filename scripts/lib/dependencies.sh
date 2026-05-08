#!/usr/bin/env bash
# Dependency validation helpers for development, CI, and release entry points.

DEPENDENCY_FAILURES=0

ZCODEX_REQUIRED_TOOLING=(
	bash
	git
	curl
	shellcheck
	shfmt
	bats
	tar
	sha256sum
)

_dependency_log() {
	local level="$1"
	shift
	local message="$*"

	case "${level}" in
	INFO)
		if declare -F log_info >/dev/null 2>&1; then
			log_info "${message}"
		else
			printf '[INFO] %s\n' "${message}" >&2
		fi
		;;
	OK)
		if declare -F log_success >/dev/null 2>&1; then
			log_success "${message}"
		else
			printf '[OK] %s\n' "${message}" >&2
		fi
		;;
	WARN)
		if declare -F log_warn >/dev/null 2>&1; then
			log_warn "${message}"
		else
			printf '[WARN] %s\n' "${message}" >&2
		fi
		;;
	ERROR)
		if declare -F log_error >/dev/null 2>&1; then
			log_error "${message}"
		else
			printf '[ERROR] %s\n' "${message}" >&2
		fi
		;;
	esac
}

dependency_install_hint() {
	local command_name="$1"

	case "${command_name}" in
	bash) printf '%s\n' 'Install bash: sudo apt install bash' ;;
	git) printf '%s\n' 'Install git: sudo apt install git' ;;
	curl) printf '%s\n' 'Install curl: sudo apt install curl' ;;
	shellcheck) printf '%s\n' 'Install shellcheck: sudo apt install shellcheck' ;;
	shfmt) printf '%s\n' 'Install shfmt: sudo apt install shfmt' ;;
	bats) printf '%s\n' 'Install Bats: sudo apt install bats' ;;
	tar) printf '%s\n' 'Install tar: sudo apt install tar' ;;
	sha256sum) printf '%s\n' 'Install sha256sum: sudo apt install coreutils' ;;
	make) printf '%s\n' 'Install make: sudo apt install make' ;;
	gzip) printf '%s\n' 'Install gzip: sudo apt install gzip' ;;
	*) printf 'Install %s with your system package manager.\n' "${command_name}" ;;
	esac
}

dependency_command_description() {
	local command_name="$1"

	case "${command_name}" in
	bash) printf '%s\n' 'Bash shell' ;;
	git) printf '%s\n' 'Git version control' ;;
	curl) printf '%s\n' 'curl HTTP client' ;;
	shellcheck) printf '%s\n' 'ShellCheck static analysis' ;;
	shfmt) printf '%s\n' 'shfmt formatter' ;;
	bats) printf '%s\n' 'Bats test runner' ;;
	tar) printf '%s\n' 'tar archiver' ;;
	sha256sum) printf '%s\n' 'SHA-256 checksum tool' ;;
	make) printf '%s\n' 'make build orchestrator' ;;
	gzip) printf '%s\n' 'gzip compressor' ;;
	*) printf '%s\n' "${command_name}" ;;
	esac
}

require_command() {
	local command_name="$1"
	local description="${2:-}"
	local hint

	if [[ -z "${description}" ]]; then
		description="$(dependency_command_description "${command_name}")"
	fi

	if command -v "${command_name}" >/dev/null 2>&1; then
		_dependency_log OK "${description} found: $(command -v "${command_name}")"
		return 0
	fi

	hint="$(dependency_install_hint "${command_name}")"
	_dependency_log ERROR "Missing required dependency: ${description} (${command_name}). ${hint}"
	DEPENDENCY_FAILURES=$((DEPENDENCY_FAILURES + 1))
	return 1
}

validate_required_tooling() {
	local command_name

	DEPENDENCY_FAILURES=0
	_dependency_log INFO 'Validating required development and release tooling.'

	for command_name in "${ZCODEX_REQUIRED_TOOLING[@]}"; do
		require_command "${command_name}" || true
	done

	if ((DEPENDENCY_FAILURES > 0)); then
		_dependency_log ERROR "Environment validation failed with ${DEPENDENCY_FAILURES} missing required dependency/dependencies."
		_dependency_log INFO 'Ubuntu quick fix: make deps-dev'
		_dependency_log INFO 'Manual Ubuntu install: sudo apt install bash git curl shellcheck shfmt bats tar coreutils make gzip'
		return 1
	fi

	_dependency_log OK 'All required development and release dependencies are available.'
}

install_dev_dependencies_ubuntu() {
	local apt_packages=(bash git curl shellcheck shfmt bats tar coreutils make gzip)
	local sudo_cmd=()

	if [[ "${EUID}" -ne 0 ]]; then
		if ! command -v sudo >/dev/null 2>&1; then
			_dependency_log ERROR 'sudo is required to install development dependencies when not running as root.'
			_dependency_log INFO 'Manual Ubuntu install: sudo apt install bash git curl shellcheck shfmt bats tar coreutils make gzip'
			return 1
		fi
		sudo_cmd=(sudo)
	fi

	if ! command -v apt-get >/dev/null 2>&1; then
		_dependency_log ERROR 'Automatic dependency installation currently requires apt-get on Ubuntu/Debian systems.'
		_dependency_log INFO 'Manual Ubuntu install: sudo apt install bash git curl shellcheck shfmt bats tar coreutils make gzip'
		return 1
	fi

	_dependency_log INFO 'Installing zcodex development dependencies with apt.'
	"${sudo_cmd[@]}" apt-get update
	"${sudo_cmd[@]}" apt-get install -y "${apt_packages[@]}"
	validate_required_tooling
}
