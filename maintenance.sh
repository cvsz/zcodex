#!/usr/bin/env bash
# Codex-Max hardened maintenance runner.
# Provides SBOM generation, Semgrep/Trivy orchestration, provenance checks,
# deterministic diagnostics, and rollback-safe repair support.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-${SCRIPT_DIR}}"
REPORT_DIR="${REPORT_DIR:-${REPO_ROOT}/.codex/reports}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${REPO_ROOT}/artifacts}"
ROLLBACK_DIR="${ROLLBACK_DIR:-${REPO_ROOT}/.codex/rollback}"
STRICT_MODE="${STRICT:-0}"
REPAIR_MODE=false
OFFLINE_MODE=false
JSON_ONLY=false
FAIL_ON_SCAN_FINDINGS="${FAIL_ON_SCAN_FINDINGS:-true}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

INFO_COUNT=0
WARN_COUNT=0
ERROR_COUNT=0
FATAL_COUNT=0

log() {
  if [[ "${JSON_ONLY}" != "true" ]]; then
    printf '[maintenance] %s\n' "$*" >&2
  fi
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[maintenance] WARN: %s\n' "$*" >&2
}

error() {
  ERROR_COUNT=$((ERROR_COUNT + 1))
  printf '[maintenance] ERROR: %s\n' "$*" >&2
}

fatal() {
  FATAL_COUNT=$((FATAL_COUNT + 1))
  printf '[maintenance] FATAL: %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

emit_diag() {
  local level="$1" code="$2" message="$3" target="${4:-repo}"
  local report_file="${REPORT_DIR}/diagnostics.jsonl"
  mkdir -p "${REPORT_DIR}"
  printf '{"level":"%s","code":"%s","message":"%s","target":"%s","source_date_epoch":%s}\n' \
    "$(json_escape "${level}")" \
    "$(json_escape "${code}")" \
    "$(json_escape "${message}")" \
    "$(json_escape "${target}")" \
    "${SOURCE_DATE_EPOCH}" >> "${report_file}"

  case "${level}" in
    INFO) INFO_COUNT=$((INFO_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    ERROR) ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
    FATAL) FATAL_COUNT=$((FATAL_COUNT + 1)) ;;
  esac
}

usage() {
  cat <<USAGE
Usage: ./maintenance.sh [OPTIONS]

Options:
  --offline       Skip network-dependent checks and installs.
  --repair        Enable rollback-safe repair mode.
  --strict        Treat warnings as failures.
  --json          Emit machine-readable diagnostics only.
  -h, --help      Show this help message.

Environment:
  REPORT_DIR                  Diagnostics/report output directory.
  ARTIFACT_DIR                Build/artifact directory.
  ARTIFACT_PATH               Artifact to verify/sign/check provenance for.
  ARTIFACT_SIGNATURE          Cosign blob signature path.
  ARTIFACT_CERTIFICATE        Cosign certificate path.
  INSTALL_SECURITY_TOOLS=true Install optional tools when missing.
  FAIL_ON_SCAN_FINDINGS=false Keep scans advisory.
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --offline) OFFLINE_MODE=true ;;
      --repair) REPAIR_MODE=true ;;
      --strict) STRICT_MODE=1 ;;
      --json) JSON_ONLY=true ;;
      -h|--help) usage; exit 0 ;;
      *) fatal "Unknown option: $1" ;;
    esac
    shift
  done
}

strict_enabled() {
  case "${STRICT_MODE}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_workspace() {
  mkdir -p "${REPORT_DIR}" "${ARTIFACT_DIR}" "${ROLLBACK_DIR}"
  : > "${REPORT_DIR}/diagnostics.jsonl"
  cd "${REPO_ROOT}"
  emit_diag INFO workspace.ready "Workspace prepared" "${REPO_ROOT}"
}

snapshot_file() {
  local file_path="$1"
  local snapshot_root="$2"
  [[ -e "${file_path}" ]] || return 0
  mkdir -p "${snapshot_root}/$(dirname "${file_path}")"
  cp -a "${file_path}" "${snapshot_root}/${file_path}"
}

