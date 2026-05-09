SHELL := /usr/bin/bash
.SHELLFLAGS := -euo pipefail -c

export LC_ALL := C.UTF-8
export LANG := C.UTF-8
export TZ := UTC
export TMPDIR ?= /tmp

.PHONY: install deps-dev validate-env lint fmt fmt-check workflow-policy test doctor validate ci-local release release-checksum release-reproducible

install:
	bash scripts/install-codex-ubuntu.sh

deps-dev:
	bash -c '. scripts/lib/dependencies.sh; install_dev_dependencies_ubuntu'

validate-env:
	bash -c '. scripts/lib/dependencies.sh; validate_required_tooling'

lint:
	{ printf '%s\0' codex.sh; find scripts tests -type f -name '*.sh' -print0 | sort -z; } | xargs -0 shellcheck

fmt:
	shfmt -w codex.sh scripts tests

fmt-check:
	shfmt -d codex.sh scripts tests

workflow-policy:
	python3 tests/workflow_policy.py

test:
	bats tests

doctor:
	bash scripts/doctor.sh

validate: validate-env lint fmt-check workflow-policy test

ci-local: validate
	bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
	scripts/release.sh --skip-validate

release:
	bash scripts/release.sh

release-checksum:
	cd dist && sha256sum -c SHA256SUMS

release-reproducible:
	rm -rf dist.repro-a dist.repro-b
	bash scripts/build-release.sh --output-dir dist.repro-a
	bash scripts/build-release.sh --output-dir dist.repro-b
	cmp dist.repro-a/zcodex-v$$(tr -d '[:space:]' < VERSION).tar.gz dist.repro-b/zcodex-v$$(tr -d '[:space:]' < VERSION).tar.gz
