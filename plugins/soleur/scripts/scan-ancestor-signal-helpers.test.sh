#!/usr/bin/env bash
#
# Tests for plugins/soleur/scripts/scan-ancestor-signal-helpers.py -- the inventory scan and
# shrink-only ratchet for shell test suites that contain a signal helper (an ancestor walk that
# signals, a signal to the parent, an all-process signal; targeted group and name-pattern signals
# are listed only). Guard 2 of the plan
# knowledge-base/project/plans/2026-10-10-chore-pid-namespace-guard-for-signal-helper-mutants-plan.md
#
# WHY NOTHING HERE SENDS A SIGNAL. The suite works on tracked DATA files (.txt, under
# plugins/soleur/test/fixtures/ancestor-signal/) that are passed to the scanner as explicit PATHs, and on a
# throwaway repository whose members are copies of those data files. The scanner only reads text.
# Walker-shaped text therefore never appears as a source line of this suite (the scan would find it in
# itself), and the walk over the whole tree is delegated to the scanner (the live row); this file keeps
# no tree walk of its own. The nonce walker data file that sits in the same fixture directory belongs to
# another suite and is never read or run here.
#
# Run: bash plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh

# shellcheck disable=SC2016  # single-quoted strings in this file are literal shell text under test, not expansions
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
SCAN="$DIR/scan-ancestor-signal-helpers.py"
BASELINE="$DIR/ancestor-signal-helpers.baseline.txt"
FIX="$REPO_ROOT/plugins/soleur/test/fixtures/ancestor-signal"

# Arms the git-location tripwire (a hook-exported GIT_DIR would redirect the fixture repository) and
# provides git_fixture_env for the throwaway repository.
# shellcheck source=/dev/null
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" || { echo "FATAL: could not source git-fixture-env.sh" >&2; exit 2; }

# Canonical fixture-dir guard (BYTE-IDENTICAL to plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh compares every copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

TMP=""
cleanup_suite() {
  [[ -n "${TMP:-}" ]] || return 0
  assert_fixture_dir "$TMP"
  rm -rf "$TMP"
}
trap cleanup_suite EXIT

TMP="$(mktemp -d "$TMPDIR/ancsig-scan.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$TMP"

passes=0
fails=0
cases=0
skipped=0
PLANNED_TOTAL=126

pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1"; }

# check <label> <command...>: one case; the counter moves at the call site, the verdict is separate.
check() {
  local label="$1"; shift
  cases=$((cases + 1))
  if "$@"; then pass "$label"; else fail "$label"; fi
}

# --- instrument self-test: drive pass, fail and check once each, require each counter to move exactly as
# --- expected, and that check turns a failing command into a fail and a passing one into a pass ---
selftest_instrument() {
  local p0="$passes" f0="$fails" c0="$cases" rc=0
  pass "selftest" >/dev/null
  fail "selftest" >/dev/null
  if [[ "$passes" -ne $((p0 + 1)) || "$fails" -ne $((f0 + 1)) ]]; then rc=1; fi
  check "selftest-true" true >/dev/null
  check "selftest-false" false >/dev/null
  if [[ "$passes" -ne $((p0 + 2)) || "$fails" -ne $((f0 + 2)) || "$cases" -ne $((c0 + 2)) ]]; then rc=1; fi
  passes="$p0"; fails="$f0"; cases="$c0"
  return "$rc"
}
selftest_instrument || { printf '[FATAL] instrument self-test: pass, fail and check did not each move their counters as expected\n' >&2; exit 1; }

# --- preconditions: a missing scanner is RED, a missing python3 is a visible SKIP ---
if ! command -v python3 >/dev/null 2>&1; then
  printf 'SKIP scan suite: python3 not found (the scan needs python3; nothing was asserted)\n'
  exit 0
fi
if [[ ! -f "$SCAN" ]]; then
  printf '[FATAL] scanner missing at %s\n' "$SCAN" >&2
  exit 1
fi
if [[ ! -d "$FIX" ]]; then
  printf '[FATAL] fixture directory missing at %s\n' "$FIX" >&2
  exit 1
