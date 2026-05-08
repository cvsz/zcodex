#!/usr/bin/env bash
# Build deterministic zcodex release artifacts and checksums.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
CHANGELOG_FILE="${REPO_ROOT}/CHANGELOG.md"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/dist}"
SOURCE_DATE_EPOCH_OVERRIDE="${SOURCE_DATE_EPOCH:-}"
SKIP_VALIDATE=0
CLEAN_OUTPUT=1
VERSION_OVERRIDE=""
GIT_REF="HEAD"

# shellcheck source=scripts/lib/dependencies.sh
. "${LIB_DIR}/dependencies.sh"

usage() {
	cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Build zcodex release artifacts from a committed git tree.

Options:
  --version VERSION       Override VERSION file value, without a leading v.
  --ref GIT_REF           Git ref to archive. Defaults to HEAD.
  --output-dir DIR        Artifact directory. Defaults to ./dist.
  --skip-validate         Skip make validate before building artifacts.
  --no-clean              Do not remove the output directory before building.
  -h, --help              Show this help.

Outputs:
  zcodex-vX.Y.Z.tar.gz
  SHA256SUMS
  RELEASE_NOTES.md
  SIGNING_INSTRUCTIONS.md
USAGE
}

log() {
	printf '[release] %s\n' "$*"
}

fail() {
	printf '[release] ERROR: %s\n' "$*" >&2
	printf '%s\n' '[release] HINT: run make validate-env for dependency diagnostics or make deps-dev on Ubuntu to install development tools.' >&2
	exit 1
}

read_version() {
	local version
	if [[ -n "${VERSION_OVERRIDE}" ]]; then
		version="${VERSION_OVERRIDE}"
	else
		[[ -f "${VERSION_FILE}" ]] || fail "missing VERSION file"
		version="$(tr -d '[:space:]' <"${VERSION_FILE}")"
	fi

	[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] ||
		fail "version must be semantic and must not include a leading v: ${version}"
	printf '%s\n' "${version}"
}

validate_release_context() {
	local version="$1"
	local tag="v${version}"

	git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git work tree"
	git -C "${REPO_ROOT}" rev-parse --verify "${GIT_REF}^{tree}" >/dev/null 2>&1 || fail "invalid archive ref: ${GIT_REF}"

	if [[ -n "${GITHUB_REF_TYPE:-}" && "${GITHUB_REF_TYPE}" == "tag" && "${GITHUB_REF_NAME:-}" != "${tag}" ]]; then
		fail "GitHub tag ${GITHUB_REF_NAME} does not match VERSION-derived tag ${tag}"
	fi

	if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" =~ ^v && "${GITHUB_REF_NAME}" != "${tag}" ]]; then
		fail "release tag ${GITHUB_REF_NAME} does not match VERSION-derived tag ${tag}"
	fi
}

validate_environment() {
	log "Validating release/runtime dependencies before release work"
	validate_required_tooling || fail "missing release/runtime dependencies"
	require_command gzip 'gzip compressor' || fail "missing release archive dependency: gzip"
	require_command tar 'tar archiver' || fail "missing release archive dependency: tar"
	if [[ "${SKIP_VALIDATE}" -eq 0 ]]; then
		require_command make 'make build orchestrator' || fail "missing validation dependency: make"
	fi
}

run_validation() {
	if [[ "${SKIP_VALIDATE}" -eq 1 ]]; then
		log "Skipping validation by request."
		return 0
	fi
	log "Running release validation: make validate"
	make -C "${REPO_ROOT}" validate
}

prepare_output_dir() {
	if [[ "${CLEAN_OUTPUT}" -eq 1 ]]; then
		rm -rf "${OUTPUT_DIR}"
	fi
	mkdir -p "${OUTPUT_DIR}"
}

extract_release_notes() {
	local version="$1"
	local notes_file="$2"

	[[ -f "${CHANGELOG_FILE}" ]] || fail "missing CHANGELOG.md"
	awk -v section="## v${version}" '
		$0 == section || index($0, section " - ") == 1 { in_section = 1; print; next }
		in_section && /^## v/ { exit }
		in_section { print }
	' "${CHANGELOG_FILE}" >"${notes_file}"

	[[ -s "${notes_file}" ]] || fail "CHANGELOG.md has no section for v${version}"
}

write_signing_instructions() {
	local version="$1"
	local file="$2"
	cat >"${file}" <<SIGNING
# zcodex v${version} signing preparation

This release currently publishes unsigned artifacts plus SHA-256 checksums.
The release pipeline is structured so signed artifacts can be added without
changing the archive naming contract.

Future GPG signing:

    gpg --armor --detach-sign SHA256SUMS

Future cosign blob signing:

    cosign sign-blob --yes --output-signature SHA256SUMS.sig SHA256SUMS

Future SBOM generation:

    syft zcodex-v${version}.tar.gz -o spdx-json > zcodex-v${version}.spdx.json

Publish additional files alongside zcodex-v${version}.tar.gz and SHA256SUMS
when repository signing keys, OIDC policy, and SBOM ownership are finalized.
SIGNING
}

