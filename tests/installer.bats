#!/usr/bin/env bats

load "test_helper.bash"

setup() {
	zcodex_test_setup
}

teardown() {
	zcodex_test_teardown
}

@test "retry succeeds after a transient failure" {
	run bash -c '. "${0}/scripts/lib/retry.sh"; count=0; flaky() { count=$((count + 1)); [[ ${count} -eq 2 ]]; }; retry 3 0 flaky' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
}

@test "secure download rejects non-HTTPS URLs" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/retry.sh"; . "${0}/scripts/lib/security.sh"; security_download "http://example.com/file" ${TMPDIR}/zcodex-test-download' "${REPO_ROOT}"
	[ "$status" -ne 0 ]
}

@test "installer help renders usage" {
	run bash "${REPO_ROOT}/scripts/install-codex-ubuntu.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
}

@test "platform normalizes arm architecture aliases" {
	local tmpbin
	tmpbin="$(zcodex_tmpdir)"
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

@test "platform does not execute os-release content from override file" {
	local os_release marker
	os_release="$(zcodex_tmpfile)"
	marker="$(zcodex_tmpfile)"
	cat >"${os_release}" <<EOF
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
\$(touch "${marker}")
EOF
	run env ZCODEX_OS_RELEASE_FILE="${os_release}" bash -c '. "${0}/scripts/lib/platform.sh"; platform_os_id; platform_os_version_id; platform_pretty_name' "${REPO_ROOT}"
	rm -f "${os_release}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ubuntu"* ]]
	[[ "$output" == *"24.04"* ]]
	[[ "$output" == *"Ubuntu 24.04 LTS"* ]]
	[ ! -f "${marker}" ]
	rm -f "${marker}"
}

@test "platform parses quoted os-release values safely" {
	local os_release
	os_release="$(zcodex_tmpfile)"
	cat >"${os_release}" <<'EOF'
ID="ubuntu"
VERSION_ID='24.04'
PRETTY_NAME="Ubuntu Linux \"Stable\""
EOF
	run env ZCODEX_OS_RELEASE_FILE="${os_release}" bash -c '. "${0}/scripts/lib/platform.sh"; printf "%s|%s|%s\n" "$(platform_os_id)" "$(platform_os_version_id)" "$(platform_pretty_name)"' "${REPO_ROOT}"
	rm -f "${os_release}"
	[ "$status" -eq 0 ]
	[[ "$output" == 'ubuntu|24.04|Ubuntu Linux "Stable"' ]]
}

@test "platform detects WSL from proc version" {
	local proc_version
	proc_version="$(zcodex_tmpfile)"
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

@test "doctor rejects unsafe PATH entries" {
	local tmpbin
	tmpbin="$(zcodex_tmpdir)"
	chmod 755 "${tmpbin}"
	run env PATH="${tmpbin}::/usr/bin" bash -c '. "${0}/scripts/doctor.sh"; logging_init; WARN_COUNT=0; ERROR_COUNT=0; check_path || true; printf "ERROR=%s WARN=%s\n" "${ERROR_COUNT}" "${WARN_COUNT}"' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"empty segment"* ]]
	[[ "$output" == *"ERROR=1"* ]]
}

@test "doctor CI mode sanitizes unsafe runner PATH" {
	local tmpbin
	tmpbin="$(zcodex_tmpdir)"
	chmod 700 "${tmpbin}"
	run env CI=true PATH="${tmpbin}:/usr/bin:/bin" bash -c '. "${0}/scripts/doctor.sh"; logging_init; WARN_COUNT=0; ERROR_COUNT=0; doctor_prepare_command_path; check_path; printf "PATH=%s\nERROR=%s WARN=%s\n" "${PATH}" "${ERROR_COUNT}" "${WARN_COUNT}"' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CI mode detected; replacing PATH"* ]]
	[[ "$output" == *"PATH=/usr/sbin:/usr/bin"* ]]
	[[ "$output" == *"ERROR=0 WARN=1"* ]]
}

@test "doctor allows user-local PATH entries in non-privileged mode" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/home/user/.local/bin" "${tmpdir}/home/user/.dotnet"
	chmod 777 "${tmpdir}/home/user/.local/bin" "${tmpdir}/home/user/.dotnet"
	run env HOME="${tmpdir}/home/user" PATH="${tmpdir}/home/user/.local/bin:${tmpdir}/home/user/.dotnet:/usr/bin" bash -c '. "${0}/scripts/doctor.sh"; logging_init; WARN_COUNT=0; ERROR_COUNT=0; check_path; printf "ERROR=%s WARN=%s\n" "${ERROR_COUNT}" "${WARN_COUNT}"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"PATH validation passed for non-privileged doctor context"* ]]
	[[ "$output" == *"User-local PATH entries detected"* ]]
	[[ "$output" == *"ERROR=0 WARN=1"* ]]
}

