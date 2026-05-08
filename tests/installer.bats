#!/usr/bin/env bats

setup() {
	export REPO_ROOT="${BATS_TEST_DIRNAME}/.."
}

@test "retry succeeds after a transient failure" {
	run bash -c '. "${0}/scripts/lib/retry.sh"; count=0; flaky() { count=$((count + 1)); [[ ${count} -eq 2 ]]; }; retry 3 0 flaky' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
}

@test "secure download rejects non-HTTPS URLs" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/retry.sh"; . "${0}/scripts/lib/security.sh"; security_download "http://example.com/file" /tmp/zcodex-test-download' "${REPO_ROOT}"
	[ "$status" -ne 0 ]
}

@test "installer help renders usage" {
	run bash "${REPO_ROOT}/scripts/install-codex-ubuntu.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
}

@test "platform normalizes arm architecture aliases" {
	local tmpbin
	tmpbin="$(mktemp -d)"
	cat >"${tmpbin}/uname" <<'SH'
#!/usr/bin/env bash
printf 'aarch64\n'
SH
	chmod +x "${tmpbin}/uname"
	run env PATH="${tmpbin}:${PATH}" bash -c '. "${0}/scripts/lib/platform.sh"; platform_arch_normalized' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[ "$output" = "arm64" ]
}

@test "platform detects WSL from proc version" {
	local proc_version
	proc_version="$(mktemp)"
	printf 'Linux version 5.15.90.1-microsoft-standard-WSL2\n' >"${proc_version}"
	run env ZCODEX_PROC_VERSION_FILE="${proc_version}" bash -c '. "${0}/scripts/lib/platform.sh"; platform_is_wsl' "${REPO_ROOT}"
	rm -f "${proc_version}"
	[ "$status" -eq 0 ]
}

@test "platform reports injected container runtime" {
	run env ZCODEX_CONTAINER_RUNTIME=containerd bash -c '. "${0}/scripts/lib/platform.sh"; platform_container_runtime' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[ "$output" = "containerd" ]
}

@test "doctor help renders usage" {
	run bash "${REPO_ROOT}/scripts/doctor.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
}

@test "doctor offline mode skips network check" {
	run bash -c '. "${0}/scripts/doctor.sh"; logging_init; OFFLINE_MODE=true; check_network' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipping network check"* ]]
}

@test "doctor allows PATH warnings by default" {
	local tmpbin
	tmpbin="$(mktemp -d)"
	chmod 755 "${tmpbin}"
	run env PATH="${tmpbin}::/usr/bin" bash -c '. "${0}/scripts/doctor.sh"; logging_init; WARN_COUNT=0; ERROR_COUNT=0; check_path || true; printf "ERROR=%s WARN=%s\n" "${ERROR_COUNT}" "${WARN_COUNT}"' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"empty entry"* ]]
	[[ "$output" == *"ERROR=0 WARN=1"* ]]
}

@test "doctor treats docker as optional" {
	run bash -c '. "${0}/scripts/doctor.sh"; logging_init; runtime_command_exists() { return 1; }; WARN_COUNT=0; ERROR_COUNT=0; check_command docker optional; printf "ERROR=%s WARN=%s\n" "${ERROR_COUNT}" "${WARN_COUNT}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"docker is missing (optional)"* ]]
	[[ "$output" == *"ERROR=0 WARN=1"* ]]
}

@test "doctor strict mode fails warnings" {
	run bash -c '. "${0}/scripts/doctor.sh"; logging_init; STRICT_MODE=1; WARN_COUNT=1; ERROR_COUNT=0; FATAL_COUNT=0; print_summary' "${REPO_ROOT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"strict mode"* ]]
}

@test "dependency validation reports missing commands" {
	run env PATH="/nonexistent" /usr/bin/bash -c '. "${0}/scripts/lib/dependencies.sh"; validate_required_tooling' "${REPO_ROOT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Missing required dependency"* ]]
	[[ "$output" == *"make deps-dev"* ]]
}

@test "dependency descriptions include release tooling" {
	run bash -c '. "${0}/scripts/lib/dependencies.sh"; dependency_command_description bats; dependency_install_hint bats' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Bats test runner"* ]]
	[[ "$output" == *"sudo apt install bats"* ]]
}

@test "doctor reports missing release tooling as warnings" {
	run bash -c '. "${0}/scripts/doctor.sh"; logging_init; runtime_command_exists() { return 1; }; WARN_COUNT=0; ERROR_COUNT=0; check_release_tooling; printf "ERROR=%s WARN=%s\n" "${ERROR_COUNT}" "${WARN_COUNT}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Bats test runner is missing"* ]]
	[[ "$output" == *"make deps-dev"* ]]
	[[ "$output" == *"ERROR=0 WARN=5"* ]]
}

