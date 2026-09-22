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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guard 3 (#7833) tripwire adoption (#7849 exit condition). This suite already runs
# `-e`, which matches test-helpers.sh -- no `+e` here, deliberately. The source sits
# ABOVE this file's assert_eq/assert_contains redefinitions so those keep winning.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh" || { echo "FATAL: could not source $SCRIPT_DIR/test-helpers.sh" >&2; exit 2; }

set -euo pipefail

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

echo "TS6d: non-engineering domain label overrides a codeable type label -> OPERATOR"
# Real dogfood case: #2603 "Publish case study" is type/feature BUT domain/marketing.
# A domain/* leader label (marketing/legal/ops/sales/finance/support/product) means the
# work is operator-driven regardless of the type/* label — never tell the founder to build it.
ISSUES_MKT='[{"number":2603,"title":"Publish first external case study","labels":[{"name":"type/feature"},{"name":"domain/marketing"}]}]'
OUT="$(pick_next_action <(printf '%s' "$ISSUES_MKT"))"
assert_contains "$OUT" "OPERATOR" "type/feature + domain/marketing -> OPERATOR (override)"
assert_not_contains "$OUT" "CODEABLE" "marketing task not classified CODEABLE"

echo "TS6e: engineering domain + type label still -> CODEABLE"
ISSUES_ENG='[{"number":1500,"title":"refactor resolver","labels":[{"name":"type/feature"},{"name":"domain/engineering"}]}]'
OUT="$(pick_next_action <(printf '%s' "$ISSUES_ENG"))"
assert_contains "$OUT" "CODEABLE" "type/feature + domain/engineering -> CODEABLE"

# --- Frontier + phase selection (#8292) ---
# pick_phase picks the live phase from milestones; filter_frontier keeps open issues
# with no open blocker and no assignee. Fixtures follow the shape `gh issue list --json
# number,title,labels,assignees,blockedBy` returns, numbers changed, listed out of order.
declare -F pick_phase >/dev/null || fail "pick_phase not defined"
declare -F filter_frontier >/dev/null || fail "filter_frontier not defined"

ms_proj() { # $1 = raw milestones JSON -> the projection main() asks gh for
  jq -c '[ .[] | {title, state, open_issues, closed_issues} ]' <<< "$1"
}
RAW_MS='[{"number":1,"title":"Phase 1: Close the Loop","state":"closed","open_issues":0,"closed_issues":15},
         {"number":9,"title":"Post-MVP / Later","state":"open","open_issues":1207,"closed_issues":3},
         {"number":5,"title":"Phase 5: Desktop Native App","state":"open","open_issues":6,"closed_issues":0},
         {"number":4,"title":"Phase 4: Validate + Scale","state":"open","open_issues":118,"closed_issues":120}]'

echo "TS8: pick_phase -> lowest open Phase milestone with open issues"
OUT="$(pick_phase <(ms_proj "$RAW_MS") 2>&1 || true)"
assert_eq "4|Phase 4: Validate + Scale" "$OUT" "Phase 4 chosen over Phase 5 and Post-MVP"

echo "TS8c: pick_phase sorts phase numbers numerically"
OUT="$(pick_phase <(printf '%s' '[{"title":"Phase 10: Later","state":"open","open_issues":3,"closed_issues":0},
                                  {"title":"Phase 2: Next","state":"open","open_issues":1,"closed_issues":0}]') 2>&1 || true)"
assert_eq "2|Phase 2: Next" "$OUT" "Phase 2 before Phase 10"

echo "TS8d: pick_phase -> empty when only Post-MVP has open issues"
OUT="$(pick_phase <(printf '%s' '[{"title":"Phase 4: Validate + Scale","state":"open","open_issues":0,"closed_issues":9},
                                  {"title":"Post-MVP / Later","state":"open","open_issues":1207,"closed_issues":3}]') 2>&1 || true)"
assert_eq "" "$OUT" "no phase with open issues -> empty"

