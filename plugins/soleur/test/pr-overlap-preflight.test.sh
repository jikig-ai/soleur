#!/usr/bin/env bash
# Suite for plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh -- the read-only check that
# lists OTHER open changes that edit the same files, carry the same edit, or carry a same-titled
# change (plan: 2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md, Phase 6,
# Guard 5).
#
# Property under test: no other open change that overlaps goes unreported; a check that could not
# run never reads as clear; only a duplicate or a CTO-designated vehicle stops a merge (exit 12 / 10);
# shared files alone are informational (exit 13); and the script never writes to GitHub.
#
# Arms:
#   1. instrument  -- the `gh` stub rejects unknown argv (exit 64) and every write verb, and the
#                     jargon matcher is shown to fire on each denylisted term and to stay quiet on
#                     ordinary words. Both are proven BEFORE anything is graded through them.
#   2. static      -- the script text carries no write verb, no bare timeout, none of the
#                     portability-banned constructs.
#   3. rows        -- one scenario per exit code (0/10/11/12/13/2) plus the 100-file page cap, the
#                     20-diff cap, self-exclusion, the issue search, start-mode without a change,
#                     hostile titles and usage errors. Each row also asserts the machine line, zero
#                     write calls, zero unknown argv, and a jargon-free human block.
#   4. mutation    -- each `# mut:<name>` line in the script is replaced by a broken version; the rows
#                     that guard it must go red. An identity replacement must stay green (the
#                     mutation harness is not always-red).
#
# Writes only under `mktemp -d` (preflight Check 10 runs suites with the repo read-only).
# Portable to bash 3.2 and mawk: no associative arrays, no mapfile, no ${var,,}, no sed -i.

set -euo pipefail
export LC_ALL=C

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
SCRIPT="$REPO_ROOT/plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh"
FIXTURES="$SUITE_DIR/fixtures/pr-overlap-preflight"
REFERENCE="$REPO_ROOT/plugins/soleur/skills/ship/references/pr-overlap.md"

TMP="$(mktemp -d -t pr-overlap-suite.XXXXXXXX)"
assert_fixture_dir "$TMP"
trap 'rm -rf "$TMP"' EXIT

assert_fixture_dir "$FIXTURES"
[[ -d "$FIXTURES" ]] || { printf 'FATAL: fixture dir %s missing\n' "$FIXTURES" >&2; exit 2; }

if [[ ! -f "$SCRIPT" ]]; then
  echo "  FAIL: script under test is missing: $SCRIPT"
  FAIL=$((FAIL + 1))
  print_results 1
fi

# ---------------------------------------------------------------------------------------------
# Dual-mode checks. REPORT mode counts through the shared assert helpers; QUIET mode only counts
# mismatches into BAD, so the mutation arm can ask "did any row go red" without touching PASS/FAIL.
# ---------------------------------------------------------------------------------------------
MODE=report
BAD=0
chk_eq() { # expected actual msg
  if [[ "$MODE" == report ]]; then assert_eq "$1" "$2" "$3"; else [[ "$1" == "$2" ]] || BAD=$((BAD + 1)); fi
}
chk_has() { # file needle msg
  local hit=0
  if grep -qF -- "$2" "$1"; then hit=1; fi
  chk_eq 1 "$hit" "$3"
}
chk_hasnt() { # file needle msg
  local hit=0
  if grep -qF -- "$2" "$1"; then hit=1; fi
  chk_eq 0 "$hit" "$3"
}

# ---------------------------------------------------------------------------------------------
# The gh stub. Dispatches on the EXACT argv shapes the script is allowed to use; anything else is
# exit 64 and a line in unknown.log. Every write verb is exit 64 and a line in write.log. The
# fixtures choose the answers (list.json, view.json, search-<n>.json, diff-<n>.diff, files-<n>.json,
# commits-<n>.json, each optionally with a sibling .rc to simulate a failure), and the stub applies
# the REAL --jq filter the caller passed, so a changed projection reds instead of passing on a
# shape production never produces.
# ---------------------------------------------------------------------------------------------
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
FIX="$(cat "$DIR/fixdir")"
printf '%s\n' "$*" >> "$DIR/argv.log"
unknown() { printf '%s\n' "$*" >> "$DIR/unknown.log"; echo "gh stub: unhandled argv: $*" >&2; exit 64; }
serve() { # serve <fixture-name>
  local f="$FIX/$1"
  if [ -f "$f.rc" ]; then echo "gh stub: simulated failure for $1" >&2; exit "$(cat "$f.rc")"; fi
  if [ ! -f "$f" ]; then printf '%s\n' "missing fixture $1" >> "$DIR/unknown.log"; echo "gh stub: no fixture $1" >&2; exit 64; fi
  cat "$f"; exit 0
}
is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
case "$*" in
  "pr comment"*|"pr edit"*|"pr close"*|"pr merge"*|"pr review"*|"pr ready"*|"pr reopen"*|"issue "*|"api "*" -X "*|"api "*"--method"*|"api "*" -f "*|"api "*" -F "*|"api "*"--input"*)
    printf '%s\n' "$*" >> "$DIR/write.log"; echo "gh stub: write verb refused: $*" >&2; exit 64 ;;