@test "backup_file preserves existing files under backup root" {
	local tmpdir
	local source_file
	tmpdir="$(mktemp -d)"
	source_file="${tmpdir}/home/user/.codex/config.toml"
	mkdir -p "$(dirname "${source_file}")"
	printf 'existing config\n' >"${source_file}"

	run env ZCODEX_BACKUP_DIR="${tmpdir}/backup" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/backup.sh"; backup_file "${1}"; cat "${ZCODEX_BACKUP_DIR}/${1#/}"' "${REPO_ROOT}" "${source_file}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"existing config"* ]]
}

@test "example zcodex config is valid TOML" {
	run python3 -c 'import pathlib, sys, tomllib; data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text()); assert data["installer"]["version"] == "0.2.0"; assert data["runtime"]["nodejs"]["version"] == "22"; assert data["custom_instructions"]["shell"].startswith("#!/bin/bash")' "${REPO_ROOT}/config/zcodex/config.toml"
	[ "$status" -eq 0 ]
}

@test "codex_write_config backs up existing config before rewrite" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	mkdir -p "${tmpdir}/home/.codex"
	printf 'old config\n' >"${tmpdir}/home/.codex/config.toml"

	run env -u CODEX_HOME HOME="${tmpdir}/home" ZCODEX_BACKUP_DIR="${tmpdir}/backup" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/backup.sh"; . "${0}/scripts/lib/codex.sh"; codex_write_config; cat "${ZCODEX_BACKUP_DIR}/${HOME#/}/.codex/config.toml"; printf -- "---\n"; cat "${HOME}/.codex/config.toml"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"old config"* ]]
	[[ "$output" == *"model = \"gpt-5-codex\""* ]]
}

@test "runtime loader exposes modular installer functions" {
	run bash -c '. "${0}/scripts/lib/runtime.sh"; declare -F platform_validate security_download codex_write_config shell_configure_codex installer_run installer_install_docker >/dev/null' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
}

@test "installer parser toggles modular phase flags" {
	run bash -c '. "${0}/scripts/lib/runtime.sh"; installer_parse_args --ci --dry-run --skip-docker --skip-optional; printf "%s %s %s %s\n" "${CI_MODE}" "${DRY_RUN}" "${SKIP_DOCKER}" "${SKIP_OPTIONAL}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[ "$output" = "true true true true" ]
}

@test "checksum verification rejects malformed digests" {
	local artifact
	artifact="$(mktemp)"
	printf 'artifact\n' >"${artifact}"
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; security_verify_sha256 "${1}" not-a-sha' "${REPO_ROOT}" "${artifact}"
	rm -f "${artifact}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid SHA-256"* ]]
}

@test "manifest checksum verification validates named artifacts" {
	local tmpdir
	local artifact
	local digest
	tmpdir="$(mktemp -d)"
	artifact="${tmpdir}/codex.tar.gz"
	printf 'artifact\n' >"${artifact}"
	digest="$(sha256sum "${artifact}" | awk '{ print $1 }')"
	printf '%s  codex.tar.gz\n' "${digest}" >"${tmpdir}/SHA256SUMS"

	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; security_verify_manifest_entry "${1}" "${2}"' "${REPO_ROOT}" "${tmpdir}/SHA256SUMS" "${artifact}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
}

@test "doctor repair creates missing Codex config" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run env -u CODEX_HOME HOME="${tmpdir}/home" CI=true bash -c '. "${0}/scripts/doctor.sh"; logging_init; FAILED=0; run_repairs; test -f "${HOME}/.codex/config.toml"; stat -c "%a" "${HOME}/.codex/config.toml"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"600"* ]]
}

@test "release orchestrator help renders usage" {
	run bash "${REPO_ROOT}/codex.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
}

@test "release orchestrator dry-run basic mode delegates to installer" {
	run env -u NVM_DIR HOME="${BATS_TEST_TMPDIR}/home" PATH="/usr/bin:/bin" ZCODEX_RELEASE_LOG="${BATS_TEST_TMPDIR}/release.log" bash "${REPO_ROOT}/codex.sh" basic --dry-run --skip-docker --skip-optional
	[ "$status" -eq 0 ]
	[[ "$output" == *"Running Basic Installation"* ]]
	[[ "$output" == *"Dry run completed without making changes"* ]]
}

@test "pins validate default deterministic versions" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/pins.sh"; pins_validate; pins_summary' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"codex-cli=0.129.0"* ]]
}