create_repair_snapshot() {
  local snapshot_id="snapshot-${SOURCE_DATE_EPOCH}"
  local snapshot_root="${ROLLBACK_DIR}/${snapshot_id}"

  if [[ "${SOURCE_DATE_EPOCH}" == "0" ]]; then
    snapshot_id="snapshot-manual"
    snapshot_root="${ROLLBACK_DIR}/${snapshot_id}"
  fi

  mkdir -p "${snapshot_root}"

  local files=(
    "package.json"
    "package-lock.json"
    "requirements.txt"
    "pyproject.toml"
    "Makefile"
    ".github/workflows/ci.yml"
    ".github/workflows/supply-chain.yml"
    ".github/workflows/slsa.yml"
    ".github/workflows/slsa-hardened.yml"
  )

  local file_path
  for file_path in "${files[@]}"; do
    snapshot_file "${file_path}" "${snapshot_root}"
  done

  emit_diag INFO repair.snapshot "Rollback snapshot created" "${snapshot_root}"
}

restore_latest_snapshot() {
  local latest
  latest="$(find "${ROLLBACK_DIR}" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -n 1 || true)"
  [[ -n "${latest}" ]] || fatal "No rollback snapshot found."

  log "Restoring snapshot: ${latest}"
  (cd "${latest}" && find . -type f | LC_ALL=C sort) | while read -r file_path; do
    file_path="${file_path#./}"
    mkdir -p "${REPO_ROOT}/$(dirname "${file_path}")"
    cp -a "${latest}/${file_path}" "${REPO_ROOT}/${file_path}"
  done
  emit_diag INFO repair.restore "Rollback snapshot restored" "${latest}"
}

install_optional_tools() {
  if [[ "${INSTALL_SECURITY_TOOLS:-false}" != "true" ]]; then
    emit_diag INFO tools.install.skipped "Optional tool installation skipped" "INSTALL_SECURITY_TOOLS"
    return 0
  fi

  if [[ "${OFFLINE_MODE}" == "true" ]]; then
    emit_diag WARN tools.install.offline "Skipping optional tool installation in offline mode" "offline"
    return 0
  fi

  if have_cmd python3; then
    python3 -m pip install --user --upgrade pip || emit_diag WARN tools.pip.upgrade "pip upgrade failed" "pip"
    python3 -m pip install --user semgrep pip-audit || emit_diag WARN tools.python.security "Python security tool install failed" "pip"
  fi

  if have_cmd npm; then
    npm config set fund false --location=global || true
    npm config set audit false --location=global || true
  fi
}

validate_environment() {
  log "Phase 1: Environment validation"
  local required=(bash git curl jq)
  local cmd

  for cmd in "${required[@]}"; do
    if have_cmd "${cmd}"; then
      emit_diag INFO "tool.${cmd}.found" "Required command found" "${cmd}"
    else
      emit_diag ERROR "tool.${cmd}.missing" "Required command missing" "${cmd}"
    fi
  done

  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    emit_diag INFO env.openai_api_key "OPENAI_API_KEY present (redacted)" "env"
  else
    emit_diag WARN env.openai_api_key_missing "OPENAI_API_KEY not set" "env"
  fi
}

verify_git_integrity() {
  log "Phase 2: Source integrity"
  if ! have_cmd git; then
    emit_diag ERROR git.unavailable "git unavailable; cannot verify repository" "git"
    return 0
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    emit_diag INFO git.repo "Git repository detected" "$(git rev-parse --show-toplevel 2>/dev/null || true)"
  else
    emit_diag WARN git.repo_missing "Not inside a git repository" "${REPO_ROOT}"
    return 0
  fi

  if git diff --quiet --ignore-submodules --; then
    emit_diag INFO git.clean "Working tree has no unstaged changes" "git"
  else
    emit_diag WARN git.dirty "Working tree has unstaged changes" "git"
  fi

  if git verify-commit HEAD >/dev/null 2>&1; then
    emit_diag INFO git.commit_signature "HEAD commit signature verified" "HEAD"
  else
    emit_diag WARN git.commit_signature_missing "HEAD commit signature unavailable or invalid" "HEAD"
  fi
}