@test "doctor CI mode emits JSON diagnostics only" {
	local output_file
	output_file="$(zcodex_tmpfile)"
	run env CI=true bash "${REPO_ROOT}/scripts/doctor.sh" --offline
	printf '%s\n' "$output" >"${output_file}"
	python3 - "${output_file}" <<'PYCHECK'
import json
import sys
required = {"check_id", "severity", "risk_score", "message", "context", "recommendation", "auto_fixable"}
severities = {"INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"}
lines = [line for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
assert lines, "doctor produced no diagnostics"
for line in lines:
    diagnostic = json.loads(line)
    assert required <= diagnostic.keys(), diagnostic
    assert diagnostic["severity"] in severities, diagnostic
    assert isinstance(diagnostic["risk_score"], int), diagnostic
    assert 0 <= diagnostic["risk_score"] <= 100, diagnostic
    assert isinstance(diagnostic["auto_fixable"], bool), diagnostic
PYCHECK
	rm -f "${output_file}"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"check_id":"doctor.summary"'* ]]
	[[ "$output" != *'[WARN]'* ]]
	[[ "$output" != *'Summary:'* ]]
}

@test "doctor debug mode includes trace context and structured JSON" {
	run bash "${REPO_ROOT}/scripts/doctor.sh" --mode debug --offline
	[ "$status" -eq 0 ]
	[[ "$output" == *"context="* ]]
	[[ "$output" == *'"check_id":"doctor.network.offline"'* ]]
}

@test "doctor JSON diagnostics include remediation suggestions" {
	local output_file
	output_file="$(zcodex_tmpfile)"
	run env CI=true bash "${REPO_ROOT}/scripts/doctor.sh" --offline
	printf '%s\n' "$output" >"${output_file}"
	python3 - "${output_file}" <<'PYCHECK'
import json
import sys
required = {"issue", "root_cause", "fix_strategy", "fix_type", "fix", "confidence", "patch_snippet"}
fix_types = {"command", "patch", "config"}
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    diagnostic = json.loads(line)
    assert required <= diagnostic.keys(), diagnostic
    assert diagnostic["fix_type"] in fix_types, diagnostic
    assert isinstance(diagnostic["fix"], str) and diagnostic["fix"], diagnostic
    assert isinstance(diagnostic["confidence"], (int, float)), diagnostic
    assert 0 <= diagnostic["confidence"] <= 1, diagnostic
PYCHECK
	rm -f "${output_file}"
	[ "$status" -eq 0 ]
}

@test "doctor suggests install commands for missing dependencies" {
	run bash -c '. "${0}/scripts/doctor.sh"; logging_init; DOCTOR_OUTPUT_MODE=ci; runtime_command_exists() { return 1; }; check_command git || true' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"check_id":"doctor.command.git.missing"'* ]]
	[[ "$output" == *'"fix_type":"command"'* ]]
	[[ "$output" == *'Install git: sudo apt install git'* ]]
}

@test "doctor suggests a PATH reorder patch for PATH misconfiguration" {
	local tmpbin
	tmpbin="$(zcodex_tmpdir)"
	chmod 755 "${tmpbin}"
	run env PATH="${tmpbin}::/usr/bin" bash -c '. "${0}/scripts/doctor.sh"; logging_init; DOCTOR_OUTPUT_MODE=ci; check_path || true' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"check_id":"doctor.path.invalid"'* ]]
	[[ "$output" == *'"fix_type":"patch"'* ]]
	[[ "$output" == *"trusted_path="* ]]
}

@test "strict PATH validation rejects user local bin but warns for dotnet" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/home/user/.dotnet"
	chmod 755 "${tmpdir}/home/user/.dotnet"
	run env HOME="${tmpdir}/home/user" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; logging_init; security_validate_path "${HOME}/.dotnet:/usr/bin" strict' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"PATH risk warning"* ]]
	[[ "$output" == *"score=65"* ]]
	[[ "$output" == *"classification=USER_LOCAL_RISKY"* ]]
}

