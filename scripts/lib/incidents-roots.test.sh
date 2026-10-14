#!/usr/bin/env bash
# Tests for scripts/lib/incidents-roots.sh.
#
# WHY THIS LIB EXISTS AS A SEPARATE, SOURCEABLE FILE.
# scripts/rule-metrics-aggregate.sh collects incident logs from a set of roots.
# Its one testable seam, INCIDENTS_REPO_ROOT, is defined as an EXCLUSIVE override
# ("the caller named the only root that may be read"), which is precisely what
# disables multi-root collection — so the enumeration cannot be exercised through
# it without destroying the narrowing every existing fixture depends on. The
# enumeration therefore lives here as two pure functions that take their input as
# text and arguments, following the scripts/lib/<name>.sh + <name>.test.sh
# precedent (legal-normalise, repo-write-boundary, scratch-root, tweet-eligibility).
#
# THE PROPERTY UNDER TEST, in one sentence: the set of incident roots the
# aggregator reads contains each distinct on-disk directory exactly once, with the
# caller's first argument still first.
#
# Both halves are load-bearing and neither is obvious:
#   - EXACTLY ONCE: `git worktree list` includes the MAIN worktree, which the
#     aggregator's existing block already adds via --git-common-dir. Union without
#     dedupe cats one file twice; counts are a commutative reduce, so the inflation
#     is silent and looks like real data.
#   - FIRST STAYS FIRST: rotation (AGGREGATOR_ROTATE=1) truncates element 0. If
#     enumeration ever prepends or sorts, rotation truncates a SIBLING worktree's
#     live log. That invariant is why dedupe preserves first-seen order rather than
#     sorting, and why there is a dedicated case for it below.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/incidents-roots.sh"

