#!/usr/bin/env bash

# Tests for plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh
# Run: bash plugins/soleur/test/roadmap-reconcile.test.sh
#
# This is the READ-ONLY reconcile module behind `product-roadmap validate` and
# `next` (feat-roadmap-program-layer, report-only design). The module parses the
# roadmap's `## Current State` table, reconciles per-phase counts against live
# GitHub milestone state, and picks the next actionable item — and it MUST NEVER
# write to any file (the existing cron-roadmap-review.ts stays the sole writer).
#
# Hermetic: the functions under test read roadmap text + milestone/issue JSON
# from stdin/args, so no real `git`/`gh` invocation. Mirrors the
# infra-validation-detect.test.sh source-and-call convention.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MODULE="$REPO_ROOT/plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_eq() { # expected actual msg
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (expected [$1] got [$2])"; fi
}
assert_contains() { # haystack needle msg
  if printf '%s' "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3 (missing [$2] in output)"; fi
}
assert_not_contains() { # haystack needle msg
  if printf '%s' "$1" | grep -qF -- "$2"; then fail "$3 (unexpected [$2])"; else pass "$3"; fi
}

# shellcheck source=/dev/null
source "$MODULE"

# --- Fixtures (synthesized; cq-test-fixtures-synthesized-only) ---
ROADMAP_FIXTURE='## Current State (2026-06-30)

| Dimension | Status |
|-----------|--------|
| Financial posture | break-even prose, no counts here |
| Phase 1 (Close the Loop) | Complete. Milestone closed. 0 open, 15 closed. |
| Phase 4 (Validate + Scale) | In progress. 30 open, 120 closed (milestone). prose. |
| Phase 5 (Desktop Native App) | Defined. 6 open, 0 closed. Trigger-gated. |
| Beta users | 0 |
'

echo "=== roadmap-reconcile tests ==="

# --- TS1: extract_phase_counts parses only Phase rows, ignores prose rows ---
echo "TS1: extract_phase_counts"
OUT="$(printf '%s' "$ROADMAP_FIXTURE" | extract_phase_counts)"
assert_contains "$OUT" "1|0|15" "Phase 1 -> 1|0|15"
assert_contains "$OUT" "4|30|120" "Phase 4 -> 4|30|120"
assert_contains "$OUT" "5|6|0" "Phase 5 -> 5|6|0"
assert_not_contains "$OUT" "Financial" "Financial posture row ignored (no counts)"
assert_not_contains "$OUT" "Beta" "Beta users row ignored (no open/closed)"

# --- TS2: reconcile_counts emits STALE_STATUS on count drift ---
echo "TS2: STALE_STATUS on drift"
# Milestone Phase 4 actually has 32 open / 127 closed -> roadmap says 30/120 -> drift.
MILESTONES='[{"title":"Phase 1: Close the Loop","open_issues":0,"closed_issues":15},
             {"title":"Phase 4: Validate + Scale","open_issues":32,"closed_issues":127},
             {"title":"Phase 5: Desktop Native App","open_issues":6,"closed_issues":0}]'
OUT="$(reconcile_counts <(printf '%s' "$ROADMAP_FIXTURE") <(printf '%s' "$MILESTONES"))"
assert_contains "$OUT" "STALE_STATUS" "drift -> STALE_STATUS verdict"
assert_contains "$OUT" "4" "STALE_STATUS names phase 4"
assert_not_contains "$OUT" "STALE_STATUS|1" "phase 1 clean -> no STALE_STATUS for it"

# --- TS3: EMPTY_MILESTONE when an open milestone has zero issues ---
echo "TS3: EMPTY_MILESTONE"
MILESTONES_EMPTY='[{"title":"Phase 1: Close the Loop","open_issues":0,"closed_issues":15},
                   {"title":"Phase 4: Validate + Scale","open_issues":30,"closed_issues":120},
                   {"title":"Phase 5: Desktop Native App","open_issues":0,"closed_issues":0}]'
