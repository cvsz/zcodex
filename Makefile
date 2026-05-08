SHELL := /usr/bin/env bash

.PHONY: install lint fmt fmt-check test doctor validate release release-checksum

install:
	bash scripts/install-codex-ubuntu.sh

lint:
	{ printf '%s\0' codex.sh; find scripts tests -type f -name '*.sh' -print0; } | xargs -0 shellcheck

fmt:
	shfmt -w codex.sh scripts tests

fmt-check:
	shfmt -d codex.sh scripts tests

test:
	bats tests

doctor:
	bash scripts/doctor.sh

validate: lint fmt-check test

release:
	bash scripts/release.sh

release-checksum:
	cd dist && sha256sum -c SHA256SUMS
