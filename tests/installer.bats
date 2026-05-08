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
