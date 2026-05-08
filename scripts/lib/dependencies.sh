#!/usr/bin/env bash
# Dependency validation helpers for development, CI, and release entry points.

DEPENDENCY_FAILURES=0

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
	*) printf 'Install %s with your system package manager.\n' "${command_name}" ;;
	esac
}

require_command() {
	local command_name="$1"
	local description="${2:-${command_name}}"
	local hint

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
	DEPENDENCY_FAILURES=0

	require_command bash 'Bash shell' || true
	require_command git 'Git version control' || true
	require_command curl 'curl HTTP client' || true
	require_command shellcheck 'ShellCheck static analysis' || true
	require_command shfmt 'shfmt formatter' || true
	require_command bats 'Bats test runner' || true
	require_command tar 'tar archiver' || true
	require_command sha256sum 'SHA-256 checksum tool' || true

	if ((DEPENDENCY_FAILURES > 0)); then
		_dependency_log ERROR "Environment validation failed with ${DEPENDENCY_FAILURES} missing required dependency/dependencies."
		_dependency_log INFO 'Ubuntu quick fix: make deps-dev'
		return 1
	fi

	_dependency_log OK 'All required development and release dependencies are available.'
}
