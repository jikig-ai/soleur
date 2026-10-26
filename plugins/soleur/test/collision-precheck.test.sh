#!/usr/bin/env bash
# Suite for plugins/soleur/scripts/collision-precheck.sh (issue #10333) and the
# lead-gate prescription it ships with.
#
# The pre-check reports, BEFORE plan/review work starts on an issue, the two
# measured collision signals: an open PR naming the same issue
# (`gh pr list --state open --search "<N>"`) and a foreign `proc.sh list_runs`
# row (a sibling session's live gate in another worktree). #10320/#10322 were
# two sessions of the same operator converting the same file for the same
# issue, discovered only at review.
#
# Arms:
#   instrument -- the gh stub rejects unknown argv and every write verb; the
#                 verdict helpers are shown able to go red first.
#   usage      -- no arg / non-digit issue / a proc pattern carrying '/'.
#   rows       -- clear, PR-hit (the fixture's open PR names the issue), foreign
#                 row, both, and the could-not-check exits (gh down, proc.sh
#                 down, both down). A probe that failed never reads as clear.
#   wiring     -- plan/SKILL.md Phase 0.6 and review/SKILL.md Step 1 name the
#                 script, and the review/work/ship lead-gate prescription is
#                 the BOUNDED default (`bash scripts/test-all.sh` previewed by
#                 `--print-selection`), never `TEST_GROUP=affected`.
#
# Writes only under `mktemp -d`. Portable to bash 3.2.

set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
trap '[[ -z "${TMP:-}" ]] || rm -rf "$TMP"' EXIT
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
# test-helpers runs `set -euo pipefail`; this suite captures non-zero rcs as
# inputs (the SUT's exit codes ARE the verdicts), so errexit must come back off.
set +e -uo pipefail

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
SCRIPT_SRC="$REPO_ROOT/plugins/soleur/scripts/collision-precheck.sh"
PLAN_SKILL="$REPO_ROOT/plugins/soleur/skills/plan/SKILL.md"
REVIEW_SKILL="$REPO_ROOT/plugins/soleur/skills/review/SKILL.md"
WORK_SKILL="$REPO_ROOT/plugins/soleur/skills/work/SKILL.md"
SHIP_SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"

TMP="$(mktemp -d -t collision-precheck.XXXXXXXX)"
assert_fixture_dir "$TMP"

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

CASES=0
chk_eq() { CASES=$((CASES + 1)); assert_eq "$1" "$2" "$3"; }
chk_has() { local h=0; grep -qF -- "$2" "$1" && h=1; CASES=$((CASES + 1)); assert_eq 1 "$h" "$3"; }
chk_hasnt() { local h=0; grep -qF -- "$2" "$1" && h=1; CASES=$((CASES + 1)); assert_eq 0 "$h" "$3"; }

[[ -f "$SCRIPT_SRC" ]] || { echo "FATAL: $SCRIPT_SRC missing" >&2; exit 2; }

# --- Sandbox: a copy of the script beside a STUB lib/proc.sh ----------------
# The real lib/proc.sh has its own suite (proc.test.sh); here a stub emits the
# scenario's rows so the foreign/mine classification path is under fixture
# control and the suite never depends on live machine state.
SANDBOX="$TMP/scripts"
mkdir -p "$SANDBOX/lib"
cp "$SCRIPT_SRC" "$SANDBOX/collision-precheck.sh"
cat > "$SANDBOX/lib/proc.sh" <<'PSTUB'
#!/usr/bin/env bash
# proc.sh stub: list_runs <pat> serves $PROC_FIX/rows-<pat>.txt verbatim;
# $PROC_FIX/proc.rc simulates a failure; anything else is a usage error.
case "${1:-}" in
  list_runs)
    [ -f "$PROC_FIX/proc.rc" ] && exit "$(cat "$PROC_FIX/proc.rc")"
    f="$PROC_FIX/rows-${2:-}.txt"
    [ -f "$f" ] && cat "$f" || echo "no processes match '${2:-}'"
    exit 0 ;;
  *) echo "proc stub: unhandled: $*" >&2; exit 2 ;;
esac
PSTUB

# --- gh stub: serves ONLY the argv shape the script is allowed to use -------
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'GSTUB'
#!/usr/bin/env bash
DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
printf '%s\n' "$*" >> "$DIR/argv.log"
case "$*" in
  "pr comment"*|"pr edit"*|"pr close"*|"pr merge"*|"pr review"*|"issue "*)
    printf '%s\n' "$*" >> "$DIR/write.log"; echo "gh stub: write verb refused" >&2; exit 64 ;;
