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

# Common env: the fixture path overrides the live GET. Token and org are
# required by the script's preflight `:?` guards but never used under fixture.
# SENTRY_PROJECT is no longer required (#7590) and is kept here only so the
# pre-existing tests stay byte-comparable to their pre-migration form; T10
# asserts the script runs without it.
# `env` parses the leading VAR=val assignments from BOTH this helper and the
# per-call `SENTRY_FIXTURE_RULES=...` prefix before exec'ing the command.
base_env() {
  env SENTRY_AUTH_TOKEN=t SENTRY_ORG=jikigai SENTRY_PROJECT=web-platform "$@"
}

# ------------------------------------------------------------------------
# T1 — both rules present → exit 0.
# ------------------------------------------------------------------------
echo "T1: all expected rules present"
cat >"$TMPDIR_T/both.json" <<'JSON'
[
  {"id": "1", "name": "byok-art-33-breach"},
  {"id": "2", "name": "byok-cap-exceeded"},
  {"id": "3", "name": "chat-message-save-failure"},
  {"id": "4", "name": "auth-exchange-code-burst"},
  {"id": "5", "name": "workspace-sync-health"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/both.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then pass "exit 0 when all expected rules present"; else fail "expected exit 0, got $rc ($out)"; fi

# ------------------------------------------------------------------------
# T2 — art-33-breach missing → non-zero exit, names the missing rule.
# ------------------------------------------------------------------------
echo "T2: byok-art-33-breach missing"
# chat-message-save-failure present so only art-33 is absent (isolation).
cat >"$TMPDIR_T/missing-breach.json" <<'JSON'
[
  {"id": "2", "name": "byok-cap-exceeded"},
  {"id": "3", "name": "chat-message-save-failure"},
  {"id": "4", "name": "auth-exchange-code-burst"},
  {"id": "5", "name": "workspace-sync-health"}
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
# chat + workspace-sync-health present so only cap is absent (isolation).
cat >"$TMPDIR_T/missing-cap.json" <<'JSON'
[
  {"id": "1", "name": "byok-art-33-breach"},
  {"id": "3", "name": "chat-message-save-failure"},
  {"id": "5", "name": "workspace-sync-health"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/missing-cap.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit when cap-exceeded absent"; else fail "expected non-zero, got 0"; fi
if grep -q "byok-cap-exceeded" <<<"$out"; then pass "names the missing cap rule"; else fail "missing cap rule not named ($out)"; fi

# ------------------------------------------------------------------------
# T4 — non-array response (auth/region/endpoint error) → non-zero exit
#      via the fail-closed JSON-array guard (not the absent-rule path).
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
if grep -q "not a JSON array" <<<"$out"; then pass "fails via the JSON-array guard (right reason)"; else fail "did not hit the array guard ($out)"; fi

# ------------------------------------------------------------------------
# T5 — missing SENTRY_AUTH_TOKEN exits non-zero (preflight guard).
# ------------------------------------------------------------------------
echo "T5: missing SENTRY_AUTH_TOKEN"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit without token"; else fail "expected non-zero, got 0"; fi

# ------------------------------------------------------------------------
# T6 — missing SENTRY_API_HOST exits non-zero.
#
# RENAMED 2026-08-19 (#7590). This test was "missing SENTRY_PROJECT exits
# non-zero"; it kept passing after that guard was removed, because with no
# fixture the run reaches the live fetch and trips the SENTRY_API_HOST guard
# instead — a pass for a reason the test's own name denies, and the exact
# shape that would have let T10 and T6 assert opposite things while both
# reported green. The rc assertion is therefore pinned to the message, not
# just to non-zero: `rc != 0` alone cannot tell these two guards apart.
# ------------------------------------------------------------------------
echo "T6: missing SENTRY_API_HOST"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" SENTRY_AUTH_TOKEN=t SENTRY_ORG=jikigai bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]] && grep -q 'SENTRY_API_HOST must be set' <<<"$out"; then
  pass "non-zero exit naming SENTRY_API_HOST"
else
  fail "expected non-zero naming SENTRY_API_HOST, got rc=$rc: $out"
fi

# ------------------------------------------------------------------------
# T7 — chat-message-save-failure missing → non-zero exit, names the rule
#      (#4849 detector-liveness parity with T2/T3).
# ------------------------------------------------------------------------
echo "T7: chat-message-save-failure missing"
cat >"$TMPDIR_T/missing-chat.json" <<'JSON'
[
  {"id": "1", "name": "byok-art-33-breach"},
  {"id": "2", "name": "byok-cap-exceeded"},
  {"id": "5", "name": "workspace-sync-health"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/missing-chat.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit when chat-message-save-failure absent"; else fail "expected non-zero, got 0"; fi
if grep -q "chat-message-save-failure" <<<"$out"; then pass "names the missing chat rule"; else fail "missing chat rule not named ($out)"; fi

# ------------------------------------------------------------------------
# T8 — workspace-sync-health missing → non-zero exit, names the rule
#      (#4882 detector-liveness parity with T2/T3/T7).
# ------------------------------------------------------------------------
echo "T8: workspace-sync-health missing"
cat >"$TMPDIR_T/missing-wsh.json" <<'JSON'
[
  {"id": "1", "name": "byok-art-33-breach"},
  {"id": "2", "name": "byok-cap-exceeded"},
  {"id": "3", "name": "chat-message-save-failure"}
]
JSON
set +e
out=$(base_env SENTRY_FIXTURE_RULES="$TMPDIR_T/missing-wsh.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then pass "non-zero exit when workspace-sync-health absent"; else fail "expected non-zero, got 0"; fi
if grep -q "workspace-sync-health" <<<"$out"; then pass "names the missing workspace-sync-health rule"; else fail "missing wsh rule not named ($out)"; fi

# ------------------------------------------------------------------------
# T9 — the live fetch targets the ORG-SCOPED replacement (#7590).
#
# Every test above injects SENTRY_FIXTURE_RULES, which returns before curl
# runs — so no fixture-driven test can see the URL, and the deprecated
# endpoint could be restored with the whole suite green. Sentry deprecated
# `projects/{org}/{proj}/rules/` on 2026-05-14 and serves it under brownouts;
# this script runs POST-apply under `set -euo pipefail` with `curl -fsS`, so a
# brownout reds apply-sentry-infra.yml after a successful terraform apply.
#
# Asserted against COMMENT-STRIPPED source: the header above discusses the old
# path by name (deliberately — the migration note has to say what it migrated
# from), and a body-grep sees comments too. Anchored on the full quoted URL
# expression rather than a bare `workflows` token, per
# `cq-assert-anchor-not-bare-token`.
# ------------------------------------------------------------------------
echo "T9: the live fetch targets organizations/{org}/workflows/"
# `|| true`: grep exits 1 when every line is a comment, which under `set -eu`
# would kill the suite at the assignment rather than fail this test.
code_only=$(grep -vE '^[[:space:]]*#' "$SCRIPT" || true)
# Non-vacuity. An empty extract makes the NEGATIVE arm below pass without
# examining anything — the failure mode where a broken anchor reads as a clean
# result. 20 is a floor, not a measurement: the script's code half is ~30 lines
# and this only has to catch "the extract collapsed".
n_code=$(grep -c . <<<"$code_only" || true)
if (( n_code < 20 )); then
  fail "T9 FIXTURE DEFECT: comment-stripped extract is ${n_code} lines — the anchor broke, so neither arm below examines the script"
fi
if grep -qE '"https://\$\{SENTRY_API_HOST\}/api/0/organizations/\$\{SENTRY_ORG\}/workflows/' <<<"$code_only"; then
  pass "fetch_rules requests the org-scoped workflows endpoint"
else
  fail "fetch_rules does not request organizations/\${SENTRY_ORG}/workflows/"
fi
if grep -qE 'projects/\$\{SENTRY_ORG\}/\$\{SENTRY_PROJECT\}/rules/' <<<"$code_only"; then
  fail "the deprecated project rules endpoint is still requested"
else
  pass "no request to the deprecated projects/{org}/{proj}/rules/ path"
fi

# ------------------------------------------------------------------------
# T10 — SENTRY_PROJECT is no longer required.
#
# The org-scoped URL has no project segment, so the variable has no consumer.
# A surviving `:?` guard would abort a correctly-configured caller that stopped
# passing a now-meaningless secret — and the guard is invisible to every test
# above, all of which set it via base_env.
# ------------------------------------------------------------------------
echo "T10: SENTRY_PROJECT is not required"
set +e
out=$(env -u SENTRY_PROJECT \
  SENTRY_AUTH_TOKEN=fake SENTRY_ORG=jikigai SENTRY_API_HOST=jikigai.sentry.io \
  SENTRY_FIXTURE_RULES="$TMPDIR_T/both.json" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  pass "runs to success with SENTRY_PROJECT unset"
else
  fail "SENTRY_PROJECT still required (rc=$rc): $out"
fi

echo ""
echo "assert-byok-rules-exist.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
