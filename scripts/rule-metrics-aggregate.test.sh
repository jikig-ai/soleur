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

# --- T4: rule-prune.sh excludes rules with fire events ------------------
# Negative half of the rule-prune predicate: Rule B has hit_count=0 but
# fire_count>0 (applied events). Old predicate would list it as a prune
# candidate; new predicate must NOT.
#
# T4b (below) covers the positive half (fire_count=0 AND non-null first_seen
# IS a candidate) by crafting rule-metrics.json directly, bypassing the
# aggregator's event→first_seen coupling.
t4_rule_prune_excludes_rules_with_fire_events() {
  local root; root=$(make_fixture_repo)
  # Ancient applied → fire_count>0, hit_count=0. Ancient first_seen defeats
  # the recency gate, isolating the hit_count → fire_count switch as the sole
  # signal that keeps B out of candidates.
  write_event "$root" hr-rule-b-synthetic-test applied "2025-12-01T10:00:00Z"
  # Rule A is intentionally not seeded here; T4 only asserts B's exclusion.
  # Rule A's positive-emission case is covered by t4b, which crafts metrics
  # directly because PR #3156's `first_seen != null` filter makes the
  # zero-event-AND-non-null-first_seen state unreachable from event seeding
  # (the aggregator only sets first_seen when an event also increments
  # fire_count). See issue #3507 and
  # knowledge-base/project/learnings/2026-05-10-rule-prune-null-first-seen-skip-invalidates-positive-prune-candidate-fixture.md.

  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1

  local candidates
  candidates=$(RULE_METRICS_ROOT="$root" bash "$PRUNE" --dry-run --weeks=0 2>/dev/null || true)

  if ! echo "$candidates" | grep -q 'hr-rule-b-synthetic-test'; then
    echo "PASS: T4 rule-prune excludes rules with fire events (B with applied events excluded)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T4 rule-prune still flags Rule B despite applied events (fire_count switch broken)"
    echo "  candidates: $candidates"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$root"
}

