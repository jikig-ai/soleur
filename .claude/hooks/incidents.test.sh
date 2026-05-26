#!/usr/bin/env bash
# Tests for .claude/hooks/lib/incidents.sh — focused on the rotation wiring
# added in #3508. The bypass-detection / repo-root resolution paths are
# exercised by pre-merge-rebase.test.sh and security_reminder_hook.test.sh;
# this file covers the per-write rotation integration.
#
# Run via:  bash .claude/hooks/incidents.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/incidents.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

ROOTS=()
trap 'for r in "${ROOTS[@]}"; do rm -rf "$r"; done' EXIT

make_root() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude"
  echo "$dir"
}

# ------------------------------------------------------------------------
# Test 1: emit_incident triggers rotation when active file exceeds threshold
# ------------------------------------------------------------------------
echo "Test 1: emit_incident triggers per-write rotation"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.rule-incidents.jsonl"
# Pre-fill with valid JSONL just over 1 KB.
for i in $(seq 1 30); do
  printf '{"schema":1,"timestamp":"2026-01-01T00:00:00Z","rule_id":"hr-pre-%d","event_type":"deny","rule_text_prefix":"x","command_snippet":""}\n' "$i" >> "$ACTIVE"
done
PRE_SIZE=$(wc -c < "$ACTIVE")
(
  # shellcheck source=/dev/null
  source "$LIB"
  INCIDENTS_REPO_ROOT="$ROOT" LOG_ROTATION_SIZE_BYTES=1024 \
    emit_incident "hr-test-rotate" "deny" "Test rule prefix" ""
)
POST_SIZE=$(wc -c < "$ACTIVE")
ARCHIVE_COUNT=$(compgen -G "$ROOT/.claude/.rule-incidents-*.jsonl.gz" | wc -l)
if [[ "$ARCHIVE_COUNT" -ne 1 ]]; then
  fail "expected 1 archive, got $ARCHIVE_COUNT (pre-size=$PRE_SIZE, post-size=$POST_SIZE)"
elif [[ "$POST_SIZE" -ge "$PRE_SIZE" ]]; then
  fail "active file not truncated (pre=$PRE_SIZE, post=$POST_SIZE)"
elif ! jq -e '.rule_id == "hr-test-rotate"' "$ACTIVE" >/dev/null 2>&1; then
  fail "post-rotation emit did not land in active file"
else
  pass "rotation triggered, archive created, post-rotate emit landed"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 2: rotation kill-switch suppresses rotation
# ------------------------------------------------------------------------
echo "Test 2: LOG_ROTATION_DISABLE suppresses rotation"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.rule-incidents.jsonl"
for i in $(seq 1 30); do
  printf '{"schema":1,"timestamp":"2026-01-01T00:00:00Z","rule_id":"hr-pre-%d","event_type":"deny","rule_text_prefix":"x","command_snippet":""}\n' "$i" >> "$ACTIVE"
done
(
  # shellcheck source=/dev/null
  source "$LIB"
  INCIDENTS_REPO_ROOT="$ROOT" LOG_ROTATION_SIZE_BYTES=1024 LOG_ROTATION_DISABLE=1 \
    emit_incident "hr-no-rotate" "deny" "x" ""
)
ARCHIVE_COUNT=$(compgen -G "$ROOT/.claude/.rule-incidents-*.jsonl.gz" | wc -l || true)
if [[ "$ARCHIVE_COUNT" -ne 0 ]]; then
  fail "rotation triggered despite kill-switch ($ARCHIVE_COUNT archives)"
elif ! jq -e 'select(.rule_id == "hr-no-rotate")' "$ACTIVE" >/dev/null 2>&1; then
  fail "emit did not land in active file under kill-switch"
else
  pass "no rotation, emit still landed in active file"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 3: emit_incident is fire-and-forget when rotator helper is missing
# ------------------------------------------------------------------------
echo "Test 3: missing rotator does not break emit_incident"
ROOT=$(make_root); ROOTS+=("$ROOT")
# Source a copy of incidents.sh from a temp lib dir that lacks log-rotation.sh
# to simulate an isolated install / partial checkout.
TMP_LIB="$ROOT/.lib"
mkdir -p "$TMP_LIB"
cp "$LIB" "$TMP_LIB/incidents.sh"
set +e
(
  # shellcheck source=/dev/null
  source "$TMP_LIB/incidents.sh"
  INCIDENTS_REPO_ROOT="$ROOT" \
    emit_incident "hr-no-rotator" "deny" "x" ""
)
RC=$?
set -e
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC when rotator helper missing (expected 0)"
elif ! jq -e '.rule_id == "hr-no-rotator"' "$ROOT/.claude/.rule-incidents.jsonl" >/dev/null 2>&1; then
  fail "emit did not land when rotator missing"
