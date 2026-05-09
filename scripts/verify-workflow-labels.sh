#!/usr/bin/env bash
set -Eeuo pipefail

valid_labels=(
	ubuntu-22.04
	ubuntu-24.04
	ubuntu-24.04-arm64
)

invalid=0
while IFS= read -r workflow; do
	while IFS= read -r label; do
		if [[ -z "$label" || "$label" == \$\{\{* ]]; then
			continue
		fi

		allowed=0
		for candidate in "${valid_labels[@]}"; do
			if [[ "$label" == "$candidate" ]]; then
				allowed=1
				break
			fi
		done

		if [[ $allowed -eq 0 ]]; then
			echo "Invalid runner label in ${workflow}: ${label}" >&2
			invalid=1
		fi
	done < <(sed -nE 's/^[[:space:]]*runs-on:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "$workflow")
done < <(find .github/workflows -type f -name '*.yml' | LC_ALL=C sort)

if [[ $invalid -ne 0 ]]; then
	exit 1
fi

echo "Workflow runner labels validated."
