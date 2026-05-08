SHELL := /usr/bin/env bash

.PHONY: install lint fmt fmt-check test doctor validate

install:
	bash scripts/install-codex-ubuntu.sh

lint:
	find scripts tests -type f -name '*.sh' -print0 | xargs -0 shellcheck

fmt:
	shfmt -w scripts tests

fmt-check:
	shfmt -d scripts tests

test:
	bats tests

doctor:
	bash scripts/doctor.sh

validate: lint fmt-check test