esac
case "$*" in
  "pr view --json number,headRefName")
    serve view.json ;;
  "pr list --state open -L 200 --json number,title,url,isDraft,files,headRefName")
    serve list.json ;;
  "pr list --state open --search "*" -L 50 --json number,title,url,isDraft,headRefName")
    is_int "$6" || unknown "$@"
    serve "search-$6.json" ;;
  "pr diff "*)
    [ $# -eq 3 ] && is_int "$3" || unknown "$@"
    serve "diff-$3.diff" ;;
  "api repos/{owner}/{repo}/pulls/"*"/files --paginate --jq .[].filename")
    n="${2#repos/*/pulls/}"; n="${n%/files}"
    is_int "$n" || unknown "$@"
    if [ -f "$FIX/files-$n.json.rc" ]; then echo "gh stub: simulated failure" >&2; exit "$(cat "$FIX/files-$n.json.rc")"; fi
    [ -f "$FIX/files-$n.json" ] || unknown "$@"
    jq -r "$5" < "$FIX/files-$n.json"; exit 0 ;;
  "api repos/{owner}/{repo}/pulls/"*"/commits --paginate --jq "*)
    n="${2#repos/*/pulls/}"; n="${n%/commits}"
    is_int "$n" || unknown "$@"
    if [ -f "$FIX/commits-$n.json.rc" ]; then echo "gh stub: simulated failure" >&2; exit "$(cat "$FIX/commits-$n.json.rc")"; fi
    cf="$FIX/commits-$n.json"
    [ -f "$cf" ] || cf="$FIX/commits-default.json"
    [ -f "$cf" ] || unknown "$@"
    jq -r "$5" < "$cf"; exit 0 ;;
  *) unknown "$@" ;;
esac
STUBEOF
chmod +x "$STUB/gh"
: > "$STUB/argv.log"; : > "$STUB/write.log"; : > "$STUB/unknown.log"

SCN_ROOT="$TMP/scn"
mkdir -p "$SCN_ROOT"
SCN=""
new_scn() { # new_scn <name> -> sets SCN to a fresh scenario dir
  SCN="$SCN_ROOT/$1"
  rm -rf "$SCN"; mkdir -p "$SCN"
  cp "$FIXTURES/commits-default.json" "$SCN/commits-default.json"
}
fx() { # fx <fixture-file> <dest-name>
  cp "$FIXTURES/$1" "$SCN/$2"
}
rc_of() { # rc_of <dest-name> <code> -> make that fixture fail with <code>
  printf '%s\n' "$2" > "$SCN/$1.rc"
}

# ---------------------------------------------------------------------------------------------
# The fixture repository: origin/main plus a feature branch with three commits. Created BEFORE the
# first run; git_fixture_env exports a discovery ceiling into this shell, so every later git call in
# this suite is against a fixture.
# ---------------------------------------------------------------------------------------------
REPO="$TMP/repo"
REPO_B="$TMP/repo-b"
mkdir -p "$REPO" "$REPO_B"
git_fixture_env "$REPO" || { echo "FATAL: git_fixture_env refused fixture $REPO" >&2; exit 64; }
git init -q -b main "$REPO"
printf 'echo one\n' > "$REPO/a.sh"
printf 'echo base\n' > "$REPO/b.sh"
git -C "$REPO" add a.sh b.sh
git -C "$REPO" commit -q -m "base"
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" checkout -q -b feat-widget-cache
printf 'x\n' > "$REPO/init.txt"
git -C "$REPO" add init.txt
git -C "$REPO" commit -q -m "chore: initialize feat-widget-cache"
printf 'echo two\n' > "$REPO/a.sh"
printf 'echo new\n' > "$REPO/c.sh"
git -C "$REPO" add a.sh c.sh
git -C "$REPO" commit -q -m "feat: add widget cache"
printf 'y\n' > "$REPO/state.txt"
git -C "$REPO" add state.txt
git -C "$REPO" commit -q -m "chore: record plan-phase session state"

