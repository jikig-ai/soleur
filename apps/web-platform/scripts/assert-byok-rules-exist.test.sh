#!/usr/bin/env bash
# Tests for assert-byok-rules-exist.sh — #4656 item 5 liveness assertion.
#
# Run via:  bash apps/web-platform/scripts/assert-byok-rules-exist.test.sh
#
# Test isolation: every invocation injects SENTRY_FIXTURE_RULES so the live
# Sentry API is NEVER called. The fixtures are synthesized inline (no captured
# real payloads — cq-test-fixtures-synthesized-only).

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/assert-byok-rules-exist.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found or not executable" >&2
  exit 1
fi

TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

# Common env: the fixture path overrides the live GET; token/org/project are
# required by the script's preflight `:?` guards but never used under fixture.
# `env` parses the leading VAR=val assignments from BOTH this helper and the
# per-call `SENTRY_FIXTURE_RULES=...` prefix before exec'ing the command.
base_env() {
  env SENTRY_AUTH_TOKEN=t SENTRY_ORG=jikigai SENTRY_PROJECT=web-platform "$@"
}

# ------------------------------------------------------------------------
# T1 — both rules present → exit 0.
# ------------------------------------------------------------------------
echo "T1: both BYOK rules present"
cat >"$TMPDIR_T/both.json" <<'JSON'
[
  {"id": "1", "name": "byok-art-33-breach"},
  {"id": "2", "name": "byok-cap-exceeded"},
  {"id": "3", "name": "auth-exchange-code-burst"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/both.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then pass "exit 0 when both rules present"; else fail "expected exit 0, got $rc ($out)"; fi

# ------------------------------------------------------------------------
# T2 — art-33-breach missing → non-zero exit, names the missing rule.
# ------------------------------------------------------------------------
echo "T2: byok-art-33-breach missing"
cat >"$TMPDIR_T/missing-breach.json" <<'JSON'
[
  {"id": "2", "name": "byok-cap-exceeded"},
  {"id": "3", "name": "auth-exchange-code-burst"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/missing-breach.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit when art-33-breach absent"; else fail "expected non-zero, got 0"; fi
if grep -q "byok-art-33-breach" <<<"$out"; then pass "names the missing rule"; else fail "missing rule not named ($out)"; fi

# ------------------------------------------------------------------------
# T3 — cap-exceeded missing → non-zero exit.
# ------------------------------------------------------------------------
echo "T3: byok-cap-exceeded missing"
cat >"$TMPDIR_T/missing-cap.json" <<'JSON'
[
  {"id": "1", "name": "byok-art-33-breach"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/missing-cap.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit when cap-exceeded absent"; else fail "expected non-zero, got 0"; fi

# ------------------------------------------------------------------------
# T4 — non-array response (auth/region/endpoint error) → non-zero exit.
# ------------------------------------------------------------------------
echo "T4: non-array API response fails closed"
cat >"$TMPDIR_T/error.json" <<'JSON'
{"detail": "Invalid token"}
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/error.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit on non-array response"; else fail "expected non-zero, got 0"; fi

# ------------------------------------------------------------------------
# T5 — missing SENTRY_AUTH_TOKEN exits non-zero (preflight guard).
# ------------------------------------------------------------------------
echo "T5: missing SENTRY_AUTH_TOKEN"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit without token"; else fail "expected non-zero, got 0"; fi

echo ""
echo "assert-byok-rules-exist.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