fi

# --- helpers ---
T=$'\t'
SCAN_CWD="$FIX"
RC=0
run_scan() { # run_scan <args...> -> RC, $TMP/out, $TMP/err ; the scanner runs from SCAN_CWD
  assert_fixture_dir "$TMP"
  ( cd "$SCAN_CWD" && timeout 60 python3 -I "$SCAN" "$@" ) >"$TMP/out" 2>"$TMP/err"
  RC=$?
}
ncls() { awk -F'\t' -v c="$1" '$1==c{n++} END{print n+0}' "$TMP/out"; }
nall() { awk -F'\t' 'NF>=4{n++} END{print n+0}' "$TMP/out"; }
has_out() { grep -cE -- "$1" "$TMP/out" >/dev/null; }
has_err() { grep -cE -- "$1" "$TMP/err" >/dev/null; }
BL="$TMP/bl.txt"
bl_new() { assert_fixture_dir "$TMP"; printf '# test baseline\n' > "$BL"; }
bl_row() { assert_fixture_dir "$TMP"; printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$BL"; }
SUMMARY_RE='^ancestor-signal scan: [0-9]+ files, [0-9]+ findings, [0-9]+ baselined, [0-9]+ new, [0-9]+ stale, [0-9]+ unbounded, [0-9]+ skipped$'

W_UNB="top=\$p; p=\$(awk '{print \$4}' \"/proc/\$p/stat\")"
W_BND="p=\$(awk '{print \$4}' \"/proc/\$p/stat\" 2>/dev/null)"
P_SITE='[ -f "$FX/x" ] && kill -9 "$PPID"'
P_TWO1='kill -9 "$PPID"'

# list_of <fixture-file>: the findings of one data file, every class, one line each
list_of() { run_scan --list "$1"; }

# ============================================================================================
# B. Detector classes on fixtures (list mode)
# ============================================================================================
list_of walker-bounded.txt
check "B1 bounded walker: one W, bounded=yes (S5 shape)" has_out "^W${T}yes${T}walker-bounded.txt${T}"
check "B1b bounded walker: exactly one finding and rc 0" test "$(nall)" -eq 1 -a "$RC" -eq 0

list_of walker-unbounded.txt
check "B2 unbounded walker: one W, bounded=no" has_out "^W${T}no${T}walker-unbounded.txt${T}"

list_of walker-ps-cursor.txt
check "B2b a cursor written with ps -o ppid= is a W" has_out "^W${T}no${T}walker-ps-cursor.txt${T}"
list_of walker-ppid-field-cursor.txt
check "B2c a cursor reading the PPid status field is a W" has_out "^W${T}no${T}walker-ppid-field-cursor.txt${T}"

list_of walker-comment-bound.txt
check "B3 a bound token only in comments reads bounded=no" has_out "^W${T}no${T}walker-comment-bound.txt${T}"

list_of walker-trailing-comment-bound.txt
check "B3b a bound token only in a trailing comment reads bounded=no" has_out "^W${T}no${T}walker-trailing-comment-bound.txt${T}"

list_of walker-echo-bound.txt
check "B4 a bound token only in echo and printf reads bounded=no" has_out "^W${T}no${T}walker-echo-bound.txt${T}"

for form in neq dbl-eq sgl-eq ne eq lt loop-cond; do
  list_of "bound-$form.txt"
  check "B5 bound form $form reads bounded=yes" has_out "^W${T}yes${T}bound-$form.txt${T}"
done
for form in n z regex-only; do
  list_of "bound-$form.txt"
  check "B5b a presence, emptiness or numeric-validation test ($form) is not a comparison: bounded=no" has_out "^W${T}no${T}bound-$form.txt${T}"
done
list_of bound-no-exit.txt
check "B6 a comparison with no exit/break/return reads bounded=no" has_out "^W${T}no${T}bound-no-exit.txt${T}"
list_of bound-no-comparator.txt
check "B7 the token without a comparison reads bounded=no" has_out "^W${T}no${T}bound-no-comparator.txt${T}"

# window edges: one fixture per edge
list_of edge-bound-above-15.txt
check "B8 bound token 15 lines above the cursor: bounded=yes" has_out "^W${T}yes${T}edge-bound-above-15.txt${T}"
list_of edge-bound-above-16.txt
check "B8 bound token 16 lines above the cursor: bounded=no" has_out "^W${T}no${T}edge-bound-above-16.txt${T}"
list_of edge-bound-below-3.txt
check "B8 bound token 3 lines below the cursor: bounded=yes" has_out "^W${T}yes${T}edge-bound-below-3.txt${T}"
list_of edge-bound-below-4.txt
check "B8 bound token 4 lines below the cursor: bounded=no" has_out "^W${T}no${T}edge-bound-below-4.txt${T}"
list_of edge-kill-below-40.txt
check "B9 kill 40 lines below the cursor is a W" test "$(ncls W)" -eq 1
list_of edge-kill-below-41.txt
check "B9 kill 41 lines below the cursor is no finding" test "$(nall)" -eq 0
list_of edge-kill-above-40.txt
check "B9 kill 40 lines above the cursor is a W" test "$(ncls W)" -eq 1
list_of edge-kill-above-41.txt
check "B9 kill 41 lines above the cursor is no finding" test "$(nall)" -eq 0
list_of edge-derived-20.txt
check "B10 parent variable assigned 20 lines before the kill is a P" test "$(ncls P)" -eq 1
list_of edge-derived-21.txt
check "B10 parent variable assigned 21 lines before the kill is no finding" test "$(nall)" -eq 0

# classes
list_of parent-direct.txt
check "B11 direct parent signals: three P" test "$(ncls P)" -eq 3 -a "$(nall)" -eq 3
list_of parent-derived.txt
check "B12 derived parent signal: one P, on the kill line" test "$(ncls P)" -eq 1 -a "$(nall)" -eq 1
check "B12b derived parent signal reports the kill line text" has_out "^P${T}-${T}parent-derived.txt${T}kill -9 \"\\\$shim\" 2>/dev/null\$"
list_of group-all.txt
check "B13 all-process and own-group signals: five G" test "$(ncls G)" -eq 5 -a "$(nall)" -eq 5
list_of listed-targeted-and-pattern.txt
check "B14 targeted group and name-pattern signals: six L, nothing else" test "$(ncls L)" -eq 6 -a "$(nall)" -eq 6

# must-PASS inputs, one fixture each so one mutant cannot hide behind another
for f in pass-comment pass-quoted pass-kill0 pass-kill-l pass-plain-pid; do
  list_of "$f.txt"
  check "B15 must-pass $f: no finding" test "$(nall)" -eq 0 -a "$RC" -eq 0
done

# ============================================================================================
# C. Baseline semantics (gated runs on explicit PATHs)
# ============================================================================================
bl_new
run_scan --baseline "$BL" walker-bounded.txt
check "C1 a W not in the baseline is NEW: rc 1" test "$RC" -eq 1
check "C1b the NEW line names the file and the class W" has_out "^NEW W walker-bounded.txt:[0-9]+: "
check "C1c a red verdict ends with the remedy footer" has_out "^ancestor-signal scan: remedy:"
check "C1d a red verdict never prints CLEAN" test "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = n

bl_new; bl_row walker-bounded.txt W "$W_BND"
run_scan --baseline "$BL" walker-bounded.txt
check "C2 a baselined bounded W is clean: rc 0 and the CLEAN literal" test "$RC" -eq 0 -a "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = y
check "C2b the summary line has the documented shape and counts" has_out "^ancestor-signal scan: 1 files, 1 findings, 1 baselined, 0 new, 0 stale, 0 unbounded, 0 skipped\$"
check "C2c the summary line matches the full format" has_out "$SUMMARY_RE"
check "C2d a clean verdict carries no remedy footer" test "$(has_out '^ancestor-signal scan: remedy:' && echo y || echo n)" = n

bl_new; bl_row walker-unbounded.txt W "$W_UNB"
run_scan --baseline "$BL" walker-unbounded.txt
check "C3 an unbounded W cannot be baselined: rc 1" test "$RC" -eq 1
check "C3b the UNBOUNDED line names the file" has_out "^UNBOUNDED W walker-unbounded.txt:[0-9]+: "
check "C3c the summary counts one unbounded and one baselined" has_out ", 1 baselined, 0 new, 0 stale, 1 unbounded, "

bl_new; bl_row two-sites.txt P "$P_TWO1"
run_scan --baseline "$BL" two-sites.txt
check "C4 two sites, the first baselined: rc 1" test "$RC" -eq 1
check "C4b the SECOND site is the one named NEW" has_out "^NEW P two-sites.txt:4: "
check "C4c the first site is not reported" test "$(has_out '^NEW P two-sites.txt:2: ' && echo y || echo n)" = n

bl_new
run_scan --baseline "$BL" site-base.txt
check "C5 deleting a baseline row of a live site is NEW: rc 1" test "$RC" -eq 1 -a "$(has_out '^NEW P site-base.txt:[0-9]+: ' && echo y || echo n)" = y

bl_new; bl_row site-base.txt P "$P_SITE"; bl_row site-base.txt P 'kill -9 "$GONE"'
run_scan --baseline "$BL" site-base.txt
check "C6 a baseline row with no live line is STALE: rc 1" test "$RC" -eq 1 -a "$(has_out '^STALE P site-base.txt: ' && echo y || echo n)" = y
check "C6b the summary counts one stale" has_out ", 1 baselined, 0 new, 1 stale, 0 unbounded, "

bl_new; bl_row dup-parent.txt P "$P_SITE"
run_scan --baseline "$BL" dup-parent.txt
check "C7 two identical lines against one row: one NEW (multiset)" test "$RC" -eq 1 -a "$(has_out ', 1 baselined, 1 new, 0 stale, ' && echo y || echo n)" = y
bl_new; bl_row dup-parent.txt P "$P_SITE"; bl_row dup-parent.txt P "$P_SITE"
run_scan --baseline "$BL" dup-parent.txt
check "C7b two identical lines against two rows: clean" test "$RC" -eq 0
bl_new; bl_row dup-parent.txt P "$P_SITE"; bl_row dup-parent.txt P "$P_SITE"; bl_row dup-parent.txt P "$P_SITE"
run_scan --baseline "$BL" dup-parent.txt
check "C7c two identical lines against three rows: one STALE" test "$RC" -eq 1 -a "$(has_out ', 2 baselined, 0 new, 1 stale, ' && echo y || echo n)" = y

bl_new; bl_row site-shifted.txt P "$P_SITE"
run_scan --baseline "$BL" site-shifted.txt
check "C8 a baselined line shifted by blank lines stays clean (content-keyed)" test "$RC" -eq 0
bl_new; bl_row site-reindented.txt P "$P_SITE"
run_scan --baseline "$BL" site-reindented.txt
check "C8b a baselined line re-indented and re-spaced stays clean (whitespace collapsed)" test "$RC" -eq 0
assert_fixture_dir "$TMP"; mkdir -p "$TMP/dp"; cp "$FIX/site-base.txt" "$TMP/dp/renamed.txt"
bl_new; bl_row site-base.txt P "$P_SITE"
SCAN_CWD="$TMP/dp" run_scan --baseline "$BL" renamed.txt
check "C8c the same content under a different path reads NEW (path-keyed)" test "$RC" -eq 1 -a "$(has_out '^NEW P renamed.txt:[0-9]+: ' && echo y || echo n)" = y
check "C8d only baseline rows of the scanned paths are judged: no STALE for the other path" has_out ", 0 baselined, 1 new, 0 stale, "

bl_new
run_scan --baseline "$BL" listed-targeted-and-pattern.txt
check "C9 class L is never gated: rc 0 and CLEAN against an empty baseline" test "$RC" -eq 0 -a "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = y

run_scan walker-bounded.txt
check "C10 without a baseline the scan is list-only: rc 0 and the notice" test "$RC" -eq 0 -a "$(has_out 'no baseline: listing only' && echo y || echo n)" = y
check "C10b list-only mode never prints CLEAN" test "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = n

# --write-baseline: refused with PATHs, a round trip over a tracked population, and the admissibility refusals
run_scan --write-baseline "$TMP/wb0.txt" parent-direct.txt
check "C11e --write-baseline with a PATH is refused: rc 2, nothing written" test "$RC" -eq 2 -a ! -e "$TMP/wb0.txt"
WBR="$TMP/wbrepo"
assert_fixture_dir "$WBR"
mkdir -p "$WBR"
cp "$FIX/parent-direct.txt" "$WBR/a.test.sh"
cp "$FIX/group-all.txt" "$WBR/b.test.sh"
cp "$FIX/walker-bounded.txt" "$WBR/c.test.sh"
( git_fixture_env "$WBR" && git -C "$WBR" init -q && git -C "$WBR" add -A && git -C "$WBR" commit -q -m seed ) >/dev/null 2>&1
run_scan --root "$WBR" --write-baseline "$TMP/wb.txt"
check "C11 --write-baseline succeeds: rc 0" test "$RC" -eq 0
check "C11b it wrote nine rows (3 P, 5 G, 1 W) beside its comment header" test "$(grep -cEv '^(#|$)' "$TMP/wb.txt")" -eq 9
check "C11c the header states that bounded=yes is lexical" test "$(grep -ci 'lexical' "$TMP/wb.txt")" -ge 1
run_scan --root "$WBR" --baseline "$TMP/wb.txt"
check "C11d the written baseline reads clean against the same files" test "$RC" -eq 0 -a "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = y
WBR2="$TMP/wbrepo2"
assert_fixture_dir "$WBR2"
mkdir -p "$WBR2"
cp "$FIX/walker-unbounded.txt" "$WBR2/u.test.sh"
( git_fixture_env "$WBR2" && git -C "$WBR2" init -q && git -C "$WBR2" add -A && git -C "$WBR2" commit -q -m seed ) >/dev/null 2>&1
run_scan --root "$WBR2" --write-baseline "$TMP/wb2.txt"
check "C12 --write-baseline refuses an unbounded W: rc 1, no file" test "$RC" -eq 1 -a ! -e "$TMP/wb2.txt"
check "C12b the refusal says why (UNBOUNDED)" has_out "UNBOUNDED"
WBR3="$TMP/wbrepo3"
assert_fixture_dir "$WBR3"
mkdir -p "$WBR3"
cp "$FIX/parent-direct.txt" "$WBR3/a.test.sh"
ln -s a.test.sh "$WBR3/l.test.sh"
( git_fixture_env "$WBR3" && git -C "$WBR3" init -q && git -C "$WBR3" add -A && git -C "$WBR3" commit -q -m seed ) >/dev/null 2>&1
run_scan --root "$WBR3" --write-baseline "$TMP/wb3.txt"
check "C11f --write-baseline with a skipped member is refused: rc 3, no file" test "$RC" -eq 3 -a ! -e "$TMP/wb3.txt"

# --list scoped to one path names only that path
run_scan --list parent-direct.txt group-all.txt
check "C13 --list PATH scopes the listing to the given paths" test "$(awk -F'\t' 'NF>=4 && $3!="parent-direct.txt" && $3!="group-all.txt"{n++} END{print n+0}' "$TMP/out")" -eq 0 -a "$(nall)" -eq 8

# ============================================================================================
# D. UNRESOLVED (rc 3) is never a clean report
# ============================================================================================
R="$TMP/repo"
assert_fixture_dir "$R"
mkdir -p "$R/sub/deep"
cp "$FIX/walker-unbounded.txt" "$R/a.test.sh"
cp "$FIX/parent-direct.txt" "$R/sub/test-x.sh"
cp "$FIX/pass-comment.txt" "$R/sub/deep/b.test.sh"
cp "$FIX/walker-unbounded.txt" "$R/notes.txt"
ln -s a.test.sh "$R/link.test.sh"
BADNAME=$'bad\xff.test.sh'
NONUTF=1
if cp "$FIX/pass-plain-pid.txt" "$R/$BADNAME" 2>/dev/null; then :; else NONUTF=0; fi

E="$TMP/empty"
assert_fixture_dir "$E"
mkdir -p "$E"
cp "$FIX/walker-unbounded.txt" "$E/notes.txt"
( git_fixture_env "$E" && git -C "$E" init -q && git -C "$E" add -A && git -C "$E" commit -q -m seed ) >/dev/null 2>&1

run_scan --root "$E"
check "D1 a repository with no matching suites: rc 3 UNRESOLVED" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
check "D1b UNRESOLVED prints no CLEAN" test "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = n
N="$TMP/no-such-dir"
assert_fixture_dir "$N"
run_scan --root "$N" --baseline "$FIX/site-base.txt"
check "D2 a root git cannot enter (the listing fails): rc 3 UNRESOLVED" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
run_scan --root "$WBR3" --baseline "$TMP/wb.txt"
check "D8 a skipped (symlinked) member under a baseline gate: rc 3 UNRESOLVED naming the skip, never CLEAN" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED: 1 listed member.*skipped' && echo y || echo n)" = y -a "$(has_out '^ancestor-signal scan: CLEAN$' && echo y || echo n)" = n
run_scan --baseline "$TMP/does-not-exist.txt" site-base.txt
check "D3 an unreadable (missing) baseline: rc 3 UNRESOLVED" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
run_scan --baseline "$TMP" site-base.txt
check "D4 a baseline that is a directory: rc 3 UNRESOLVED" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
assert_fixture_dir "$TMP"
printf 'only-one-field\n' > "$TMP/bad-bl.txt"
run_scan --baseline "$TMP/bad-bl.txt" site-base.txt
check "D5 a malformed baseline row: rc 3 UNRESOLVED" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
run_scan --list no-such-file.txt
check "D6 an explicit PATH that does not exist: rc 3 UNRESOLVED" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
if [[ -w /dev/full ]]; then
  ( cd "$FIX" && timeout 60 python3 -I "$SCAN" --list site-base.txt ) >/dev/full 2>"$TMP/err"
  RC=$?
  check "D7 an exception inside main (stdout is full): rc 3, never a traceback-only rc 1" test "$RC" -eq 3 -a "$(has_err 'UNRESOLVED' && echo y || echo n)" = y
else
  skipped=$((skipped + 1)); printf 'SKIP D7: /dev/full is not writable here\n'
fi

# ============================================================================================
# E. Producer, environment and reading model (throwaway repository, hostile inputs)
# ============================================================================================
( git_fixture_env "$R" && git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -q -m seed ) >/dev/null 2>&1
SCAN_CWD="$TMP"
run_scan --list --root "$R"
cp "$TMP/out" "$TMP/out.plain"
check "E1 the producer reaches *.test.sh anywhere (a W in a.test.sh)" has_out "^W${T}no${T}a.test.sh${T}"
check "E1b the producer reaches test-*.sh in a subdirectory (P in sub/test-x.sh)" test "$(awk -F'\t' '$1=="P" && $3=="sub/test-x.sh"{n++} END{print n+0}' "$TMP/out")" -eq 3
check "E2 a tracked .txt copy of a walker is not scanned" test "$(has_out "${T}notes.txt${T}" && echo y || echo n)" = n
if [[ "$NONUTF" -eq 1 ]]; then EXPECT_FILES=4; else EXPECT_FILES=3; fi
check "E3 files read: the benign suites count, the symlink does not" has_out " ${EXPECT_FILES} files, "
check "E3b a symlinked member is counted skipped, not read" has_out " 1 skipped"
if [[ "$NONUTF" -eq 0 ]]; then
  skipped=$((skipped + 1)); printf 'SKIP E4: this filesystem refused a non-UTF-8 file name\n'
else
  check "E4 a non-UTF-8 path is in the population (not silently dropped)" has_out " ${EXPECT_FILES} files, "
fi
( cd "$TMP" && env GIT_DIR=/nonexistent/gitdir GIT_INDEX_FILE=/nonexistent/index GIT_WORK_TREE=/nonexistent timeout 60 python3 -I "$SCAN" --list --root "$R" ) >"$TMP/out" 2>"$TMP/err"
RC=$?
check "E5 bogus GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE do not change the population" test "$RC" -eq 0 && cmp -s "$TMP/out" "$TMP/out.plain"
check "E5b the same listing byte for byte" cmp -s "$TMP/out" "$TMP/out.plain"

assert_fixture_dir "$TMP"
head -c 102400 /dev/zero | tr '\0' 'a' > "$TMP/big.txt"; printf '\n' >> "$TMP/big.txt"
SCAN_CWD="$TMP"
run_scan --list big.txt
check "E6 a 100 KB single line: no hang, no finding, rc 0" test "$RC" -eq 0 -a "$(nall)" -eq 0
check "E6b the overlong line is counted" has_out "overlong lines: 1"
{ head -c 102400 /dev/zero | tr '\0' 'a'; printf ' kill'; printf '\n'; } > "$TMP/big-kill.txt"
run_scan --list big-kill.txt
check "E7 an overlong line that carries a signal verb is still reported (G, fail closed)" test "$RC" -eq 0 -a "$(ncls G)" -eq 1

assert_fixture_dir "$TMP"
head -c 3000000 /dev/zero | tr '\0' 'a' > "$TMP/huge.txt"
run_scan --list huge.txt
check "E7b a file over 2 MB is skipped, not read" test "$RC" -eq 0 -a "$(nall)" -eq 0 -a "$(has_out ' 0 files, ' && echo y || echo n)" = y -a "$(has_out ' 1 skipped' && echo y || echo n)" = y

printf 'kill -9 "$PPID"\r\n' > "$TMP/crlf.txt"
run_scan --list crlf.txt
check "E8 a CRLF line is read without its carriage return" has_out "^P${T}-${T}crlf.txt${T}kill -9 \"\\\$PPID\"\$"
printf 'a\xe2\x80\xa8b\x0b\x0c\nkill -9 "$PPID"\n' > "$TMP/seps.txt"
bl_new
run_scan --baseline "$BL" seps.txt
check "E9 lines split on newline only (U+2028, VT, FF do not shift the line number)" has_out "^NEW P seps.txt:2: "

# ============================================================================================
# F. Live row: the whole tree, the committed baseline (the walk is the scanner's)
# ============================================================================================
SCAN_CWD="$REPO_ROOT"
T0="${EPOCHREALTIME:-0}"
run_scan --root "$REPO_ROOT" --baseline "$BASELINE"
T1="${EPOCHREALTIME:-0}"
cp "$TMP/out" "$TMP/out.live"
LIVE_RC="$RC"
LIVE_US=0
if [[ "$T0" != "0" ]]; then LIVE_US=$(( ${T1/./} - ${T0/./} )); fi
printf 'scan live run: %s ms (target under 5000, probe cap 15000)\n' "$((LIVE_US / 1000))"
check "F1 live scan with the committed baseline: rc 0" test "$LIVE_RC" -eq 0
check "F2 live scan: 0 new, 0 stale, 0 unbounded" has_out ", 0 new, 0 stale, 0 unbounded, "
check "F3 live scan prints the CLEAN literal the discoverability probe matches" has_out "^ancestor-signal scan: CLEAN\$"
LIVE_FILES="$(sed -n 's/^ancestor-signal scan: \([0-9][0-9]*\) files, .*/\1/p' "$TMP/out.live")"
check "F4 population floor: at least 600 files read" test "${LIVE_FILES:-0}" -ge 600
check "F5 root set covers .claude" has_out "^ancestor-signal scan: roots: (.* )?\.claude( |\$)"
for root in apps plugins scripts tests; do
  check "F5 root set covers $root" has_out "^ancestor-signal scan: roots: (.* )?$root( |\$)"
done
check "F6 live run well inside the 15 s probe cap" test "$((LIVE_US / 1000))" -lt 15000
run_scan --list --root "$REPO_ROOT"
check "F7 the S5 helper is found as W bounded=yes" has_out "^W${T}yes${T}plugins/soleur/scripts/resolve-regenerable-conflicts\.test\.sh${T}"
check "F7b the roadmap-reconcile walker is found as W bounded=yes" has_out "^W${T}yes${T}plugins/soleur/test/roadmap-reconcile\.test\.sh${T}"
check "F7c no walker anywhere in the tree reads bounded=no" test "$(awk -F'\t' '$1=="W" && $2=="no"{n++} END{print n+0}' "$TMP/out")" -eq 0
check "F8 the listed-only class L is part of the listing" test "$(ncls L)" -ge 1
check "F9 this suite and the scanner are not findings of their own" test "$(awk -F'\t' '$3 ~ /scan-ancestor-signal-helpers/{n++} END{print n+0}' "$TMP/out")" -eq 0
BL_ROWS="$(grep -cEv '^(#|$)' "$BASELINE")"
check "F10 the committed baseline has rows and at least the two known walkers (F7 and F7b name them)" test "${BL_ROWS:-0}" -ge 1 -a "$(awk -F'\t' '$2=="W"{n++} END{print n+0}' "$BASELINE")" -ge 2

# Row 18: the original roadmap-reconcile walker must read unbounded, the bounded edit bounded
SCAN_CWD="$FIX"
list_of roadmap-walker-original.txt
check "G1 the original roadmap-reconcile walker reads bounded=no" has_out "^W${T}no${T}roadmap-walker-original.txt${T}"
list_of roadmap-walker-fixed.txt
check "G2 the bounded roadmap-reconcile walker reads bounded=yes" has_out "^W${T}yes${T}roadmap-walker-fixed.txt${T}"

# ============================================================================================
# H. Reading gaps closed after review (one fixture per shape)
# ============================================================================================
SCAN_CWD="$FIX"
list_of q-cursor.txt
check "H1 a double-quoted cursor substitution still reads W" has_out "^W${T}no${T}q-cursor.txt${T}"
list_of path-kill.txt
check "H2 kill invoked by absolute path is a P" has_out "^P${T}-${T}path-kill.txt${T}"
list_of prefix-env.txt
check "H3 kill behind env and an assignment prefix: two P" test "$(ncls P)" -eq 2
list_of prefix-timeout.txt
check "H4 kill behind timeout with an option is a P" has_out "^P${T}-${T}prefix-timeout.txt${T}"
list_of body-sh-c.txt
check "H5 a signal inside sh -c '...' is a P" has_out "^P${T}-${T}body-sh-c.txt${T}"
list_of body-trap.txt
check "H6 a signal inside trap '...' is a G" has_out "^G${T}-${T}body-trap.txt${T}"
list_of negated-derived.txt
check "H7 a negated derived parent variable (kill -9 -\$up) is a P" has_out "^P${T}-${T}negated-derived.txt${T}"
list_of ppid-upper.txt
check "H8 ps with the uppercase PPID header is a P" has_out "^P${T}-${T}ppid-upper.txt${T}"
awk 'BEGIN{for(i=0;i<60000;i++)print "p=$PPID"; for(i=0;i<60000;i++)print "kill $x"}' > "$TMP/stress.txt"
run_scan --list "$TMP/stress.txt"
check "H9 many parent assignments times many kills finish inside the 60 s cap (no quadratic stall)" test "$RC" -eq 0

# ============================================================================================
# Anti-vacuity and accounting (direct printf + exit, never through fail())
# ============================================================================================
if [[ "$cases" -lt 124 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s cases ran, floor is 124\n' "$cases" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '[FATAL] accounting: %s passed + %s failed != %s cases (verdicts were discarded)\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
if [[ $((cases + skipped)) -ne "$PLANNED_TOTAL" ]]; then
  printf '[FATAL] accounting: %s cases + %s skipped != planned total %s (a row was deleted or silently skipped)\n' "$cases" "$skipped" "$PLANNED_TOTAL" >&2
  exit 1
fi

printf '\n%s passed, %s failed (%s cases, %s skipped, planned %s)\n' "$passes" "$fails" "$cases" "$skipped" "$PLANNED_TOTAL"
[[ "$fails" -eq 0 ]]