# A second repository with NO origin/main: merge mode must refuse to guess.
git_fixture_env "$REPO_B" || { echo "FATAL: git_fixture_env refused fixture $REPO_B" >&2; exit 64; }
git init -q -b main "$REPO_B"
printf 'x\n' > "$REPO_B/README.md"
git -C "$REPO_B" add README.md
git -C "$REPO_B" commit -q -m "base"
git_fixture_env "$REPO" || { echo "FATAL: git_fixture_env refused fixture $REPO" >&2; exit 64; }

PF_SCRIPT="$SCRIPT"
PF_CWD="$REPO"
OUTF="$TMP/last.out"
ERRF="$TMP/last.err"
RC=0
run_pf() { # run_pf <args...>  (uses $SCN) -> RC, OUTF, ERRF
  printf '%s' "$SCN" > "$STUB/fixdir"
  : > "$STUB/argv.log"; : > "$STUB/write.log"; : > "$STUB/unknown.log"
  set +e
  ( cd "$PF_CWD" && PATH="$STUB:$PATH" bash "$PF_SCRIPT" "$@" ) >"$OUTF" 2>"$ERRF"
  RC=$?
  set -e
}

# ---------------------------------------------------------------------------------------------
# Jargon matcher over the human block (every line but the last, which is the machine line).
# Uppercase tokens are matched case-sensitively and as whole words, so "approach" and "shape" never
# trip PR / SHA; the rest are whole words, case-insensitive.
# ---------------------------------------------------------------------------------------------
jargon_hits() { # jargon_hits <outfile> -> number of offending lines
  local f="$1" blk="$TMP/block.txt" n=0 c
  sed '$d' "$f" > "$blk"
  c="$(grep -cE '(^|[^A-Za-z0-9_-])(PR|SHA|HEAD)([^A-Za-z0-9_-]|$)' "$blk" || true)"; n=$((n + c))
  c="$(grep -ciE '(^|[^A-Za-z0-9_])(patch-id|rebase|merge-base|stdout|diffs?|commits?|drafts?|pull request|branch(es)?|unarmed)([^A-Za-z0-9_]|$)' "$blk" || true)"; n=$((n + c))
  c="$(grep -cE '#[0-9]+' "$blk" || true)"; n=$((n + c))
  printf '%s' "$n"
}

# Common closing checks for a row that produced RC / OUTF.
finish_row() { # finish_row <row-name> [expect-machine-prs]
  local name="$1" last ok=0 mcode wn un
  last="$(tail -n 1 "$OUTF")"
  if grep -qE '^SOLEUR_OVERLAP exit=(0|2|10|11|12|13) prs=(none|[0-9]+(,[0-9]+)*) vehicle=(none|this|[0-9]+)$' <<<"$last"; then ok=1; fi
  chk_eq 1 "$ok" "$name: last line is the machine line"
  mcode="${last#SOLEUR_OVERLAP exit=}"; mcode="${mcode%% *}"
  chk_eq "$RC" "$mcode" "$name: machine line exit matches the real exit"
  chk_eq 1 "$(grep -c '^SOLEUR_OVERLAP ' "$OUTF" || true)" "$name: exactly one machine line"
  wn="$(wc -l < "$STUB/write.log" | tr -d ' ')"
  un="$(wc -l < "$STUB/unknown.log" | tr -d ' ')"
  chk_eq 0 "$wn" "$name: zero write calls to GitHub"
  chk_eq 0 "$un" "$name: zero unknown gh argv"
  chk_eq 0 "$(jargon_hits "$OUTF")" "$name: human block is free of jargon"
  if [[ -n "${2:-}" ]]; then chk_has "$OUTF" "prs=$2 " "$name: machine line lists the overlapping changes ($2)"; fi
}

bulk_files_json() { # bulk_files_json <count> -> JSON array of {path:...}
  jq -n -c --argjson n "$1" '[range(0;$n) | {path: ("bulk/f\(.).sh"), additions: 1, deletions: 0}]'
}

