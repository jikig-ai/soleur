#!/usr/bin/env bash
# Tests for scripts/skill-freshness-aggregate.sh.
#
# Sets SKILL_FRESHNESS_REPO_ROOT to a tmp fixture so reads/writes don't
# touch the real .claude/.skill-invocations.jsonl or skill-freshness.json.
#
# Run via:  bash scripts/skill-freshness-aggregate.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGGREGATOR="$SCRIPT_DIR/skill-freshness-aggregate.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Build a fake repo root with N skills and an optional invocations log.
make_fake_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/plugins/soleur/skills/alpha"
  mkdir -p "$dir/plugins/soleur/skills/beta"
  mkdir -p "$dir/plugins/soleur/skills/gamma"
  printf -- '---\nname: alpha\n---\n' > "$dir/plugins/soleur/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\n---\n'  > "$dir/plugins/soleur/skills/beta/SKILL.md"
  printf -- '---\nname: gamma\n---\n' > "$dir/plugins/soleur/skills/gamma/SKILL.md"
  mkdir -p "$dir/.claude"
  echo "$dir"
}

# Deterministic relative timestamp: <days_ago> days before now.
ts_days_ago() {
  local days="$1"
  date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || python3 -c "from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) - timedelta(days=$days)).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

# ------------------------------------------------------------------------
# Test 1: empty invocations log → all skills "never_invoked"
# ------------------------------------------------------------------------
echo "Test 1: empty invocations log"
ROOT=$(make_fake_repo)
OUT=$(SKILL_FRESHNESS_REPO_ROOT="$ROOT" bash "$AGGREGATOR" --dry-run)
TOTAL=$(echo "$OUT" | jq -r '.summary.total_skills')
NEVER=$(echo "$OUT" | jq -r '.summary.never_invoked')
IDLE180=$(echo "$OUT" | jq -r '.summary.idle_180d')
IDLE365=$(echo "$OUT" | jq -r '.summary.idle_365d')
SCHEMA=$(echo "$OUT" | jq -r '.schema')
if [[ "$TOTAL" -ne 3 ]]; then
  fail "total_skills expected 3, got $TOTAL"
elif [[ "$NEVER" -ne 3 ]]; then
  fail "never_invoked expected 3, got $NEVER"
elif [[ "$IDLE180" -ne 0 || "$IDLE365" -ne 0 ]]; then
  fail "idle counts non-zero on empty log"
elif [[ "$SCHEMA" -ne 1 ]]; then
  fail "schema expected 1, got $SCHEMA"
else
  pass "3 never_invoked, schema 1"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 2: malformed JSONL line → skipped, valid lines counted
# ------------------------------------------------------------------------
echo "Test 2: malformed line tolerance"
ROOT=$(make_fake_repo)
{
  echo "not json at all"
  printf '{"schema":1,"ts":"%s","skill":"alpha"}\n' "$(ts_days_ago 1)"
  echo "}}}"
} > "$ROOT/.claude/.skill-invocations.jsonl"
OUT=$(SKILL_FRESHNESS_REPO_ROOT="$ROOT" bash "$AGGREGATOR" --dry-run)
ALPHA_STATUS=$(echo "$OUT" | jq -r '.skills[] | select(.name == "alpha") | .status')
ALPHA_COUNT=$(echo "$OUT" | jq -r '.skills[] | select(.name == "alpha") | .invocation_count')
BETA_STATUS=$(echo "$OUT" | jq -r '.skills[] | select(.name == "beta") | .status')
if [[ "$ALPHA_STATUS" != "fresh" ]]; then
  fail "alpha (1d ago) expected fresh, got $ALPHA_STATUS"
elif [[ "$ALPHA_COUNT" -ne 1 ]]; then
  fail "alpha invocation_count expected 1, got $ALPHA_COUNT"
elif [[ "$BETA_STATUS" != "never_invoked" ]]; then
  fail "beta expected never_invoked, got $BETA_STATUS"
else
  pass "malformed lines skipped, valid line counted"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 3: threshold boundaries — 179d / 180d / 364d / 365d
# ------------------------------------------------------------------------
echo "Test 3: threshold boundaries"
ROOT=$(make_fake_repo)
mkdir -p "$ROOT/plugins/soleur/skills/delta"
mkdir -p "$ROOT/plugins/soleur/skills/epsilon"
printf -- '---\nname: delta\n---\n'   > "$ROOT/plugins/soleur/skills/delta/SKILL.md"
printf -- '---\nname: epsilon\n---\n' > "$ROOT/plugins/soleur/skills/epsilon/SKILL.md"
{
  printf '{"schema":1,"ts":"%s","skill":"alpha"}\n'   "$(ts_days_ago 179)"
  printf '{"schema":1,"ts":"%s","skill":"beta"}\n'    "$(ts_days_ago 180)"
  printf '{"schema":1,"ts":"%s","skill":"gamma"}\n'   "$(ts_days_ago 364)"
  printf '{"schema":1,"ts":"%s","skill":"delta"}\n'   "$(ts_days_ago 365)"
  printf '{"schema":1,"ts":"%s","skill":"epsilon"}\n' "$(ts_days_ago 0)"
} > "$ROOT/.claude/.skill-invocations.jsonl"
OUT=$(SKILL_FRESHNESS_REPO_ROOT="$ROOT" bash "$AGGREGATOR" --dry-run)
A=$(echo "$OUT" | jq -r '.skills[] | select(.name == "alpha")   | .status')
B=$(echo "$OUT" | jq -r '.skills[] | select(.name == "beta")    | .status')
G=$(echo "$OUT" | jq -r '.skills[] | select(.name == "gamma")   | .status')
D=$(echo "$OUT" | jq -r '.skills[] | select(.name == "delta")   | .status')
E=$(echo "$OUT" | jq -r '.skills[] | select(.name == "epsilon") | .status')
EXPECT="alpha=fresh beta=idle gamma=idle delta=archival_candidate epsilon=fresh"
GOT="alpha=$A beta=$B gamma=$G delta=$D epsilon=$E"
if [[ "$GOT" != "$EXPECT" ]]; then
  fail "expected: $EXPECT  /  got: $GOT"
else
  pass "179d=fresh, 180d=idle, 364d=idle, 365d=archival_candidate, 0d=fresh"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 4: aggregator counts multiple invocations of the same skill
# ------------------------------------------------------------------------
echo "Test 4: invocation_count aggregates"
ROOT=$(make_fake_repo)
# Capture exact timestamps at write time so the assertion matches the
# value in the JSONL (avoids 1s race between write and post-aggregator
# `ts_days_ago 2` recomputation).
TS_5=$(ts_days_ago 5)
TS_4=$(ts_days_ago 4)
TS_3=$(ts_days_ago 3)
TS_2=$(ts_days_ago 2)
{
  printf '{"schema":1,"ts":"%s","skill":"alpha"}\n' "$TS_5"
  printf '{"schema":1,"ts":"%s","skill":"alpha"}\n' "$TS_4"
  printf '{"schema":1,"ts":"%s","skill":"alpha"}\n' "$TS_3"
  printf '{"schema":1,"ts":"%s","skill":"alpha"}\n' "$TS_2"
} > "$ROOT/.claude/.skill-invocations.jsonl"
OUT=$(SKILL_FRESHNESS_REPO_ROOT="$ROOT" bash "$AGGREGATOR" --dry-run)
COUNT=$(echo "$OUT" | jq -r '.skills[] | select(.name == "alpha") | .invocation_count')
LAST=$(echo "$OUT"  | jq -r '.skills[] | select(.name == "alpha") | .last_invoked')
EXPECTED_LAST="$TS_2"
if [[ "$COUNT" -ne 4 ]]; then
  fail "invocation_count expected 4, got $COUNT"
elif [[ "$LAST" != "$EXPECTED_LAST" ]]; then
  fail "last_invoked expected $EXPECTED_LAST, got $LAST"
else
  pass "4 invocations counted, last_invoked = max ts"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 5: write to skill-freshness.json on first run; no rewrite on
# second identical run (materially-changed gate)
# ------------------------------------------------------------------------
echo "Test 5: materially-changed write"
ROOT=$(make_fake_repo)
mkdir -p "$ROOT/knowledge-base/engineering/operations"
SKILL_FRESHNESS_REPO_ROOT="$ROOT" bash "$AGGREGATOR" >/dev/null
OUT_PATH="$ROOT/knowledge-base/engineering/operations/skill-freshness.json"
if [[ ! -f "$OUT_PATH" ]]; then
  fail "first run did not write output file"
else
  FIRST_MTIME=$(stat -c %Y "$OUT_PATH" 2>/dev/null || stat -f %m "$OUT_PATH")
  sleep 1
  OUT2=$(SKILL_FRESHNESS_REPO_ROOT="$ROOT" bash "$AGGREGATOR" 2>&1)
  if echo "$OUT2" | grep -q "No material change"; then
    pass "second identical run skipped write"
  else
    fail "second run rewrote unchanged output: $OUT2"
  fi
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
