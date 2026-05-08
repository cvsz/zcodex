#!/usr/bin/env bash
# Node.js installation helpers.

: "${ZCODEX_RUNTIME_MODE:=clean-system}"
: "${ZCODEX_ALLOW_USER_RUNTIME_MUTATION:=false}"

nodejs_installed_version() {
	command_exists node || return 1
	node --version | sed 's/^v//'
}

nodejs_version_matches_pin() {
	local installed="$1"
	case "${installed}" in
	"${ZCODEX_NODEJS_VERSION}" | "${ZCODEX_NODEJS_VERSION}."*) return 0 ;;
	*) return 1 ;;
	esac
}

nodejs_unique_path_entries() {
	awk 'NF && !seen[$0]++' 2>/dev/null || true
}

nodejs_find_all_in_path() {
	local command_name="$1"
	if ! type -P -a "${command_name}" >/dev/null 2>&1; then
		return 0
	fi
	type -P -a "${command_name}" | nodejs_unique_path_entries
}

nodejs_path_under() {
	local path="$1"
	local root="$2"
	[[ -n "${path}" && -n "${root}" && "${path}" == "${root}"/* ]]
}

nodejs_has_nvm() {
	[[ -n "${NVM_DIR:-}" && -d "${NVM_DIR}" ]] && return 0
	[[ -s "${HOME:-}/.nvm/nvm.sh" ]] && return 0
	command -v nvm >/dev/null 2>&1
}

nodejs_has_asdf() {
	[[ -n "${ASDF_DIR:-}" && -d "${ASDF_DIR}" ]] && return 0
	[[ -d "${HOME:-}/.asdf" ]] && return 0
	command -v asdf >/dev/null 2>&1
}

nodejs_dpkg_package_installed() {
	local package_name="$1"
	command_exists dpkg-query || return 1
	dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q 'install ok installed'
}

nodejs_dpkg_package_version() {
	local package_name="$1"
	command_exists dpkg-query || return 1
	dpkg-query -W -f='${Version}' "${package_name}" 2>/dev/null || true
}

nodejs_apt_candidate_origin() {
	command_exists apt-cache || return 1
	apt-cache policy nodejs 2>/dev/null | awk '
		/^[[:space:]]+Candidate:/ {candidate=$2; next}
		candidate && $1 == candidate {in_candidate=1; next}
		in_candidate && /release .*o=/ {
			split($0, parts, "o=");
			split(parts[2], origin, ",");
			print origin[1];
			exit
		}
		in_candidate && /origin / {print $2; exit}
	' || true
}

nodejs_is_nodesource_package() {
	local package_version origin
	package_version="$(nodejs_dpkg_package_version nodejs)"
	case "${package_version}" in
	*nodesource* | *NodeSource*) return 0 ;;
	esac
	origin="$(nodejs_apt_candidate_origin)"
	case "${origin}" in
	*nodesource.com* | *NodeSource* | *nodesource*) return 0 ;;
	esac
	find /etc/apt -path '*sources.list*' -type f -exec grep -qi 'deb.nodesource.com' {} + 2>/dev/null
}

nodejs_dpkg_owner_for_path() {
	local path="$1"
	local real_path package_line package_name candidate
	command_exists dpkg-query || return 1
	real_path="$(readlink -f "${path}" 2>/dev/null || printf '%s\n' "${path}")"
	for candidate in "${path}" "${real_path}"; do
		[[ -n "${candidate}" ]] || continue
		package_line="$(dpkg-query -S "${candidate}" 2>/dev/null | head -n 1 || true)"
		[[ -n "${package_line}" ]] || continue
		package_name="${package_line%%:*}"
		package_name="${package_name%%,*}"
		printf '%s\n' "${package_name}"
		return 0
	done
	return 1
}

nodejs_system_owner_for_package() {
	local package_name="$1"
	case "${package_name}" in
	nodejs)
		if nodejs_is_nodesource_package; then
			printf '%s\n' system-apt-nodesource
		else
			printf '%s\n' system-apt-distro
		fi
		;;
	npm) printf '%s\n' system-apt-distro ;;
	*) return 1 ;;
	esac
}

nodejs_owner_for_path() {
	local path="$1"
	local real_path nvm_root asdf_root package_owner package_domain
	real_path="$(readlink -f "${path}" 2>/dev/null || printf '%s\n' "${path}")"
	nvm_root="${NVM_DIR:-${HOME:-}/.nvm}"
	asdf_root="${ASDF_DIR:-${HOME:-}/.asdf}"

	if nodejs_path_under "${real_path}" "${nvm_root}"; then
		printf '%s\n' user-nvm
		return 0
	fi
	if nodejs_path_under "${real_path}" "${asdf_root}" || [[ "${real_path}" == */.asdf/shims/* ]]; then
		printf '%s\n' user-asdf
		return 0
	fi
	package_owner="$(nodejs_dpkg_owner_for_path "${path}" 2>/dev/null || true)"
	if [[ -n "${package_owner}" ]]; then
		package_domain="$(nodejs_system_owner_for_package "${package_owner}" 2>/dev/null || true)"
		if [[ -n "${package_domain}" ]]; then
			printf '%s\n' "${package_domain}"
			return 0
		fi
	fi
	case "${real_path}" in
	/usr/bin/* | /bin/* | /usr/local/bin/*) printf '%s\n' system-unowned ;;
	*) printf '%s\n' unknown ;;
	esac
}

nodejs_runtime_audit() {
	local node_path npm_path node_version npm_version node_owner npm_owner node_count npm_count node_package npm_package
	node_path="$(command -v node 2>/dev/null || true)"
	npm_path="$(command -v npm 2>/dev/null || true)"
	node_version="$(nodejs_installed_version 2>/dev/null || true)"
	npm_version="$(npm --version 2>/dev/null || true)"
	node_owner="absent"
	npm_owner="absent"
	node_package="absent"
	npm_package="absent"
	[[ -n "${node_path}" ]] && node_owner="$(nodejs_owner_for_path "${node_path}")"
	[[ -n "${npm_path}" ]] && npm_owner="$(nodejs_owner_for_path "${npm_path}")"
	[[ -n "${node_path}" ]] && node_package="$(nodejs_dpkg_owner_for_path "${node_path}" 2>/dev/null || printf unknown)"
	[[ -n "${npm_path}" ]] && npm_package="$(nodejs_dpkg_owner_for_path "${npm_path}" 2>/dev/null || printf unknown)"
	node_count="$(nodejs_find_all_in_path node | wc -l | tr -d ' ')"
	npm_count="$(nodejs_find_all_in_path npm | wc -l | tr -d ' ')"

	cat <<AUDIT
mode=${ZCODEX_RUNTIME_MODE}
node_path=${node_path:-absent}
node_version=${node_version:-absent}
node_owner=${node_owner}
node_package=${node_package}
node_path_count=${node_count:-0}
npm_path=${npm_path:-absent}
npm_version=${npm_version:-absent}
npm_owner=${npm_owner}
npm_package=${npm_package}
npm_path_count=${npm_count:-0}
nvm_detected=$(nodejs_has_nvm && printf true || printf false)
asdf_detected=$(nodejs_has_asdf && printf true || printf false)
apt_nodejs=$(nodejs_dpkg_package_installed nodejs && printf true || printf false)
nodesource_nodejs=$(nodejs_is_nodesource_package && printf true || printf false)
distro_npm=$(nodejs_dpkg_package_installed npm && printf true || printf false)
node_paths=$(nodejs_find_all_in_path node | paste -sd, -)
npm_paths=$(nodejs_find_all_in_path npm | paste -sd, -)
AUDIT
}

nodejs_audit_value() {
	local audit="$1"
	local key="$2"
	awk -F= -v key="${key}" '$1 == key {print substr($0, length(key) + 2); exit}' <<<"${audit}"
}

nodejs_runtime_owner_is_user_managed() {
	case "$1" in
	user-nvm | user-asdf) return 0 ;;
	*) return 1 ;;
	esac
}

nodejs_log_runtime_audit() {
	local audit="$1"
	log_info "Runtime audit: mode=$(nodejs_audit_value "${audit}" mode), node=$(nodejs_audit_value "${audit}" node_path) owner=$(nodejs_audit_value "${audit}" node_owner) package=$(nodejs_audit_value "${audit}" node_package) version=$(nodejs_audit_value "${audit}" node_version), npm=$(nodejs_audit_value "${audit}" npm_path) owner=$(nodejs_audit_value "${audit}" npm_owner) package=$(nodejs_audit_value "${audit}" npm_package)."
	if [[ "$(nodejs_audit_value "${audit}" node_path_count)" != "0" && "$(nodejs_audit_value "${audit}" node_path_count)" != "1" ]]; then
		log_warn "Multiple node binaries found in PATH: $(nodejs_audit_value "${audit}" node_paths)"
	fi
	if [[ "$(nodejs_audit_value "${audit}" npm_path_count)" != "0" && "$(nodejs_audit_value "${audit}" npm_path_count)" != "1" ]]; then
		log_warn "Multiple npm binaries found in PATH: $(nodejs_audit_value "${audit}" npm_paths)"
	fi
}

nodejs_runtime_conflict_report() {
	local audit="$1"
	local mode node_owner npm_owner nvm_detected asdf_detected apt_nodejs nodesource_nodejs distro_npm node_count npm_count node_version npm_package
	mode="$(nodejs_audit_value "${audit}" mode)"
	node_owner="$(nodejs_audit_value "${audit}" node_owner)"
	npm_owner="$(nodejs_audit_value "${audit}" npm_owner)"
	nvm_detected="$(nodejs_audit_value "${audit}" nvm_detected)"
	asdf_detected="$(nodejs_audit_value "${audit}" asdf_detected)"
	apt_nodejs="$(nodejs_audit_value "${audit}" apt_nodejs)"
	nodesource_nodejs="$(nodejs_audit_value "${audit}" nodesource_nodejs)"
	distro_npm="$(nodejs_audit_value "${audit}" distro_npm)"
	node_count="$(nodejs_audit_value "${audit}" node_path_count)"
	npm_count="$(nodejs_audit_value "${audit}" npm_path_count)"
	node_version="$(nodejs_audit_value "${audit}" node_version)"
	npm_package="$(nodejs_audit_value "${audit}" npm_package)"

	if [[ "${nvm_detected}" == "true" && "${apt_nodejs}" == "true" ]]; then
		printf 'fatal|nvm and apt-managed nodejs are both present|Use --runtime-mode existing-runtime with the nvm node active, or remove apt nodejs/npm before clean-system install.\n'
	elif [[ "${nvm_detected}" == "true" && "${node_owner}" != "user-nvm" ]]; then
		printf 'warn|nvm is installed but the active node is owned by %s|If nvm should own this install, activate the desired nvm version and rerun with --runtime-mode existing-runtime.\n' "${node_owner}"
	fi
	if [[ "${asdf_detected}" == "true" && "${apt_nodejs}" == "true" ]]; then
		printf 'fatal|asdf and apt-managed nodejs are both present|Use --runtime-mode existing-runtime with the asdf node active, or remove apt nodejs/npm before clean-system install.\n'
	elif [[ "${asdf_detected}" == "true" && "${node_owner}" != "user-asdf" ]]; then
		printf 'warn|asdf is installed but the active node is owned by %s|If asdf should own this install, activate the desired asdf node and rerun with --runtime-mode existing-runtime.\n' "${node_owner}"
	fi
	if [[ "${nodesource_nodejs}" == "true" && "${distro_npm}" == "true" ]]; then
		printf 'fatal|NodeSource nodejs is installed with distro npm|Remove distro npm, or use a single NodeSource/npm ownership path before rerunning.\n'
	fi
	if [[ "${node_owner}" != "absent" && "${npm_owner}" != "absent" && "${node_owner}" != "${npm_owner}" ]]; then
		printf 'fatal|node and npm resolve to different ownership domains (%s vs %s)|Adjust PATH so node and npm come from the same runtime owner.\n' "${node_owner}" "${npm_owner}"
	fi
	if [[ "${npm_owner}" != "absent" && "${npm_package}" == "unknown" ]]; then
		printf 'warn|npm package ownership could not be verified for the active npm binary|Use a package-manager-owned npm or a recognized nvm/asdf runtime before installing global packages.\n'
	fi
	if ((node_count > 1)); then
		printf 'warn|multiple node binaries are visible in PATH|Prefer one node provider at the front of PATH; current order: %s.\n' "$(nodejs_audit_value "${audit}" node_paths)"
	fi
	if ((npm_count > 1)); then
		printf 'warn|multiple npm binaries are visible in PATH|Prefer one npm provider at the front of PATH; current order: %s.\n' "$(nodejs_audit_value "${audit}" npm_paths)"
	fi
	case "${mode}" in
	clean-system)
		if nodejs_runtime_owner_is_user_managed "${node_owner}"; then
			printf 'fatal|clean-system mode would mutate a user-managed runtime (%s)|Switch to --runtime-mode existing-runtime or deactivate nvm/asdf before installing.\n' "${node_owner}"
		elif [[ "${node_owner}" == "unknown" || "${node_owner}" == "system-unowned" || "${npm_owner}" == "unknown" || "${npm_owner}" == "system-unowned" ]]; then
			printf 'fatal|clean-system mode found unowned or unknown Node.js/npm binaries (%s/%s)|Remove unmanaged binaries from PATH or use --runtime-mode existing-runtime with a verifiable runtime.\n' "${node_owner}" "${npm_owner}"
		fi
		;;
	existing-runtime | developer)
		if [[ "${node_owner}" == "absent" || "${npm_owner}" == "absent" ]]; then
			printf 'fatal|existing runtime mode requires node and npm to be preinstalled|Activate or install your Node.js runtime first, then rerun with --runtime-mode %s.\n' "${mode}"
		elif ! nodejs_version_matches_pin "${node_version}"; then
			printf 'fatal|existing Node.js version v%s does not satisfy pin %s|Activate a compatible Node.js version or run clean-system mode on a host without user runtime managers.\n' "${node_version}" "${ZCODEX_NODEJS_VERSION}"
		fi
		;;
	ci)
		if [[ "${node_owner}" == "absent" || "${npm_owner}" == "absent" ]]; then
			printf 'fatal|ci mode requires node and npm in the image|Install pinned Node.js in the CI image before running zcodex.\n'
		elif ! nodejs_version_matches_pin "${node_version}"; then
			printf 'fatal|ci Node.js version v%s does not satisfy pin %s|Bake Node.js %s.x and matching npm into the CI image before running zcodex.\n' "${node_version}" "${ZCODEX_NODEJS_VERSION}" "${ZCODEX_NODEJS_VERSION}"
		fi
		;;
	*)
		printf 'fatal|invalid runtime mode %s|Use one of: clean-system, existing-runtime, ci, developer.\n' "${mode}"
		;;
	esac
}

nodejs_runtime_audit_phase() {
	local audit severity description remediation fatal_count=0 warning_count=0
	audit="$(nodejs_runtime_audit)"
	nodejs_log_runtime_audit "${audit}"
	while IFS='|' read -r severity description remediation; do
		[[ -n "${severity}" ]] || continue
		case "${severity}" in
		fatal)
			fatal_count=$((fatal_count + 1))
			log_error "Runtime conflict: ${description}. Remediation: ${remediation}"
			;;
		warn)
			warning_count=$((warning_count + 1))
			log_warn "Runtime warning: ${description}. Guidance: ${remediation}"
			;;
		esac
	done < <(nodejs_runtime_conflict_report "${audit}")

	if ((fatal_count > 0)); then
		log_error "Runtime audit failed with ${fatal_count} dangerous conflict(s); refusing to mutate Node.js/npm."
		return 1
	fi
	log_success "Runtime audit passed with ${warning_count} warning(s)."
}

nodejs_install_managed() {
	local installed_version audit node_owner npm_owner
	audit="$(nodejs_runtime_audit)"
	node_owner="$(nodejs_audit_value "${audit}" node_owner)"
	npm_owner="$(nodejs_audit_value "${audit}" npm_owner)"
	installed_version="$(nodejs_audit_value "${audit}" node_version)"

	case "${ZCODEX_RUNTIME_MODE}" in
	existing-runtime | developer | ci)
		if [[ "${installed_version}" != "absent" ]] && nodejs_version_matches_pin "${installed_version}"; then
			log_success "Using existing Node.js v${installed_version} from ${node_owner}."
			return 0
		fi
		log_error "Runtime mode ${ZCODEX_RUNTIME_MODE} does not install or modify Node.js/npm. Remediation: activate Node.js ${ZCODEX_NODEJS_VERSION}.x and matching npm before rerunning."
		return 1
		;;
	clean-system) ;;
	*)
		log_error "Invalid runtime mode: ${ZCODEX_RUNTIME_MODE}"
		return 1
		;;
	esac

	if nodejs_runtime_owner_is_user_managed "${node_owner}" || nodejs_runtime_owner_is_user_managed "${npm_owner}"; then
		log_error "Refusing to install over user-managed Node.js/npm (${node_owner}/${npm_owner}). Use --runtime-mode existing-runtime or deactivate nvm/asdf."
		return 1
	fi

	if [[ -n "${installed_version}" && "${installed_version}" != "absent" ]] && nodejs_version_matches_pin "${installed_version}"; then
		log_success "Node.js v${installed_version} matches pin ${ZCODEX_NODEJS_VERSION}."
		return 0
	fi

	if ! supports_apt; then
		log_error "Node.js installation requires the APT capability."
		return 1
	fi

	log_info "Installing Node.js pin ${ZCODEX_NODEJS_VERSION} through the managed APT package path."
	if [[ -n "${ZCODEX_NODEJS_PACKAGE_VERSION}" ]]; then
		packages_install "nodejs=${ZCODEX_NODEJS_PACKAGE_VERSION}" npm
	else
		packages_install nodejs npm
	fi

	installed_version="$(nodejs_installed_version 2>/dev/null || true)"
	if [[ -z "${installed_version}" ]] || ! nodejs_version_matches_pin "${installed_version}"; then
		log_error "Installed Node.js version v${installed_version:-missing} does not satisfy pin ${ZCODEX_NODEJS_VERSION}."
		return 1
	fi
}

nodejs_install_global_packages() {
	local packages=("$@") audit node_owner npm_owner
	if ((${#packages[@]} == 0)); then
		return 0
	fi
	audit="$(nodejs_runtime_audit)"
	node_owner="$(nodejs_audit_value "${audit}" node_owner)"
	npm_owner="$(nodejs_audit_value "${audit}" npm_owner)"
	if nodejs_runtime_owner_is_user_managed "${node_owner}" || nodejs_runtime_owner_is_user_managed "${npm_owner}"; then
		if [[ "${ZCODEX_ALLOW_USER_RUNTIME_MUTATION}" != "true" ]]; then
			log_error "Refusing to install global npm packages into user-managed runtime (${node_owner}/${npm_owner}). Set ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true only after reviewing this mutation."
			return 1
		fi
		log_warn "Installing global npm packages into user-managed runtime because ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true."
		retry 3 2 npm install --global "${packages[@]}"
		return $?
	fi
	retry 3 2 sudo npm install --global "${packages[@]}"
}

nodejs_install_ubuntu() {
	nodejs_install_managed "$@"
}