OUT="$(reconcile_counts <(printf '%s' "$ROADMAP_FIXTURE") <(printf '%s' "$MILESTONES_EMPTY"))"
assert_contains "$OUT" "EMPTY_MILESTONE" "0/0 milestone -> EMPTY_MILESTONE"

# --- TS4: MISSING_ISSUE when a roadmap phase has no resolvable milestone ---
echo "TS4: MISSING milestone for a roadmap phase"
MILESTONES_NO4='[{"title":"Phase 1: Close the Loop","open_issues":0,"closed_issues":15},
                 {"title":"Phase 5: Desktop Native App","open_issues":6,"closed_issues":0}]'
OUT="$(reconcile_counts <(printf '%s' "$ROADMAP_FIXTURE") <(printf '%s' "$MILESTONES_NO4"))"
assert_contains "$OUT" "MISSING_ISSUE" "phase 4 row, no milestone -> MISSING_ISSUE"

# --- TS5: clean state -> no verdicts (exit-style empty) ---
echo "TS5: clean state"
MILESTONES_CLEAN='[{"title":"Phase 1: Close the Loop","open_issues":0,"closed_issues":15},
                   {"title":"Phase 4: Validate + Scale","open_issues":30,"closed_issues":120},
                   {"title":"Phase 5: Desktop Native App","open_issues":6,"closed_issues":0}]'
OUT="$(reconcile_counts <(printf '%s' "$ROADMAP_FIXTURE") <(printf '%s' "$MILESTONES_CLEAN"))"
assert_not_contains "$OUT" "STALE_STATUS" "matched counts -> no STALE_STATUS"

# --- TS6: pick_next_action classifies codeable vs operator by label ---
echo "TS6: pick_next_action classification + tie-break + empty"
# Two open issues; lower number is non-codeable (recruit), higher is codeable.
ISSUES='[{"number":1439,"title":"recruit founders","labels":[{"name":"type/research"}]},
         {"number":1442,"title":"usage tracking","labels":[{"name":"domain/engineering"}]}]'
OUT="$(pick_next_action <(printf '%s' "$ISSUES"))"
# Deterministic tie-break = lowest issue number first -> 1439 (operator action).
assert_contains "$OUT" "OPERATOR" "lowest-# non-codeable -> OPERATOR action"
assert_contains "$OUT" "1439" "names issue 1439"

echo "TS6b: codeable-only set -> CODEABLE"
ISSUES_CODE='[{"number":1442,"title":"usage tracking","labels":[{"name":"domain/engineering"}]}]'
OUT="$(pick_next_action <(printf '%s' "$ISSUES_CODE"))"
assert_contains "$OUT" "CODEABLE" "engineering label -> CODEABLE"
assert_contains "$OUT" "1442" "names issue 1442"

echo "TS6c: empty set -> explicit NONE (never silent)"
OUT="$(pick_next_action <(printf '%s' '[]'))"
assert_contains "$OUT" "NONE" "empty -> explicit NONE"

# --- TS7: ZERO file writes (brand-survival invariant) ---
echo "TS7: module makes zero file writes"
TMP_GIT="$(mktemp -d)"
cp "$MODULE" "$TMP_GIT/mod.sh"
( cd "$TMP_GIT" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
# Run every public function against the sandbox CWD; assert the tree stays clean.
( cd "$TMP_GIT"
  # shellcheck source=/dev/null
  source "$MODULE"
  printf '%s' "$ROADMAP_FIXTURE" | extract_phase_counts >/dev/null
  reconcile_counts <(printf '%s' "$ROADMAP_FIXTURE") <(printf '%s' "$MILESTONES") >/dev/null
  pick_next_action <(printf '%s' "$ISSUES") >/dev/null )
DIRTY="$(cd "$TMP_GIT" && git status --porcelain)"
assert_eq "" "$DIRTY" "sandbox tree clean after running all functions (zero writes)"
rm -rf "$TMP_GIT"

echo ""
echo "=== roadmap-reconcile: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