# ============================== rows ==============================
row_clear() {
  new_scn clear; fx list-clear.json list.json
  run_pf --mode merge --pr 100
  chk_eq 0 "$RC" "clear: exits 0"
  chk_has "$OUTF" "No other open work overlaps with this change." "clear: says plainly that nothing overlaps"
  chk_has "$OUTF" "prs=none vehicle=none" "clear: machine line has no changes and no vehicle"
  finish_row clear
}
row_shared() {
  new_scn shared; fx list-basic.json list.json; fx diff-200-different.diff diff-200.diff
  run_pf --mode merge --pr 100
  chk_eq 13 "$RC" "shared-only: exits 13 (informational, nothing stops)"
  chk_has "$OUTF" "speed up widget lookups" "shared-only: names the OTHER change by its cleaned title (second in the list, first one did not overlap)"
  chk_has "$OUTF" "https://github.com/example-org/example-repo/pull/200" "shared-only: gives the link"
  chk_has "$OUTF" "a.sh" "shared-only: names the shared file in plain words"
  chk_hasnt "$OUTF" "onboarding guide" "shared-only: does not report the change that shares nothing"
  chk_hasnt "$OUTF" "(#10188)" "shared-only: trailing change number is stripped from the title"
  chk_hasnt "$OUTF" "perf(lookup)" "shared-only: conventional-commit prefix is stripped from the title"
  chk_hasnt "$OUTF" "same edit" "shared-only: a different edit to the same file is not called the same edit"
  chk_has "$OUTF" "exit=13 prs=200 vehicle=none" "shared-only: machine line"
  finish_row shared
}
row_vehicle10() {
  new_scn vehicle10; fx list-basic.json list.json; fx diff-200-different.diff diff-200.diff
  run_pf --mode merge --pr 100 --vehicle 200
  chk_eq 10 "$RC" "vehicle=other: exits 10 (this change carves out)"
  chk_has "$OUTF" "exit=10 prs=200 vehicle=200" "vehicle=other: machine line"
  chk_has "$OUTF" "holding mine back" "vehicle=other: plain sentence says this change holds back"
  finish_row vehicle10
}
row_vehicle11() {
  new_scn vehicle11; fx list-basic.json list.json; fx diff-200-different.diff diff-200.diff
  run_pf --mode merge --pr 100 --vehicle 100
  chk_eq 11 "$RC" "vehicle=this: exits 11 (the others carve out)"
  chk_has "$OUTF" "exit=11 prs=200 vehicle=100" "vehicle=this: machine line"
  finish_row vehicle11
}
row_dupedit() {
  new_scn dupedit; fx list-basic.json list.json; fx diff-200-same.diff diff-200.diff
  run_pf --mode merge --pr 100
  chk_eq 12 "$RC" "same edit: exits 12 with no vehicle"
  chk_has "$OUTF" "makes the same edit as yours" "same edit: plain wording"
  chk_has "$OUTF" "exit=12 prs=200 vehicle=none" "same edit: machine line"
  chk_hasnt "$OUTF" "0000000" "same edit: no patch id in the output"
  finish_row dupedit
}
row_subject_draft() {
  # Must-PASS control (H2): same-subject-only overlap on a draft, differing from the same-file canonical.
  new_scn subject; fx list-subject-draft.json list.json; fx commits-202.json commits-202.json
  run_pf --mode merge --pr 100
  chk_eq 12 "$RC" "same title, draft, no shared file: exits 12"
  chk_has "$OUTF" "same title as one of yours" "same title: plain wording"
  chk_has "$OUTF" "still being worked on" "same title: a draft is described in plain words"
  chk_has "$OUTF" "exit=12 prs=202 vehicle=none" "same title: machine line"
  finish_row subject
}
row_generic() {
  new_scn generic; fx list-subject-draft.json list.json; fx commits-generic.json commits-202.json
  run_pf --mode merge --pr 100
  chk_eq 0 "$RC" "generic subjects (initialize, WIP, session-state record) never match: exits 0"
  finish_row generic
}
row_listfail() {
  new_scn listfail; fx list-basic.json list.json; rc_of list.json 1
  run_pf --mode merge --pr 100
  chk_eq 2 "$RC" "list failure: exits 2"
  chk_has "$OUTF" "I could not check" "list failure: says it could not check"
  chk_hasnt "$OUTF" "No other open work overlaps" "list failure: never prints the clear sentence"
  chk_has "$OUTF" "exit=2 prs=none" "list failure: machine line"
  finish_row listfail
}
row_paginate() {
  new_scn paginate
  jq -n -c --argjson f "$(bulk_files_json 100)" '[{number:300,title:"feat: bulk rename",url:"https://github.com/example-org/example-repo/pull/300",isDraft:false,headRefName:"feat-bulk",files:$f}]' > "$SCN/list.json"
  jq -n -c '[range(0;149) | {filename: ("bulk/f\(.).sh")}] + [{filename: "a.sh"}]' > "$SCN/files-300.json"
  fx diff-200-different.diff diff-300.diff
  run_pf --mode merge --pr 100
  chk_eq 13 "$RC" "100-file change: the overlap beyond the first page is found (exit 13)"
  chk_has "$OUTF" "a.sh" "100-file change: names the file that was beyond the first page"
  chk_eq 1 "$(grep -c '^api repos/{owner}/{repo}/pulls/300/files' "$STUB/argv.log" || true)" "100-file change: exactly one paginated re-read"
  finish_row paginate 300
  # A failed re-read is exit 2, never clear.
  rc_of files-300.json 1
  run_pf --mode merge --pr 100
  chk_eq 2 "$RC" "100-file change: a failed re-read exits 2"
  chk_has "$OUTF" "I could not check" "100-file change: failed re-read says it could not check"
  finish_row paginate_fail
  # Below the cap there is no re-read at all.
  new_scn paginate_small
  jq -n -c --argjson f "$(bulk_files_json 99)" '[{number:300,title:"feat: bulk rename",url:"https://github.com/example-org/example-repo/pull/300",isDraft:false,headRefName:"feat-bulk",files:$f}]' > "$SCN/list.json"
  run_pf --mode merge --pr 100
  chk_eq 0 "$RC" "99-file change: below the cap, no overlap, exits 0"
  chk_eq 0 "$(grep -c '^api repos/{owner}/{repo}/pulls/[0-9]*/files' "$STUB/argv.log" || true)" "99-file change: no re-read below the cap"
  finish_row paginate_small
}
row_diffcap() {
  new_scn diffcap
  jq -n -c '[range(400;425) | {number: ., title: ("feat: item \(.)"), url: ("https://github.com/example-org/example-repo/pull/\(.)"), isDraft: false, headRefName: ("feat-item-\(.)"), files: [{path: "a.sh", additions: 1, deletions: 1}]}]' > "$SCN/list.json"
  local i
  for i in $(seq 400 424); do fx diff-200-different.diff "diff-$i.diff"; done
  run_pf --mode merge --pr 100
  chk_eq 13 "$RC" "25 sharing changes: exits 13"
  chk_eq 20 "$(grep -c '^pr diff ' "$STUB/argv.log" || true)" "25 sharing changes: edits of only 20 are compared"
  chk_has "$OUTF" "20 of the 25" "25 sharing changes: discloses 'looked at 20 of 25'"
  finish_row diffcap
}
row_diff_unreadable() {
  new_scn diffbad; fx list-basic.json list.json; rc_of diff-200.diff 1
  run_pf --mode merge --pr 100
  chk_eq 13 "$RC" "unreadable edit: still reported by file name (exit 13), not silently clear"
  chk_has "$OUTF" "could not compare the edits themselves" "unreadable edit: says so"
  finish_row diffbad 200
}
row_self() {
  new_scn self; fx list-self.json list.json
  run_pf --mode merge --pr 100
  chk_eq 0 "$RC" "self-exclusion: this change (by number) and a change from the same working copy (by name) are not overlaps"
  finish_row self
}
row_view_default() {
  new_scn viewdef; fx list-self.json list.json; fx view.json view.json
  run_pf --mode merge
  chk_eq 0 "$RC" "no --pr: the current change is read from GitHub and excluded"
  chk_eq 1 "$(grep -c '^pr view --json number,headRefName$' "$STUB/argv.log" || true)" "no --pr: one read of the current change"
  finish_row viewdef
}
row_issue_start() {
  new_scn issue; fx list-clear.json list.json; fx issue-search.json search-555.json; rc_of view.json 1
  run_pf --mode start --issue 555 --files "q.sh"
  chk_eq 13 "$RC" "start + --issue: a change that mentions the same issue is informational (exit 13)"
  chk_has "$OUTF" "Mentions the same issue" "start + --issue: plain wording"
  chk_has "$OUTF" "retry limit" "start + --issue: names the change"
  chk_hasnt "$OUTF" "widget cache" "start + --issue: this working copy's own change is excluded"
  chk_has "$OUTF" "exit=13 prs=203 vehicle=none" "start + --issue: machine line"
  finish_row issue 203
  rc_of search-555.json 1
  run_pf --mode start --issue 555 --files "q.sh"
  chk_eq 2 "$RC" "start + --issue: a failed search exits 2"
  finish_row issue_fail
}
row_start_nopr() {
  new_scn startnopr; fx list-basic.json list.json; fx diff-200-different.diff diff-200.diff; rc_of view.json 1
  run_pf --mode start --files "a.sh"
  chk_eq 13 "$RC" "start with no change yet: reads files from --files, exits 13 on a shared file"
  finish_row startnopr 200
  run_pf --mode merge --files "a.sh"
  chk_eq 2 "$RC" "merge with no change found: exits 2"
  finish_row mergenopr
  run_pf --mode start --files "a.sh" --vehicle this
  chk_eq 11 "$RC" "start + --vehicle this: exits 11"
  chk_has "$OUTF" "vehicle=this" "start + --vehicle this: machine line"
  finish_row startthis
}
row_hostile() {
  new_scn hostile; fx list-hostile.json list.json; fx diff-200-different.diff diff-204.diff
  run_pf --mode merge --pr 100
  chk_eq 13 "$RC" "hostile title: still an overlap (exit 13)"
  chk_eq 0 "$(grep -c $'\033' "$OUTF" || true)" "hostile title: no escape byte reaches the output"
  chk_eq 0 "$(grep -c $'\007' "$OUTF" || true)" "hostile title: no bell byte reaches the output"
  local tline tlen
  tline="$(grep '^- "' "$OUTF" | head -n 1)"
  tlen="$(printf '%s' "$tline" | sed -E 's/^- "(.*)" - https.*$/\1/' | awk '{print length($0)}')"
  chk_eq 1 "$(( tlen <= 80 ))" "hostile title: shown title is at most 80 characters ($tlen)"
  chk_eq "SOLEUR_OVERLAP exit=13 prs=204 vehicle=none" "$(tail -n 1 "$OUTF")" "hostile title: the forged machine-line text inside a title does not become the last line"
  finish_row hostile 204
}
row_usage() {
  new_scn usage
  local a
  for a in "--bogus" "--mode bogus" "--pr abc" "--vehicle abc" "--issue x1" "--pr"; do
    # shellcheck disable=SC2086
    run_pf $a
    chk_eq 2 "$RC" "usage: '$a' exits 2"
    chk_has "$OUTF" "I could not check" "usage: '$a' says it could not check"
    finish_row "usage($a)"
  done
}
row_nobase() {
  new_scn nobase; fx list-basic.json list.json
  PF_CWD="$REPO_B"
  run_pf --mode merge --pr 100
  PF_CWD="$REPO"
  chk_eq 2 "$RC" "no starting point (no origin/main): merge mode exits 2"
  chk_has "$OUTF" "I could not check" "no starting point: says it could not check"
  finish_row nobase
}

