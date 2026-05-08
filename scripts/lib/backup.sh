#!/usr/bin/env bash
# Backup helpers for files modified by zcodex.

: "${ZCODEX_BACKUP_DIR:=}"

backup_init() {
	if [[ -z "${ZCODEX_BACKUP_DIR}" ]]; then
		ZCODEX_BACKUP_DIR="${HOME}/.zcodex/backups/$(date -u +%Y%m%dT%H%M%SZ)"
	fi
	install -d -m 700 "${ZCODEX_BACKUP_DIR}"
	printf '%s\n' "${ZCODEX_BACKUP_DIR}"
}

backup_destination_for() {
	local source_file="$1"
	local relative_path="${source_file#/}"
	printf '%s/%s\n' "${ZCODEX_BACKUP_DIR}" "${relative_path}"
}

backup_file() {
	local source_file="$1"
	local destination

	if [[ ! -e "${source_file}" ]]; then
		log_info "No existing file to back up: ${source_file}"
		return 0
	fi

	backup_init >/dev/null
	destination="$(backup_destination_for "${source_file}")"
	install -d -m 700 "$(dirname "${destination}")"
	cp -p "${source_file}" "${destination}"
	log_success "Backed up ${source_file} to ${destination}."
}