@test "advanced PATH risk analysis emits per-entry JSON for warning and allow actions" {
	local tmpdir output_file
	tmpdir="$(zcodex_tmpdir)"
	output_file="$(zcodex_tmpfile)"
	mkdir -p "${tmpdir}/home/user/.dotnet"
	chmod 755 "${tmpdir}/home/user/.dotnet"
	run env HOME="${tmpdir}/home/user" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; logging_init; security_analyze_path "${1}:/usr/bin" strict true' "${REPO_ROOT}" "${tmpdir}/home/user/.dotnet"
	printf '%s\n' "$output" >"${output_file}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	python3 - "${output_file}" <<'PYCHECK'
import json
import sys
entries = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.startswith("{")]
assert len(entries) == 2, entries
risky = entries[0]
assert risky["classification"] == "USER_LOCAL_RISKY", risky
assert risky["risk_score"] == 65, risky
assert risky["action"] == "warn", risky
system = entries[1]
assert system["classification"] == "TRUSTED_SYSTEM", system
assert system["risk_score"] == 0, system
assert system["action"] == "allow", system
PYCHECK
	rm -f "${output_file}"
}

@test "strict PATH risk analysis blocks critical writable directories before system PATH" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/unknown"
	chmod 777 "${tmpdir}/unknown"
	run env HOME="${tmpdir}/home/user" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; logging_init; security_validate_path "${1}:/usr/bin" strict' "${REPO_ROOT}" "${tmpdir}/unknown"
	rm -rf "${tmpdir}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"PATH risk blocked"* ]]
	[[ "$output" == *"score=85"* ]]
	[[ "$output" == *"classification=USER_LOCAL_RISKY"* ]]
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
	[[ "$output" =~ ERROR=0[[:space:]]WARN=[0-9]+ ]]
}

@test "backup_file preserves existing files under backup root" {
	local tmpdir
	local source_file
	tmpdir="$(zcodex_tmpdir)"
	source_file="${tmpdir}/home/user/.codex/config.toml"
	mkdir -p "$(dirname "${source_file}")"
	printf 'existing config\n' >"${source_file}"

	run env ZCODEX_BACKUP_DIR="${tmpdir}/backup" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/backup.sh"; backup_file "${1}"; cat "${ZCODEX_BACKUP_DIR}/${1#/}"' "${REPO_ROOT}" "${source_file}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"existing config"* ]]
}

@test "example zcodex config is valid TOML" {
	run python3 -c 'import pathlib, sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["installer"]["version"] == "0.3.0"
assert data["runtime"]["nodejs"]["version"] == "22"
assert data["custom_instructions"]["shell"].startswith("#!/bin/bash")
' "${REPO_ROOT}/config/zcodex/config.toml"
	[ "$status" -eq 0 ]
}
@test "codex_write_config backs up existing config before rewrite" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/home/.codex"
	printf 'old config\n' >"${tmpdir}/home/.codex/config.toml"

	run env -u CODEX_HOME HOME="${tmpdir}/home" ZCODEX_BACKUP_DIR="${tmpdir}/backup" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/backup.sh"; . "${0}/scripts/lib/codex.sh"; codex_write_config; cat "${ZCODEX_BACKUP_DIR}/${HOME#/}/.codex/config.toml"; printf -- "---\n"; cat "${HOME}/.codex/config.toml"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"old config"* ]]
	[[ "$output" == *"model = \"codex-1\""* ]]
}

@test "runtime loader exposes modular installer functions" {
	run bash -c '. "${0}/scripts/lib/runtime.sh"; declare -F runtime_ctx_set platform_validate security_download codex_write_config shell_configure_codex installer_run installer_install_docker >/dev/null' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
}

@test "installer parser toggles modular phase flags" {
	run bash -c '. "${0}/scripts/lib/runtime.sh"; installer_parse_args --ci --dry-run --skip-docker --skip-optional; printf "%s %s %s %s\n" "${CI_MODE}" "${DRY_RUN}" "${SKIP_DOCKER}" "${SKIP_OPTIONAL}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[ "$output" = "true true true true" ]
}

@test "checksum verification rejects malformed digests" {
	local artifact
	artifact="$(zcodex_tmpfile)"
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
	tmpdir="$(zcodex_tmpdir)"
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
	tmpdir="$(zcodex_tmpdir)"
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
	run env -u NVM_DIR HOME="${ZCODEX_TEST_WORKDIR}/home" PATH="/usr/bin:/bin" ZCODEX_RELEASE_LOG="${ZCODEX_TEST_WORKDIR}/release.log" bash "${REPO_ROOT}/codex.sh" basic --dry-run --skip-docker --skip-optional
	[ "$status" -eq 0 ]
	[[ "$output" == *"Running Basic Installation"* ]]
	[[ "$output" == *"Dry run completed without making changes"* ]]
}

@test "release orchestrator prefers explicit release log" {
	run env -u NVM_DIR HOME="${ZCODEX_TEST_WORKDIR}/home" PATH="/usr/bin:/bin" LOG_FILE="${ZCODEX_TEST_WORKDIR}/missing/ambient.log" ZCODEX_RELEASE_LOG="${ZCODEX_TEST_WORKDIR}/release.log" bash "${REPO_ROOT}/codex.sh" basic --dry-run --skip-docker --skip-optional
	[ "$status" -eq 0 ]
	[ -s "${ZCODEX_TEST_WORKDIR}/release.log" ]
	[ ! -e "${ZCODEX_TEST_WORKDIR}/missing/ambient.log" ]
}

@test "release orchestrator rejects non-executable local scripts" {
	local tmprepo
	tmprepo="$(zcodex_tmpdir)/repo"
	mkdir -p "${tmprepo}"
	cp -a "${REPO_ROOT}/codex.sh" "${REPO_ROOT}/scripts" "${tmprepo}/"
	chmod -x "${tmprepo}/scripts/doctor.sh"

	run env -u NVM_DIR HOME="${ZCODEX_TEST_WORKDIR}/home" PATH="/usr/bin:/bin" ZCODEX_RELEASE_LOG="${ZCODEX_TEST_WORKDIR}/release.log" bash "${tmprepo}/codex.sh" basic --dry-run --skip-docker --skip-optional
	rm -rf "${tmprepo%/repo}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Required script is not executable:"* ]]
	[[ "$output" == *"Fix: chmod +x"* ]]
}

