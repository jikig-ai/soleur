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
if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT does not exist — RED phase expected this." >&2
  exit 1
fi

t_empty
t_counts
t_idempotent
t_dry_run

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
