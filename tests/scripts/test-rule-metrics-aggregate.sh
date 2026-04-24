#!/usr/bin/env bash
# Tests for scripts/rule-metrics-aggregate.sh.
# Uses an isolated fake-repo root so neither AGENTS.md nor the real jsonl
# is touched.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/rule-metrics-aggregate.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

# Builds a fake repo with a minimal AGENTS.md and writes given jsonl events.
_setup() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/.claude" "$root/knowledge-base/project"
  cat > "$root/AGENTS.md" <<'AGENTS'
# Agent Instructions

## Hard Rules

- Rule A text [id: hr-rule-a] [hook-enforced: foo.sh]. tail.
- Rule B text [id: hr-rule-b]. tail.

## Communication

- Rule C text [id: cm-rule-c]. tail.
AGENTS
  : > "$root/.claude/.rule-incidents.jsonl"
  echo "$root"
}

# T1: empty jsonl → all hit_count=0, rules listed, summary correct
t_empty() {
  local root; root=$(_setup)
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" >/dev/null 2>&1 || {
    _report "empty jsonl aggregation" fail "non-zero exit"
    rm -rf "$root"; return
  }
  local out="$root/knowledge-base/project/rule-metrics.json"
  [[ -s "$out" ]] || { _report "empty: output exists" fail; rm -rf "$root"; return; }
  jq empty "$out" >/dev/null 2>&1 || { _report "empty: valid JSON" fail; rm -rf "$root"; return; }
  local total unused
  total=$(jq '.rules | length' < "$out")
  unused=$(jq '.summary.rules_unused_over_8w // 0' < "$out")
  [[ "$total" == "3" ]] || { _report "empty: 3 rules parsed" fail "got $total"; rm -rf "$root"; return; }
  # all rules unused because jsonl is empty
  [[ "$unused" == "3" ]] || { _report "empty: all 3 unused" fail "got $unused"; rm -rf "$root"; return; }
  _report "empty jsonl aggregation" ok
  rm -rf "$root"
}

# T2: three denies for hr-rule-a + one bypass for hr-rule-b → counts correct
t_counts() {
  local root; root=$(_setup)
  for i in 1 2 3; do
    jq -nc --arg i "$i" '{timestamp:("2026-04-0" + $i + "T00:00:00Z"), rule_id:"hr-rule-a", event_type:"deny", rule_text_prefix:"Rule A text", command_snippet:""}' \
      >> "$root/.claude/.rule-incidents.jsonl"
  done
  jq -nc '{timestamp:"2026-04-04T00:00:00Z", rule_id:"hr-rule-b", event_type:"bypass", rule_text_prefix:"Rule B text", command_snippet:""}' \
    >> "$root/.claude/.rule-incidents.jsonl"

  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" >/dev/null 2>&1 || {
    _report "synthetic denies aggregation" fail "non-zero exit"
    rm -rf "$root"; return
  }
  local out="$root/knowledge-base/project/rule-metrics.json"
  local a_hits b_byp b_hits
  a_hits=$(jq '.rules[] | select(.id == "hr-rule-a") | .hit_count' < "$out")
  b_byp=$(jq  '.rules[] | select(.id == "hr-rule-b") | .bypass_count' < "$out")
  b_hits=$(jq '.rules[] | select(.id == "hr-rule-b") | .hit_count' < "$out")
  if [[ "$a_hits" == "3" && "$b_byp" == "1" && "$b_hits" == "0" ]]; then
    _report "synthetic denies aggregation" ok
  else
    _report "synthetic denies aggregation" fail "a_hits=$a_hits b_byp=$b_byp b_hits=$b_hits"
  fi
  rm -rf "$root"
}

# T3: re-run with no new data → no rewrite (idempotent, diff-noise)
t_idempotent() {
  local root; root=$(_setup)
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" >/dev/null 2>&1
  local out="$root/knowledge-base/project/rule-metrics.json"
  local first_mtime
  first_mtime=$(stat -c %Y "$out")
  sleep 1
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" >/dev/null 2>&1
  local second_mtime
  second_mtime=$(stat -c %Y "$out")
  if [[ "$first_mtime" == "$second_mtime" ]]; then
    _report "re-run is a no-op (diff-noise mitigation)" ok
  else
    _report "re-run is a no-op (diff-noise mitigation)" fail "mtime changed $first_mtime -> $second_mtime"
  fi
  rm -rf "$root"
}

