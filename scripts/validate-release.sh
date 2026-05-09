#!/usr/bin/env bash
# Validate that a release tag, VERSION, and changelog form a publishable release.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
CHANGELOG_FILE="${REPO_ROOT}/CHANGELOG.md"
RELEASE_TAG="${1:-${GITHUB_REF_NAME:-}}"

usage() {
	cat <<USAGE
Usage: validate-release.sh [TAG]

Validate that TAG matches VERSION and the release changelog section.
When TAG is omitted, GITHUB_REF_NAME is used.
USAGE
}

fail() {
	printf '[release] ERROR: %s\n' "$*" >&2
	exit 1
}

read_release_version() {
	[[ -f "${VERSION_FILE}" ]] || fail "missing VERSION file: ${VERSION_FILE}"
	tr -d '[:space:]' <"${VERSION_FILE}"
}

main() {
	if [[ "${RELEASE_TAG}" == "-h" || "${RELEASE_TAG}" == "--help" ]]; then
		usage
		return 0
	fi

	[[ -n "${RELEASE_TAG}" ]] || fail 'missing release tag; pass TAG or set GITHUB_REF_NAME'

	local version expected_tag
	version="$(read_release_version)"
	expected_tag="v${version}"

	[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] ||
		fail "VERSION must be semantic and must not include a leading v: ${version}"
	[[ "${RELEASE_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] ||
		fail "release tag must be semantic and include one leading v: ${RELEASE_TAG}"
	[[ "${RELEASE_TAG}" == "${expected_tag}" ]] ||
		fail "release tag ${RELEASE_TAG} does not match VERSION-derived tag ${expected_tag}"

	if [[ -f "${CHANGELOG_FILE}" ]]; then
		grep -Eq "^## ${expected_tag}( |$)" "${CHANGELOG_FILE}" ||
			fail "CHANGELOG.md has no section for ${expected_tag}"
	else
		fail "missing CHANGELOG.md file: ${CHANGELOG_FILE}"
	fi

	printf '[release] OK: tag %s matches VERSION %s and CHANGELOG.md\n' "${RELEASE_TAG}" "${version}"
}

main "$@"
