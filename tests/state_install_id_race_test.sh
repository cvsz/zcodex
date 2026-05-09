#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/lib/state.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
state_dir="${workdir}/state"

pids=()
for _ in $(seq 1 20); do
  (
    unset ZCODEX_INSTALL_ID
    state_read_or_create_install_id "${state_dir}" >/dev/null
  ) &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "${pid}"
done

if [[ ! -r "${state_dir}/install_id" ]]; then
  echo "install_id file was not created" >&2
  exit 1
fi

expected="$(cat "${state_dir}/install_id")"
if [[ -z "${expected}" ]]; then
  echo "install_id file is empty" >&2
  exit 1
fi

for _ in $(seq 1 10); do
  observed="$(state_read_or_create_install_id "${state_dir}")"
  [[ "${observed}" == "${expected}" ]] || {
    echo "install_id drift detected: expected ${expected}, got ${observed}" >&2
    exit 1
  }
done

echo "state install_id creation is stable under concurrent readers/writers"
