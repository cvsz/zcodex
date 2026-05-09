#!/usr/bin/env bash
# Containerized end-to-end validation runner for zcodex.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCENARIO_FILE="${REPO_ROOT}/tests/e2e/scenarios.tsv"
ARTIFACT_DIR="${ARTIFACT_DIR:-${REPO_ROOT}/artifacts/e2e}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
ARCH="${ARCH:-amd64}"
SCENARIO="${SCENARIO:-all}"
E2E_TIMEOUT_SECONDS="${E2E_TIMEOUT_SECONDS:-1500}"
DRY_RUN=0

usage() {
	cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  --ubuntu VERSION   Ubuntu container version: 22.04 or 24.04. Default: ${UBUNTU_VERSION}.
  --arch ARCH        Container architecture: amd64 or arm64. Default: ${ARCH}.
  --scenario NAME    Scenario from tests/e2e/scenarios.tsv, or all. Default: all.
  --timeout SECONDS  Per-scenario timeout. Default: ${E2E_TIMEOUT_SECONDS}.
  --dry-run          Print the deterministic execution plan without starting Docker.
  --list             List scenarios.
  -h, --help         Show this help.
USAGE
}

fail() {
	printf '[e2e] ERROR: %s\n' "$*" >&2
	exit 1
}

platform_for_arch() {
	case "$1" in
	amd64) printf 'linux/amd64\n' ;;
	arm64) printf 'linux/arm64\n' ;;
	*) fail "unsupported architecture: $1" ;;
	esac
}

validate_ubuntu() {
	case "$1" in
	22.04 | 24.04) ;;
	*) fail "unsupported Ubuntu version: $1" ;;
	esac
}

scenario_rows() {
	awk -F '\t' 'NF >= 3 && $1 !~ /^#/ { print $1 "\t" $2 "\t" $3 }' "${SCENARIO_FILE}" | LC_ALL=C sort
}

list_scenarios() { scenario_rows | cut -f1; }

collect_failure_artifacts() {
	local name="$1" container_name="$2" scenario_dir="$3"
	mkdir -p "${scenario_dir}"
	if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' | grep -Fxq "${container_name}"; then
		docker logs "${container_name}" >"${scenario_dir}/container.log" 2>&1 || true
		docker cp "${container_name}:/tmp/zcodex-artifacts/." "${scenario_dir}/" >/dev/null 2>&1 || true
		docker rm -f "${container_name}" >/dev/null 2>&1 || true
	fi
	printf '[e2e] collected failure artifacts for %s in %s\n' "${name}" "${scenario_dir}" >&2
}

run_scenario_in_container() {
	local name="$1" mode="$2" args="$3"
	local platform image workdir scenario_dir container_name
	platform="$(platform_for_arch "${ARCH}")"
	image="ubuntu:${UBUNTU_VERSION}"
	workdir="/work/zcodex"
	scenario_dir="${ARTIFACT_DIR}/${UBUNTU_VERSION}-${ARCH}/${name}"
	container_name="zcodex-e2e-${UBUNTU_VERSION//./}-${ARCH}-${name//[^A-Za-z0-9_.-]/-}-$$"

	printf '[e2e] ubuntu=%s arch=%s scenario=%s timeout=%ss mode=%s args=%s\n' "${UBUNTU_VERSION}" "${ARCH}" "${name}" "${E2E_TIMEOUT_SECONDS}" "${mode}" "${args}"
	if [[ "${DRY_RUN}" -eq 1 ]]; then
		return 0
	fi

	command -v docker >/dev/null 2>&1 || fail 'docker is required for containerized E2E execution'
	rm -rf "${scenario_dir}"
	mkdir -p "${scenario_dir}"

	if ! timeout "${E2E_TIMEOUT_SECONDS}" docker run --name "${container_name}" --platform "${platform}" \
		-e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 -e TZ=UTC -e CI=true \
		-v "${REPO_ROOT}:${workdir}:ro" \
		-w "${workdir}" \
		"${image}" \
		bash -lc "set -Eeuo pipefail; mkdir -p /tmp/zcodex-artifacts; trap 'cp -a /tmp/zcodex-home /tmp/zcodex-state /tmp/zcodex-artifacts/ 2>/dev/null || true' EXIT; apt-get update; apt-get install -y bash ca-certificates curl git make tar gzip coreutils python3; mkdir -p /tmp/zcodex-home /tmp/zcodex-tmp /tmp/zcodex-state /tmp/zcodex-cache/npm /tmp/zcodex-prefix; export HOME=/tmp/zcodex-home TMPDIR=/tmp/zcodex-tmp XDG_CACHE_HOME=/tmp/zcodex-home/.cache XDG_CONFIG_HOME=/tmp/zcodex-home/.config XDG_DATA_HOME=/tmp/zcodex-home/.local/share XDG_STATE_HOME=/tmp/zcodex-home/.local/state npm_config_cache=/tmp/zcodex-cache/npm NPM_CONFIG_CACHE=/tmp/zcodex-cache/npm npm_config_prefix=/tmp/zcodex-prefix NPM_CONFIG_PREFIX=/tmp/zcodex-prefix ZCODEX_STATE_HOME=/tmp/zcodex-state ZCODEX_TMP_DIR=/tmp/zcodex-tmp/runtime; ./codex.sh ${mode} ${args}" \
		>"${scenario_dir}/stdout.log" 2>"${scenario_dir}/stderr.log"; then
		collect_failure_artifacts "${name}" "${container_name}" "${scenario_dir}"
		return 1
	fi
	docker rm -f "${container_name}" >/dev/null 2>&1 || true
}

main() {
	while [[ "$#" -gt 0 ]]; do
		case "$1" in
		--ubuntu)
			UBUNTU_VERSION="${2:-}"
			shift 2
			;;
		--arch)
			ARCH="${2:-}"
			shift 2
			;;
		--scenario)
			SCENARIO="${2:-}"
			shift 2
			;;
		--timeout)
			E2E_TIMEOUT_SECONDS="${2:-}"
			shift 2
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		--list)
			list_scenarios
			return 0
			;;
		-h | --help)
			usage
			return 0
			;;
		*) fail "unknown option: $1" ;;
		esac
	done

	validate_ubuntu "${UBUNTU_VERSION}"
	platform_for_arch "${ARCH}" >/dev/null
	[[ "${E2E_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || fail "timeout must be numeric: ${E2E_TIMEOUT_SECONDS}"
	[[ -r "${SCENARIO_FILE}" ]] || fail "missing scenario file: ${SCENARIO_FILE}"

	local matched=0
	while IFS=$'\t' read -r name mode args; do
		if [[ "${SCENARIO}" != all && "${SCENARIO}" != "${name}" ]]; then
			continue
		fi
		matched=1
		run_scenario_in_container "${name}" "${mode}" "${args}"
	done < <(scenario_rows)

	[[ "${matched}" -eq 1 ]] || fail "unknown scenario: ${SCENARIO}"
}

main "$@"
