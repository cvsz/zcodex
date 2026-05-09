#!/usr/bin/env bash
set -Eeuo pipefail

invalid=0
while IFS= read -r workflow; do
  while IFS= read -r action; do
    if [[ "$action" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    if [[ "$action" != *@v* ]]; then
      echo "Action pin missing major version in ${workflow}: ${action}" >&2
      invalid=1
      continue
    fi

    if [[ ! "$action" =~ @v[0-9]+([._-].*)?$ ]]; then
      echo "Action version does not look stable in ${workflow}: ${action}" >&2
      invalid=1
    fi
  done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*uses:[[:space:]]*([^[:space:]]+).*$/\1/p' "$workflow")
done < <(find .github/workflows -type f -name '*.yml' | LC_ALL=C sort)

if [[ $invalid -ne 0 ]]; then
  exit 1
fi

echo "Action versions validated."
