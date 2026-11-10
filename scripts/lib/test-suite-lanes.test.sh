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
#   6. The replay arms' explicit override: empty tokens, equal to the derived set
#      minus lock:test-all (#12013).
#   7. Start-first order (#12013): the replay arms start with the pool, in the
#      runner's real registration stream (see the section for the contract).

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
declare -A tok_of=()   # label -> token set, kept for section 7 (no second fork per label)
for r in "${rows[@]}"; do
  # TAB-split, not whitespace: labels like `apps/web-platform [unit]` contain
  # spaces and are one field in the SUITE_COMMAND record.
  IFS=$'\t' read -ra fields <<<"$r"
  label="${fields[1]}"
  [[ -n "${seen_label[$label]:-}" ]] && continue
  seen_label[$label]=1
  toks="$(lane_tokens_for "$label" "${fields[@]:2}" 2>/dev/null)" || { unresolvable=$((unresolvable + 1)); continue; }
  tok_of[$label]="$toks"
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

# 5b. The star predicate (#12231): one tokenizer for the park and the conflict rule. `*` as any whitespace-separated word is a star
#     (space, tab, newline-first-line like lane_tokens_conflict's read -ra); a token merely containing `*`, or an empty set, is not.
h_ok=1
star_row() {  # <expect star: 1|0> <set> — has_star must match AND lane_tokens_conflict must agree against an unrelated set
  local want="$1" set="$2" got=0 conf=0
  lane_tokens_has_star "$set" && got=1
  lane_tokens_conflict "$set" "zzz:unrelated" && conf=1
  lane_tokens_conflict "zzz:unrelated" "$set" && conf=$(( conf + 1 ))
  if (( got != want )) || (( conf != want * 2 )); then
    printf '  5b row wrong: set=%q want-star=%s has_star=%s conflict-hits=%s (want %s)\n' "$set" "$want" "$got" "$conf" "$(( want * 2 ))"
    h_ok=0
  fi
}
star_row 1 "*"
star_row 1 "artifact:x *"
star_row 1 "* artifact:x"
star_row 1 $'artifact:x\t*'
star_row 1 $'*\nartifact:x'          # a star on the first line is a star
star_row 0 ""
star_row 0 "artifact:x lock:y"
star_row 0 "a*b"
star_row 0 "artifact:*"
star_row 0 "*x"                       # a token merely STARTING with * is not the star token
star_row 0 "**"
star_row 0 $'artifact:x\n*'          # read -ra reads the first line only: a later-line star is invisible to BOTH functions
if (( h_ok == 1 )); then
  pass "lane_tokens_has_star: a * word in any whitespace position (first line) is a star; a token containing or starting with * and an empty set are not; it agrees with lane_tokens_conflict row by row"
else
  fail "lane_tokens_has_star contract violated"
fi

# Sections 6 and 7 (the replay arms' empty-override reservation and their start-first order, #12013) retired
# with the S4 evidence layer on 2026-11-09: the arm suite, its lane_declare overrides and its registrations are
# all gone, so the checks had nothing left to pin. The lane table's remaining override set is verified by
# sections 1-5 above (resolve, label-membership, reason, uniqueness, conflict contract).

# Dispatch floor, reported directly (never through fail()): deleting a block of assertions lowers PASSES.
# 7 assertions from sections 0-5 (census + five lane contracts). The replay-arm sections retired with S4.
(( PASSES < 7 )) && { printf '[FATAL] only %s assertions passed, expected at least 7\n' "$PASSES"; exit 1; }
echo ""
echo "=== test-suite-lanes: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
