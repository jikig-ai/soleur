#!/usr/bin/env bash
# Guard 3 (#8377, ADR-235) — the generated knowledge-base caches stay UNTRACKED.
#
# ── WHY A GUARD AND NOT JUST A .gitignore LINE ─────────────────────────────────────────────
# .gitignore refuses an accidental `git add`, and that covers the common case. It does NOT
# cover `git add -f`, and it does not cover a file that is ALREADY tracked: ignore rules are
# silently inert for tracked paths, so re-adding one of these re-opens the entire defect class
# ADR-235 closed — every advance of main conflicting with every open PR — with no error
# anywhere. This suite is the thing that notices.
#
# The oracle is `git ls-files` (what is tracked) plus `git check-ignore` (what the rules match),
# because the two can disagree in exactly the direction that hurts: a path can be matched by
# .gitignore and tracked at the same time, which reads as protected and is not.
#
# ── WHAT IS DELIBERATELY *NOT* HERE ────────────────────────────────────────────────────────
# knowledge-base/engineering/architecture/diagrams/model.likec4.json is a PRODUCT, not a cache:
# the web-platform C4 viewer (app/api/kb/c4/project/route.ts) fetches the committed blob from
# GitHub on the request path with no build step, so it must exist as a committed blob. It
# stays committed and is resolved on conflict by resolve-regenerable-conflicts.sh. Adding it to
# the list below would be wrong, and the sixth-path row is what makes that a deliberate edit.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

passes=0
fails=0
CASES_RUN=0
FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# INSTRUMENT SELF-TEST — drive both helpers and require all three observables to move.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2
  exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

# THE LIST. Its CARDINALITY is asserted below, which is what makes row 3 (add a sixth path
# without a .gitignore line) and row 4 (empty the list) detectable. A count-only ratchet cannot
# see a RENAME, so the members are named here and compared as a SET, not tallied.
CACHE_PATHS=(
  "knowledge-base/INDEX.md"
  "knowledge-base/kb-tags.txt"
  "knowledge-base/kb-categories.txt"
  "knowledge-base/project/rule-metrics.json"
  "knowledge-base/.kb-index.stamp"
)
EXPECTED_N=5

echo "=== kb caches stay untracked (Guard 3) ==="

# Row 4's own dispatch: a suite whose list has been emptied must not report a clean sweep.
CASES_RUN=$((CASES_RUN + 1))
if [[ "${#CACHE_PATHS[@]}" -eq "$EXPECTED_N" ]]; then
  pass "the guarded list holds $EXPECTED_N paths"
else
  fail "the guarded list holds ${#CACHE_PATHS[@]} paths, expected $EXPECTED_N — a member was added or dropped without updating the count"
fi

# ── TRACKED? `git ls-files` prints the path when tracked and nothing when not. ──────────────
for p in "${CACHE_PATHS[@]}"; do
  CASES_RUN=$((CASES_RUN + 1))
  tracked="$(git -C "$REPO_ROOT" ls-files -- "$p")"
  if [[ -z "$tracked" ]]; then
    pass "untracked: $p"
  else
    fail "TRACKED: $p — a generated cache is committed again; every main advance will conflict with every open PR (ADR-235)"
  fi
done

# ── IGNORED? An untracked-but-unignored path is a `git add -A` away from being tracked. ─────
for p in "${CACHE_PATHS[@]}"; do
  CASES_RUN=$((CASES_RUN + 1))
  # `git check-ignore -q` exits 0 when the path IS ignored, 1 when it is not, >1 on error —
  # branch on the code rather than on truthiness so an error is not read as "not ignored".
  rc=0
  git -C "$REPO_ROOT" check-ignore -q -- "$p" || rc=$?
  case "$rc" in
    0) pass "ignored: $p" ;;
    1) fail "NOT IGNORED: $p — nothing stops a later add-all from tracking it" ;;
    *) fail "check-ignore errored (rc=$rc) on $p — the oracle could not answer, which is not a pass" ;;
  esac
done

# ── The product artifact must NOT be in the list, and must still be tracked. ────────────────
# Guards the boundary in the other direction: untracking model.likec4.json would break the
# web-platform C4 viewer for every synced repo without a compiler.
MODEL="knowledge-base/engineering/architecture/diagrams/model.likec4.json"
CASES_RUN=$((CASES_RUN + 1))
in_list=0
for p in "${CACHE_PATHS[@]}"; do [[ "$p" == "$MODEL" ]] && in_list=1; done
if [[ "$in_list" -eq 0 ]]; then
  pass "the committed C4 product is not in the cache list"
else
  fail "$MODEL is in the cache list — it is a PRODUCT (read by the web-platform viewer without a compiler), not a cache"
fi
CASES_RUN=$((CASES_RUN + 1))
if [[ -n "$(git -C "$REPO_ROOT" ls-files -- "$MODEL")" ]]; then
  pass "the committed C4 product is still tracked"
else
  fail "$MODEL is no longer tracked — the C4 viewer reads it from synced repos that cannot regenerate it"
fi

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

# Reported with printf + exit directly, never through the helpers they backstop.
_min_cases=13
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' "$((passes + fails))" "$CASES_RUN" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
echo "kb-caches-untracked: all $passes assertions passed"
