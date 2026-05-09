#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# CODEX-MAX AUTONOMOUS EXECUTION PIPELINE
# Repository: cvsz/zcodex
# =========================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="${ROOT_DIR}/cvsz/zcodex/prompts"
LOG_DIR="${ROOT_DIR}/cvsz/zcodex/logs"
REPORT_DIR="${ROOT_DIR}/cvsz/zcodex/reports"

mkdir -p "${LOG_DIR}"
mkdir -p "${REPORT_DIR}"

# =========================================================
# PROMPT LIST
# =========================================================

PROMPTS=(
  "00_global_system_prompt.txt"
  "01_recon_and_inventory.txt"
  "02_static_analysis.txt"
  "03_dependency_audit.txt"
  "04_dynamic_analysis.txt"
  "05_cicd_repair.txt"
  "06_security_exploit_review.txt"
  "07_recursive_bugfix_loop.txt"
  "08_performance_optimizer.txt"
  "09_architecture_refactor.txt"
  "10_final_validation.txt"
)

# =========================================================
# SETTINGS
# =========================================================

MAX_RETRIES=2
SLEEP_BETWEEN=2

# Optional environment flags
export CODEX_DISABLE_TELEMETRY=1
export CODEX_AUTONOMOUS_MODE=1
export CODEX_RECURSIVE_FIX=1
export CODEX_OUTPUT_FORMAT=json

# =========================================================
# HELPERS
# =========================================================

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*"
}

run_prompt() {
  local prompt_file="$1"

  local full_path="${PROMPT_DIR}/${prompt_file}"

  if [[ ! -f "${full_path}" ]]; then
    log "ERROR: Missing prompt file: ${full_path}"
    return 1
  fi

  local base_name
  base_name="$(basename "${prompt_file}" .txt)"

  local log_file="${LOG_DIR}/${base_name}.log"
  local json_file="${REPORT_DIR}/${base_name}.json"

  log "===================================================="
  log "RUNNING: ${prompt_file}"
  log "===================================================="

  local attempt=1

  while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
    log "Attempt ${attempt}/${MAX_RETRIES}"

    if codex run "${full_path}" \
      --json-output "${json_file}" \
      2>&1 | tee "${log_file}"; then

      log "SUCCESS: ${prompt_file}"
      return 0
    fi

    log "FAILED: ${prompt_file}"
    ((attempt++))

    sleep "${SLEEP_BETWEEN}"
  done

  log "FINAL FAILURE: ${prompt_file}"
  return 1
}

# =========================================================
# PRECHECKS
# =========================================================

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not installed"
  exit 1
fi

if [[ ! -d "${PROMPT_DIR}" ]]; then
  echo "ERROR: Prompt directory not found: ${PROMPT_DIR}"
  exit 1
fi

# =========================================================
# EXECUTION
# =========================================================

START_TS=$(date +%s)

log "Starting Codex-Max Autonomous Pipeline"

FAILED_PHASES=()

for prompt in "${PROMPTS[@]}"; do
  if ! run_prompt "${prompt}"; then
    FAILED_PHASES+=("${prompt}")
  fi
done

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

# =========================================================
# SUMMARY
# =========================================================

echo
echo "===================================================="
echo "PIPELINE SUMMARY"
echo "===================================================="
echo "Duration: ${DURATION}s"

if [[ ${#FAILED_PHASES[@]} -eq 0 ]]; then
  echo "Status: SUCCESS"
  echo "All phases completed successfully."
else
  echo "Status: FAILED"
  echo "Failed phases:"
  for failed in "${FAILED_PHASES[@]}"; do
    echo " - ${failed}"
  done
fi

echo
echo "Logs:     ${LOG_DIR}"
echo "Reports:  ${REPORT_DIR}"

# =========================================================
# OPTIONAL RECURSIVE MODE
# =========================================================

if [[ "${1:-}" == "--recursive" ]]; then
  echo
  echo "===================================================="
  echo "RECURSIVE VALIDATION LOOP"
  echo "===================================================="

  PASS=1
  MAX_PASSES=3

  while [[ ${PASS} -le ${MAX_PASSES} ]]; do
    echo
    log "Recursive pass ${PASS}/${MAX_PASSES}"

    run_prompt "07_recursive_bugfix_loop.txt"
    run_prompt "10_final_validation.txt"

    ((PASS++))
  done
fi

echo
log "Pipeline completed."
