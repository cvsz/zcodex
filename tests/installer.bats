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
