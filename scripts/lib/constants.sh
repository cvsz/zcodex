#!/usr/bin/env bash
# Centralized constants and configuration for zcodex.

# State and configuration directories
: "${ZCODEX_STATE_HOME:=${HOME}/.local/share/zcodex}"
: "${ZCODEX_CONFIG_HOME:=${HOME}/.config/zcodex}"
: "${ZCODEX_CACHE_HOME:=${HOME}/.cache/zcodex}"
: "${ZCODEX_BACKUP_DIR:=${HOME}/.zcodex/backups}"

# File paths
: "${ZCODEX_MANIFEST_FILE:=${ZCODEX_STATE_HOME}/manifest.json}"
: "${ZCODEX_INSTALL_RECORDS_FILE:=${ZCODEX_STATE_HOME}/install-records.jsonl}"
: "${ZCODEX_LOCK_FILE:=/tmp/zcodex-install.lock}"
: "${ZCODEX_LOG_FILE:=/tmp/zcodex-install.log}"

# Schema versions
: "${ZCODEX_MANIFEST_SCHEMA_VERSION:=2}"
: "${ZCODEX_STATE_SCHEMA_VERSION:=1}"

# Default runtime settings
: "${ZCODEX_RUNTIME_MODE:=clean-system}"
: "${ZCODEX_ALLOW_USER_RUNTIME_MUTATION:=false}"
: "${ZCODEX_ROLLBACK_ON_FAILURE:=true}"

# Security defaults
: "${ZCODEX_SECURE_PATH:=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
: "${ZCODEX_CI_TRUSTED_PATH:=/usr/sbin:/usr/bin:/sbin:/bin}"
: "${ZCODEX_ALLOW_INSECURE_PATH:=false}"

# Timeout and retry defaults
: "${ZCODEX_DEFAULT_TIMEOUT:=300}"
: "${ZCODEX_DEFAULT_RETRIES:=3}"
: "${ZCODEX_RETRY_DELAY:=5}"

# Version pins (should match VERSION file)
: "${ZCODEX_NODEJS_VERSION:=20}"
: "${ZCODEX_CODEX_VERSION:=latest}"

# Feature flags
: "${ZCODEX_SKIP_DOCKER:=false}"
: "${ZCODEX_SKIP_OPTIONAL:=false}"
: "${ZCODEX_DRY_RUN:=false}"
: "${ZCODEX_CI_MODE:=${CI:-false}}"
: "${ZCODEX_STRICT_MODE:=0}"

# Exported for subprocesses
export ZCODEX_STATE_HOME
export ZCODEX_CONFIG_HOME
export ZCODEX_CACHE_HOME
export ZCODEX_BACKUP_DIR
export ZCODEX_MANIFEST_FILE
export ZCODEX_INSTALL_RECORDS_FILE
export ZCODEX_LOCK_FILE
export ZCODEX_LOG_FILE
export ZCODEX_MANIFEST_SCHEMA_VERSION
export ZCODEX_STATE_SCHEMA_VERSION
export ZCODEX_RUNTIME_MODE
export ZCODEX_ALLOW_USER_RUNTIME_MUTATION
export ZCODEX_ROLLBACK_ON_FAILURE
export ZCODEX_SECURE_PATH
export ZCODEX_CI_TRUSTED_PATH
export ZCODEX_ALLOW_INSECURE_PATH
export ZCODEX_DEFAULT_TIMEOUT
export ZCODEX_DEFAULT_RETRIES
export ZCODEX_RETRY_DELAY
export ZCODEX_NODEJS_VERSION
export ZCODEX_CODEX_VERSION
export ZCODEX_SKIP_DOCKER
export ZCODEX_SKIP_OPTIONAL
export ZCODEX_DRY_RUN
export ZCODEX_CI_MODE
export ZCODEX_STRICT_MODE