echo "TS8e: pick_phase skips a CLOSED Phase milestone that still has open issues"
OUT="$(pick_phase <(printf '%s' '[{"title":"Phase 4: Validate + Scale","state":"closed","open_issues":2,"closed_issues":9},
                                  {"title":"Phase 5: Desktop Native App","state":"open","open_issues":6,"closed_issues":0}]') 2>&1 || true)"
assert_eq "5|Phase 5: Desktop Native App" "$OUT" "closed milestone skipped"

ff() { # $1 = issues JSON -> "ready|blocked|claimed|frontier-numbers"
  local o
  o="$(filter_frontier <(printf '%s' "$1") 2>&1)" || { printf 'RC-NONZERO %s' "$o"; return 0; }
  jq -r '"\(.frontier|length)|\(.blocked)|\(.claimed)|\([.frontier[].number]|join(","))"' <<< "$o"
}
nb='{"nodes":[],"totalCount":0}'

echo "TS9: open blocker -> held back, counted blocked"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[],"blockedBy":{"nodes":[{"number":6,"state":"OPEN","repository":{"nameWithOwner":"o/r"}}],"totalCount":1}}]')"
assert_eq "0|1|0|" "$OUT" "open blocker -> not in frontier, blocked=1"

echo "TS10: closed blocker -> in frontier"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[],"blockedBy":{"nodes":[{"number":6,"state":"CLOSED","repository":{"nameWithOwner":"o/r"}}],"totalCount":1}}]')"
assert_eq "1|0|0|7" "$OUT" "closed blocker -> frontier"

echo "TS11: assigned -> held back, counted claimed"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[{"login":"x"}],"blockedBy":'"$nb"'}]')"
assert_eq "0|0|1|" "$OUT" "assignee -> claimed=1"

echo "TS11b: blocked AND assigned counts as blocked, not claimed"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[{"login":"x"}],"blockedBy":{"nodes":[{"number":6,"state":"OPEN","repository":{"nameWithOwner":"o/r"}}],"totalCount":1}}]')"
assert_eq "0|1|0|" "$OUT" "blocked+assigned -> blocked=1 claimed=0"

echo "TS12: unreadable blocker (nodes empty, totalCount 1) -> held back"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[],"blockedBy":{"nodes":[],"totalCount":1}}]')"
assert_eq "0|1|0|" "$OUT" "count exceeds nodes -> held back"

echo "TS12b: partial page (totalCount 2, one CLOSED node) -> held back"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[],"blockedBy":{"nodes":[{"number":6,"state":"CLOSED","repository":{"nameWithOwner":"o/r"}}],"totalCount":2}}]')"
assert_eq "0|1|0|" "$OUT" "partial page -> held back"

echo "TS12c: blocker with null or missing state -> held back"
OUT="$(ff '[{"number":7,"title":"a","labels":[],"assignees":[],"blockedBy":{"nodes":[{"number":6,"state":null}],"totalCount":1}},
            {"number":8,"title":"b","labels":[],"assignees":[],"blockedBy":{"nodes":[{"number":6}],"totalCount":1}}]')"
assert_eq "0|2|0|" "$OUT" "null/missing state -> held back"

echo "TS12d: frontier sorted by number"
OUT="$(ff '[{"number":9,"title":"a","labels":[],"assignees":[],"blockedBy":'"$nb"'},
            {"number":3,"title":"b","labels":[],"assignees":[],"blockedBy":'"$nb"'}]')"
assert_eq "2|0|0|3,9" "$OUT" "frontier ascending"