TMP_ROOT=$(mktemp -d -t incidentsroots.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
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
assert_fixture_dir "$TMP_ROOT"

fails=0
passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# --- instrument self-test -------------------------------------------------------
# Drive BOTH helpers once each and require both counters to move. A suite whose
# only gate is a failure counter exits 0 having asserted nothing; this is the
# dispatch axis, and it must run before any real case so a gutted helper cannot
# report a clean sweep. Reports with printf + exit, never through the helpers it
# guards (ADR-193).
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0   # subtract the deliberate self-test failure
SELFTEST_PASSES=$passes

[[ -r "$LIB" ]] || { echo "  FAIL: $LIB not readable (RED expected before implementation)"; echo "0 passed, 1 failed"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

echo "incidents-roots.test.sh"

# --- 1. porcelain parse: every worktree, in order -------------------------------
# Cardinality axis: THREE members, so a parser that stops after the first (or
# returns only the last) is distinguishable from a correct one. Records are
# NUL-terminated (the `-z` shape); entries are separated by an empty record.
# Output is read back with `tr` so the comparison is on a newline-joined string.
out=$(printf '%s\0' \
  "worktree /repo/main" "HEAD abc123" "branch refs/heads/main" "" \
  "worktree /repo/.worktrees/feat-a" "HEAD def456" "branch refs/heads/feat-a" "" \
  "worktree /repo/.worktrees/feat-b" "HEAD 789abc" "detached" "" \
  | incidents_roots_from_porcelain | tr '\0' '\n')
# $(...) strips trailing newlines, so the want has none.
want=$'/repo/main\n/repo/.worktrees/feat-a\n/repo/.worktrees/feat-b'
if [[ "$out" == "$want" ]]; then
  pass "porcelain parse emits every worktree path in input order"
else
  fail "porcelain parse — got '$out' want '$want'"
fi

# --- 2. porcelain parse: only `worktree ` records -------------------------------
# A parser keying on whitespace rather than the record prefix would pick up the
# `branch`/`HEAD` values here.
out=$(printf '%s\0' "worktree /repo/main" "HEAD abc" "branch refs/heads/worktree-ish" "bare" \
  | incidents_roots_from_porcelain | tr '\0' '\n')
if [[ "$out" == '/repo/main' ]]; then
  pass "porcelain parse ignores HEAD/branch/bare records"
else
  fail "porcelain parse non-worktree records — got '$out'"
fi

# --- 3. porcelain parse: empty input is empty output, rc 0 ----------------------
out=$(printf '' | incidents_roots_from_porcelain); rc=$?
if [[ "$rc" -eq 0 && -z "$out" ]]; then
  pass "porcelain parse on empty input: empty output, rc 0"
else
  fail "porcelain parse empty input — rc=$rc out='$out'"
fi

# --- 3b. porcelain parse: a path containing a NEWLINE is ONE root ---------------
# The review probe: under line framing, a worktree at "/repo/x\nworktree /FORGED"
# enumerated /FORGED as a worktree. Under NUL framing the embedded newline is
# just a byte in the path. Asserted as a COUNT of records plus the exact bytes,
# so a parser that splits on \n (two records) and one that drops the record
# (zero) are both distinguishable from correct (one).
evil=$'/repo/x\nworktree /FORGED'
# bash command substitution DROPS NUL bytes ("ignored null byte"), so the record
# count is taken inside the pipeline and the bytes are read back through tr.
nrec=$(printf '%s\0' "worktree $evil" "HEAD abc" "" | incidents_roots_from_porcelain | tr -cd '\0' | wc -c)
out=$(printf '%s\0' "worktree $evil" "HEAD abc" "" | incidents_roots_from_porcelain | tr '\0' '\n')
if [[ "$nrec" -eq 1 && "$out" == "$evil" ]]; then
  pass "porcelain parse keeps a newline-bearing path as ONE record (no forged root)"
else
  fail "porcelain parse newline path — records=$nrec out='$out'"
fi

# --- 4. dedupe: distinct dirs all survive, FIRST-SEEN ORDER PRESERVED -----------
# The order half is the rotation invariant (element 0 is what AGGREGATOR_ROTATE
# truncates). Names are chosen so that a `sort` would REORDER them — "zzz" first,
# "aaa" second — which is what makes this case able to fail.
assert_fixture_dir "$TMP_ROOT"
mkdir -p "$TMP_ROOT/zzz" "$TMP_ROOT/aaa" "$TMP_ROOT/mmm"
out=$(incidents_dedupe_existing_dirs "$TMP_ROOT/zzz" "$TMP_ROOT/aaa" "$TMP_ROOT/mmm" | tr '\0' '\n')
want=$(printf '%s\n%s\n%s' "$TMP_ROOT/zzz" "$TMP_ROOT/aaa" "$TMP_ROOT/mmm")
if [[ "$out" == "$want" ]]; then
  pass "dedupe keeps distinct dirs in first-seen order (does not sort)"
else
  fail "dedupe order — got '$out'"
fi

# --- 5. dedupe: the same path twice collapses ----------------------------------
out=$(incidents_dedupe_existing_dirs "$TMP_ROOT/zzz" "$TMP_ROOT/zzz" | tr '\0' '\n')
if [[ "$out" == "$TMP_ROOT/zzz" ]]; then
  pass "dedupe collapses a repeated path"
else
  fail "dedupe repeated path — got '$out'"
fi

# --- 6. dedupe: two DIFFERENT paths naming one inode collapse ------------------
# This is the real defect. `git worktree list` yields the main worktree by its own
# path while the aggregator's existing block derives the same directory from
# --git-common-dir; the two strings differ, the inode does not. A string-keyed
# dedupe passes cases 4 and 5 and fails only here.
assert_fixture_dir "$TMP_ROOT"
ln -s "$TMP_ROOT/zzz" "$TMP_ROOT/zzz-alias"
out=$(incidents_dedupe_existing_dirs "$TMP_ROOT/zzz" "$TMP_ROOT/zzz-alias" | tr '\0' '\n')
if [[ "$out" == "$TMP_ROOT/zzz" ]]; then
  pass "dedupe collapses two paths that resolve to one inode (keeps the first)"
else
  fail "dedupe inode-alias — got '$out' (string-keyed dedupe would emit both)"
fi

# --- 7. dedupe: a non-existent dir is dropped ----------------------------------
out=$(incidents_dedupe_existing_dirs "$TMP_ROOT/zzz" "$TMP_ROOT/does-not-exist" | tr '\0' '\n')
if [[ "$out" == "$TMP_ROOT/zzz" ]]; then
  pass "dedupe drops a path that does not exist"
else
  fail "dedupe missing dir — got '$out'"
fi

# --- 8. dedupe: an UNREADABLE dir does not abort the caller --------------------
# The aggregator runs under `set -euo pipefail`. Widening the root set makes
# another user's worktree reachable for the first time, so an EACCES here must not
# take the whole aggregation down. Skipped when running as root, which can read it
# regardless — a silent pass there would be a false green.
assert_fixture_dir "$TMP_ROOT"
mkdir -p "$TMP_ROOT/locked"
chmod 000 "$TMP_ROOT/locked"
if [[ "$(id -u)" -eq 0 ]]; then
  pass "dedupe unreadable dir — SKIPPED (running as root; mode 000 is not enforced)"
else
  out=$(incidents_dedupe_existing_dirs "$TMP_ROOT/zzz" "$TMP_ROOT/locked" "$TMP_ROOT/aaa" | tr '\0' '\n'); rc=$?
  # The locked dir IS emitted (stat -L succeeds on a mode-000 dir); readability
  # is the consumer's decision, and both consumers now say so loudly.
  if [[ "$rc" -eq 0 && "$out" == *"$TMP_ROOT/zzz"* && "$out" == *"$TMP_ROOT/aaa"* && "$out" == *"$TMP_ROOT/locked"* ]]; then
    pass "dedupe survives an unreadable dir, emits it, and still returns the readable ones"
  else
    fail "dedupe unreadable dir — rc=$rc out='$out'"
  fi
fi
chmod 755 "$TMP_ROOT/locked" 2>/dev/null || true

# --- 9. dedupe: no arguments is empty output, rc 0 -----------------------------
out=$(incidents_dedupe_existing_dirs); rc=$?
if [[ "$rc" -eq 0 && -z "$out" ]]; then
  pass "dedupe with no arguments: empty output, rc 0"
else
  fail "dedupe no args — rc=$rc out='$out'"
fi

# --- 10. stage 2 keeps NUL framing: a newline-bearing dir is ONE root ---------
# The review escape: stage 1 (porcelain) was NUL-safe and stage 2 (dedupe)
# emitted newlines, so a dir named "x<newline>/FORGED" re-split downstream.
evil_dir="$TMP_ROOT/x"$'\n'"FORGED"
mkdir -p "$evil_dir"
nrec=$(incidents_dedupe_existing_dirs "$evil_dir" | tr -cd '\0' | wc -c)
if [[ "$nrec" -eq 1 ]]; then
  pass "dedupe emits a newline-bearing dir as ONE NUL-terminated record"
else
  fail "dedupe re-split a newline path — records=$nrec"
fi

# --- 11. the composition: repo root first, worktrees appended, deduped ----------
# A real git repo with one worktree; the main worktree appears via BOTH the
# repo-root argument and `git worktree list`, so exactly-once is exercised.
GR="$TMP_ROOT/gitrepo"; mkdir -p "$GR" && git -C "$GR" init -q -b main 2>/dev/null \
  && git -C "$GR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed \
  && git -C "$GR" worktree add -q "$TMP_ROOT/gitwt" -b wt >/dev/null 2>&1 \
  && mkdir -p "$GR/.claude" "$TMP_ROOT/gitwt/.claude"
out=$(incidents_enumerate_log_roots "$GR" | tr '\0' '\n')
first=$(printf '%s\n' "$out" | head -1); nroots=$(printf '%s\n' "$out" | grep -c .)
if [[ "$first" == "$GR/.claude" && "$nroots" -eq 2 ]]; then
  pass "composition: repo root first, sibling worktree appended, main counted exactly once"
else
  fail "composition — first='$first' roots=$nroots out='$out'"
fi

# --- anti-vacuity floor --------------------------------------------------------
# Counts REAL cases (total passes minus the one self-test pass). Reported with
# printf + exit rather than through fail(), so an edit that guts fail() cannot
# suppress the floor itself.
# SELFTEST_PASSES is a LITERAL here, not the variable bound after the self-test:
# guard-vacuity-floor.test.sh slices the floor plus its CONTIGUOUS assignments into
# a mutant, and a binding 130 lines up is unbound there (measured: CONSTRUCTION, not
# FIRES). The self-test above asserts passes == 1, so the literal is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=12
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
[[ "$fails" -eq 0 ]] || exit 1