release_source_date_epoch() {
	if [[ -n "${SOURCE_DATE_EPOCH_OVERRIDE}" ]]; then
		[[ "${SOURCE_DATE_EPOCH_OVERRIDE}" =~ ^[0-9]+$ ]] || fail "SOURCE_DATE_EPOCH must be an integer Unix timestamp"
		printf '%s\n' "${SOURCE_DATE_EPOCH_OVERRIDE}"
		return 0
	fi

	if git -C "${REPO_ROOT}" rev-parse --verify "${GIT_REF}^{commit}" >/dev/null 2>&1; then
		git -C "${REPO_ROOT}" log -1 --format=%ct "${GIT_REF}"
		return 0
	fi

	printf '%s\n' 0
}

release_archive_stream() {
	local version="$1"
	local tag="v${version}"
	local prefix="zcodex-${tag}"
	local epoch

	epoch="$(release_source_date_epoch)"
	(
		local staging_dir
		staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/zcodex-release.XXXXXX")"
		trap 'rm -rf "${staging_dir}"' EXIT

		git -C "${REPO_ROOT}" archive --format=tar --prefix="${prefix}/" "${GIT_REF}" | tar -xf - -C "${staging_dir}"

		LC_ALL=C tar \
			--sort=name \
			--format=posix \
			--pax-option='exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime' \
			--mtime="@${epoch}" \
			--owner=0 \
			--group=0 \
			--numeric-owner \
			-cf - \
			-C "${staging_dir}" \
			"${prefix}" | gzip -n
	)
}

verify_reproducible_archive() {
	local version="$1"
	local archive_path="$2"
	local probe_path="${archive_path}.repro"
	local first_sha second_sha

	release_archive_stream "${version}" >"${probe_path}"
	first_sha="$(sha256sum "${archive_path}" | awk '{ print $1 }')"
	second_sha="$(sha256sum "${probe_path}" | awk '{ print $1 }')"
	rm -f "${probe_path}"
	if [[ "${first_sha}" != "${second_sha}" ]]; then
		fail "release archive is not reproducible across repeated builds"
	fi
	log "Reproducibility check passed: ${first_sha}"
}

build_archive() {
	local version="$1"
	local tag="v${version}"
	local archive_name="zcodex-${tag}.tar.gz"
	local archive_path="${OUTPUT_DIR}/${archive_name}"
	local release_notes="${OUTPUT_DIR}/RELEASE_NOTES.md"
	local signing_notes="${OUTPUT_DIR}/SIGNING_INSTRUCTIONS.md"

	log "Building deterministic archive: ${archive_name}"
	release_archive_stream "${version}" >"${archive_path}"
	verify_reproducible_archive "${version}" "${archive_path}"

	log "Generating SHA256SUMS"
	(
		cd "${OUTPUT_DIR}"
		sha256sum "${archive_name}" >SHA256SUMS
	)

	log "Extracting release notes from CHANGELOG.md"
	extract_release_notes "${version}" "${release_notes}"

	log "Writing signing and SBOM preparation notes"
	write_signing_instructions "${version}" "${signing_notes}"

	log "Release artifacts are ready in ${OUTPUT_DIR}"
	printf '%s\n' "${archive_path}"
	printf '%s\n' "${OUTPUT_DIR}/SHA256SUMS"
	printf '%s\n' "${release_notes}"
	printf '%s\n' "${signing_notes}"
}

main() {
	while [[ "$#" -gt 0 ]]; do
		case "$1" in
		--version)
			VERSION_OVERRIDE="${2:-}"
			[[ -n "${VERSION_OVERRIDE}" ]] || fail "--version requires a value"
			shift 2
			;;
		--ref)
			GIT_REF="${2:-}"
			[[ -n "${GIT_REF}" ]] || fail "--ref requires a value"
			shift 2
			;;
		--output-dir)
			OUTPUT_DIR="${2:-}"
			[[ -n "${OUTPUT_DIR}" ]] || fail "--output-dir requires a value"
			shift 2
			;;
		--skip-validate)
			SKIP_VALIDATE=1
			shift
			;;
		--no-clean)
			CLEAN_OUTPUT=0
			shift
			;;
		-h | --help)
			usage
			return 0
			;;
		*)
			fail "unknown option: $1"
			;;
		esac
	done

	local version
	validate_environment
	version="$(read_version)"
	validate_release_context "${version}"
	run_validation
	prepare_output_dir
	build_archive "${version}"
}

main "$@"
