#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$ROOT_DIR/.codex"
PROMPT_DIR="$ROOT/prompts"
LOG_DIR="$ROOT/logs"
REPORT_DIR="$ROOT/reports"
PATCH_DIR="$ROOT/patches"
STATE_DIR="$ROOT/state"

mkdir -p \
  "$LOG_DIR" \
  "$REPORT_DIR" \
  "$PATCH_DIR" \
  "$STATE_DIR"

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

CODEX_BIN="${CODEX_BIN:-codex}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
MASTER_LOG="$LOG_DIR/master_run_${TIMESTAMP}.log"

echo "========================================" | tee -a "$MASTER_LOG"
echo "CODEX-MAX AUTONOMOUS EXECUTION PIPELINE" | tee -a "$MASTER_LOG"
echo "Repository: $ROOT_DIR" | tee -a "$MASTER_LOG"
echo "Timestamp : $TIMESTAMP" | tee -a "$MASTER_LOG"
echo "========================================" | tee -a "$MASTER_LOG"

run_prompt() {
  local prompt_file="$1"
  local prompt_path="$PROMPT_DIR/$prompt_file"

  if [[ ! -f "$prompt_path" ]]; then
    echo "[ERROR] Missing prompt: $prompt_path" | tee -a "$MASTER_LOG"
    return 1
  fi

  local base
  base="$(basename "$prompt_file" .txt)"

  local phase_log="$LOG_DIR/${base}_${TIMESTAMP}.log"

  echo "" | tee -a "$MASTER_LOG"
  echo "========================================" | tee -a "$MASTER_LOG"
  echo "[START] $prompt_file" | tee -a "$MASTER_LOG"
  echo "========================================" | tee -a "$MASTER_LOG"

  local start_ts
  start_ts="$(date +%s)"

  set +e
  "$CODEX_BIN" run "$prompt_path" 2>&1 | tee "$phase_log"
  local exit_code=$?
  set -e

  local end_ts
  end_ts="$(date +%s)"

  local duration
  duration="$((end_ts - start_ts))"

  echo "" | tee -a "$MASTER_LOG"
  echo "[END] $prompt_file" | tee -a "$MASTER_LOG"
  echo "Exit Code : $exit_code" | tee -a "$MASTER_LOG"
  echo "Duration  : ${duration}s" | tee -a "$MASTER_LOG"
  echo "Log File  : $phase_log" | tee -a "$MASTER_LOG"

  echo "$exit_code" > "$STATE_DIR/${base}.exitcode"

  if [[ "$exit_code" -ne 0 ]]; then
    echo "[WARNING] Prompt failed: $prompt_file" | tee -a "$MASTER_LOG"
  else
    echo "[SUCCESS] Prompt completed: $prompt_file" | tee -a "$MASTER_LOG"
  fi
}

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  echo "ERROR: $CODEX_BIN CLI not installed"
  exit 1
fi

for prompt in "${PROMPTS[@]}"; do
  run_prompt "$prompt"
done

echo "" | tee -a "$MASTER_LOG"
echo "========================================" | tee -a "$MASTER_LOG"
echo "PIPELINE SUMMARY" | tee -a "$MASTER_LOG"
echo "========================================" | tee -a "$MASTER_LOG"

FAILED=0

for prompt in "${PROMPTS[@]}"; do
  base="$(basename "$prompt" .txt)"
  code="$(cat "$STATE_DIR/${base}.exitcode" 2>/dev/null || echo 999)"

  if [[ "$code" -eq 0 ]]; then
    echo "[OK]     $prompt" | tee -a "$MASTER_LOG"
  else
    echo "[FAILED] $prompt (exit=$code)" | tee -a "$MASTER_LOG"
    FAILED=1
  fi
done

echo "" | tee -a "$MASTER_LOG"

if [[ "$FAILED" -eq 0 ]]; then
  echo "[FINAL STATUS] ALL PHASES COMPLETED SUCCESSFULLY" | tee -a "$MASTER_LOG"
else
  echo "[FINAL STATUS] SOME PHASES FAILED" | tee -a "$MASTER_LOG"
fi

echo "Master Log: $MASTER_LOG" | tee -a "$MASTER_LOG"
