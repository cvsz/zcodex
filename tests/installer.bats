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

@test "doctor flags empty PATH entries" {
	local tmpbin
	tmpbin="$(mktemp -d)"
	chmod 755 "${tmpbin}"
	run env PATH="${tmpbin}::/usr/bin" bash -c '. "${0}/scripts/doctor.sh"; logging_init; FAILED=0; check_path || true; printf "FAILED=%s\n" "${FAILED}"' "${REPO_ROOT}"
	rm -rf "${tmpbin}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"empty entry"* ]]
	[[ "$output" == *"FAILED=1"* ]]
}

@test "doctor treats docker as optional" {
	run bash -c '. "${0}/scripts/doctor.sh"; logging_init; command_exists() { return 1; }; FAILED=0; check_command docker optional; printf "FAILED=%s\n" "${FAILED}"' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"docker is missing (optional)"* ]]
	[[ "$output" == *"FAILED=0"* ]]
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
	run bash -c '. "${0}/scripts/lib/runtime.sh"; declare -F platform_validate security_download codex_write_config shell_configure_codex >/dev/null' "${REPO_ROOT}"
	[ "$status" -eq 0 ]
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
