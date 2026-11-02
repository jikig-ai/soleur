#!/usr/bin/env bash
# test-suite-lanes.test.sh — census over the concurrency-lane table (#8231).
#
# Auto-registered via the scripts/lib/*.test.sh glob. Asserts:
#   1. Every label --enumerate-commands emits resolves to a token set — the
#      classifier never leaves a registration unclassifiable (an unclassifiable
#      suite would either guess a lane or, worse, run independent by default).
#   2. Every override-table entry names an EMITTED label — a stale override
#      silently protects nothing, which is the exact drift class the exclusion
#      shape exists to catch.
#   3. Every override carries a non-empty reason.
#   4. No label appears in the override table twice.
#   5. The two contract edges: lane_tokens_conflict says `*` conflicts with
#      everything (the drain barrier) and disjoint token sets do not conflict.

set -euo pipefail

cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

PASSES=0; FAILURES=0
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }

# shellcheck source=scripts/lib/test-suite-lanes.sh
source "scripts/lib/test-suite-lanes.sh"

# The label set, read through the SAME channel the scheduler's input flows
# through: --enumerate-commands SUITE_COMMAND records (label + argv).
ENUM_OUT="$(TEST_TIMING_LOG=/dev/null timeout 300 bash scripts/test-all.sh --enumerate-commands all 2>/dev/null || true)"
mapfile -t rows < <(grep '^SUITE_COMMAND\b' <<<"$ENUM_OUT" || true)

if (( ${#rows[@]} < 100 )); then
  fail "enumerate returned only ${#rows[@]} SUITE_COMMAND records — the census needs the real population"
else
  pass "census covers ${#rows[@]} emitted registrations"
fi

# 1. Every emitted label resolves — lane_tokens_for must always answer.
unresolvable=0
declare -A seen_label=()
for r in "${rows[@]}"; do
  # TAB-split, not whitespace: labels like `apps/web-platform [unit]` contain
  # spaces and are one field in the SUITE_COMMAND record.
  IFS=$'\t' read -ra fields <<<"$r"
  label="${fields[1]}"
  [[ -n "${seen_label[$label]:-}" ]] && continue
  seen_label[$label]=1
  toks="$(lane_tokens_for "$label" "${fields[@]:2}" 2>/dev/null)" || { unresolvable=$((unresolvable + 1)); continue; }
done
# Union in every `run_suite` literal in the runner source: conditionally
# emitted registrations (`apps/web-platform [unit]` relevance-declines to a
# skip_suite in this diff state; the infra runner's leg gating can do the
# same) are real labels the override table may legitimately name even when
# this run's enumerate output does not emit them.
while IFS= read -r lit; do
  seen_label["$lit"]=1
done < <(grep -oE 'run_suite "[^"]+"' scripts/test-all.sh | sed 's/run_suite "//; s/"$//')
if (( unresolvable == 0 )); then
  pass "every emitted label resolves to a token set (unclassifiable → *, never unresolvable)"
else
  fail "$unresolvable labels did not resolve"
fi

# 2. Overrides name emitted labels only.
stale=()
for l in "${LANE_OVERRIDE_LABELS[@]}"; do
  [[ -n "${seen_label[$l]:-}" ]] || stale+=("$l")
done
if (( ${#stale[@]} == 0 )); then
  pass "every override entry names a label --enumerate emits (${#LANE_OVERRIDE_LABELS[@]} entries)"
else
  fail "stale override labels: ${stale[*]}"
fi

# 3. Every override carries a non-empty reason.
empty_reason=0
for (( i = 0; i < ${#LANE_OVERRIDE_REASONS[@]}; i++ )); do
  [[ -n "${LANE_OVERRIDE_REASONS[i]:-}" ]] || empty_reason=$((empty_reason + 1))
done
(( ${#LANE_OVERRIDE_REASONS[@]} == ${#LANE_OVERRIDE_LABELS[@]} )) || empty_reason=999
if (( empty_reason == 0 )); then
  pass "every override carries a non-empty machine-checkable reason"
else
  fail "$empty_reason override entries have a missing/empty reason"
fi

# 4. No label in the override table twice.
declare -A dup_check=()
dups=0
for l in "${LANE_OVERRIDE_LABELS[@]}"; do
  [[ -n "${dup_check[$l]:-}" ]] && dups=$((dups + 1))
  dup_check[$l]=1
done
if (( dups == 0 )); then
  pass "no label declared twice in the override table"
else
  fail "$dups duplicate override labels"
fi

# 5. The conflict contract.
c_ok=1
lane_tokens_conflict "*" "" || c_ok=0
lane_tokens_conflict "*" "lock:test-all" || c_ok=0
lane_tokens_conflict "artifact:_site" "artifact:_site" || c_ok=0
lane_tokens_conflict "artifact:_site" "lock:test-all" && c_ok=0
lane_tokens_conflict "" "" && c_ok=0
if (( c_ok == 1 )); then
  pass "lane_tokens_conflict: * drains everything, shared tokens intersect, disjoint sets do not"
else
  fail "lane_tokens_conflict contract violated"
fi

echo ""
echo "=== test-suite-lanes: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