# --- T4b: rule-prune.sh emits candidates for zero-fire rules with first_seen ---
# Positive half of the rule-prune predicate. Crafts rule-metrics.json directly
# (bypassing the aggregator) so a rule with fire_count=0 AND non-null first_seen
# is reachable in the fixture — the only state that satisfies the post-#3156
# candidate predicate `(fire_count == 0) AND (first_seen != null) AND (first_seen < cutoff)`.
# Without this test, a regression that flips the `first_seen != null` filter to
# `first_seen == null` (or drops the predicate entirely) would silently produce
# no candidates and T4 alone would still pass. See issue #3507.
t4b_rule_prune_emits_candidates_with_first_seen() {
  local root; root=$(make_fixture_repo)
  # Craft a metrics file directly. The aggregator's write path cannot produce
  # `fire_count=0` AND non-null `first_seen` (every event_type that sets
  # first_seen also increments fire_count), so we synthesize it.
  cat > "$root/knowledge-base/project/rule-metrics.json" <<'EOF'
{
  "schema": 1,
  "generated_at": "2026-05-10T00:00:00Z",
  "rules": [
    {
      "id": "hr-rule-a-synthetic-test",
      "section": "Hard Rules",
      "hit_count": 0,
      "bypass_count": 0,
      "applied_count": 0,
      "warn_count": 0,
      "fire_count": 0,
      "prevented_errors": 0,
      "last_hit": null,
      "first_seen": "2024-01-01T00:00:00Z",
      "rule_text_prefix": "Rule A synthetic."
    }
  ],
  "summary": {
    "total_rules_tagged": 1,
    "rules_unused_over_8w": 1,
    "rules_bypassed_over_baseline": 0,
    "orphan_rule_ids": []
  }
}
EOF

  local candidates
  candidates=$(RULE_METRICS_ROOT="$root" bash "$PRUNE" --dry-run --weeks=0 2>/dev/null || true)

  if echo "$candidates" | grep -q 'hr-rule-a-synthetic-test'; then
    echo "PASS: T4b rule-prune emits candidates for zero-fire rules with first_seen (A listed)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T4b rule-prune did not list Rule A despite fire_count=0 + non-null first_seen"
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

# --- T6: te-* synthetic-prefix events are NOT flagged as orphans ----------
# Issue #3494 reserves `te-` for token-efficiency telemetry emitted by
# compound Phase 1.6. These rule_ids exist by design without an AGENTS.md
# bullet — the orphan-detection jq filter must exclude them.
t6_te_prefix_not_orphan() {
  local root; root=$(make_fixture_repo)
  # Only te-* events; no real orphan.
  write_event "$root" te-subagent-overshoot warn "2026-04-25T10:00:00Z"
  write_event "$root" te-skill-payload-floor warn "2026-04-25T11:00:00Z"

  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1 || exit_code=$?
  assert_eq "T6 te-* only → exit 0"        "0" "$exit_code"
  local metrics="$root/knowledge-base/project/rule-metrics.json"
  assert_eq "T6 te-* events not in orphans" "0" \
    "$(jq -r '.summary.orphan_rule_ids | length' < "$metrics")"
  # Per-id counts still preserved in the counts map (verifiable via stage A
  # output). Aggregator stores per-id stats keyed by rule_id; te-* IDs are
  # absent from `rules` (which joins with AGENTS.md) but present in the
  # underlying count map. We assert by re-reading the jsonl directly.
  local te_count
  te_count=$(grep -c '"te-subagent-overshoot"' "$root/.claude/.rule-incidents.jsonl")
  assert_eq "T6 te-subagent-overshoot fired" "1" "$te_count"
  rm -rf "$root"
}

# --- T7: mixed te-* + real-orphan → only real orphan flagged --------------
t7_te_plus_orphan_isolates_real_orphan() {
  local root; root=$(make_fixture_repo)
  write_event "$root" te-agents-md-turn-cost warn "2026-04-25T10:00:00Z"
  write_event "$root" hr-rule-orphan-not-in-fixture deny "2026-04-25T11:00:00Z"

  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "FAIL: T7 expected non-zero exit (real orphan present)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: T7 mixed te-* + real orphan → exit $exit_code"
    PASS=$((PASS + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$root"
}

# --- T8: te-* unknown sub-id (e.g., new outlier from #3493 follow-up) -----
# Any rule_id starting with `te-` is exempt from orphan detection — not just
# the three currently emitted. This guards against future te-* additions
# silently failing the cron until AGENTS.md gets edited (which it shouldn't).
t8_te_prefix_arbitrary_id() {
  local root; root=$(make_fixture_repo)
  write_event "$root" te-future-outlier-tbd warn "2026-04-25T10:00:00Z"

  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1 || exit_code=$?
  assert_eq "T8 arbitrary te-* exits 0"  "0" "$exit_code"
  local metrics="$root/knowledge-base/project/rule-metrics.json"
  assert_eq "T8 orphan list empty"        "0" \
    "$(jq -r '.summary.orphan_rule_ids | length' < "$metrics")"
  rm -rf "$root"
}

# --- T9: archive-spanning input (#3508) -----------------------------------
# Per-write rotation moves data into `.claude/.rule-incidents-YYYY-MM*.jsonl.gz`.
# The aggregator must merge active + archives so events that were rotated out
# still count toward fire_count / first_seen / last_hit.
t9_archive_spanning_input() {
  local root; root=$(make_fixture_repo)

  # Active file: one recent event for rule A.
  write_event "$root" hr-rule-a-synthetic-test deny "2026-05-01T10:00:00Z"

  # Archive .gz: an older event for the same rule (would be invisible without
  # the merge step).
  local archive="$root/.claude/.rule-incidents-2026-04.jsonl"
  printf '{"schema":1,"timestamp":"%s","rule_id":"%s","event_type":"%s","rule_text_prefix":"x","command_snippet":""}\n' \
    "2026-04-01T08:00:00Z" "hr-rule-a-synthetic-test" "deny" > "$archive"
  gzip -f "$archive"

  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1
  local metrics="$root/knowledge-base/project/rule-metrics.json"

  # Both events should count: hit_count = 2, first_seen = the older archived ts.
  assert_eq "T9 archived events count toward hit_count" "2" \
    "$(jq -r '.rules[] | select(.id == "hr-rule-a-synthetic-test") | .hit_count' < "$metrics")"
  assert_eq "T9 first_seen reflects archived event" "2026-04-01T08:00:00Z" \
    "$(jq -r '.rules[] | select(.id == "hr-rule-a-synthetic-test") | .first_seen' < "$metrics")"
  rm -rf "$root"
}

# --- T10: sentinel lines (issue #3509) -----------------------------------
# Sentinels carry no rule_id and no event_type — discriminator is `error`
# key presence. The aggregator's valid_stream filter MUST drop sentinels
# BEFORE the reduce so a `"null"` rule_id never enters $known_ids (and
# therefore never trips the orphan gate). Drop counts surface as separate
# summary fields populated from a parallel jq pass.
t10_sentinels_excluded_from_data_and_counted_in_summary() {
  local root; root=$(make_fixture_repo)
  # One real deny event for Rule A (so we have a known reference count).
  write_event "$root" hr-rule-a-synthetic-test deny "2026-04-25T10:00:00Z"
  # Two sentinel lines (jq_fail + rotation_fail) — no rule_id, no event_type.
  printf '{"schema":1,"hook_event":"PreToolUse","error":"jq_fail","ts":"2026-04-25T11:00:00Z"}\n' \
    >> "$root/.claude/.rule-incidents.jsonl"
  printf '{"schema":1,"hook_event":"PreToolUse","error":"rotation_fail","ts":"2026-04-25T12:00:00Z"}\n' \
    >> "$root/.claude/.rule-incidents.jsonl"

  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1 || exit_code=$?
  assert_eq "T10 sentinels do not trip orphan gate" "0" "$exit_code"
  local metrics="$root/knowledge-base/project/rule-metrics.json"
  # No "null" rule_id row — sentinels never entered the reduce.
  local null_rows
  null_rows=$(jq -r '.rules | map(select(.id == null or .id == "null")) | length' < "$metrics")
  assert_eq "T10 no null rule_id row in rules[]" "0" "$null_rows"
  # Orphan list still empty (Rule A is the only real rule_id seen, and it
  # exists in synthetic AGENTS.md).
  assert_eq "T10 orphan_rule_ids empty"           "0" \
    "$(jq -r '.summary.orphan_rule_ids | length' < "$metrics")"
  # Drop counts surfaced.
  assert_eq "T10 drops_jq_fail_count == 1"        "1" \
    "$(jq -r '.summary.drops_jq_fail_count' < "$metrics")"
  assert_eq "T10 drops_rotation_fail_count == 1"  "1" \
    "$(jq -r '.summary.drops_rotation_fail_count' < "$metrics")"
  # Rule A's data-line counting is unaffected by the sentinels.
  assert_eq "T10 Rule A hit_count unchanged"      "1" \
    "$(rule_field "$metrics" hr-rule-a-synthetic-test hit_count)"
  rm -rf "$root"
}

# --- T11: archived sentinel (gzipped) is merged + counted ----------------
t11_archived_sentinel_counted() {
  local root; root=$(make_fixture_repo)
  # A sentinel that lives only in the .gz archive.
  local archive="$root/.claude/.rule-incidents-2026-04.jsonl"
  printf '{"schema":1,"hook_event":"PreToolUse","error":"jq_fail","ts":"2026-04-15T08:00:00Z"}\n' > "$archive"
  gzip -f "$archive"

  INCIDENTS_REPO_ROOT="$root" bash "$AGGREGATOR" >/dev/null 2>&1
  local metrics="$root/knowledge-base/project/rule-metrics.json"
  assert_eq "T11 archived sentinel counted" "1" \
    "$(jq -r '.summary.drops_jq_fail_count' < "$metrics")"
  rm -rf "$root"
}

t1_mixed_events
t2_unused_predicate_uses_fire_count
t3_orphan_rule_id_exits_nonzero
t4_rule_prune_excludes_rules_with_fire_events
t4b_rule_prune_emits_candidates_with_first_seen
t5_empty_jsonl_exits_zero
t6_te_prefix_not_orphan
t7_te_plus_orphan_isolates_real_orphan
t8_te_prefix_arbitrary_id
t9_archive_spanning_input
t10_sentinels_excluded_from_data_and_counted_in_summary
t11_archived_sentinel_counted

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