@test "release orchestrator CI dry-run treats missing host tools as advisory" {
	local tmpbin
	tmpbin="$(zcodex_tmpdir)"
	local command_name command_path
	for command_name in bash basename cat date dirname env mkdir tee; do
		command_path="$(type -P "${command_name}")"
		ln -s "${command_path}" "${tmpbin}/${command_name}"
	done

	run env -u NVM_DIR CI=true HOME="${ZCODEX_TEST_WORKDIR}/home" PATH="${tmpbin}" ZCODEX_RELEASE_LOG="${ZCODEX_TEST_WORKDIR}/release-ci.log" bash "${REPO_ROOT}/codex.sh" basic --dry-run --skip-docker --skip-optional
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Warning: Docker not found"* ]]
	[[ "$output" == *"Dry run completed without making changes"* ]]
}

@test "release orchestrator falls back when default log path is unwritable" {
	local tmpbin blocked_path
	tmpbin="$(zcodex_tmpdir)"
	blocked_path="${ZCODEX_TEST_WORKDIR}/not-a-directory"
	printf 'blocked\n' >"${blocked_path}"
	local command_name command_path
	for command_name in bash basename cat date dirname env mkdir tee; do
		command_path="$(type -P "${command_name}")"
		ln -s "${command_path}" "${tmpbin}/${command_name}"
	done

	run env -u NVM_DIR CI=true HOME="${ZCODEX_TEST_WORKDIR}/home" PATH="${tmpbin}" TMPDIR="${ZCODEX_TEST_WORKDIR}/tmp" LOG_FILE="${blocked_path}/release.log" bash "${REPO_ROOT}/codex.sh" basic --dry-run --skip-docker --skip-optional
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"not writable; using ${ZCODEX_TEST_WORKDIR}/tmp/zcodex/codex_release.log instead"* ]]
	[[ "$output" == *"Dry run completed without making changes"* ]]
	[ -s "${ZCODEX_TEST_WORKDIR}/tmp/zcodex/codex_release.log" ]
}

@test "apt package helpers force noninteractive timezone-safe installs" {
	local tmpbin
	tmpbin="$(zcodex_tmpdir)"
	cat >"${tmpbin}/apt-get" <<'SH'
#!/usr/bin/env bash
printf 'DEBIAN_FRONTEND=%s\n' "${DEBIAN_FRONTEND:-}"
printf 'DEBCONF_NONINTERACTIVE_SEEN=%s\n' "${DEBCONF_NONINTERACTIVE_SEEN:-}"
printf 'TZ=%s\n' "${TZ:-}"
printf 'args=%s\n' "$*"
SH
	chmod +x "${tmpbin}/apt-get"
	run env PATH="${tmpbin}:/usr/bin:/bin" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/retry.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/exec.sh"; . "${0}/scripts/lib/packages.sh"; runtime_privileged() { "$@"; }; packages_install tzdata' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"DEBIAN_FRONTEND=noninteractive"* ]]
	[[ "$output" == *"DEBCONF_NONINTERACTIVE_SEEN=true"* ]]
	[[ "$output" == *"TZ=Etc/UTC"* ]]
	[[ "$output" == *"--force-confdef"* ]]
}

@test "pins validate default deterministic versions" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/pins.sh"; pins_validate; pins_summary' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"codex-cli=0.129.0"* ]]
}