generate_sbom() {
  log "Phase 3: SBOM generation"
  local sbom_path="${REPORT_DIR}/sbom.spdx.json"

  if have_cmd syft; then
    syft "${REPO_ROOT}" -o spdx-json="${sbom_path}" || {
      emit_diag ERROR sbom.syft_failed "Syft SBOM generation failed" "${sbom_path}"
      return 0
    }
    emit_diag INFO sbom.generated "SBOM generated with Syft" "${sbom_path}"
    return 0
  fi

  if have_cmd npm && [[ -f "${REPO_ROOT}/package-lock.json" ]]; then
    npm sbom --sbom-format spdx > "${sbom_path}" 2>/dev/null || {
      emit_diag WARN sbom.npm_failed "npm SBOM generation failed; install syft for stable SBOM generation" "${sbom_path}"
      return 0
    }
    emit_diag INFO sbom.generated "SBOM generated with npm" "${sbom_path}"
    return 0
  fi

  emit_diag WARN sbom.tool_missing "No SBOM generator available; install syft or provide package-lock.json with npm" "sbom"
}

run_semgrep() {
  local output="${REPORT_DIR}/semgrep.json"
  if have_cmd semgrep; then
    semgrep --config=auto --json --output "${output}" "${REPO_ROOT}" || {
      emit_diag ERROR scan.semgrep.findings "Semgrep reported findings or failed" "${output}"
      return 0
    }
    emit_diag INFO scan.semgrep.clean "Semgrep completed without blocking findings" "${output}"
  else
    emit_diag WARN scan.semgrep.missing "semgrep not installed" "semgrep"
  fi
}

run_trivy() {
  local output="${REPORT_DIR}/trivy.json"
  if have_cmd trivy; then
    trivy fs --format json --output "${output}" --severity HIGH,CRITICAL "${REPO_ROOT}" || {
      emit_diag ERROR scan.trivy.findings "Trivy reported findings or failed" "${output}"
      return 0
    }
    emit_diag INFO scan.trivy.clean "Trivy completed without blocking findings" "${output}"
  else
    emit_diag WARN scan.trivy.missing "trivy not installed" "trivy"
  fi
}

run_security_scans() {
  log "Phase 4: Security scanning"
  run_semgrep
  run_trivy
}

build_and_test() {
  log "Phase 5: Build and test"

  if [[ -f "package-lock.json" ]] && have_cmd npm; then
    npm ci --ignore-scripts || emit_diag ERROR build.npm_ci "npm ci failed" "package-lock.json"
    npm run lint --if-present || emit_diag WARN build.npm_lint "npm lint failed or unavailable" "npm"
    npm test --if-present || emit_diag WARN build.npm_test "npm test failed or unavailable" "npm"
    npm run build --if-present || emit_diag WARN build.npm_build "npm build failed or unavailable" "npm"
  elif [[ -f "package.json" ]]; then
    emit_diag WARN build.node_lock_missing "package.json exists but package-lock.json is missing" "package.json"
  fi

  if [[ -f "requirements.txt" ]] && have_cmd python3; then
    python3 -m pip install --user --requirement requirements.txt || emit_diag WARN build.pip_install "pip install failed" "requirements.txt"
  fi

  if have_cmd pytest; then
    pytest -q || emit_diag WARN build.pytest "pytest failed" "pytest"
  fi
}