@test "state tracking writes current phase and history" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark VERIFY "unit test"; state_current_phase; test -s "${ZCODEX_STATE_DIR}/history.log"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"VERIFY"* ]]
}

@test "manifest writer emits schema and pinned codex component" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run env HOME="${tmpdir}/home" ZCODEX_CONTAINER_RUNTIME=none bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/state.sh"; . "${0}/scripts/lib/manifest.sh"; logging_init; state_mark VERIFY_RUNTIME "unit test"; manifest_write running; python3 -m json.tool "${ZCODEX_MANIFEST_FILE}" >/dev/null; cat "${ZCODEX_MANIFEST_FILE}"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"schema_version": 1'* ]]
	[[ "$output" == *'"installer_version": "0.2.0"'* ]]
	[[ "$output" == *'"install_state": {'* ]]
	[[ "$output" == *'"verification_hashes": {'* ]]
	[[ "$output" == *'"name": "codex-cli"'* ]]
	[[ "$output" == *'"desired_version": "0.129.0"'* ]]
}

@test "pins reject unsafe apt package versions" {
	run env ZCODEX_DOCKER_PACKAGE_VERSION='1.2.3;rm' bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/pins.sh"; pins_validate' "${REPO_ROOT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid ZCODEX_DOCKER_PACKAGE_VERSION"* ]]
}

@test "state machine rejects invalid phases and marks completed phases" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark INSTALL "unit test" running; state_complete_phase INSTALL; state_phase_completed INSTALL; ! state_mark UNKNOWN "bad"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Invalid install phase"* ]]
}

@test "installer resume skips completed install phase" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run env HOME="${tmpdir}/home" ZCODEX_CONTAINER_RUNTIME=none bash -c '. "${0}/scripts/lib/runtime.sh"; logging_init; state_mark INSTALL "interrupted" running; state_complete_phase INSTALL; INSTALLER_PREVIOUS_PHASE=INSTALL; installer_prepare_recovery; installer_run_phase INSTALL "install core runtime" bash -c "echo should-not-run; exit 3"; printf "phase=%s\n" "$(state_current_phase)"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipping INSTALL"* ]]
	[[ "$output" != *"should-not-run"* ]]
}

@test "runtime capability registry reports apt support" {
	run bash -c '. "${0}/scripts/lib/platform.sh"; runtime_capability_registry' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"supports_apt="* ]]
	[[ "$output" == *"supports_systemd="* ]]
	[[ "$output" == *"supports_docker="* ]]
	[[ "$output" == *"supports_rootless="* ]]
}

@test "supports_apt is command capability based" {
	local tmpbin
	tmpbin="$(mktemp -d)"
	cat >"${tmpbin}/apt-get" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	cat >"${tmpbin}/dpkg-query" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	chmod +x "${tmpbin}/apt-get" "${tmpbin}/dpkg-query"
	run env PATH="${tmpbin}:/usr/bin:/bin" bash -c '. "${0}/scripts/lib/platform.sh"; supports_apt' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
}

@test "supports_systemd can be enabled for tests without a running init" {
	run env ZCODEX_ASSUME_SYSTEMD=true bash -c '. "${0}/scripts/lib/platform.sh"; supports_systemd' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
}

@test "runtime_exec_logged preserves command exit status" {
	local logfile
	logfile="${BATS_TEST_TMPDIR}/exec.log"
	run bash -c '. "${0}/scripts/lib/exec.sh"; runtime_exec_logged "${1}" "unit command" bash -c "printf output; exit 7"' "${REPO_ROOT}" "${logfile}"
	[ "$status" -eq 7 ]
	[[ "$output" == *"unit command"* ]]
	[[ "$output" == *"output"* ]]
}

@test "state explicit context writes isolated phase state" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark_in "${1}/home" "${1}/state" VERIFY "explicit" running; state_current_phase_in "${1}/state"; test -s "${1}/state/history.log"' "${REPO_ROOT}" "${tmpdir}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"VERIFY"* ]]
}

@test "installer parser accepts runtime modes and ci selects ci mode" {
	run bash -c '. "${0}/scripts/lib/runtime.sh"; installer_parse_args --runtime-mode existing-runtime; printf "%s\n" "${ZCODEX_RUNTIME_MODE}"; installer_parse_args --ci; printf "%s %s\n" "${CI_MODE}" "${ZCODEX_RUNTIME_MODE}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *$'existing-runtime
true ci'* ]]
}

