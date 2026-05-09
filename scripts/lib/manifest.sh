#!/usr/bin/env bash
# Machine-readable installation manifest helpers.

: "${ZCODEX_STATE_HOME:=${HOME}/.local/share/zcodex}"
: "${ZCODEX_MANIFEST_FILE:=${ZCODEX_STATE_HOME}/manifest.json}"
: "${ZCODEX_MANIFEST_SCHEMA_VERSION:=2}"
: "${ZCODEX_INSTALL_RECORDS_FILE:=${ZCODEX_STATE_HOME}/install-records.jsonl}"

manifest_command_exists() {
	if declare -F command_exists >/dev/null 2>&1; then
		command_exists "$1"
	else
		command -v "$1" >/dev/null 2>&1
	fi
}

manifest_json_escape() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	value="${value//$'\r'/\\r}"
	value="${value//$'\t'/\\t}"
	printf '%s' "${value}"
}

manifest_json_string() {
	local value="$1"
	printf '"%s"' "$(manifest_json_escape "${value}")"
}

manifest_json_nullable() {
	local value="${1:-}"
	if [[ -z "${value}" ]]; then
		printf 'null'
	else
		manifest_json_string "${value}"
	fi
}

manifest_command_version() {
	local command_name="$1"
	shift
	manifest_command_exists "${command_name}" || return 1
	"${command_name}" "$@" 2>/dev/null | head -n 1
}

manifest_dpkg_version() {
	local package_name="$1"
	dpkg-query -W -f='${Version}' "${package_name}" 2>/dev/null || true
}

manifest_sha256_for_command() {
	local command_name="$1"
	local command_path
	command_path="$(command -v "${command_name}" 2>/dev/null || true)"
	[[ -n "${command_path}" && -r "${command_path}" ]] || return 0
	sha256sum "${command_path}" 2>/dev/null | awk '{ print $1 }'
}

manifest_platform_json() {
	local os_release_file
	local pretty_name='unknown Linux'
	local os_id='unknown'
	local version_id='unknown'
	os_release_file="$(platform_os_release_file)"
	if [[ -r "${os_release_file}" ]]; then
		# shellcheck disable=SC1090
		. "${os_release_file}"
		pretty_name="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-unknown}}"
		os_id="${ID:-unknown}"
		version_id="${VERSION_ID:-unknown}"
	fi
	cat <<JSON
  "platform": {
    "os": $(manifest_json_string "${pretty_name}"),
    "id": $(manifest_json_string "${os_id}"),
    "version_id": $(manifest_json_string "${version_id}"),
    "arch": $(manifest_json_string "$(platform_arch)"),
    "normalized_arch": $(manifest_json_string "$(platform_arch_normalized)"),
    "container_runtime": $(manifest_json_string "$(platform_container_runtime)"),
    "capabilities":
$(runtime_capability_json)
  }
JSON
}

manifest_component_json() {
	local name="$1"
	local desired_version="$2"
	local installed_version="$3"
	local status="$4"
	local sha256="${5:-}"
	cat <<JSON
    {
      "name": $(manifest_json_string "${name}"),
      "desired_version": $(manifest_json_nullable "${desired_version}"),
      "installed_version": $(manifest_json_nullable "${installed_version}"),
      "status": $(manifest_json_string "${status}"),
      "sha256": $(manifest_json_nullable "${sha256}")
    }
JSON
}

manifest_component_status() {
	local installed_version="$1"
	if [[ -n "${installed_version}" ]]; then
		printf '%s\n' installed
	else
		printf '%s\n' missing
	fi
}

