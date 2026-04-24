#!/usr/bin/env bash
# Tests for scripts/rule-metrics-aggregate.sh.
#
# Covers the applied/warn/fire_count fields added for rule-metrics emit_incident
# coverage (plan 2026-04-24, issue #2866):
#   - mixed event types count into correct fields,
#   - applied/warn-only rules are NOT flagged as unused (fire_count predicate),
#   - prevented_errors stays deny-only,
#   - unknown rule_id (not in AGENTS.md) causes exit non-zero via orphan_rule_ids,
#   - rule-prune.sh uses fire_count for its orphan predicate.
#
# Isolation: each test builds a throwaway repo via `mktemp -d` with a synthetic
# AGENTS.md and .claude/.rule-incidents.jsonl. INCIDENTS_REPO_ROOT + RULE_METRICS_ROOT
# redirect the aggregator / prune consumer to that tree so the operator's real
# .claude/.rule-incidents.jsonl is untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGGREGATOR="$SCRIPT_DIR/rule-metrics-aggregate.sh"
PRUNE="$SCRIPT_DIR/rule-prune.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }

make_fixture_repo() {
  local root
  root=$(mktemp -d)
  mkdir -p "$root/.claude" "$root/knowledge-base/project"
  cat > "$root/AGENTS.md" <<'EOF'
# Agent Instructions

## Hard Rules

- Rule A synthetic fixture bullet for aggregator tests [id: hr-rule-a-synthetic-test].
- Rule B synthetic fixture bullet for aggregator tests [id: hr-rule-b-synthetic-test].
- Rule C synthetic fixture bullet for aggregator tests [id: hr-rule-c-synthetic-test].
- Rule D synthetic fixture bullet for aggregator tests [id: hr-rule-d-synthetic-test].
EOF
  echo "$root"
}

