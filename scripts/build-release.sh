#!/usr/bin/env bash
# Deterministic release artifact builder.
#
# This entry point intentionally delegates to scripts/release.sh so there is one
# implementation for archive ordering, metadata normalization, gzip headers, and
# checksum generation.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/release.sh" --skip-validate "$@"