# --- End-to-end through main() with a fake gh on PATH (hermetic) ---
# One owning EXIT trap for this suite's scratch dirs, composed with the incident
# sandbox cleanup test-helpers.sh registers (replacing its trap would leak that).
_rr_cleanup() {
  rm -rf "${E2E_ROOT:-}" "${TMP_GIT:-}"
  if declare -F _soleur_sb_cleanup >/dev/null; then _soleur_sb_cleanup; fi
}
trap _rr_cleanup EXIT
E2E_ROOT="$(mktemp -d)"
FAKE_DIR="$E2E_ROOT/bin"; RUN_DIR="$E2E_ROOT/run"; TMP_SANDBOX="$E2E_ROOT/tmp"
mkdir -p "$FAKE_DIR/cfg" "$RUN_DIR" "$TMP_SANDBOX"
cat > "$FAKE_DIR/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DIR/calls"
case "$1 $2" in
  "api repos/{owner}/{repo}/milestones?state=all&per_page=100")
    [[ "${3:-}" == "--jq" && -n "${4:-}" ]] || { echo "FAKE_GH_UNEXPECTED $*" >&2; exit 97; }
    exec jq -c "$4" "$FAKE_MS" ;;
  "issue list")
    case "${FAKE_GH_ISSUES:-ok}" in
      ok)     exec cat "$FAKE_ISSUES" ;;
      oldgh)  echo 'Unknown JSON field: "blockedBy"' >&2; exit 1 ;;
      neterr) echo 'error connecting to api.github.com' >&2; exit 1 ;;
    esac ;;
esac
echo "FAKE_GH_UNEXPECTED $*" >&2
exit 97
FAKE
chmod +x "$FAKE_DIR/gh"
[[ -x "$FAKE_DIR/gh" ]] && pass "fake gh is executable" || fail "fake gh not executable"

E2E_ROADMAP="$E2E_ROOT/roadmap.md"
printf '%s' '## Current State (2026-09-22)

| Dimension | Status |
|-----------|--------|
| Phase 1 (Close the Loop) | Complete. 0 open, 15 closed. |
| Phase 4 (Validate + Scale) | In progress. Counts are not frozen here. |
| Phase 5 (Desktop Native App) | Defined. 6 open, 0 closed. |
' > "$E2E_ROADMAP"
FAKE_MS="$E2E_ROOT/ms.json"; printf '%s' "$RAW_MS" > "$FAKE_MS"
ISSUES_MIXED="$E2E_ROOT/issues-mixed.json"
printf '%s' '[{"number":1450,"title":"usage tracking","labels":[{"name":"domain/engineering"}],"assignees":[],"blockedBy":{"nodes":[],"totalCount":0}},
 {"number":1441,"title":"pricing page","labels":[{"name":"domain/engineering"}],"assignees":[],"blockedBy":{"nodes":[{"number":1440,"state":"OPEN","repository":{"nameWithOwner":"o/r"}}],"totalCount":1}},
 {"number":1443,"title":"interview loop","labels":[],"assignees":[{"login":"someone"}],"blockedBy":{"nodes":[],"totalCount":0}},
 {"number":1447,"title":"recruit founders","labels":[{"name":"type/research"}],"assignees":[],"blockedBy":{"nodes":[],"totalCount":0}}]' > "$ISSUES_MIXED"
ISSUES_HELD="$E2E_ROOT/issues-held.json"
printf '%s' '[{"number":1441,"title":"pricing page","labels":[],"assignees":[],"blockedBy":{"nodes":[{"number":1440,"state":"OPEN","repository":{"nameWithOwner":"o/r"}}],"totalCount":1}},
 {"number":1443,"title":"interview loop","labels":[],"assignees":[{"login":"someone"}],"blockedBy":{"nodes":[],"totalCount":0}}]' > "$ISSUES_HELD"
ISSUES_NOBLOCK="$E2E_ROOT/issues-noblock.json"
printf '%s' '[{"number":1450,"title":"usage tracking","labels":[],"assignees":[]}]' > "$ISSUES_NOBLOCK"
ISSUES_NOASSIGN="$E2E_ROOT/issues-noassign.json"
printf '%s' '[{"number":1450,"title":"usage tracking","labels":[],"blockedBy":{"nodes":[],"totalCount":0}}]' > "$ISSUES_NOASSIGN"
ISSUES_OK1="$E2E_ROOT/issues-ok1.json"
printf '%s' '[{"number":1450,"title":"usage tracking","labels":[],"assignees":[],"blockedBy":{"nodes":[],"totalCount":0}}]' > "$ISSUES_OK1"

