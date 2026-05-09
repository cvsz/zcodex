#!/usr/bin/env bash
set -euo pipefail

runs="${1:-5000}"
if ! [[ "${runs}" =~ ^[0-9]+$ ]] || (( runs < 1 )); then
  echo "usage: $0 [runs>=1]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

phase_cycle=(VALIDATE DOWNLOAD VERIFY RUNTIME_AUDIT INSTALL CONFIGURE VERIFY_RUNTIME COMPLETE)

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
state_home="${tmpdir}/home"
state_dir="${tmpdir}/state"
mkdir -p "${state_home}" "${state_dir}"

# shellcheck source=scripts/lib/logging.sh
. "${repo_root}/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/state.sh
. "${repo_root}/scripts/lib/state.sh"

# shellcheck disable=SC2119
logging_init >/dev/null 2>&1 || true

benchmark_transition() {
  local total_ns=0
  local started ended elapsed i phase

  for ((i=0; i<runs; i++)); do
    phase="${phase_cycle[i % ${#phase_cycle[@]}]}"
    started="$(date +%s%N)"
    state_mark_in "${state_home}" "${state_dir}" "${phase}" "bench" running >/dev/null
    state_complete_phase_in "${state_home}" "${state_dir}" "${phase}" >/dev/null
    ended="$(date +%s%N)"
    elapsed=$((ended - started))
    total_ns=$((total_ns + elapsed))
  done

  local avg_ns=$((total_ns / runs))
  local avg_us=$((avg_ns / 1000))
  local throughput=$((1000000000 / avg_ns))

  printf 'state_transition throughput=%d/sec avg=%dns avg_us=%d runs=%d\n' "${throughput}" "${avg_ns}" "${avg_us}" "${runs}"
}

benchmark_transition
