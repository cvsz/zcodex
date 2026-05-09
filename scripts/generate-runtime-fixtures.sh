#!/usr/bin/env bash
# Generate deterministic runtime fixtures used by Bats and E2E tests.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="${ROOT_DIR}/tests/runtime-fixtures"

write_exe() {
	local path="$1"
	shift
	mkdir -p "$(dirname "${path}")"
	cat >"${path}"
	chmod +x "${path}"
}

write_node() {
	local fixture="$1" version="$2"
	write_exe "${FIXTURE_ROOT}/${fixture}/bin/node" <<-EOF_NODE
		#!/usr/bin/env bash
		printf '%s\n' '${version}'
	EOF_NODE
}

write_npm() {
	local fixture="$1" version="$2"
	write_exe "${FIXTURE_ROOT}/${fixture}/bin/npm" <<-EOF_NPM
		#!/usr/bin/env bash
		printf '%s\n' '${version}'
	EOF_NPM
}

write_codex() {
	local fixture="$1" version="$2"
	write_exe "${FIXTURE_ROOT}/${fixture}/bin/codex" <<-EOF_CODEX
		#!/usr/bin/env bash
		printf 'codex-cli %s\n' '${version}'
	EOF_CODEX
}

write_dpkg() {
	local fixture="$1" node_pkg="$2" npm_pkg="$3"
	write_exe "${FIXTURE_ROOT}/${fixture}/bin/dpkg-query" <<-EOF_DPKG
		#!/usr/bin/env bash
		case " \${*} " in
		*nodejs*) printf '%s\n' '${node_pkg}' ;;
		*npm*) printf '%s\n' '${npm_pkg}' ;;
		*) exit 1 ;;
		esac
	EOF_DPKG
}

write_ownership() {
	local fixture="$1" node_owner="$2" npm_owner="$3" codex_owner="${4:-unowned}"
	mkdir -p "${FIXTURE_ROOT}/${fixture}/ownership"
	printf '%s\n' "${node_owner}" >"${FIXTURE_ROOT}/${fixture}/ownership/node.owner"
	printf '%s\n' "${npm_owner}" >"${FIXTURE_ROOT}/${fixture}/ownership/npm.owner"
	printf '%s\n' "${codex_owner}" >"${FIXTURE_ROOT}/${fixture}/ownership/codex.owner"
}

init_fixture() {
	local fixture="$1"
	rm -rf "${FIXTURE_ROOT:?}/${fixture}"
	mkdir -p "${FIXTURE_ROOT}/${fixture}/bin" "${FIXTURE_ROOT}/${fixture}/ownership"
}

main() {
	mkdir -p "${FIXTURE_ROOT}"
	for fixture in clean-system apt-node nodesource-node nvm-node broken-npm stale-runtime corrupted-manifest interrupted-install path-shadowing conflicting-runtime missing-runtime; do
		init_fixture "${fixture}"
	done

	write_dpkg clean-system 'not-installed' 'not-installed'
	cat >"${FIXTURE_ROOT}/clean-system/README.md" <<-'EOF_CLEAN'
		# clean-system

		No Node.js, npm, Docker, or Codex binaries are injected ahead of the trusted system PATH.
	EOF_CLEAN

	write_node apt-node v18.19.1
	write_npm apt-node 9.2.0
	write_codex apt-node 0.129.0
	write_dpkg apt-node '18.19.1-ubuntu1' '9.2.0-ubuntu1'
	write_ownership apt-node system-apt-distro system-apt-distro system-npm

	write_node nodesource-node v22.16.0
	write_npm nodesource-node 10.8.2
	write_codex nodesource-node 0.129.0
	write_dpkg nodesource-node '22.16.0-1nodesource1' '10.8.2-1nodesource1'
	write_ownership nodesource-node system-apt-nodesource system-apt-nodesource system-npm

	write_node nvm-node v22.16.0
	write_npm nvm-node 10.8.2
	write_codex nvm-node 0.129.0
	write_dpkg nvm-node 'not-installed' 'not-installed'
	write_ownership nvm-node user-nvm user-nvm user-nvm

	write_node broken-npm v22.16.0
	write_exe "${FIXTURE_ROOT}/broken-npm/bin/npm" <<-'EOF_BROKEN_NPM'
		#!/usr/bin/env bash
		printf 'npm: corrupted prefix\n' >&2
		exit 42
	EOF_BROKEN_NPM
	write_dpkg broken-npm '22.16.0-1nodesource1' '10.8.2-1nodesource1'
	write_ownership broken-npm system-apt-nodesource system-apt-nodesource

	write_node stale-runtime v20.11.0
	write_npm stale-runtime 10.2.4
	write_codex stale-runtime 0.1.0
	write_dpkg stale-runtime '20.11.0-ubuntu1' '10.2.4-ubuntu1'
	write_ownership stale-runtime system-apt-distro system-apt-distro stale-global
	cat >"${FIXTURE_ROOT}/stale-runtime/manifest.json" <<-'EOF_STALE'
		{"schema_version":2,"state":{"phase":"COMPLETE","status":"complete"},"components":[{"name":"codex-cli","version":"0.1.0"}]}
	EOF_STALE

	write_node corrupted-manifest v22.16.0
	write_npm corrupted-manifest 10.8.2
	write_dpkg corrupted-manifest '22.16.0-1nodesource1' '10.8.2-1nodesource1'
	write_ownership corrupted-manifest system-apt-nodesource system-apt-nodesource
	printf '%s\n' '{"schema_version":2,"components":"not-a-list"' >"${FIXTURE_ROOT}/corrupted-manifest/manifest.json"

	write_node interrupted-install v22.16.0
	write_npm interrupted-install 10.8.2
	write_dpkg interrupted-install '22.16.0-1nodesource1' '10.8.2-1nodesource1'
	write_ownership interrupted-install system-apt-nodesource system-apt-nodesource
	printf 'INSTALL\n' >"${FIXTURE_ROOT}/interrupted-install/state"

	write_node path-shadowing v22.16.0
	write_npm path-shadowing 10.8.2
	write_dpkg path-shadowing '22.16.0-1nodesource1' '10.8.2-1nodesource1'
	write_ownership path-shadowing shadowed shadowed
	write_exe "${FIXTURE_ROOT}/path-shadowing/bin/sudo" <<-'EOF_SUDO'
		#!/usr/bin/env bash
		printf 'shadow sudo invoked\n' >&2
		exit 99
	EOF_SUDO

	write_node conflicting-runtime v20.11.0
	write_npm conflicting-runtime 10.2.4
	write_codex conflicting-runtime 0.129.0
	write_dpkg conflicting-runtime '20.11.0-ubuntu1' '10.2.4-ubuntu1'
	write_ownership conflicting-runtime system-unowned system-apt-distro system-npm

	write_exe "${FIXTURE_ROOT}/missing-runtime/bin/dpkg-query" <<-'EOF_MISSING'
		#!/usr/bin/env bash
		exit 1
	EOF_MISSING
	write_ownership missing-runtime unknown unknown unknown
}

main "$@"