ALL_ROWS="clear shared vehicle10 vehicle11 dupedit subject_draft generic listfail paginate diffcap diff_unreadable self view_default issue_start start_nopr hostile usage nobase"

run_rows() { # run_rows "<row names>"
  local r
  for r in $1; do "row_$r"; done
}

# ---------------------------------------------------------------------------------------------
echo "=== Arm 1: instrument self-test ==="
# ---------------------------------------------------------------------------------------------
new_scn instr; fx list-basic.json list.json
printf '%s' "$SCN" > "$STUB/fixdir"
run_stub() { # run_stub <args...> -> STUB_RC
  : > "$STUB/argv.log"; : > "$STUB/write.log"; : > "$STUB/unknown.log"
  set +e; PATH="$STUB:$PATH" gh "$@" >/dev/null 2>&1; STUB_RC=$?; set -e
}
run_stub pr list --state open -L 200 --json number,title,url,isDraft,files,headRefName
assert_eq "0" "$STUB_RC" "stub serves the exact list argv"
run_stub pr list --state open -L 100 --json number,title
assert_eq "64" "$STUB_RC" "stub rejects a changed list argv (exit 64)"
assert_eq "1" "$(wc -l < "$STUB/unknown.log" | tr -d ' ')" "stub records the unknown argv"
for w in "pr comment 1 --body hi" "pr edit 1 --title x" "pr close 1" "pr merge 1" "pr review 1" "pr ready 1" "issue comment 1 --body hi" "api repos/{owner}/{repo}/pulls/1 -X PATCH" "api repos/{owner}/{repo}/issues/1/comments -f body=hi"; do
  # shellcheck disable=SC2086
  run_stub $w
  assert_eq "64" "$STUB_RC" "stub refuses the write verb: $w"
  assert_eq "1" "$(wc -l < "$STUB/write.log" | tr -d ' ')" "stub logs the write verb: $w"