else
  pass "emit succeeded even with no rotator helper"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 4: 3-arg call defaults kind to "rule_event"
# ------------------------------------------------------------------------
# Why kind: F2 prod-write-defer-gate.sh writes discriminator values
# ("would_defer", "defer_requested", "bypass", "hook_self_fault") into the
# same JSONL sink alongside existing event_type ("deny", "warn", "applied",
# "bypass"). kind disambiguates F2-source rows from existing deny/warn rows
# so the aggregator can include/exclude defer telemetry independently of
# event_type. Additive-optional: v1 readers and the Python sibling
# (security_reminder_hook.py, no kind field) keep working — see Test 6 for
# the null-kind fall-through invariant.
echo "Test 4: 3-arg call defaults kind to rule_event"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.rule-incidents.jsonl"
(
  # shellcheck source=/dev/null
  source "$LIB"
  INCIDENTS_REPO_ROOT="$ROOT" \
    emit_incident "hr-test-kind-default" "deny" "Test prefix"
)
if ! jq -e 'select(.rule_id == "hr-test-kind-default") | .kind == "rule_event"' "$ACTIVE" >/dev/null 2>&1; then
  fail "3-arg call did not emit kind=rule_event (line: $(jq -c 'select(.rule_id == "hr-test-kind-default")' "$ACTIVE"))"
else
  pass "3-arg call → kind=rule_event"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 5: 5-arg call preserves hook_event slot 5; kind defaults to rule_event
# ------------------------------------------------------------------------
# Slot 5 was hook_event (default "PreToolUse"). No production caller ever
# passed it explicitly (audit 2026-05-15, 22 sites), but the slot is part
# of the function's documented signature so a future caller might. The
# kind extension must not shift slot 5's semantics.
echo "Test 5: 5-arg call preserves hook_event slot 5; kind defaults"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.rule-incidents.jsonl"
(
  # shellcheck source=/dev/null
  source "$LIB"
  INCIDENTS_REPO_ROOT="$ROOT" \
    emit_incident "hr-test-5arg" "deny" "prefix" "cmd-snippet" "UserPromptSubmit"
)
# 5-arg call: hook_event="UserPromptSubmit" reaches sentinel paths if they
# fire, but the canonical line itself doesn't carry hook_event (kept that
# way to preserve the v1 schema). Confirm: kind defaults and command_snippet
# slot 4 still works.
if ! jq -e 'select(.rule_id == "hr-test-5arg") | .kind == "rule_event" and .command_snippet == "cmd-snippet"' "$ACTIVE" >/dev/null 2>&1; then
  fail "5-arg call did not preserve slot semantics (line: $(jq -c 'select(.rule_id == "hr-test-5arg")' "$ACTIVE"))"
else
  pass "5-arg call → kind defaults + cmd slot preserved"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 6: 6-arg call emits kind explicitly + null-kind predicate falls through
# ------------------------------------------------------------------------
echo "Test 6: 6-arg call emits kind; null-kind predicate falls through"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.rule-incidents.jsonl"
# Seed one v1-shape row (no kind field) to verify aggregators treating
# null kind as fall-through still see this row.
printf '{"schema":1,"timestamp":"2026-01-01T00:00:00Z","rule_id":"hr-v1-legacy","event_type":"deny","rule_text_prefix":"x","command_snippet":""}\n' >> "$ACTIVE"
(
  # shellcheck source=/dev/null
  source "$LIB"
  INCIDENTS_REPO_ROOT="$ROOT" \
    emit_incident "hr-test-6arg" "applied" "prefix" "cmd" "PreToolUse" "would_defer"
)
if ! jq -e 'select(.rule_id == "hr-test-6arg") | .kind == "would_defer"' "$ACTIVE" >/dev/null 2>&1; then
  fail "6-arg call did not emit kind=would_defer (line: $(jq -c 'select(.rule_id == "hr-test-6arg")' "$ACTIVE"))"
else
  pass "6-arg call → kind=would_defer"
fi
# Null-kind predicate: aggregators using `select((.kind // "rule_event") == "rule_event")`
# must see both the v1-legacy row (no kind field) AND any future row emitted
# with kind="rule_event". This is the additive-optional contract.
COUNT=$(jq -c 'select((.kind // "rule_event") == "rule_event") | .rule_id' "$ACTIVE" | wc -l)
if [[ "$COUNT" -ne 1 ]]; then
  fail "null-kind fall-through: expected 1 row (the v1-legacy seed), got $COUNT"
else
  pass "null-kind predicate falls through (legacy row visible under rule_event filter)"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