run_main() { # FAKE_ISSUES / FAKE_GH_ISSUES / E2E_RM from caller; sets OUT RC CALLS
  : > "$FAKE_DIR/calls"
  RC=0
  OUT="$(cd "$RUN_DIR" && FAKE_DIR="$FAKE_DIR" FAKE_MS="$FAKE_MS" FAKE_ISSUES="${FAKE_ISSUES:-$ISSUES_MIXED}" \
    FAKE_GH_ISSUES="${FAKE_GH_ISSUES:-ok}" PATH="$FAKE_DIR:$PATH" GH_TOKEN= GH_CONFIG_DIR="$FAKE_DIR/cfg" \
    ROADMAP_FILE="${E2E_RM:-$E2E_ROADMAP}" TMPDIR="$TMP_SANDBOX" bash "$MODULE" "$@" 2>&1)" || RC=$?
  CALLS="$(cat "$FAKE_DIR/calls")"
}

echo "TS13: next + next --frontier end-to-end (live phase, full fetch, composition)"
FAKE_ISSUES="$ISSUES_MIXED" FAKE_GH_ISSUES=ok run_main next
assert_eq "0" "$RC" "next exits 0"
assert_contains "$OUT" "Phase 4" "next picks Phase 4 (no count cell) over Phase 5"
assert_not_contains "$OUT" "Phase 5" "next never names Phase 5"
assert_contains "$OUT" "#1447" "next names the lowest ready issue"
assert_not_contains "$OUT" "#1441" "blocked issue never recommended"
assert_not_contains "$OUT" "#1443" "claimed issue never recommended"
assert_contains "$OUT" "1 waiting on another issue, 1 with someone on it" "next line shows held-back counts"
[[ -n "$CALLS" ]] && pass "fake gh was called" || fail "fake gh never called (real gh leak?)"
assert_eq "1" "$(grep -c '^issue list' <<< "$CALLS" || true)" "exactly one issue list call"
assert_contains "$CALLS" "--milestone Phase 4: Validate + Scale" "fetch targets Phase 4 milestone"
assert_contains "$CALLS" "--limit 1000" "fetch is not truncated at 30"
assert_contains "$CALLS" "blockedBy" "fetch requests blockedBy"
assert_contains "$CALLS" "assignees" "fetch requests assignees"
NEXT_NUM="$(grep -oE '#[0-9]+' <<< "$OUT" | head -1)" || NEXT_NUM=""
FAKE_ISSUES="$ISSUES_MIXED" FAKE_GH_ISSUES=ok run_main next --frontier
assert_eq "0" "$RC" "next --frontier exits 0"
assert_contains "$(head -1 <<< "$OUT")" "roadmap-frontier: Phase 4 — 2 ready to start, 1 waiting on another issue, 1 with someone on it" "summary line first"
FIRST_ITEM="$(sed -n 2p <<< "$OUT")"
assert_eq "OPERATOR|#1447|recruit founders" "$FIRST_ITEM" "first frontier item classified"
assert_eq "CODEABLE|#1450|usage tracking" "$(sed -n 3p <<< "$OUT")" "second frontier item classified"
assert_eq "3" "$(wc -l <<< "$OUT" | tr -d ' ')" "only ready issues listed"
assert_contains "$FIRST_ITEM" "$NEXT_NUM" "next names the first --frontier item"

echo "TS14: empty frontier stays on its phase and shows the counts"
FAKE_ISSUES="$ISSUES_HELD" FAKE_GH_ISSUES=ok run_main next
assert_eq "0" "$RC" "empty frontier exits 0"
assert_contains "$OUT" "Phase 4" "NONE line names the phase"
assert_contains "$OUT" "nothing ready to start" "NONE line says nothing is ready"
assert_contains "$OUT" "1 waiting on another issue, 1 with someone on it" "NONE line shows counts"
assert_not_contains "$OUT" "no open issues" "never reads as finished"
assert_not_contains "$OUT" "Phase 5" "never falls through to the next phase"

