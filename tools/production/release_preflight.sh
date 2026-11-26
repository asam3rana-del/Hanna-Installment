#!/usr/bin/env bash
# Read-only production release preflight. Does not deploy, sign, or modify customer data.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
PASS=0; WARN=0; FAIL=0
check(){ local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf 'PASS  %s\n' "$label"; PASS=$((PASS+1)); else printf 'FAIL  %s\n' "$label"; FAIL=$((FAIL+1)); fi; }
warn(){ local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf 'PASS  %s\n' "$label"; PASS=$((PASS+1)); else printf 'WARN  %s\n' "$label"; WARN=$((WARN+1)); fi; }
exists(){ [[ -e "$1" ]]; }
cmd(){ command -v "$1" >/dev/null 2>&1; }
printf 'Hanna Installment — Release Preflight\nProject: %s\n\n' "$ROOT"
check 'pubspec.yaml exists' exists pubspec.yaml
check 'pubspec.lock exists' exists pubspec.lock
check 'pubspec.yaml parses as YAML' ruby -e 'require "yaml"; YAML.load_file("pubspec.yaml")'
warn 'Android platform project exists' exists android
warn 'iOS platform project exists' exists ios
warn 'Windows platform project exists' exists windows
warn 'Flutter SDK available' cmd flutter
warn 'Dart SDK available' cmd dart
warn 'Firebase CLI available for approved staging work' cmd firebase
warn 'GitHub Actions workflows exist' exists .github/workflows
warn 'Production release checklist exists' exists PRODUCTION_RELEASE_CHECKLIST.md
warn 'Phase 3 security/sync runbook exists' exists docs/production/phase3/PHASE3_SECURITY_SYNC_BACKUP.md
warn 'Release signing config is present (verify securely in CI; values are never printed)' bash -c '[[ -n "${KEYSTORE_BASE64:-}" && -n "${KEYSTORE_PASSWORD:-}" && -n "${KEY_PASSWORD:-}" ]]'
printf '\nTotals: PASS=%d WARN=%d FAIL=%d\n' "$PASS" "$WARN" "$FAIL"
if (( FAIL > 0 )); then printf 'RESULT: BLOCKED — required project files are missing.\n'; exit 2; fi
if (( WARN > 0 )); then printf 'RESULT: NOT CLEARED — warnings require human/CI verification.\n'; exit 1; fi
printf 'RESULT: PREFLIGHT CLEAR ONLY — this is not production certification.\n'