done
rc_of list.json 7
run_stub pr list --state open -L 200 --json number,title,url,isDraft,files,headRefName
assert_eq "7" "$STUB_RC" "stub honours a simulated failure code"
run_stub pr diff 12abc
assert_eq "64" "$STUB_RC" "stub rejects a non-numeric diff operand"

# Dispatch cannot be neutered: an assert_eq that must fail has to move FAIL.
( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }
( MODE=quiet; BAD=0; chk_eq a b x; [[ $BAD -eq 1 ]] ) || { printf 'FATAL: chk_eq cannot fail in quiet mode\n' >&2; exit 2; }

# Jargon matcher: fires on every denylisted term, quiet on ordinary words.
jt() { # jt <text> -> hits
  printf '%s\n%s\n' "$1" "SOLEUR_OVERLAP exit=0 prs=none vehicle=none" > "$TMP/jt.out"
  jargon_hits "$TMP/jt.out"
}
for term in "the patch-id matches" "same SHA" "rebase it" "merge-base moved" "to stdout" "see the diff" "a new commit" "still a draft" "the PR is open" "a pull request" "on this branch" "it is unarmed" "see #123" "at HEAD"; do
  assert_eq "1" "$(jt "$term")" "jargon matcher fires on: $term"
done
for ok in "I took a different approach" "merge and release changes" "undo the change" "a good shape for this" "a rollback plan" "SHAPE of the thing" "Upgrade the headline"; do
  assert_eq "0" "$(jt "$ok")" "jargon matcher is quiet on: $ok"