@test "runtime conflict report fails NodeSource nodejs with distro npm" {
	local audit
	audit=$'mode=clean-system\nnode_path=/usr/bin/node\nnode_version=22.1.0\nnode_owner=system-apt-nodesource\nnode_path_count=1\nnpm_path=/usr/bin/npm\nnpm_version=10.0.0\nnpm_owner=system-apt-nodesource\nnpm_path_count=1\nnvm_detected=false\nasdf_detected=false\napt_nodejs=true\nnodesource_nodejs=true\ndistro_npm=true\nnode_paths=/usr/bin/node\nnpm_paths=/usr/bin/npm'
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_conflict_report "${1}"' "${REPO_ROOT}" "${audit}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"fatal|NodeSource nodejs is installed with distro npm"* ]]
}

@test "runtime conflict report warns on PATH shadows" {
	local audit
	audit=$'mode=clean-system\nnode_path=/usr/local/bin/node\nnode_version=22.1.0\nnode_owner=system-unowned\nnode_path_count=2\nnpm_path=/usr/local/bin/npm\nnpm_version=10.0.0\nnpm_owner=system-unowned\nnpm_path_count=2\nnvm_detected=false\nasdf_detected=false\napt_nodejs=false\nnodesource_nodejs=false\ndistro_npm=false\nnode_paths=/usr/local/bin/node,/usr/bin/node\nnpm_paths=/usr/local/bin/npm,/usr/bin/npm'
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_conflict_report "${1}"' "${REPO_ROOT}" "${audit}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"warn|multiple node binaries"* ]]
	[[ "$output" == *"warn|multiple npm binaries"* ]]
}

@test "global npm install refuses user-managed runtime without opt-in" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/retry.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_audit() { printf "node_owner=user-nvm\nnpm_owner=user-nvm\n"; }; nodejs_install_global_packages example-package' "${REPO_ROOT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Refusing to install global npm packages into user-managed runtime"* ]]
}

@test "runtime ownership uses dpkg package owner for npm verification" {
	local tmpbin
	tmpbin="$(mktemp -d)"
	cat >"${tmpbin}/dpkg-query" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-S" && "$2" == "/usr/bin/npm" ]]; then
	printf 'npm: /usr/bin/npm\n'
	exit 0
fi
if [[ "$1" == "-S" && "$2" == "/usr/bin/node" ]]; then
	printf 'nodejs: /usr/bin/node\n'
	exit 0
fi
if [[ "$1" == "-W" && "$4" == "nodejs" ]]; then
	printf 'install ok installed'
	exit 0
fi
exit 1
SH
	cat >"${tmpbin}/apt-cache" <<'SH'
#!/usr/bin/env bash
cat <<POLICY
nodejs:
  Candidate: 22.0.0-1nodesource1
  Version table:
     22.0.0-1nodesource1 500
        release o=NodeSource
POLICY
SH
	chmod +x "${tmpbin}/dpkg-query" "${tmpbin}/apt-cache"
	run env PATH="${tmpbin}:/usr/bin:/bin" bash -c '. "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_owner_for_path /usr/bin/npm; nodejs_owner_for_path /usr/bin/node' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *$'system-apt-distro
system-apt-nodesource'* ]]
}

@test "runtime conflict report rejects clean-system unowned active binaries" {
	local audit
	audit=$'mode=clean-system\nnode_path=/usr/local/bin/node\nnode_version=22.1.0\nnode_owner=system-unowned\nnode_package=unknown\nnode_path_count=1\nnpm_path=/usr/local/bin/npm\nnpm_version=10.0.0\nnpm_owner=system-unowned\nnpm_package=unknown\nnpm_path_count=1\nnvm_detected=false\nasdf_detected=false\napt_nodejs=false\nnodesource_nodejs=false\ndistro_npm=false\nnode_paths=/usr/local/bin/node\nnpm_paths=/usr/local/bin/npm'
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_conflict_report "${1}"' "${REPO_ROOT}" "${audit}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"fatal|clean-system mode found unowned or unknown Node.js/npm binaries"* ]]
	[[ "$output" == *"warn|npm package ownership could not be verified"* ]]
}

@test "runtime conflict report enforces ci node pin" {
	local audit
	audit=$'mode=ci\nnode_path=/usr/bin/node\nnode_version=20.1.0\nnode_owner=system-apt-distro\nnode_package=nodejs\nnode_path_count=1\nnpm_path=/usr/bin/npm\nnpm_version=10.0.0\nnpm_owner=system-apt-distro\nnpm_package=npm\nnpm_path_count=1\nnvm_detected=false\nasdf_detected=false\napt_nodejs=true\nnodesource_nodejs=false\ndistro_npm=true\nnode_paths=/usr/bin/node\nnpm_paths=/usr/bin/npm'
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_conflict_report "${1}"' "${REPO_ROOT}" "${audit}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"fatal|ci Node.js version v20.1.0 does not satisfy pin 22"* ]]
}