esac
[ -f "$DIR/gh.rc" ] && exit "$(cat "$DIR/gh.rc")"
prev=""; filt=""
for a in "$@"; do [ "$prev" = "--jq" ] && filt="$a"; prev="$a"; done
case "$*" in
  "pr list --state open --search "*" -L 100 --json number,url --jq "*)
    [ -f "$DIR/list.json" ] || { echo "gh stub: no list.json" >&2; exit 64; }
    jq -r "$filt" < "$DIR/list.json" ;;
  *) printf '%s\n' "$*" >> "$DIR/unknown.log"; echo "gh stub: unhandled argv: $*" >&2; exit 64 ;;
esac
GSTUB
chmod +x "$STUB/gh"
: > "$STUB/argv.log"; : > "$STUB/write.log"; : > "$STUB/unknown.log"

SCN="$TMP/scn"; mkdir -p "$SCN"
new_scn() { rm -rf "$SCN"; mkdir -p "$SCN"; printf '[]\n' > "$SCN/list.json"; }
OUTF="$TMP/out"; ERRF="$TMP/err"; RC=0
run_cp() { # run_cp <args...> (uses $SCN)
  cp "$SCN/list.json" "$STUB/list.json" 2>/dev/null || :
  [ -f "$SCN/gh.rc" ] && cp "$SCN/gh.rc" "$STUB/gh.rc" || rm -f "$STUB/gh.rc"
  rm -rf "$TMP/proc-cur"; mkdir -p "$TMP/proc-cur"
  [ -d "$SCN/proc" ] && cp -r "$SCN/proc/." "$TMP/proc-cur/" || :
  : > "$STUB/argv.log"; : > "$STUB/write.log"; : > "$STUB/unknown.log"
  PROC_FIX="$TMP/proc-cur" PATH="$STUB:$PATH" bash "$SANDBOX/collision-precheck.sh" "$@" > "$OUTF" 2> "$ERRF"; RC=$?
}
pr_row() { # pr_row <n> -> one open-PR object on the list
  jq -n -c --argjson n "$1" '[{number: $n, url: ("https://github.com/o/r/pull/\($n)")}]' > "$SCN/list.json"
}

echo "=== collision-precheck suite ==="

# --- instrument -------------------------------------------------------------
CASES=$((CASES + 1))
p0=$PASS; f0=$FAIL
assert_eq a b "verdict-helper negative control (EXPECTED FAIL)"
if (( PASS == p0 && FAIL == f0 + 1 )); then PASS=$p0; FAIL=$f0; echo "  ok   verdict helpers move both counters"; else echo "FATAL: verdict helpers broken" >&2; exit 1; fi

new_scn
run_cp 10333
chk_eq 0 "$RC" "instrument: a clear fixture run exits 0"
chk_has "$STUB/argv.log" 'pr list --state open --search 10333 -L 100 --json number,url --jq' "instrument: the stub saw the prescribed query shape"
chk_eq 0 "$(wc -l < "$STUB/unknown.log" | tr -d ' ')" "instrument: zero unknown gh argv"
chk_eq 0 "$(wc -l < "$STUB/write.log" | tr -d ' ')" "instrument: zero write calls to GitHub"

# --- usage ------------------------------------------------------------------
run_cp
chk_eq 64 "$RC" "usage: no issue number exits 64"
run_cp abc
chk_eq 64 "$RC" "usage: non-digit issue exits 64"
run_cp 10333 'dir/test-all.sh'
chk_eq 64 "$RC" "usage: a '/' in the proc pattern exits 64"

# --- rows -------------------------------------------------------------------
new_scn; run_cp 10333
chk_eq 0 "$RC" "clear: no PR and no foreign row exits 0"
chk_has "$OUTF" 'SOLEUR_COLLISION exit=0 prs=none foreign=none' "clear: machine line says none/none"

new_scn; pr_row 10320; run_cp 10333
chk_eq 10 "$RC" "PR hit: an open PR naming the issue exits 10"
chk_has "$OUTF" 'An open change names #10333: PR #10320' "PR hit: the human block names the PR"
chk_has "$OUTF" 'prs=10320 ' "PR hit: the machine line lists it"
chk_has "$STUB/argv.log" 'pr list --state open --search 10333 -L 100' "PR hit: the stub saw the prescribed query shape"
chk_eq 0 "$(wc -l < "$STUB/write.log" | tr -d ' ')" "PR hit: zero write calls to GitHub"

