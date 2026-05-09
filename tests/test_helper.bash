#!/usr/bin/env bash
# Shared Bats helpers for deterministic, CI-safe test execution.

# shellcheck source=tests/helpers/runtime.bash
. "${BATS_TEST_DIRNAME}/helpers/runtime.bash"

zcodex_test_setup() {
	setup_test_environment
}

zcodex_test_teardown() {
	teardown_test_environment
}

zcodex_tmpdir() {
	mktemp -d "${TMPDIR%/}/${1:-tmp}.XXXXXX"
}

zcodex_tmpfile() {
	mktemp "${TMPDIR%/}/${1:-tmp}.XXXXXX"
}