manifest_canonicalize_file() {
	local source="$1"
	local target="${2:-${source}}"
	manifest_command_exists python3 || return 1
	python3 - "${source}" "${target}" <<'PYCANON'
import json
import os
import tempfile
import sys

source, target = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as fh:
    doc = json.load(fh)
rendered = json.dumps(doc, sort_keys=True, indent=2, separators=(",", ": ")) + "\n"
if source == target:
    directory = os.path.dirname(target) or "."
    fd, tmp = tempfile.mkstemp(prefix=f".{os.path.basename(target)}.", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(rendered)
        os.chmod(tmp, 0o600)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
else:
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    os.chmod(target, 0o600)
PYCANON
}

manifest_integrity_digest() {
	local manifest="$1"
	manifest_command_exists python3 || return 1
	python3 - "${manifest}" <<'PYDIGEST'
import copy
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
normalized = copy.deepcopy(doc)
normalized.setdefault("integrity", {})["canonical_sha256"] = ""
rendered = json.dumps(normalized, sort_keys=True, indent=2, separators=(",", ": ")) + "\n"
print(hashlib.sha256(rendered.encode("utf-8")).hexdigest())
PYDIGEST
}

manifest_seal_integrity() {
	local manifest="$1"
	manifest_command_exists python3 || return 1
	python3 - "${manifest}" <<'PYSEAL'
import copy
import hashlib
import json
import os
import tempfile
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
doc.setdefault("integrity", {})["algorithm"] = "sha256"
doc["integrity"]["canonical_sha256"] = ""
rendered = json.dumps(doc, sort_keys=True, indent=2, separators=(",", ": ")) + "\n"
digest = hashlib.sha256(rendered.encode("utf-8")).hexdigest()
doc["integrity"]["canonical_sha256"] = digest
rendered = json.dumps(doc, sort_keys=True, indent=2, separators=(",", ": ")) + "\n"
directory = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(prefix=f".{os.path.basename(path)}.", dir=directory, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PYSEAL
}

manifest_migrate_file() {
	local manifest="${1:-${ZCODEX_MANIFEST_FILE}}"
	local target="${2:-${manifest}}"
	manifest_command_exists python3 || return 1
	python3 - "${manifest}" "${target}" <<'PYMIGRATE'
import json
import os
import tempfile
import sys

source, target = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as fh:
    doc = json.load(fh)
version = int(doc.get("schema_version", 1))
if version > 2:
    raise SystemExit(f"unsupported future manifest schema_version: {version}")
if version < 2:
    phase = doc.get("state", {}).get("phase") or doc.get("install_state", {}).get("phase") or "UNKNOWN"
    status = doc.get("state", {}).get("status") or doc.get("install_state", {}).get("status") or "unknown"
    components = doc.get("components", [])
    if isinstance(components, dict):
        components = [{"name": key, "installed_version": value, "status": "installed" if value else "missing"} for key, value in sorted(components.items())]
    doc = {
        "schema_version": 2,
        "installer_version": doc.get("installer_version") or doc.get("version") or "unknown",
        "environment_mode": doc.get("environment_mode", "unknown"),
        "install_timestamp": doc.get("install_timestamp") or doc.get("written_at") or "unknown",
        "architecture": doc.get("architecture", "unknown"),
        "installer": doc.get("installer", {"name": "zcodex", "version": doc.get("installer_version", "unknown"), "install_id": doc.get("install_id", "unknown"), "written_at": doc.get("written_at", "unknown")}),
        "platform": doc.get("platform", doc.get("platform_info", {})),
        "platform_info": doc.get("platform_info", {}),
        "install_state": doc.get("install_state", {"phase": phase, "status": status, "install_id": doc.get("install_id", "unknown"), "state_dir": "unknown"}),
        "state": {"phase": phase, "status": status},
        "runtime": doc.get("runtime", {}),
        "components": components,
        "packages": doc.get("packages", {}),
        "verification_hashes": doc.get("verification_hashes", {}),
        "migrations": (doc.get("migrations", []) + [{"from": 1, "to": 2, "reason": "schema-versioning"}]),
    }
rendered = json.dumps(doc, sort_keys=True, indent=2, separators=(",", ": ")) + "\n"
if source == target:
    directory = os.path.dirname(target) or "."
    fd, tmp = tempfile.mkstemp(prefix=f".{os.path.basename(target)}.", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(rendered)
        os.chmod(tmp, 0o600)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
else:
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    os.chmod(target, 0o600)
PYMIGRATE
	manifest_seal_integrity "${target}"
}

manifest_validate_schema() {
	local manifest="${1:-${ZCODEX_MANIFEST_FILE}}"
	[[ -r "${manifest}" ]] || return 1
	if manifest_command_exists python3; then
		python3 - "${manifest}" <<'PYVALIDATE'
import copy
import hashlib
import json
import sys

VALID_PHASES = {"VALIDATE", "DOWNLOAD", "VERIFY", "RUNTIME_AUDIT", "INSTALL", "CONFIGURE", "VERIFY_RUNTIME", "COMPLETE", "FAILED", "UNKNOWN"}
VALID_STATUSES = {"running", "completed", "complete", "failed", "repair", "unknown"}
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:
    raise SystemExit(f"invalid manifest json: {exc}")
required = ["schema_version", "installer", "platform", "state", "components", "verification_hashes", "runtime"]
missing = [key for key in required if key not in doc]
if missing:
    raise SystemExit(f"missing manifest keys: {','.join(missing)}")
try:
    schema_version = int(doc["schema_version"])
except Exception as exc:
    raise SystemExit(f"schema_version must be an integer: {exc}")
if schema_version != 2:
    raise SystemExit("schema_version must be 2")
if not isinstance(doc["components"], list):
    raise SystemExit("components must be a list")
for index, component in enumerate(doc["components"]):
    if not isinstance(component, dict):
        raise SystemExit(f"components[{index}] must be an object")
    if not component.get("name"):
        raise SystemExit(f"components[{index}] missing name")
state = doc.get("state") or {}
phase = state.get("phase", "UNKNOWN")
status = state.get("status", "unknown")
if phase not in VALID_PHASES:
    raise SystemExit(f"invalid state phase: {phase}")
if status not in VALID_STATUSES:
    raise SystemExit(f"invalid state status: {status}")
integrity = doc.get("integrity")
if integrity:
    expected = integrity.get("canonical_sha256")
    if not isinstance(expected, str) or not expected:
        raise SystemExit("integrity.canonical_sha256 is required when integrity is present")
    normalized = copy.deepcopy(doc)
    normalized.setdefault("integrity", {})["canonical_sha256"] = ""
    rendered = json.dumps(normalized, sort_keys=True, indent=2, separators=(",", ": ")) + "\n"
    actual = hashlib.sha256(rendered.encode("utf-8")).hexdigest()
    if expected != actual:
        raise SystemExit("manifest integrity digest mismatch")
PYVALIDATE
		return $?
	fi
	grep -q '"schema_version": 2' "${manifest}"
}

manifest_append_install_record() {
	local manifest="${1:-${ZCODEX_MANIFEST_FILE}}"
	local records_file="${2:-${ZCODEX_INSTALL_RECORDS_FILE}}"
	local digest written_at
	[[ -r "${manifest}" ]] || return 1
	install -d -m 700 "$(dirname "${records_file}")"
	digest="$(sha256sum "${manifest}" | awk '{ print $1 }')"
	written_at="$(zcodex_utc_now 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '{"schema_version":1,"written_at":"%s","install_id":"%s","manifest":"%s","sha256":"%s"}\n' "${written_at}" "${ZCODEX_INSTALL_ID:-unknown}" "${manifest}" "${digest}" >>"${records_file}"
	chmod 600 "${records_file}"
}

manifest_write() {
	local status="$1"
	local node_version npm_version docker_version compose_version codex_version
	local node_sha npm_sha docker_sha codex_sha manifest_sha
	local written_at current_phase current_status install_timestamp path_digest

	install -d -m 700 "$(dirname "${ZCODEX_MANIFEST_FILE}")"
	written_at="$(zcodex_utc_now 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
	install_timestamp="${ZCODEX_INSTALL_TIMESTAMP:-${written_at}}"
	current_phase="$(state_current_phase 2>/dev/null || printf '%s' UNKNOWN)"
	current_status="$(state_status 2>/dev/null || printf '%s' "${status}")"
	node_version="$(manifest_command_version node --version || true)"
	npm_version="$(manifest_command_version npm --version || true)"
	docker_version="$(manifest_command_version docker --version || true)"
	compose_version="$(manifest_command_version docker compose version || true)"
	codex_version="$(manifest_command_version codex --version || true)"
	node_sha="$(manifest_sha256_for_command node || true)"
	npm_sha="$(manifest_sha256_for_command npm || true)"
	docker_sha="$(manifest_sha256_for_command docker || true)"
	codex_sha="$(manifest_sha256_for_command codex || true)"
	path_digest="$(printf '%s' "${PATH:-}" | sha256sum | awk '{ print $1 }')"
	manifest_sha="$(printf '%s|%s|%s|%s|%s|%s' "${ZCODEX_INSTALLER_VERSION}" "${ZCODEX_NODEJS_VERSION}" "${ZCODEX_DOCKER_PACKAGE_VERSION:-ubuntu-candidate}" "${ZCODEX_CODEX_CLI_VERSION}" "$(platform_arch_normalized)" "${current_phase}" | sha256sum | awk '{ print $1 }')"

	cat >"${ZCODEX_MANIFEST_FILE}.tmp" <<JSON
{
  "schema_version": ${ZCODEX_MANIFEST_SCHEMA_VERSION},
  "installer_version": $(manifest_json_string "${ZCODEX_INSTALLER_VERSION}"),
  "environment_mode": $(manifest_json_string "${ZCODEX_RUNTIME_MODE:-clean-system}"),
  "node_version": $(manifest_json_nullable "${node_version}"),
  "docker_version": $(manifest_json_nullable "${docker_version}"),
  "codex_version": $(manifest_json_nullable "${codex_version}"),
  "install_timestamp": $(manifest_json_string "${install_timestamp}"),
  "platform_info": {
    "os_release": $(manifest_json_string "$(platform_os_release_file)"),
$(manifest_platform_json | sed '1d;$d')
  },
  "architecture": $(manifest_json_string "$(platform_arch_normalized)"),
  "install_state": {
    "phase": $(manifest_json_string "${current_phase}"),
    "status": $(manifest_json_string "${current_status}"),
    "install_id": $(manifest_json_string "${ZCODEX_INSTALL_ID:-unknown}"),
    "state_dir": $(manifest_json_string "${ZCODEX_STATE_DIR}")
  },
  "verification_hashes": {
    "manifest_inputs": $(manifest_json_string "${manifest_sha}"),
    "path": $(manifest_json_string "${path_digest}"),
    "node": $(manifest_json_nullable "${node_sha}"),
    "npm": $(manifest_json_nullable "${npm_sha}"),
    "docker": $(manifest_json_nullable "${docker_sha}"),
    "codex": $(manifest_json_nullable "${codex_sha}")
  },
  "installer": {
    "name": "zcodex",
    "version": $(manifest_json_string "${ZCODEX_INSTALLER_VERSION}"),
    "install_id": $(manifest_json_string "${ZCODEX_INSTALL_ID:-unknown}"),
    "written_at": $(manifest_json_string "${written_at}")
  },
$(manifest_platform_json),
  "state": {
    "phase": $(manifest_json_string "${current_phase}"),
    "status": $(manifest_json_string "${status}")
  },
  "runtime": {
$(nodejs_runtime_audit | awk -F= 'BEGIN { first=1 } { gsub(/\\/, "\\\\", $2); gsub(/"/, "\\\"", $2); printf "%s    \"%s\": \"%s\"", first ? "" : ",\n", $1, $2; first=0 } END { printf "\n" }')
  },
  "components": [
$(manifest_component_json "nodejs" "${ZCODEX_NODEJS_VERSION}" "${node_version}" "$(manifest_component_status "${node_version}")" "${node_sha}"),
$(manifest_component_json "npm" "system" "${npm_version}" "$(manifest_component_status "${npm_version}")" "${npm_sha}"),
$(manifest_component_json "docker" "${ZCODEX_DOCKER_PACKAGE_VERSION:-ubuntu-candidate}" "${docker_version}" "$(manifest_component_status "${docker_version}")" "${docker_sha}"),
$(manifest_component_json "docker-compose-plugin" "${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION:-ubuntu-candidate}" "${compose_version}" "$(manifest_component_status "${compose_version}")"),
$(manifest_component_json "codex-cli" "${ZCODEX_CODEX_CLI_VERSION}" "${codex_version}" "$(manifest_component_status "${codex_version}")" "${codex_sha}")
  ],
  "packages": {
    "nodejs": $(manifest_json_nullable "$(manifest_dpkg_version nodejs)"),
    "npm": $(manifest_json_nullable "$(manifest_dpkg_version npm)"),
    "docker.io": $(manifest_json_nullable "$(manifest_dpkg_version docker.io)"),
    "docker-compose-plugin": $(manifest_json_nullable "$(manifest_dpkg_version docker-compose-plugin)")
  }
}
JSON
	chmod 600 "${ZCODEX_MANIFEST_FILE}.tmp"
	manifest_canonicalize_file "${ZCODEX_MANIFEST_FILE}.tmp"
	manifest_seal_integrity "${ZCODEX_MANIFEST_FILE}.tmp"
	manifest_validate_schema "${ZCODEX_MANIFEST_FILE}.tmp"
	mv "${ZCODEX_MANIFEST_FILE}.tmp" "${ZCODEX_MANIFEST_FILE}"
	manifest_append_install_record "${ZCODEX_MANIFEST_FILE}"
	log_success "Wrote install manifest to ${ZCODEX_MANIFEST_FILE}."
}