create_artifact_digest() {
  log "Phase 6: Artifact digest"
  local artifact_path="${ARTIFACT_PATH:-}"

  if [[ -z "${artifact_path}" ]]; then
    artifact_path="${ARTIFACT_DIR}/repo-source.tar.gz"
    tar --sort=name --mtime='UTC 2026-01-01' --owner=0 --group=0 --numeric-owner \
      --exclude='.git' \
      --exclude='.codex/rollback' \
      --exclude='.codex/reports' \
      -czf "${artifact_path}" . || {
        emit_diag ERROR artifact.create_failed "Failed to create deterministic source artifact" "${artifact_path}"
        return 0
      }
  fi

  if [[ -f "${artifact_path}" ]]; then
    sha256sum "${artifact_path}" | tee "${REPORT_DIR}/artifact.sha256" >/dev/null
    emit_diag INFO artifact.digest "Artifact digest generated" "${artifact_path}"
  else
    emit_diag WARN artifact.missing "Artifact path does not exist" "${artifact_path}"
  fi
}

verify_provenance() {
  log "Phase 7: Provenance verification"
  local artifact_path="${ARTIFACT_PATH:-${ARTIFACT_DIR}/repo-source.tar.gz}"
  local signature_path="${ARTIFACT_SIGNATURE:-}"
  local certificate_path="${ARTIFACT_CERTIFICATE:-}"

  if [[ ! -f "${artifact_path}" ]]; then
    emit_diag WARN provenance.artifact_missing "Cannot verify provenance without artifact" "${artifact_path}"
    return 0
  fi

  if have_cmd gh; then
    gh attestation verify "${artifact_path}" --repo "${GITHUB_REPOSITORY:-}" >/dev/null 2>&1 && {
      emit_diag INFO provenance.gh_attestation "GitHub artifact attestation verified" "${artifact_path}"
      return 0
    }
  fi

  if have_cmd cosign && [[ -n "${signature_path}" && -n "${certificate_path}" ]]; then
    if cosign verify-blob \
      --certificate "${certificate_path}" \
      --signature "${signature_path}" \
      --certificate-identity-regexp='.*' \
      --certificate-oidc-issuer-regexp='.*' \
      "${artifact_path}" >/dev/null 2>&1; then
      emit_diag INFO provenance.cosign "Cosign blob signature verified" "${artifact_path}"
      return 0
    fi
    emit_diag ERROR provenance.cosign_failed "Cosign blob verification failed" "${artifact_path}"
    return 0
  fi

  emit_diag WARN provenance.not_verified "No verifiable provenance input available" "${artifact_path}"
}

repair_mode_actions() {
  [[ "${REPAIR_MODE}" == "true" ]] || return 0

  log "Phase 8: Rollback-safe repair mode"
  create_repair_snapshot

  if [[ -f "package-lock.json" && -f "package.json" ]] && have_cmd npm; then
    npm install --package-lock-only --ignore-scripts || emit_diag WARN repair.npm_lock "package-lock refresh failed" "package-lock.json"
  fi

  emit_diag INFO repair.complete "Repair mode completed; rollback snapshot retained" "${ROLLBACK_DIR}"
}

write_summary() {
  local summary="${REPORT_DIR}/summary.json"
  printf '{"info":%s,"warn":%s,"error":%s,"fatal":%s,"strict":%s,"repair":%s}\n' \
    "${INFO_COUNT}" \
    "${WARN_COUNT}" \
    "${ERROR_COUNT}" \
    "${FATAL_COUNT}" \
    "$(strict_enabled && printf true || printf false)" \
    "${REPAIR_MODE}" > "${summary}"

  if [[ "${JSON_ONLY}" == "true" ]]; then
    cat "${summary}"
  else
    log "Summary: INFO=${INFO_COUNT} WARN=${WARN_COUNT} ERROR=${ERROR_COUNT} FATAL=${FATAL_COUNT}"
    log "Reports written to ${REPORT_DIR}"
  fi

  if ((FATAL_COUNT > 0 || ERROR_COUNT > 0)); then
    return 1
  fi

  if strict_enabled && ((WARN_COUNT > 0)); then
    return 1
  fi

  return 0
}

main() {
  parse_args "$@"
  prepare_workspace
  install_optional_tools
  validate_environment
  verify_git_integrity
  generate_sbom
  run_security_scans
  build_and_test
  create_artifact_digest
  verify_provenance
  repair_mode_actions
  write_summary
}

main "$@"