@test "state tracking writes current phase and history" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark VERIFY "unit test"; state_current_phase; test -s "${ZCODEX_STATE_DIR}/history.log"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"VERIFY"* ]]
}

@test "manifest writer emits schema and pinned codex component" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	run env HOME="${tmpdir}/home" ZCODEX_CONTAINER_RUNTIME=none bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/state.sh"; . "${0}/scripts/lib/manifest.sh"; logging_init; state_mark VERIFY_RUNTIME "unit test"; manifest_write running; python3 -m json.tool "${ZCODEX_MANIFEST_FILE}" >/dev/null; cat "${ZCODEX_MANIFEST_FILE}"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"schema_version": 2'* ]]
	[[ "$output" == *'"installer_version": "0.3.0"'* ]]
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
	tmpdir="$(zcodex_tmpdir)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark INSTALL "unit test" running; state_complete_phase INSTALL; state_phase_completed INSTALL; ! state_mark UNKNOWN "bad"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Invalid install phase"* ]]
}

@test "installer resume skips completed install phase" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
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
	tmpbin="$(zcodex_tmpdir)"
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
	logfile="${ZCODEX_TEST_WORKDIR}/exec.log"
	run bash -c '. "${0}/scripts/lib/exec.sh"; runtime_exec_logged "${1}" "unit command" bash -c "printf output; exit 7"' "${REPO_ROOT}" "${logfile}"
	[ "$status" -eq 7 ]
	[[ "$output" == *"unit command"* ]]
	[[ "$output" == *"output"* ]]
}

@test "state explicit context writes isolated phase state" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark_in "${1}/home" "${1}/state" VERIFY "explicit" running; state_current_phase_in "${1}/state"; test -s "${1}/state/history.log"' "${REPO_ROOT}" "${tmpdir}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"VERIFY"* ]]
}

@test "installer CI dry-run sanitizes unsafe runner PATH" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	chmod 700 "${tmpdir}"
	run env CI=true PATH="${tmpdir}:/usr/bin:/bin" bash -c '. "${0}/scripts/lib/runtime.sh"; platform_validate() { printf "PATH=%s\n" "${PATH}"; }; pins_validate() { :; }; pins_summary() { :; }; installer_verify_inputs() { :; }; installer_runtime_audit_dry_run() { :; }; installer_run --dry-run --skip-docker --skip-optional' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CI mode detected; replacing PATH"* ]]
	[[ "$output" == *"PATH=/usr/sbin:/usr/bin"* ]]
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
	tmpbin="$(zcodex_tmpdir)"
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

@test "dry-run runtime audit reports install blockers without failing" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_audit() { cat <<AUDIT
mode=clean-system
node_path=/usr/local/bin/node
node_version=20.1.0
node_owner=system-unowned
node_package=unknown
node_path_count=1
npm_path=/usr/local/bin/npm
npm_version=10.0.0
npm_owner=unknown
npm_package=unknown
npm_path_count=1
nvm_detected=true
asdf_detected=false
apt_nodejs=false
nodesource_nodejs=false
distro_npm=false
node_paths=/usr/local/bin/node
npm_paths=/usr/local/bin/npm
AUDIT
}; nodejs_runtime_audit_phase false' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Runtime dry-run conflict"* ]]
	[[ "$output" == *"Runtime dry run reported"* ]]
}

@test "strict runtime audit still fails install blockers" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_audit() { cat <<AUDIT
mode=clean-system
node_path=/usr/local/bin/node
node_version=20.1.0
node_owner=system-unowned
node_package=unknown
node_path_count=1
npm_path=/usr/local/bin/npm
npm_version=10.0.0
npm_owner=unknown
npm_package=unknown
npm_path_count=1
nvm_detected=true
asdf_detected=false
apt_nodejs=false
nodesource_nodejs=false
distro_npm=false
node_paths=/usr/local/bin/node
npm_paths=/usr/local/bin/npm
AUDIT
}; nodejs_runtime_audit_phase true' "${REPO_ROOT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Runtime audit failed"* ]]
}

@test "runtime conflict report enforces ci node pin" {
	local audit
	audit=$'mode=ci\nnode_path=/usr/bin/node\nnode_version=20.1.0\nnode_owner=system-apt-distro\nnode_package=nodejs\nnode_path_count=1\nnpm_path=/usr/bin/npm\nnpm_version=10.0.0\nnpm_owner=system-apt-distro\nnpm_package=npm\nnpm_path_count=1\nnvm_detected=false\nasdf_detected=false\napt_nodejs=true\nnodesource_nodejs=false\ndistro_npm=true\nnode_paths=/usr/bin/node\nnpm_paths=/usr/bin/npm'
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/nodejs.sh"; nodejs_runtime_conflict_report "${1}"' "${REPO_ROOT}" "${audit}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"fatal|ci Node.js version v20.1.0 does not satisfy pin 22"* ]]
}