new_scn
printf '424242\tforeign\t/data/x/.worktrees/feat-other\n7\tmine\t/tmp/self\n' > "$SCN/proc-rows"
mkdir -p "$SCN/proc"; cp "$SCN/proc-rows" "$SCN/proc/rows-test-all.sh.txt"
run_cp 10333
chk_eq 10 "$RC" "foreign row: a sibling-owned gate process exits 10"
chk_has "$OUTF" 'pid 424242' "foreign row: the human block names the pid and worktree"
chk_has "$OUTF" 'foreign=424242' "foreign row: the machine line lists the pid"

new_scn; pr_row 10320
mkdir -p "$SCN/proc"; printf '424242\tforeign\t/wt/x\n' > "$SCN/proc/rows-test-all.sh.txt"
run_cp 10333
chk_eq 10 "$RC" "both probes hit: exit 10"
chk_has "$OUTF" 'prs=10320 foreign=424242' "both: machine line carries both lists"

new_scn; printf '1\n' > "$SCN/gh.rc"; run_cp 10333
chk_eq 2 "$RC" "gh down + clear proc: could not check exits 2"
chk_has "$OUTF" 'prs=unchecked' "gh down: machine line says unchecked, never none"
chk_has "$OUTF" 'not a clear result' "gh down: human block refuses to read as clear"

new_scn; mkdir -p "$SCN/proc"; printf '1\n' > "$SCN/proc/proc.rc"; run_cp 10333
chk_eq 2 "$RC" "proc down + clear gh: could not check exits 2"
chk_has "$OUTF" 'foreign=unchecked' "proc down: machine line says unchecked"

new_scn; printf '1\n' > "$SCN/gh.rc"; mkdir -p "$SCN/proc"; printf '1\n' > "$SCN/proc/proc.rc"; run_cp 10333
chk_eq 2 "$RC" "both probes down: exit 2"

# --- wiring -----------------------------------------------------------------
chk_has "$PLAN_SKILL" 'collision-precheck.sh' "plan/SKILL.md names the collision pre-check"
chk_has "$PLAN_SKILL" 'gh pr list --state open --search' "plan/SKILL.md names the open-PR probe"
chk_has "$REVIEW_SKILL" 'collision-precheck.sh' "review/SKILL.md names the collision pre-check"
chk_has "$REVIEW_SKILL" 'proc.sh list_runs' "review/SKILL.md names the foreign-rows probe"

# The lead gate is the BOUNDED default, never the heuristic selector. Extract
# the lead-prescription span from each skill and pin both halves.
for pair in "$REVIEW_SKILL:Two backstops" "$WORK_SKILL:Two mechanical backstops"; do
  sk="${pair%%:*}"; stop="${pair#*:}"
  span="$(awk -v s="$stop" '/lead runs the gate/{f=1} f{print} index($0,s){f=0}' "$sk")"
  CASES=$((CASES + 1))
  if grep -qF 'bash scripts/test-all.sh' <<<"$span" && grep -qF -- '--print-selection' <<<"$span"; then
    pass "lead-gate span in ${sk##*/} prescribes the bounded default + print-selection"
  else
    fail "lead-gate span in ${sk##*/} lost the bounded default or the preview: $span"
  fi
  CASES=$((CASES + 1))
  if grep -qF 'TEST_GROUP=affected' <<<"$span"; then
    fail "lead-gate span in ${sk##*/} still prescribes TEST_GROUP=affected — the #8591 heuristic is the spawned-agent form, not the lead's gate"
  else
    pass "lead-gate span in ${sk##*/} does not prescribe TEST_GROUP=affected"
  fi
done
chk_has "$SHIP_SKILL" 'bash scripts/test-all.sh --print-selection' "ship/SKILL.md previews the bounded selection at the Phase 4 gate"
chk_has "$SHIP_SKILL" 'selected N of M' "ship/SKILL.md states the selected-N-of-M discipline"

MIN_CASES=30
if (( CASES < MIN_CASES )); then
  printf '[FATAL] anti-vacuity floor: only %d case(s) ran, expected >= %d\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi

print_results
