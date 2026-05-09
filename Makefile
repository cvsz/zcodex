SHELL := /usr/bin/bash
.SHELLFLAGS := -euo pipefail -c

export LC_ALL := C.UTF-8
export LANG := C.UTF-8
export TZ := UTC
export TMPDIR ?= /tmp

.PHONY: install deps-dev validate-env lint fmt fmt-check workflow-policy test e2e-dry-run doctor diagnostics validate ci-local release release-checksum release-verify release-reproducible

install:
	bash scripts/install-codex-ubuntu.sh

deps-dev:
	bash -c '. scripts/lib/dependencies.sh; install_dev_dependencies_ubuntu'

validate-env:
	bash -c '. scripts/lib/dependencies.sh; validate_required_tooling'

lint:
	{ printf '%s\0' codex.sh reproducibility_validation.sh; find scripts tests -type f \( -name '*.sh' -o -name '*.bash' \) -print0 | LC_ALL=C sort -z; } | xargs -0 shellcheck

fmt:
	shfmt -w codex.sh reproducibility_validation.sh scripts tests

fmt-check:
	shfmt -d codex.sh reproducibility_validation.sh scripts tests

workflow-policy:
	python3 tests/workflow_policy.py

test:
	bats tests

e2e-dry-run:
	bash scripts/e2e-runner.sh --dry-run --ubuntu 22.04 --arch amd64
	bash scripts/e2e-runner.sh --dry-run --ubuntu 24.04 --arch arm64


doctor:
	bash scripts/doctor.sh

diagnostics:
	bash scripts/diagnostics.sh

validate: validate-env lint fmt-check workflow-policy test e2e-dry-run

ci-local: validate
	bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
	scripts/release.sh --skip-validate

release:
	bash scripts/release.sh

release-checksum:
	cd dist && sha256sum -c SHA256SUMS

release-verify:
	bash scripts/verify-release-artifacts.sh dist

release-reproducible:
	rm -rf dist.repro-a dist.repro-b
	bash scripts/build-release.sh --output-dir dist.repro-a
	bash scripts/build-release.sh --output-dir dist.repro-b
	cmp dist.repro-a/zcodex-v$$(tr -d '[:space:]' < VERSION).tar.gz dist.repro-b/zcodex-v$$(tr -d '[:space:]' < VERSION).tar.gz