@test "security PATH validation rejects empty and relative segments" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; logging_init; PATH="/usr/bin::relative"; security_validate_path "${PATH}"' "${REPO_ROOT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"PATH contains an empty segment"* ]]
	[[ "$output" == *"PATH entry is not absolute"* ]]
}

@test "security PATH canonicalization removes duplicate entries" {
	run bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/security.sh"; logging_init; security_canonicalize_path "/usr/bin:/bin/../bin"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[ "$output" = "/usr/bin" ]
}

@test "runtime privileged wrapper rejects shadow sudo" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	printf '#!/usr/bin/env bash\nexit 0\n' >"${tmpdir}/sudo"
	chmod +x "${tmpdir}/sudo"
	[ "${EUID}" -eq 0 ] && skip "sudo shadow rejection only applies for non-root execution"
	run env PATH="${tmpdir}:/usr/bin:/bin" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/exec.sh"; logging_init; runtime_privileged true' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Refusing sudo outside trusted system paths"* ]]
}

@test "manifest schema validation rejects legacy schema" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	cat >"${tmpdir}/manifest.json" <<'JSON'
{"schema_version":1,"installer":{},"platform":{},"state":{},"components":[],"verification_hashes":{},"runtime":{}}
JSON
	run bash -c '. "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/manifest.sh"; manifest_validate_schema "${1}"' "${REPO_ROOT}" "${tmpdir}/manifest.json"
	rm -rf "${tmpdir}"
	[ "$status" -ne 0 ]
}

@test "release tag validation accepts VERSION-derived tag" {
	local version
	version="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"

	run bash "${REPO_ROOT}/scripts/validate-release-tag.sh" "v${version}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"matches VERSION ${version}"* ]]
}

@test "release tag validation rejects VERSION mismatch" {
	run bash "${REPO_ROOT}/scripts/validate-release-tag.sh" v9.9.9
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not match VERSION-derived tag"* ]]
}

@test "release archive generation is byte reproducible across output directories" {
	local first_dir second_dir version first_archive second_archive first_sha second_sha
	first_dir="$(zcodex_tmpdir)"
	second_dir="$(zcodex_tmpdir)"
	version="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"
	first_archive="${first_dir}/zcodex-v${version}.tar.gz"
	second_archive="${second_dir}/zcodex-v${version}.tar.gz"

	run env LC_ALL=C.UTF-8 LANG=C.UTF-8 TZ=UTC TMPDIR="${TMPDIR}" bash "${REPO_ROOT}/scripts/release.sh" --skip-validate --output-dir "${first_dir}"
	[ "$status" -eq 0 ]
	run env LC_ALL=C.UTF-8 LANG=C.UTF-8 TZ=UTC TMPDIR="${TMPDIR}" bash "${REPO_ROOT}/scripts/release.sh" --skip-validate --output-dir "${second_dir}"
	[ "$status" -eq 0 ]

	first_sha="$(sha256sum "${first_archive}" | awk '{ print $1 }')"
	second_sha="$(sha256sum "${second_archive}" | awk '{ print $1 }')"
	[ "${first_sha}" = "${second_sha}" ]
}

@test "release archive metadata is normalized" {
	local output_dir version archive listing
	output_dir="$(zcodex_tmpdir)"
	version="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"
	archive="${output_dir}/zcodex-v${version}.tar.gz"

	run env LC_ALL=C.UTF-8 LANG=C.UTF-8 TZ=UTC TMPDIR="${TMPDIR}" bash "${REPO_ROOT}/scripts/release.sh" --skip-validate --output-dir "${output_dir}"
	[ "$status" -eq 0 ]
	listing="$(tar -tvf "${archive}" | sed -n '1,5p')"
	[[ "${listing}" == *" 0/0 "* ]]
	[[ "${listing}" == *"2025-01-01"* ]]
}

@test "workflow policy rejects Bats helpers, cache restores, and deprecated action majors" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/workflows"
	cat >"${tmpdir}/workflows/bats-cache.yaml" <<'YAML'
name: bad-bats-cache
jobs:
  test:
    steps:
      - uses: actions/checkout@v4
      - uses: bats-core/bats-action@3.0.1
        with:
          support-install: true
          support-path: /usr/lib/bats-support
      - uses: actions/cache@v4
        with:
          path: /usr/lib/bats-support
          key: Linux-X64-bats-support-0.3.0