echo "TS15: old gh (Unknown JSON field) -> exit 2 naming the version"
FAKE_GH_ISSUES=oldgh run_main next
assert_eq "2" "$RC" "old gh exits 2"
assert_contains "$OUT" "requires gh >= 2.94.0" "old gh message names the version"

echo "TS15b: other fetch failure -> exit 2, stderr relayed, no version text"
FAKE_GH_ISSUES=neterr run_main next
assert_eq "2" "$RC" "fetch failure exits 2"
assert_contains "$OUT" "error connecting" "gh stderr relayed"
assert_not_contains "$OUT" "requires gh" "no version text on a network failure"
assert_not_contains "$OUT" "no open issues" "fetch failure never reads as empty"

echo "TS15c: missing blockedBy / assignees field -> exit 2 naming it"
FAKE_ISSUES="$ISSUES_NOBLOCK" FAKE_GH_ISSUES=ok run_main next
assert_eq "2" "$RC" "missing blockedBy exits 2"
assert_contains "$OUT" "blockedBy" "message names blockedBy"
FAKE_ISSUES="$ISSUES_NOASSIGN" FAKE_GH_ISSUES=ok run_main next
assert_eq "2" "$RC" "missing assignees exits 2"
assert_contains "$OUT" "assignees" "message names assignees"
FAKE_ISSUES="$ISSUES_OK1" FAKE_GH_ISSUES=ok run_main next
assert_eq "0" "$RC" "positive control: fields present exits 0"

echo "TS16: unknown next argument -> exit 64 before any fetch"
FAKE_ISSUES="$ISSUES_MIXED" FAKE_GH_ISSUES=ok run_main next --bogus
assert_eq "64" "$RC" "next --bogus exits 64"
assert_contains "$OUT" "next [--frontier]" "usage names --frontier"
assert_eq "" "$CALLS" "no gh call before argument parsing"

echo "TS17: validate verdicts unchanged by the new state projection"
E2E_RM_V="$E2E_ROOT/roadmap-v.md"; printf '%s' "$ROADMAP_FIXTURE" > "$E2E_RM_V"
EXPECT="$(reconcile_counts "$E2E_RM_V" <(jq -c '[ .[] | {title, open_issues, closed_issues} ]' "$FAKE_MS"))"
E2E_RM="$E2E_RM_V" run_main validate
GOT="$(grep -E '^(STALE_STATUS|MISSING_ISSUE|EMPTY_MILESTONE)\|' <<< "$OUT" || true)"
[[ -n "$EXPECT" ]] && pass "fixture produces verdicts (non-vacuous)" || fail "fixture produced no verdicts"
assert_eq "$EXPECT" "$GOT" "main validate verdicts == reconcile_counts on the old projection"

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
  pick_next_action <(printf '%s' "$ISSUES") >/dev/null
  pick_phase <(ms_proj "$RAW_MS") >/dev/null || true
  filter_frontier "$ISSUES_MIXED" >/dev/null || true )
DIRTY="$(cd "$TMP_GIT" && git status --porcelain)"
assert_eq "" "$DIRTY" "sandbox tree clean after running all functions (zero writes)"
rm -rf "$TMP_GIT"
FAKE_ISSUES="$ISSUES_MIXED" FAKE_GH_ISSUES=ok run_main next --frontier
assert_eq "" "$(ls -A "$TMP_SANDBOX")" "main next leaves no temp file behind"
FAKE_GH_ISSUES=neterr run_main next
assert_eq "" "$(ls -A "$TMP_SANDBOX")" "main next leaves no temp file behind on exit 2"
rm -rf "$E2E_ROOT"

echo ""
echo "=== roadmap-reconcile: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
