# Static Analysis Report (maximum-depth)

Date: 2026-05-09
Scope: `cvsz/zcodex` shell runtime, installer libs, and tests.

## Methodology
- Pattern search for sinks/sources: `eval`, subshell execution, curl/download, temp file creation, `source`/`.` includes, privileged execution, and path handling.
- Manual taint-trace review across installer runtime flow.
- Security category mapping for exploitability and reachability.

## Findings (ranked)

### 1) High — Local code execution via untrusted os-release sourcing when env override is attacker-controlled
- **Location**: `scripts/lib/platform.sh` lines 35-50 and 53-60.
- **Root cause**: `platform_os_release_file` trusts `ZCODEX_OS_RELEASE_FILE`, and callers source that path with `.`.
- **Taint flow**:
  - Source: environment variable `ZCODEX_OS_RELEASE_FILE`.
  - Propagation: `platform_os_release_file` -> `platform_os_id` / `platform_os_version_id` / `platform_pretty_name`.
  - Sink: shell `.` command executes file content in current process.
- **Impact**: If installer is launched in a hostile environment where attacker controls process environment and file path, arbitrary shell commands can execute in installer context. If installer later uses `sudo`, this may become privilege escalation by influencing control flow/logging/actions.
- **Reachability**: Reachable in standard startup validation path through platform checks.
- **Exploit chain example**:
  1. Attacker sets `ZCODEX_OS_RELEASE_FILE=/tmp/malicious`.
  2. Attacker writes shell payload to file.
  3. Installer invokes platform detection and sources file.
  4. Payload executes.
- **Remediation**:
  - Remove env override in production path, or restrict to strict allowlist (`/etc/os-release`, `/usr/lib/os-release`).
  - Parse key/value file without `source` (e.g., grep/sed parser honoring shell quoting rules safely, or python parser).
  - If override is needed for tests, gate behind explicit `ZCODEX_TEST_MODE=true`.

### 2) Medium — SSRF/network pivot possibility through generic downloader helper
- **Location**: `scripts/lib/security.sh` lines 378-403.
- **Root cause**: `security_download` accepts arbitrary HTTPS URL and follows redirects.
- **Taint flow**:
  - Source: function argument `url`.
  - Sink: `curl --location ... "${url}"`.
- **Impact**: Internal callers currently appear controlled, but this helper is generic. Future or external reuse with untrusted URL input could permit SSRF to internal metadata/HTTPs endpoints reachable from host network namespace.
- **Reachability**: Conditionally reachable depending on callsites (currently low external exposure).
- **Remediation**:
  - Enforce domain allowlist for release artifacts.
  - Pin final resolved host and reject private/rfc1918/link-local destinations when policy requires.
  - Consider `--proto-redir '=https'` to prevent insecure redirect protocol downgrade (even though base URL is HTTPS).

### 3) Medium — Unsafe trust boundary on command discovery if library functions are reused without pre-validation
- **Location**: `scripts/lib/security.sh` lines 405-427; `scripts/lib/packages.sh` lines 4-25.
- **Root cause**: Some commands execute by name (e.g., `apt-get`, `curl`) and rely on upstream path validation discipline.
- **Taint flow**:
  - Source: process `PATH`.
  - Propagation: command resolution by shell.
  - Sink: privileged command execution via `runtime_privileged ... apt-get` and unprivileged `curl`.
- **Impact**: If future call paths skip `security_validate_path`/shadow checks, PATH hijack can invoke trojan binaries.
- **Reachability**: Mitigated in intended flow, but hidden coupling exists (security depends on call order invariants).
- **Remediation**:
  - Use absolute paths for sensitive commands (`/usr/bin/apt-get`, `/usr/bin/curl`) after verification.
  - Add explicit precondition checks in each sink helper (defense in depth).

## No confirmed vulnerabilities (after review)
- SQL injection, XSS, CSRF, prototype pollution: not applicable to current shell-based CLI repo surfaces.
- Deserialization risk: JSON handled via Python stdlib with local files; no unsafe object deserialization found.
- Unsafe temp files/symlink attacks: `mktemp` usage and atomic replace patterns are generally safe (`state_atomic_write`, manifest canonicalization).
- Race conditions/async misuse: no parallel shared-memory concurrency model found; lock helper exists in security module.
- Integer overflow/memory leaks: not meaningful in current shell script architecture.

## Broken invariants / hidden coupling
- Security posture assumes specific orchestration ordering:
  1. path validation,
  2. command shadowing checks,
  3. privileged actions.
- This invariant is implicit, not enforced by sink APIs.

## Dead code / unreachable branches / lint / type
- `shellcheck` execution unavailable in environment (`shellcheck: command not found`), so lint/type-style static diagnostics are partially blocked.
- Manual pass did not identify obvious dead branches, but exhaustive branch reachability would require shellcheck + bats coverage + mutation testing.

## Regression tests recommended
1. **os-release injection guard**:
   - Set `ZCODEX_OS_RELEASE_FILE` to malicious script and assert no command execution occurs.
2. **download URL policy test**:
   - Reject non-allowlisted hosts and private IP targets in downloader helper.
3. **sink hardening tests**:
   - Assert package/install helpers fail if command path not trusted even when PATH is poisoned.
4. **invariant tests**:
   - Directly call sink helpers without prior validation and assert they self-protect.

## Severity summary
- High: 1
- Medium: 2
- Low: 0
- Informational: multiple design notes