# T4: --dry-run prints summary, never writes the file
t_dry_run() {
  local root; root=$(_setup)
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" --dry-run > "$root/dry.out" 2>&1 || {
    _report "--dry-run: exits clean" fail "$(cat "$root/dry.out")"
    rm -rf "$root"; return
  }
  [[ ! -f "$root/knowledge-base/project/rule-metrics.json" ]] || {
    _report "--dry-run: no file written" fail
    rm -rf "$root"; return
  }
  jq -e '.summary.rules_unused_over_8w != null' < "$root/dry.out" >/dev/null 2>&1 \
    && _report "--dry-run: emits summary JSON" ok \
    || _report "--dry-run: emits summary JSON" fail "$(cat "$root/dry.out")"
  rm -rf "$root"
}

# Entry
# T5: malformed jsonl lines → skipped with stderr warning, not a hard fail
t_malformed_tolerance() {
  local root; root=$(_setup)
  # Write one valid line, one malformed line, one more valid line
  jq -nc '{timestamp:"2026-04-10T00:00:00Z", rule_id:"hr-rule-a", event_type:"deny", rule_text_prefix:"", command_snippet:""}' \
    >> "$root/.claude/.rule-incidents.jsonl"
  echo "this is not JSON" >> "$root/.claude/.rule-incidents.jsonl"
  jq -nc '{timestamp:"2026-04-11T00:00:00Z", rule_id:"hr-rule-a", event_type:"deny", rule_text_prefix:"", command_snippet:""}' \
    >> "$root/.claude/.rule-incidents.jsonl"

  local err; err="$root/err.log"
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" 2> "$err" >/dev/null || {
    _report "malformed lines do not abort aggregation" fail "exit non-zero; stderr: $(cat "$err")"
    rm -rf "$root"; return
  }

  grep -q 'Dropped 1 malformed line' "$err" \
    || { _report "malformed: warning emitted" fail "$(cat "$err")"; rm -rf "$root"; return; }

  local a_hits
  a_hits=$(jq '.rules[] | select(.id == "hr-rule-a") | .hit_count' < "$root/knowledge-base/project/rule-metrics.json")
  if [[ "$a_hits" == "2" ]]; then
    _report "malformed: valid lines counted despite corruption" ok
  else
    _report "malformed: valid lines counted despite corruption" fail "got $a_hits"
  fi
  rm -rf "$root"
}

# T6: schema field present on output
t_schema_field() {
  local root; root=$(_setup)
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" >/dev/null 2>&1
  local out="$root/knowledge-base/project/rule-metrics.json"
  local schema; schema=$(jq -r '.schema' < "$out")
  [[ "$schema" == "1" ]] && _report "schema field present on output" ok \
    || _report "schema field present on output" fail "got schema=$schema"
  rm -rf "$root"
}

# T7: malformed first_seen → aggregator still exits 0, rows intact.
t_malformed_first_seen() {
  local root; root=$(_setup)
  # Emit an event for hr-rule-a with a broken timestamp string. The
  # aggregator's try/catch on fromdateiso8601 rescues the row. Per
  # rule-metrics emit_incident coverage (#2866), rules_unused_over_8w
  # switched from hit_count==0 to fire_count==0 — any event (deny,
  # bypass, applied, warn) excludes the rule from the unused bucket. So
  # hr-rule-a is NOT unused (one bypass → fire_count=1); hr-rule-b and
  # cm-rule-c remain unused (null first_seen + fire_count=0).
  printf '{"timestamp":"not-a-date","rule_id":"hr-rule-a","event_type":"bypass","rule_text_prefix":"","command_snippet":""}\n' \
    >> "$root/.claude/.rule-incidents.jsonl"
  local err="$root/err.log"
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" 2> "$err" >/dev/null \
    || { _report "malformed first_seen tolerated" fail "non-zero exit; stderr: $(cat "$err")"; rm -rf "$root"; return; }
  local unused
  unused=$(jq '.summary.rules_unused_over_8w' < "$root/knowledge-base/project/rule-metrics.json")
  [[ "$unused" == "2" ]] && _report "malformed first_seen → rule in unused bucket" ok \
    || _report "malformed first_seen → rule in unused bucket" fail "got $unused"
  rm -rf "$root"
}