done
# The machine line is the one line excluded from the check.
printf '%s\n%s\n' "Nothing to see." "SOLEUR_OVERLAP exit=12 prs=200 vehicle=none SHA diff" > "$TMP/jt.out"
assert_eq "0" "$(jargon_hits "$TMP/jt.out")" "jargon matcher excludes the machine line only"

# ---------------------------------------------------------------------------------------------
echo "=== Arm 2: static ==="
# ---------------------------------------------------------------------------------------------
if bash -n "$SCRIPT" 2>/dev/null; then ok=1; else ok=0; fi
assert_eq "1" "$ok" "script parses (bash -n)"
CODE="$TMP/code.txt"
grep -vE '^[[:space:]]*#' "$SCRIPT" > "$CODE" || true
assert_eq "0" "$(grep -cE 'gh[[:space:]]+(pr[[:space:]]+)?(comment|edit|close|merge|review|ready|reopen|create|lock)([[:space:]]|$)' "$CODE" || true)" "no gh write verb in the script body"
assert_eq "0" "$(grep -cE 'git[[:space:]]+(push|commit|add|reset|checkout|stash|fetch|pull|merge|rebase|branch)([[:space:]]|$)' "$CODE" || true)" "no git mutating or network verb in the script body"
assert_eq "0" "$(grep -E 'gh[[:space:]]+api' "$CODE" | grep -cE '(-X[[:space:]]|--method|--input|[[:space:]]-f[[:space:]]|[[:space:]]-F[[:space:]])' || true)" "no gh api write flag in the script body"
# Every gh call is one of the four read shapes.
gh_calls="$(grep -E '(^|[^A-Za-z_])gh[[:space:]]+(pr|api|issue|repo|run|auth)' "$CODE" || true)"
assert_eq "0" "$(printf '%s\n' "$gh_calls" | grep -cE 'gh[[:space:]]+(issue|repo|run|auth)' || true)" "gh is only called for pr view / pr list / pr diff / api GET"
assert_eq "0" "$(grep -cE 'sed[[:space:]]+-i|date[[:space:]]+-d|stat[[:space:]]+-c|mapfile|readarray|declare[[:space:]]+-A|\$\{[A-Za-z_]+(,,|\^\^)\}' "$CODE" || true)" "no sed -i, date -d, stat -c, mapfile, associative array or case-mod expansion"
assert_eq "0" "$(grep -cF '[^\n]' "$CODE" || true)" "no [^\\n] in an ERE"
# timeout is only ever used behind the guarded wrapper.
assert_eq "0" "$(grep -E '(^|[^A-Za-z_-])timeout[[:space:]]' "$CODE" | grep -cvE 'command -v|timeout "\$secs"' || true)" "no bare timeout (only the guarded wrapper)"
assert_eq "1" "$(grep -c 'command -v timeout' "$CODE" || true)" "the wrapper checks that timeout exists"
assert_eq "1" "$(grep -c '^set -uo pipefail$' "$CODE" || true)" "set -uo pipefail, deliberately without -e"
assert_eq "0" "$(grep -c 'pr-overlap-preflight' "$REPO_ROOT/plugins/soleur/skills/review/SKILL.md" || true)" "review/SKILL.md does not invoke the preflight (it is wired in one-shot and ship only)"
if command -v shellcheck >/dev/null 2>&1; then
  set +e; shellcheck -S warning "$SCRIPT" >"$TMP/shellcheck.out" 2>&1; rc=$?; set -e
  assert_eq "0" "$rc" "shellcheck -S warning is clean on the script"
else
  echo "  SKIP: shellcheck not installed"; SKIPPED=$((SKIPPED + 1))
fi
# Every mutation point exists exactly once.
for m in samefile firstonly paginate pagefail sharedblock listfail vehicle printid write; do
  assert_eq "1" "$(grep -cF "# mut:$m" "$SCRIPT" || true)" "mutation marker # mut:$m appears exactly once"