write_event() {
  local root="$1" rule="$2" event="$3" ts="$4"
  printf '{"schema":1,"timestamp":"%s","rule_id":"%s","event_type":"%s","rule_text_prefix":"x","command_snippet":""}\n' \
    "$ts" "$rule" "$event" >> "$root/.claude/.rule-incidents.jsonl"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

rule_field() {
  local metrics="$1" id="$2" field="$3"
  jq -r --arg id "$id" --arg f "$field" \
    '.rules[] | select(.id==$id) | .[$f]' < "$metrics"
}

# --- T1: mixed event types -----------------------------------------------
t1_mixed_events() {
  local root; root=$(make_fixture_repo)
  # Rule A: 3 deny + 1 bypass → hit=3, bypass=1, fire=4, prevented=2
  write_event "$root" hr-rule-a-synthetic-test deny   "2026-04-20T10:00:00Z"
  write_event "$root" hr-rule-a-synthetic-test deny   "2026-04-20T11:00:00Z"
  write_event "$root" hr-rule-a-synthetic-test deny   "2026-04-20T12:00:00Z"
  write_event "$root" hr-rule-a-synthetic-test bypass "2026-04-20T13:00:00Z"
  # Rule B: 2 applied → applied=2, fire=2, hit=0, prevented=0
  write_event "$root" hr-rule-b-synthetic-test applied "2026-04-20T14:00:00Z"
  write_event "$root" hr-rule-b-synthetic-test applied "2026-04-20T15:00:00Z"
  # Rule C: 1 warn → warn=1, fire=1
  write_event "$root" hr-rule-c-synthetic-test warn "2026-04-20T16:00:00Z"

  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1
  local metrics="$root/knowledge-base/project/rule-metrics.json"

  assert_eq "T1 Rule A hit_count"     "3" "$(rule_field "$metrics" hr-rule-a-synthetic-test hit_count)"
  assert_eq "T1 Rule A bypass_count"  "1" "$(rule_field "$metrics" hr-rule-a-synthetic-test bypass_count)"
  assert_eq "T1 Rule A applied_count" "0" "$(rule_field "$metrics" hr-rule-a-synthetic-test applied_count)"
  assert_eq "T1 Rule A warn_count"    "0" "$(rule_field "$metrics" hr-rule-a-synthetic-test warn_count)"
  assert_eq "T1 Rule A fire_count"    "4" "$(rule_field "$metrics" hr-rule-a-synthetic-test fire_count)"
  assert_eq "T1 Rule A prevented"     "2" "$(rule_field "$metrics" hr-rule-a-synthetic-test prevented_errors)"

  assert_eq "T1 Rule B hit_count"     "0" "$(rule_field "$metrics" hr-rule-b-synthetic-test hit_count)"
  assert_eq "T1 Rule B applied_count" "2" "$(rule_field "$metrics" hr-rule-b-synthetic-test applied_count)"
  assert_eq "T1 Rule B fire_count"    "2" "$(rule_field "$metrics" hr-rule-b-synthetic-test fire_count)"
  assert_eq "T1 Rule B prevented"     "0" "$(rule_field "$metrics" hr-rule-b-synthetic-test prevented_errors)"

  assert_eq "T1 Rule C warn_count"    "1" "$(rule_field "$metrics" hr-rule-c-synthetic-test warn_count)"
  assert_eq "T1 Rule C fire_count"    "1" "$(rule_field "$metrics" hr-rule-c-synthetic-test fire_count)"

  # Rule D: zero events → zero across the board
  assert_eq "T1 Rule D fire_count"    "0" "$(rule_field "$metrics" hr-rule-d-synthetic-test fire_count)"

  rm -rf "$root"
}

# --- T2: rules_unused_over_8w uses fire_count, not hit_count -------------
# Old predicate (hit_count==0) would flag rules B+C as unused even though they
# had applied/warn events. New predicate (fire_count==0) flags only A+D.
t2_unused_predicate_uses_fire_count() {
  local root; root=$(make_fixture_repo)
  # Ancient timestamps (>8 weeks back) so old-code predicate would otherwise
  # also trip on first_seen-null-or-old for Rule B/C; the ONLY gate that keeps
  # them out of rules_unused_over_8w is the new fire_count predicate.
  write_event "$root" hr-rule-b-synthetic-test applied "2025-12-01T10:00:00Z"
  write_event "$root" hr-rule-b-synthetic-test applied "2025-12-02T10:00:00Z"
  write_event "$root" hr-rule-c-synthetic-test warn    "2025-12-01T10:00:00Z"

  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1
  local metrics="$root/knowledge-base/project/rule-metrics.json"
  local unused; unused=$(jq -r '.summary.rules_unused_over_8w' < "$metrics")
  # Only A and D should be unused. Under old predicate, would be 4.
  assert_eq "T2 rules_unused_over_8w = 2 (A and D only)" "2" "$unused"
  rm -rf "$root"
}

# --- T3: orphan rule_id causes aggregator exit non-zero ------------------
t3_orphan_rule_id_exits_nonzero() {
  local root; root=$(make_fixture_repo)
  # rule_id NOT in synthetic AGENTS.md → orphan
  write_event "$root" hr-rule-orphan-not-in-synthetic deny "2026-04-20T10:00:00Z"

  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "PASS: T3 aggregator exits non-zero on orphan rule_id (exit=$exit_code)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T3 aggregator exited 0 despite orphan rule_id"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$root"
}

# --- T4: rule-prune.sh uses fire_count predicate -------------------------
# Rule B has hit_count=0 but fire_count>0 (applied events). Old predicate would
# list it as a prune candidate; new predicate must NOT.
t4_rule_prune_uses_fire_count() {
  local root; root=$(make_fixture_repo)
  # Ancient applied → fire_count>0, hit_count=0. Ancient first_seen defeats
  # the recency gate under BOTH old and new predicates, isolating the
  # hit_count → fire_count switch as the sole signal that keeps B out.
  write_event "$root" hr-rule-b-synthetic-test applied "2025-12-01T10:00:00Z"
  # Rule A: zero events → fire_count=0 → still a prune candidate.

  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1

  local candidates
  candidates=$(RULE_METRICS_ROOT="$root" bash "$PRUNE" --dry-run --weeks=0 2>/dev/null || true)

  local saw_a=0 saw_b=0
  echo "$candidates" | grep -q 'hr-rule-a-synthetic-test' && saw_a=1
  echo "$candidates" | grep -q 'hr-rule-b-synthetic-test' && saw_b=1

  if [[ "$saw_a" -eq 1 && "$saw_b" -eq 0 ]]; then
    echo "PASS: T4 rule-prune candidates use fire_count (A listed, B not)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T4 rule-prune candidates wrong (saw_a=$saw_a saw_b=$saw_b)"
    echo "  candidates: $candidates"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$root"
}

# --- T5: empty jsonl → exit 0, well-formed JSON --------------------------
t5_empty_jsonl_exits_zero() {
  local root; root=$(make_fixture_repo)
  # No events at all — aggregator should still emit a valid report.
  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1 || exit_code=$?
  assert_eq "T5 empty jsonl exit code"    "0" "$exit_code"
  local metrics="$root/knowledge-base/project/rule-metrics.json"
  assert_eq "T5 total_rules_tagged = 4"   "4" "$(jq -r '.summary.total_rules_tagged' < "$metrics")"
  assert_eq "T5 orphan_rule_ids empty"    "0" "$(jq -r '.summary.orphan_rule_ids | length' < "$metrics")"
  rm -rf "$root"
}

t1_mixed_events
t2_unused_predicate_uses_fire_count
t3_orphan_rule_id_exits_nonzero
t4_rule_prune_uses_fire_count
t5_empty_jsonl_exits_zero

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