YAML

	run python3 "${REPO_ROOT}/tests/workflow_policy.py" "${tmpdir}/workflows"
	rm -rf "${tmpdir}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"bats-core/bats-action"* ]]
	[[ "$output" == *"support-install:"* ]]
	[[ "$output" == *"actions/checkout@v4"* ]]
	[[ "$output" == *"actions/cache@"* ]]
}

@test "workflow label validator ignores templated expressions" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/.github/workflows"
	cat >"${tmpdir}/.github/workflows/template.yml" <<'YAML'
name: templated
jobs:
  test:
    runs-on: ${{ matrix.runner }}
    steps:
      - run: echo ok
YAML

	run bash -c 'cd "$1" && bash "$2"' _ "${tmpdir}" "${REPO_ROOT}/scripts/verify-workflow-labels.sh"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
}

@test "runtime context stores sorted explicit phase metadata" {
	run bash -c '. "${0}/scripts/lib/context.sh"; runtime_ctx_set phase INSTALL; runtime_ctx_set phase_status running; runtime_ctx_snapshot' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[ "$output" = $'phase=INSTALL
phase_status=running' ]
}

@test "installer phase updates explicit runtime context" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/runtime.sh"; logging_init; installer_run_phase VERIFY "context test" true; runtime_ctx_get phase; runtime_ctx_get phase_status' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *$'VERIFY
completed'* ]]
}

@test "installer phase records elapsed timing metadata" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/runtime.sh"; logging_init; installer_run_phase VERIFY "timing test" bash -c "sleep 0.01"; runtime_ctx_get phase_elapsed_ms' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^[0-9]+$ ]]
	(( output >= 0 ))
}

@test "runtime fixture injection isolates PATH and HOME" {
	runtime_fixture_inject nodesource-node
	run bash -c 'printf "%s\n%s\n%s\n" "${HOME}" "${TMPDIR}" "$(node --version)"'
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ZCODEX_TEST_WORKDIR}/home"* ]]
	[[ "$output" == *"${ZCODEX_TEST_WORKDIR}/tmp"* ]]
	[[ "$output" == *"v22.16.0"* ]]
}

@test "deterministic environment helper normalizes locale and timezone" {
	run env LC_ALL=C LANG=C TZ=America/New_York bash -c '. "${0}/scripts/lib/environment.sh"; printf "%s %s %s\n" "${LC_ALL}" "${LANG}" "${TZ}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[ "$output" = "C.UTF-8 C.UTF-8 UTC" ]
}

@test "runtime fixtures can simulate broken npm without host npm" {
	runtime_fixture_inject broken-npm
	run npm --version
	[ "$status" -eq 42 ]
	[[ "$output" == *"corrupted prefix"* ]]
}

@test "manifest validation rejects corrupted fixture manifests" {
	runtime_fixture_inject corrupted-manifest
	run bash -c '. "${0}/scripts/lib/exec.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/manifest.sh"; manifest_validate_schema "${1}"' "${REPO_ROOT}" "${ZCODEX_RUNTIME_FIXTURE_DIR}/manifest.json"
	[ "$status" -ne 0 ]
}

@test "runtime helper exposes required isolation aliases" {
	local previous_workdir
	previous_workdir="${ZCODEX_TEST_WORKDIR}"
	teardown_test_environment

	run bash -c '. "${0}/tests/helpers/runtime.bash"; export BATS_TEST_DIRNAME="${0}/tests" BATS_TEST_NUMBER=777; setup_test_environment; inject_runtime_fixture conflicting-runtime; printf "%s\n%s\n%s\n%s\n" "${LC_ALL}/${LANG}/${TZ}" "${HOME}" "${TMPDIR}" "$(node --version)"; teardown_test_environment' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"C.UTF-8/C.UTF-8/UTC"* ]]
	[[ "$output" == *"/zcodex.777."* ]]
	[[ "$output" == *"v20.11.0"* ]]

	ZCODEX_TEST_WORKDIR="${previous_workdir}"
}

@test "runtime fixture matrix includes all release-hardening scenarios" {
	local fixture
	for fixture in clean-system apt-node nodesource-node nvm-node broken-npm stale-runtime corrupted-manifest interrupted-install path-shadowing conflicting-runtime missing-runtime; do
		[ -d "${REPO_ROOT}/tests/runtime-fixtures/${fixture}" ]
	done
}

@test "runtime helper isolates npm cache and prefix" {
	run bash -c 'printf "%s\n%s\n%s\n" "${npm_config_cache}" "${NPM_CONFIG_CACHE}" "${npm_config_prefix}"'
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ZCODEX_TEST_WORKDIR}/npm-cache"* ]]
	[[ "$output" == *"${ZCODEX_TEST_WORKDIR}/npm-prefix"* ]]
}