done
# The reference doc exists and is plain: no table of internals, and it carries the exit table.
if [[ -f "$REFERENCE" ]]; then
  for t in "exit 0" "exit 10" "exit 11" "exit 12" "exit 13" "exit 2"; do
    assert_eq "1" "$(( $(grep -ciF -- "$t" "$REFERENCE" || true) >= 1 ))" "reference documents $t"
  done
  assert_eq "1" "$(grep -c 'Step 0a.5' "$REFERENCE" || true)" "reference carries the one-shot Step 0a.5 wiring text once"
  assert_eq "1" "$(grep -c 'Phase 6.5' "$REFERENCE" || true)" "reference carries the ship Phase 6.5 wiring text once"
else
  echo "  FAIL: reference doc missing: $REFERENCE"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------------------
echo "=== Arm 3: rows ==="
# ---------------------------------------------------------------------------------------------
MODE=report
run_rows "$ALL_ROWS"
# Order independence: reverse the list so the overlapping change comes FIRST; still reported.
new_scn reversed
jq -c 'reverse' "$FIXTURES/list-basic.json" > "$SCN/list.json"; fx diff-200-different.diff diff-200.diff
run_pf --mode merge --pr 100
assert_eq "13" "$RC" "reversed order: the overlapping change is still reported"
MODE=report; finish_row reversed 200

# ---------------------------------------------------------------------------------------------
echo "=== Arm 4: mutation ==="
# ---------------------------------------------------------------------------------------------
mutate() { # mutate <name> <replacement-line> -> path of mutant script
  local d="$TMP/mut/$1"; mkdir -p "$d"
  MUT_REP="$2" awk -v m="# mut:$1" 'index($0, m) { print ENVIRON["MUT_REP"]; next } { print }' "$SCRIPT" > "$d/pr-overlap-preflight.sh"
  printf '%s' "$d/pr-overlap-preflight.sh"
}
mut_expect_red() { # mut_expect_red <name> <replacement> <rows> <msg>
  local mp bad
  mp="$(mutate "$1" "$2")"
  PF_SCRIPT="$mp"; MODE=quiet; BAD=0
  run_rows "$3"
  bad="$BAD"; MODE=report; PF_SCRIPT="$SCRIPT"
  assert_eq "1" "$(( bad > 0 ))" "$4 (rows red: $bad)"
}

# Identity replacement: the harness is not always-red, and the rows are green on the real script.
orig_line() { grep -F "# mut:$1" "$SCRIPT" | head -n 1; }
mp="$(mutate samefile "$(orig_line samefile)")"
PF_SCRIPT="$mp"; MODE=quiet; BAD=0; run_rows "$ALL_ROWS"; bad="$BAD"; MODE=report; PF_SCRIPT="$SCRIPT"
assert_eq "0" "$bad" "identity mutant: every row is green (the mutation harness is not always-red)"

mut_expect_red samefile 'SAMEFILE_ON=0' "shared dupedit vehicle10" "M1 remove the same-file signal -> shared-file rows red"
mut_expect_red listfail '[ "$rc" -ne 0 ] && LIST_JSON="[]"' "listfail" "M2 a failed list prints no overlap -> the could-not-check row red"
mut_expect_red firstonly 'SCAN_LIMIT=1' "shared" "M3 only the first listed change is examined -> the second-position overlap row red"
mut_expect_red vehicle 'vehicle_is_this() { return 1; }' "vehicle11" "M4 vehicle handling always exit 10 (never 11) -> the this-is-the-vehicle row red"
mut_expect_red printid 'MSG_EDIT="This change makes the same edit as yours (patch-id 0000abc)."' "dupedit" "M5 a patch id in the output -> the jargon assertion red"
mut_expect_red write 'trap '"'"'rm -rf "$WORK"; gh pr comment 1 --body hi'"'"' EXIT' "shared" "M6 any gh write call -> the write-call assertion red"
mut_expect_red paginate 'PAGE_CAP=100000' "paginate" "M7 trust the 100-file cap -> the beyond-the-first-page row red"
mut_expect_red pagefail ': ' "paginate" "M7b a failed re-read treated as clear -> the exit-2 row red"
mut_expect_red sharedblock 'SHARED_ONLY_EXIT=12' "shared" "M8 shared-file-only overlap blocking -> the exit-13 row red"

# A red run must show WHICH scenario failed: the captured streams live under $TMP.
if (( FAIL > 0 )); then
  if [[ -s "$ERRF" ]]; then
    printf -- '--- last stderr\n'; sed 's/^/    /' "$ERRF"
  fi
fi
# Floor set at the measured green count (339); ratchet it with every added assertion.
print_results 339