# T8: orphan rule_id in jsonl surfaces in summary.orphan_rule_ids AND
# causes the aggregator to exit 5 (post-#2866 invariant: drift must be a
# loud CI failure, not silent normalization). The output file is still
# written before exit so operators have forensic context.
t_orphan_ids_surfaced() {
  local root; root=$(_setup)
  jq -nc '{timestamp:"2026-04-10T00:00:00Z", rule_id:"ghost-id-not-in-agents-md", event_type:"deny", rule_text_prefix:"", command_snippet:""}' \
    >> "$root/.claude/.rule-incidents.jsonl"
  local exit_code=0
  INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT" >/dev/null 2>&1 || exit_code=$?
  local orphan
  orphan=$(jq -r '.summary.orphan_rule_ids | join(",")' < "$root/knowledge-base/project/rule-metrics.json")
  if [[ "$orphan" == "ghost-id-not-in-agents-md" && "$exit_code" == "5" ]]; then
    _report "orphan rule_ids surfaced in summary + exit 5" ok
  else
    _report "orphan rule_ids surfaced in summary + exit 5" fail "orphan='$orphan' exit=$exit_code"
  fi
  rm -rf "$root"
}

# T9: rotate-twice-same-month → second archive uniquified (no clobber).
t_rotate_twice_same_month() {
  local root; root=$(_setup)
  # First run: one event, rotate.
  jq -nc '{timestamp:"2026-04-10T00:00:00Z", rule_id:"hr-rule-a", event_type:"deny", rule_text_prefix:"", command_snippet:""}' \
    >> "$root/.claude/.rule-incidents.jsonl"
  INCIDENTS_REPO_ROOT="$root" AGGREGATOR_ROTATE=1 bash "$SCRIPT" >/dev/null 2>&1
  # Second run: different event, rotate again within the same month.
  # RULE_METRICS_ROTATE_SUFFIX pins the uniquify suffix so this test does
  # not depend on wall-clock granularity (second- or nano-level races).
  jq -nc '{timestamp:"2026-04-11T00:00:00Z", rule_id:"hr-rule-b", event_type:"deny", rule_text_prefix:"", command_snippet:""}' \
    >> "$root/.claude/.rule-incidents.jsonl"
  INCIDENTS_REPO_ROOT="$root" AGGREGATOR_ROTATE=1 RULE_METRICS_ROTATE_SUFFIX=testrun \
    bash "$SCRIPT" >/dev/null 2>&1
  # Expect the monthly archive (first run) AND the suffixed archive
  # (second run with RULE_METRICS_ROTATE_SUFFIX=testrun).
  local monthly suffixed
  monthly=$(find "$root/.claude" -maxdepth 1 -name '.rule-incidents-????-??.jsonl.gz' 2>/dev/null | wc -l | tr -d ' ')
  suffixed=$(find "$root/.claude" -maxdepth 1 -name '.rule-incidents-????-??-testrun.jsonl.gz' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$monthly" -ge 1 && "$suffixed" -ge 1 ]]; then
    _report "rotate-twice-same-month: archives do not clobber" ok
  else
    _report "rotate-twice-same-month: archives do not clobber" fail "monthly=$monthly suffixed=$suffixed; files: $(ls "$root/.claude" 2>/dev/null)"
  fi
  rm -rf "$root"
}

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT does not exist — RED phase expected this." >&2
  exit 1
fi

t_empty
t_counts
t_idempotent
t_dry_run
t_malformed_tolerance
t_schema_field
t_malformed_first_seen
t_orphan_ids_surfaced
t_rotate_twice_same_month

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