@test "state and logging honor fixed deterministic timestamps" {
	local tmpdir logfile
	tmpdir="$(zcodex_tmpdir)"
	logfile="${tmpdir}/fixed.log"
	run env HOME="${tmpdir}/home" LOG_FILE="${logfile}" ZCODEX_FIXED_TIMESTAMP="2001-02-03T04:05:06Z" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark VERIFY "fixed clock" running; log_json INFO "fixed log"; cat "${ZCODEX_STATE_DIR}/history.log"; cat "${LOG_FILE}"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"2001-02-03T04:05:06Z phase=VERIFY"* ]]
	[[ "$output" == *'"timestamp":"2001-02-03T04:05:06Z"'* ]]
	[[ "$output" == *"[2001-02-03T04:05:06Z]"* ]]
}

@test "missing-runtime fixture contains no host node or npm shadow" {
	inject_runtime_fixture missing-runtime
	run bash -c 'command -v node || true; command -v npm || true'
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "manifest migration upgrades v1 and validates integrity" {
	local tmpdir manifest
	tmpdir="$(zcodex_tmpdir)"
	manifest="${tmpdir}/manifest-v1.json"
	cat >"${manifest}" <<'JSON'
{"schema_version":1,"install_id":"legacy","state":{"phase":"INSTALL","status":"running"},"components":{"nodejs":"22.0.0"}}
JSON
	run bash -c '. "${0}/scripts/lib/exec.sh"; . "${0}/scripts/lib/manifest.sh"; manifest_migrate_file "${1}"; manifest_validate_schema "${1}"; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d[\"schema_version\"]); print(d[\"state\"][\"phase\"]); print(d[\"integrity\"][\"algorithm\"])" "${1}"' "${REPO_ROOT}" "${manifest}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *$'2\nINSTALL\nsha256'* ]]
}

@test "manifest validation rejects integrity tampering" {
	local tmpdir manifest
	tmpdir="$(zcodex_tmpdir)"
	manifest="${tmpdir}/manifest.json"
	run env HOME="${tmpdir}/home" ZCODEX_CONTAINER_RUNTIME=none bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/platform.sh"; . "${0}/scripts/lib/pins.sh"; . "${0}/scripts/lib/state.sh"; . "${0}/scripts/lib/manifest.sh"; logging_init; state_mark VERIFY_RUNTIME "unit test"; manifest_write running; python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d[\"state\"][\"phase\"] = \"INSTALL\"; open(p, \"w\").write(json.dumps(d, sort_keys=True, indent=2)+\"\\n\")" "${ZCODEX_MANIFEST_FILE}"; ! manifest_validate_schema "${ZCODEX_MANIFEST_FILE}"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"manifest integrity digest mismatch"* ]]
}

@test "state reconciliation removes stale completion markers" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	run env HOME="${tmpdir}/home" bash -c '. "${0}/scripts/lib/logging.sh"; . "${0}/scripts/lib/state.sh"; logging_init; state_mark INSTALL "unit test" running; mkdir -p "${ZCODEX_STATE_DIR}/completed.d"; printf stale >"${ZCODEX_STATE_DIR}/completed.d/NOT_A_PHASE"; state_reconcile; test ! -e "${ZCODEX_STATE_DIR}/completed.d/NOT_A_PHASE"' "${REPO_ROOT}"
	rm -rf "${tmpdir}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"stale_markers=1"* ]]
}

@test "release artifact verifier rejects malformed checksum manifests" {
	local tmpdir
	tmpdir="$(zcodex_tmpdir)"
	mkdir -p "${tmpdir}/dist"
	printf 'artifact\n' >"${tmpdir}/dist/zcodex-v0.0.0.tar.gz"
	printf 'bad  zcodex-v0.0.0.tar.gz\n' >"${tmpdir}/dist/SHA256SUMS"
	run bash "${REPO_ROOT}/scripts/verify-release-artifacts.sh" "${tmpdir}/dist"
	rm -rf "${tmpdir}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"FAILED"* || "$output" == *"ERROR"* ]]
}

@test "logging_init accepts explicit writable logfile" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run bash -c '. "${0}/scripts/lib/logging.sh"; logging_init "${1}/installer.log"; log_info "hello"; test -s "${1}/installer.log"' "${REPO_ROOT}" "${tmpdir}"
	[ "${status}" -eq 0 ]
}

@test "logging_init fails for missing log directory" {
	local tmpdir
	tmpdir="$(mktemp -d)"
	run bash -c '. "${0}/scripts/lib/logging.sh"; ! logging_init "${1}/missing/installer.log"' "${REPO_ROOT}" "${tmpdir}"
	[ "${status}" -eq 0 ]
}
