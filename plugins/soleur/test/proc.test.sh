#!/usr/bin/env bash
# Tests for plugins/soleur/scripts/lib/proc.sh.
#
# Run via:  bash plugins/soleur/test/proc.test.sh
#
# Auto-discovered by scripts/test-all.sh's `plugins/soleur/test/*.test.sh` glob.
# It is NOT registered by hand and MUST NOT be — a second registration would
# double-run it, and T-AC5 below asserts the runner registers it exactly once.
#
# NOTHING HERE SIGNALS A PROCESS IT DID NOT CREATE. The classification arms run
# against a SYNTHESIZED procfs with PROC_SH_DRY_RUN=1. The two arms that really
# signal (T3, T-FAILED) spawn their own `setsid sleep` inside a fresh mktemp
# sandbox and scope the worktree boundary to that sandbox, so no other process
# on the machine can be selected.
#
# WHY THE ASSERTION FLOOR AT THE BOTTOM IS LOAD-BEARING: the first revision of
# this file had none, and neutering `pass()`/`fail()` to no-ops produced
# `Total: 0 pass: 0 FAIL: 0` and exit 0 — CI green having asserted nothing. A
# battery that only mutates the SUT can never detect that, because it observes
# the SUT THROUGH these helpers.

set -uo pipefail

# scripts/test-all.sh and run-registered-suites.sh default TMPDIR=/var/tmp, but a
# DIRECT invocation of this suite — the documented inner loop while editing
# proc.sh — inherits the bare /tmp, a machine-global 4 GiB tmpfs shared by every
# parallel worktree. Without this the verdicts become a function of another
# session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/../scripts/lib/proc.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONTENTION_LIB="$REPO_ROOT/scripts/lib/test-contention.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  pass: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# Harness positive control. The assertion floor at the bottom catches a
# disabled `pass()` (the count collapses), but it CANNOT catch a disabled
# `fail()` on its own: PASS still climbs to its full value, the floor is
# satisfied, and the suite simply loses the ability to go red. Measured — with
# only the floor, neutering `fail()` gave `Total: 49 pass: 49 FAIL: 0`, rc=0.
#
# So both counters are exercised once, here, before anything else runs, and the
# result is checked at exit. The deliberate FAIL is rolled back so it does not
# pollute the real tally; the `(EXPECTED)` marker mirrors the house form used by
# scripts/tenant-dpa-register-guard-unit.
HARNESS_OK=0
_harness_selfcheck() {
  local p0="$PASS" f0="$FAIL"
  pass "harness self-test: pass() increments"
  fail "harness self-test: fail() increments (EXPECTED)"
  if (( PASS == p0 + 1 && FAIL == f0 + 1 )); then
    HARNESS_OK=1
  fi
  PASS="$p0"
  FAIL="$f0"
}

ROOTS=()
SPAWNED=()
cleanup() {
  local p r
  for p in ${SPAWNED[@]+"${SPAWNED[@]}"}; do
    kill -KILL "$p" 2>/dev/null || true
  done
  for r in ${ROOTS[@]+"${ROOTS[@]}"}; do
    rm -rf "$r" 2>/dev/null || true
  done
}
trap cleanup EXIT

if [[ ! -f "$HELPER" ]]; then
  echo "ERROR: $HELPER does not exist" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Synthesized procfs fixture (mirrors scripts/test-contention.test.sh).
#
# comm is deliberately "(te) st)" — it contains BOTH a space and an INNER
# close-paren, so a parser that splits on whitespace, or strips through the
# FIRST ') ' rather than the last, mis-indexes and reddens. That is the exact
# defect in the /proc recipe currently recommended in git-worktree/SKILL.md
# (`awk '{print $4}'`), and M5 pins it.
#
# An EMPTY cwd argument omits the `cwd` symlink, reproducing the real
# <unreadable> case. argv is variadic so a wrapper shape (`timeout 600 bash
# suite.sh`) can be expressed — without that, the wrapper class is untestable.
# ---------------------------------------------------------------------------
make_fake_proc() {
  local root="$1" pid="$2" cwd="$3" ppid="$4" pgrp="$5"; shift 5
  mkdir -p "$root/$pid" || return 1
  local a
  : > "$root/$pid/cmdline" || return 1
  for a in "$@"; do printf '%s\0' "$a" >> "$root/$pid/cmdline" || return 1; done
  local filler="S $ppid $pgrp" i
  for ((i = 4; i <= 19; i++)); do filler+=" 0"; done
  printf '%s (te) st) %s 0 0\n' "$pid" "$filler" > "$root/$pid/stat" || return 1
  [[ -n "$cwd" ]] && ln -sfn "$cwd" "$root/$pid/cwd"
  return 0
}

# A harness that fails to SET UP must abort, never continue — otherwise the next
# case runs against the previous case's state and reports a confident wrong
# verdict about the SUT.
FP_ROOT="$(mktemp -d -t proc-test.XXXXXXXX)" || { echo "ERROR: mktemp failed" >&2; exit 2; }
ROOTS+=("$FP_ROOT")

WT="$FP_ROOT/wt"
FAKE_PROC="$FP_ROOT/proc"
mkdir -p "$WT/sub" "${WT}-two" "$FAKE_PROC" || { echo "ERROR: fixture mkdir failed" >&2; exit 2; }

# A symlink to the worktree root. This is the FAR SIDE of the canonicalization
# transform, and without a fixture here every path in the suite is already
# canonical — so deleting _proc_canon's body changes nothing and the mutation
# survives, while proc.sh's own comment claims the positive control catches it.
# It does not; only a fixture on this side can.
LINKED="$FP_ROOT/wt-link"
ln -sfn "$WT" "$LINKED" || { echo "ERROR: symlink fixture failed" >&2; exit 2; }

# The F1 carrier: a directory whose NAME contains a newline plus a forged row.
# If the scan->signal channel ever carries paths again, this fabricates a
# `signal` row for pid 31337 and the suite must catch it.
EVIL_DIR="$FP_ROOT/$(printf 'evil\nsignal\t31337\t/pwned')"
mkdir -p "$EVIL_DIR" || { echo "ERROR: evil fixture mkdir failed" >&2; exit 2; }

SELF_PID=9999   # pgrp 7777
# 9999 <- 9998 <- 9997 : a THREE-deep chain. 9998 shares self's pgrp (excluded
# twice over), 9997 does NOT — which is what makes M2 meaningful: under a
# $$+$PPID-only exclusion, 9997 becomes visible.
make_fake_proc "$FAKE_PROC" 9999 "$WT"       9998 7777 bash scripts/test-all.sh || exit 2
make_fake_proc "$FAKE_PROC" 9998 "$WT"       9997 7777 bash scripts/test-all.sh || exit 2
make_fake_proc "$FAKE_PROC" 9997 "$WT"       1    6666 bash scripts/test-all.sh || exit 2
# Owned by THIS worktree.
make_fake_proc "$FAKE_PROC" 1001 "$WT"       1    5000 bash scripts/test-all.sh || exit 2
# Sibling worktree at <ROOT>-two — the M1 prefix-boundary fixture.
make_fake_proc "$FAKE_PROC" 1002 "${WT}-two" 1    5001 bash scripts/test-all.sh || exit 2
# Merely MENTIONS the pattern (`grep -rn test-all.sh …`) — the M4 fixture.
make_fake_proc "$FAKE_PROC" 1003 "$WT"       1    5002 grep test-all.sh || exit 2
# Shares the invoker's process group — the M3 / T7 fixture.
make_fake_proc "$FAKE_PROC" 1004 "$WT"       1    7777 bash scripts/test-all.sh || exit 2
# No cwd symlink → <unreadable> — the T8 fixture.
make_fake_proc "$FAKE_PROC" 1005 ""          1    5003 bash scripts/test-all.sh || exit 2
# A SECOND owned process, in a SUBdirectory. Cardinality: with only one owned
# fixture, `killed=1` cannot distinguish "signals mine" from "signals exactly
# one thing", and a regression killing only the first of five ships green.
make_fake_proc "$FAKE_PROC" 1006 "$WT/sub"   1    5004 bash scripts/test-all.sh || exit 2
# A SECOND shell from the allowlist. The set has 8 members; fixturing one makes
# `bash) ;;` an undetectable narrowing.
make_fake_proc "$FAKE_PROC" 1007 "$WT"       1    5005 sh scripts/test-all.sh || exit 2
# A WRAPPER shape. `timeout N bash <suite>` is a real launch form in this repo
# (test-contention.sh documents it); without the wrapper step it is invisible.
make_fake_proc "$FAKE_PROC" 1008 "$WT"       1    5006 timeout 600 bash scripts/test-all.sh || exit 2
# A DELETED cwd. The kernel appends " (deleted)" with rc 0; that is a
# could-not-establish state, not a path, so it must be refused.
make_fake_proc "$FAKE_PROC" 1009 "$WT/gone (deleted)" 1 5007 bash scripts/test-all.sh || exit 2
# The F1 injection carrier.
make_fake_proc "$FAKE_PROC" 1010 "$EVIL_DIR" 1    5008 bash scripts/test-all.sh || exit 2
# A process whose cwd reaches the worktree THROUGH a symlink. Owned, but only
# once canonicalized — the M9 fixture.
make_fake_proc "$FAKE_PROC" 1011 "$LINKED/sub" 1  5010 bash scripts/test-all.sh || exit 2
# pid `0` — matches the `[0-9]*` glob, and `kill -TERM 0` signals the caller's
# whole process group. The M7 fixture.
make_fake_proc "$FAKE_PROC" 0    "$WT"       1    5009 bash scripts/test-all.sh || exit 2

# The one line every mutation must move.
#   excluded by ancestry: 9997/9998/9999.
#   signalled: 1001, 1006 (subdir), 1007 (sh), 1008 (wrapper), 1011 (symlink).
#   refused: 1002 (sibling), 1005 (<unreadable>), 1009 (deleted), 1010 (evil).
#   skipped: 1004 (pgid).  unmatched: 1003.  rejected before scan: 0.
#   scanned counts the 14 valid pids (pid 0 fails the numeric guard).
#
# `late_refusals` is part of the oracle, not decoration. The signal site
# RE-VERIFIES ownership before signalling, which is correct defence-in-depth
# and has an awkward consequence for measurement: flipping the classification
# fork (M6) is then re-caught downstream and the counts do not move, so the
# fork reads as non-load-bearing. Counting the re-verification's own refusals
# separates the two enforcement points, so each is pinned independently.
BASELINE_COUNTS='killed=5 failed=0 refused=4 skipped_same_pgroup=1 scanned=14 mode=dry-run late_refusals=0'

run_fake() {
  local helper="$1"; shift
  env PROC_SH_ROOT="$FAKE_PROC" \
      PROC_SH_SELF_PID="$SELF_PID" \
      PROC_SH_WORKTREE="$WT" \
      PROC_SH_DRY_RUN=1 \
      bash "$helper" "$@"
}

# Same fixture, but the boundary is reached through a SYMLINK. Used as the
# oracle for the root-side canonicalization mutation, which is invisible to a
# run whose root is already canonical.
run_linked() {
  local helper="$1"; shift
  env PROC_SH_ROOT="$FAKE_PROC" \
      PROC_SH_SELF_PID="$SELF_PID" \
      PROC_SH_WORKTREE="$LINKED" \
      PROC_SH_DRY_RUN=1 \
      bash "$helper" "$@"
}

_signature() {
  awk '/^killed=/ { c = $0 }
       /reason=ownership-changed-before-signal/ { n++ }
       END { if (c == "") exit 0; printf "%s late_refusals=%d\n", c, n + 0 }'
}
counts_of()        { run_fake   "$1" kill_mine test-all.sh 2>/dev/null | _signature; }
counts_of_linked() { run_linked "$1" kill_mine test-all.sh 2>/dev/null | _signature; }

echo "== proc.sh =="
_harness_selfcheck

# --- AC1: sources cleanly, defines both verbs, executes nothing -------------
out=$(bash -c "source '$HELPER' && declare -F list_runs kill_mine" 2>&1)
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'list_runs' <<<"$out" && grep -q 'kill_mine' <<<"$out"; then
  pass "AC1: sources cleanly and defines list_runs + kill_mine"
else
  fail "AC1: source/declare failed (rc=$rc): $out"
fi

# --- AC8: the kill site signals an INDIVIDUAL pid ---------------------------
# Counting kill SITES is not enough: `kill -"$sig" -"$pid"` keeps the count at 1
# while converting the survivor into a PROCESS-GROUP signal — the exact form
# proc.sh's own comment forbids. Assert the TARGET's shape, not the tally.
code_only=$(grep -vE '^[[:space:]]*#' "$HELPER")
n=$(grep -cE '(^|[^_[:alnum:]])kill[[:space:]]+-' <<<"$code_only")
if [[ "$n" == "1" ]]; then
  pass "AC8a: exactly one kill invocation in code"
else
  fail "AC8a: expected exactly 1 kill invocation in code, found $n"
fi
if grep -qE '(^|[^_[:alnum:]])kill[[:space:]]+-"\$sig"[[:space:]]+"\$pid"' <<<"$code_only"; then
  pass "AC8b: the kill target is a bare \"\$pid\" (not a process group)"
else
  fail "AC8b: kill target is not the expected bare \"\$pid\" form"
fi
if grep -qE '(^|[^_[:alnum:]])(p?kill|killall)[[:space:]]+[^|;&]*-[0-9-]' <<<"$code_only"; then
  fail "AC8c: a kill/pkill/killall targets a negative or group pid"
else
  pass "AC8c: no kill targets a negative pid or process group"
fi
if grep -qE '(^|[^_[:alnum:]])(pkill|killall)([[:space:]]|$)' <<<"$code_only"; then
  fail "AC8d: pkill/killall present — the unbounded forms this file replaces"
else
  pass "AC8d: no pkill/killall in code"
fi

# --- T1: neither verb self-matches, even though the pattern is in our argv --
out=$(run_fake "$HELPER" list_runs test-all.sh 2>/dev/null)
if grep -qE "^(9999|9998|9997)	" <<<"$out"; then
  fail "T1: self/ancestor pid reported by list_runs"
else
  pass "T1: no self or ancestor pid reported (pattern present in own argv)"
fi
[[ -d "/proc/$$" ]] && pass "T1b: invoking shell survived list_runs" || fail "T1b: invoking shell died"

# --- Classification arms ----------------------------------------------------
check_row() { # $1=pid $2=expected-class $3=label
  if grep -qE "^$1	$2	" <<<"$out"; then pass "$3"; else fail "$3 — row for pid $1 not '$2': $(grep -E "^$1	" <<<"$out" || echo MISSING)"; fi
}
check_row 1002 foreign "T2: sibling worktree at <ROOT>-two classified foreign (prefix boundary)"
check_row 1005 foreign "T8: <unreadable> cwd refused AND printed"
check_row 1004 skipped "T7: same-pgroup target reported as skipped, not absorbed into silence"
check_row 1006 mine    "T-CARD: a SECOND owned process, in a subdirectory, is selected"
# NOTE: no backticks in these labels. Inside a double-quoted string a backtick
# is COMMAND SUBSTITUTION, so a label reading "timeout 600 bash <suite>" in
# backticks was executed as a command and the label arrived empty — the same
# trap work/SKILL.md documents for commit messages, one layer down.
check_row 1007 mine    "T-SH: a run under sh (not just bash) is selected"
check_row 1008 mine    "T-WRAP: 'timeout 600 bash <suite>' is selected (wrapper argv[0])"
check_row 1011 mine    "T-SYMCWD: a cwd reaching the worktree through a symlink is owned"
check_row 1009 foreign "T-DEL: a cwd reported as ' (deleted)' is refused, not string-matched"
check_row 1010 foreign "T-EVIL: the newline-cwd carrier itself is refused"

if grep -qE "^1003	" <<<"$out"; then
  fail "T5: process that merely mentions the pattern was selected"
else
  pass "T5: process merely mentioning the pattern not selected (argv position)"
fi
if grep -qE "^0	" <<<"$out"; then
  fail "T-PID0: pid 0 was classified — kill -TERM 0 signals the caller's group"
else
  pass "T-PID0: pid 0 rejected by the numeric guard, never classified"
fi

# --- T-INJECT: the F1 regression guard (the reason the channel carries no paths)
kout=$(run_fake "$HELPER" kill_mine test-all.sh 2>/dev/null)
# Anchor on the SIGNAL-LINE shape, not on the bare digits: the sanitized
# display of the carrier's own cwd legitimately contains the forged pid's
# digits (that string IS the directory name), so `grep 31337` would fail on a
# correct implementation. What must never exist is a signal/would-signal line
# whose pid is the forged one.
if grep -qE '^(would-signal|signalled) pid=31337( |$)' <<<"$kout"; then
  fail "T-INJECT: a forged row from a cwd containing a newline reached the signal site"
else
  pass "T-INJECT: cwd containing a newline cannot forge a classification row"
fi
# The carrier's path must still be reported, with its control characters
# neutralized — a refusal you cannot see is indistinguishable from a match that
# never happened, but a raw newline in the output would re-create the ambiguity
# on the operator's terminal.
if grep -qE '^refused   pid=1010 cwd=.*evil\?signal\?31337' <<<"$kout"; then
  pass "T-INJECT-C: the carrier's cwd is printed with control characters neutralized"
else
  fail "T-INJECT-C: carrier cwd not printed sanitized: $(grep -E 'pid=1010' <<<"$kout" || echo MISSING)"
fi
if grep -qE '^(would-signal|signalled) pid=(-|[^0-9])' <<<"$kout"; then
  fail "T-INJECT-B: a non-numeric or negative pid reached the signal site"
else
  pass "T-INJECT-B: every signalled pid is numeric"
fi

# --- T-baseline / T-D6 ------------------------------------------------------
got=$(counts_of "$HELPER")
if [[ "$got" == "$BASELINE_COUNTS" ]]; then
  pass "T-baseline: counters are '$BASELINE_COUNTS'"
else
  fail "T-baseline: expected '$BASELINE_COUNTS', got '$got'"
fi
if run_fake "$HELPER" kill_mine no-such-pattern-xyz 2>/dev/null \
   | grep -qE '^killed=0 failed=0 refused=0 skipped_same_pgroup=0 scanned=14 mode=dry-run$'; then
  pass "T-D6: counter line printed even when nothing matched"
else
  fail "T-D6: counter line missing/wrong on a zero-match run"
fi

# --- T-SLASH: a pattern that can never match fails loudly, not silently -----
sout=$(run_fake "$HELPER" kill_mine scripts/test-all.sh 2>&1); src=$?
if [[ $src -ne 0 ]] && grep -q "can never match" <<<"$sout"; then
  pass "T-SLASH: a pattern containing '/' is rejected with a usage error"
else
  fail "T-SLASH: expected loud rejection, got rc=$src: $sout"
fi

# --- T9: no ownership boundary => fail loudly, signal nothing ---------------
NOGIT="$(mktemp -d -t proc-nogit.XXXXXXXX)" || exit 2
ROOTS+=("$NOGIT")
out9=$(cd "$NOGIT" && env -u PROC_SH_WORKTREE -u GIT_DIR -u GIT_WORK_TREE \
  PROC_SH_ROOT="$FAKE_PROC" PROC_SH_SELF_PID="$SELF_PID" \
  bash "$HELPER" kill_mine test-all.sh 2>&1); rc9=$?
if [[ $rc9 -ne 0 ]] && ! grep -qE '^killed=[1-9]' <<<"$out9"; then
  pass "T9: outside a git repo with no PROC_SH_WORKTREE, fails loudly and signals nothing"
else
  fail "T9: expected loud non-zero failure, got rc=$rc9: $out9"
fi

# --- T-ROOT: a boundary of '/' or a relative path is refused ---------------
for badroot in "/" "relative/path"; do
  bout=$(env PROC_SH_ROOT="$FAKE_PROC" PROC_SH_SELF_PID="$SELF_PID" \
             PROC_SH_WORKTREE="$badroot" PROC_SH_DRY_RUN=1 \
             bash "$HELPER" kill_mine test-all.sh 2>&1); brc=$?
  if [[ $brc -ne 0 ]] && ! grep -qE '^killed=[1-9]' <<<"$bout"; then
    pass "T-ROOT: boundary '$badroot' refused"
  else
    fail "T-ROOT: boundary '$badroot' accepted (rc=$brc): $bout"
  fi
done

# --- T-CANON: a symlinked worktree root still matches ----------------------
# The far side of the ROOT-side canonicalization transform (M10's oracle).
lout=$(counts_of_linked "$HELPER")
if [[ "$lout" == "$BASELINE_COUNTS" ]]; then
  pass "T-CANON: a symlinked worktree root canonicalizes and still selects its own runs"
else
  fail "T-CANON: symlinked root changed the verdict: '$lout'"
fi

# --- AC7: mirrored primitives pinned against drift, over CODE only ---------
# A whole-file presence grep is satisfied by a comment quoting the historical
# form, so the pin is applied to comment-stripped source.
if [[ -r "$CONTENTION_LIB" ]]; then
  drift=0
  contention_code=$(grep -vE '^[[:space:]]*#' "$CONTENTION_LIB")
  for anchor in 'rest="${line##*'"'"') '"'"'}"' 'guard < 64'; do
    grep -qF -- "$anchor" <<<"$contention_code" || { fail "AC7: anchor absent from test-contention.sh CODE: $anchor"; drift=1; }
    grep -qF -- "$anchor" <<<"$code_only" || { fail "AC7: anchor absent from proc.sh CODE: $anchor"; drift=1; }
  done
  [[ "$drift" == "0" ]] && pass "AC7: mirrored /proc primitives match test-contention.sh anchors (code, not comments)"
else
  fail "AC7: $CONTENTION_LIB not readable"
fi

# --- AC11: this suite issues no kill against a pid it did not create --------
own_code=$(grep -vE '^[[:space:]]*#' "${BASH_SOURCE[0]}")
# Two anchoring decisions, both load-bearing, both learned by getting them
# wrong here first:
#   (a) COMMAND POSITION, not bare presence. This file legitimately contains
#       the strings `pkill` and `killall` inside the AC8c/AC8d grep patterns
#       above; a bare-token check flags those and fails on a correct suite.
#   (b) BRACKETS in this pattern, so the pattern cannot match ITSELF. This is
#       the one place the bracket trick is the right tool — a grep over source
#       is exactly what it was invented for. (It is a category error against a
#       /proc walk, which is why proc.sh does not use it.)
if grep -qE '^[[:space:]]*(p[k]ill|kill[a]ll)[[:space:]]' <<<"$own_code"; then
  fail "AC11a: this suite invokes pkill/killall"
else
  pass "AC11a: this suite invokes no pkill/killall"
fi
if grep -qE '(^|[^_[:alnum:]])kill[[:space:]]+-[A-Za-z0-9]+[[:space:]]+"\$(p|SLEEP_PID)' <<<"$own_code"; then
  pass "AC11b: every kill in this suite targets a variable holding a pid it spawned"
else
  fail "AC11b: a kill in this suite does not target a spawned pid variable"
fi

# ---------------------------------------------------------------------------
# T3 / T-FAILED — the two arms that really signal.
#
# Blast radius is zero by construction: the boundary is a fresh mktemp sandbox,
# so no process outside it can classify as `signal`. setsid is load-bearing —
# without a new process group the spawned sleep shares the invoker's pgid and
# is correctly SKIPPED by the guard under test.
# ---------------------------------------------------------------------------
spawn_victim() { # $1 = sandbox; echoes pid or empty
  local sb="$1" p=""
  (cd "$sb" && exec setsid sleep 300) >/dev/null 2>&1 &
  local _
  for _ in $(seq 1 60); do
    p=$(env PROC_SH_WORKTREE="$sb" bash "$HELPER" list_runs sleep 2>/dev/null \
      | awk -F'\t' '$2 == "mine" { print $1; exit }')
    [[ -n "$p" ]] && break
    sleep 0.1
  done
  printf '%s' "$p"
}

SANDBOX="$(mktemp -d -t proc-real.XXXXXXXX)" || exit 2
ROOTS+=("$SANDBOX")
SLEEP_PID=$(spawn_victim "$SANDBOX")
if [[ -z "$SLEEP_PID" ]]; then
  fail "T3: fixture error — spawned sleep never appeared in list_runs (cannot test the kill path)"
else
  SPAWNED+=("$SLEEP_PID")
  real=$(env PROC_SH_WORKTREE="$SANDBOX" bash "$HELPER" kill_mine sleep 2>/dev/null | grep -E '^killed=' | tail -1)
  if [[ "$real" == killed=1\ failed=0\ * && "$real" == *mode=live* ]]; then
    pass "T3: positive control — worktree-owned process signalled (killed=1, mode=live)"
  else
    fail "T3: expected 'killed=1 failed=0 … mode=live', got '$real'"
  fi
  gone=0
  for _ in $(seq 1 40); do
    kill -0 "$SLEEP_PID" 2>/dev/null || { gone=1; break; }
    sleep 0.1
  done
  [[ "$gone" == "1" ]] && pass "T3b: the signalled process actually terminated (real kill path works)" \
                       || fail "T3b: process $SLEEP_PID survived kill_mine"
fi
[[ -d "/proc/$$" ]] && pass "T3c: invoking shell survived kill_mine" || fail "T3c: invoking shell died"

# --- T-DRYSAFE: an unrecognized PROC_SH_DRY_RUN value must NOT kill ---------
# The previous form matched only the literal `1`, so PROC_SH_DRY_RUN=true
# performed a REAL kill on an operator who had asked for a rehearsal.
SB2="$(mktemp -d -t proc-dry.XXXXXXXX)" || exit 2
ROOTS+=("$SB2")
V2=$(spawn_victim "$SB2")
if [[ -z "$V2" ]]; then
  fail "T-DRYSAFE: fixture error — victim never appeared"
else
  SPAWNED+=("$V2")
  d_out=$(env PROC_SH_WORKTREE="$SB2" PROC_SH_DRY_RUN=true bash "$HELPER" kill_mine sleep 2>/dev/null | grep -E '^killed=' | tail -1)
  if kill -0 "$V2" 2>/dev/null; then
    pass "T-DRYSAFE: PROC_SH_DRY_RUN=true is treated as a dry run — victim survived"
  else
    fail "T-DRYSAFE: PROC_SH_DRY_RUN=true performed a REAL kill"
  fi
  [[ "$d_out" == *mode=dry-run* ]] && pass "T-DRYSAFE-B: the counter line reports mode=dry-run" \
                                   || fail "T-DRYSAFE-B: mode not reported as dry-run: '$d_out'"
  kill -KILL "$V2" 2>/dev/null || true
fi

# --- T-FAILED: a signal that is not delivered is NOT counted as killed ------
SB3="$(mktemp -d -t proc-fail.XXXXXXXX)" || exit 2
ROOTS+=("$SB3")
V3=$(spawn_victim "$SB3")
if [[ -z "$V3" ]]; then
  fail "T-FAILED: fixture error — victim never appeared"
else
  SPAWNED+=("$V3")
  f_out=$(env PROC_SH_WORKTREE="$SB3" bash "$HELPER" kill_mine sleep NOSUCHSIG 2>/dev/null | grep -E '^killed=' | tail -1)
  if [[ "$f_out" == killed=0\ failed=1\ * ]]; then
    pass "T-FAILED: an undeliverable signal counts as failed=1, not killed=1"
  else
    fail "T-FAILED: expected 'killed=0 failed=1 …', got '$f_out'"
  fi
  kill -0 "$V3" 2>/dev/null && pass "T-FAILED-B: the victim survived a failed signal" \
                            || fail "T-FAILED-B: victim died despite an invalid signal"
  kill -KILL "$V3" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Mutation battery.
#
# `mutate` sets a GLOBAL rather than echoing the path. The previous form was
# `t=$(mutate …)`, a COMMAND SUBSTITUTION — so its `fail` ran in a SUBSHELL and
# the FAIL counter never moved in the parent: the suite printed
# `FAIL: mutation did not land` and still exited 0. That is the exact subshell
# defect work/SKILL.md documents, committed three lines from the rule.
# ---------------------------------------------------------------------------
MUT_DIR="$(mktemp -d -t proc-mut.XXXXXXXX)" || exit 2
ROOTS+=("$MUT_DIR")
cp "$HELPER" "$MUT_DIR/pristine.sh" || { echo "ERROR: mutation backup failed" >&2; exit 2; }

MUT_TARGET=""
mutate() { # sets MUT_TARGET; returns non-zero (and FAILs, in the PARENT) if the edit did not land
  local name="$1" old="$2" new="$3"
  MUT_TARGET=""
  local target="$MUT_DIR/$name.sh"
  cp "$MUT_DIR/pristine.sh" "$target" || { fail "$name: sandbox copy failed"; return 1; }
  if ! OLD="$old" NEW="$new" python3 - "$target" <<'PY'
import os, sys
p = sys.argv[1]
old, new = os.environ["OLD"], os.environ["NEW"]
s = open(p).read()
n = s.count(old)
# Exactly one occurrence, or the anchor is ambiguous and the mutation could
# land on a comment instead of the construct it names.
assert n == 1, f"anchor occurs {n} times (want exactly 1): {old!r}"
open(p, "w").write(s.replace(old, new, 1))
PY
  then
    fail "$name: mutation anchor missing or ambiguous — the row did not run"
    return 1
  fi
  if diff -q "$MUT_DIR/pristine.sh" "$target" >/dev/null 2>&1; then
    fail "$name: mutation did not land (files identical)"
    return 1
  fi
  MUT_TARGET="$target"
  return 0
}

expect_red() { # $1=name $2=why [$3=oracle fn, default counts_of]
  local name="$1" why="$2" oracle="${3:-counts_of}" got
  got=$("$oracle" "$MUT_TARGET")
  if [[ -z "$got" ]]; then
    # A mutant that cannot RUN is not a detected mutation — it is a broken file,
    # and crediting it as RED would let any syntax error masquerade as coverage.
    fail "$name: mutant emitted NO counter line (unrunnable file, not a detection)"
  elif [[ "$got" == "$BASELINE_COUNTS" ]]; then
    fail "$name SURVIVED — $why (counters unchanged: '$got')"
  else
    pass "$name: drove RED as required — $why"
  fi
}

mutate M1 '"$cwd" == "$root" || "$cwd" == "$root"/*' '"$cwd" == "$root" || "$cwd" == "$root"*' \
  && expect_red M1 "sibling worktree <ROOT>-two must not be selected when the / boundary is dropped"
mutate M2 'guard < 64' 'guard < 2' \
  && expect_red M2 "a 3-deep wrapper must still be excluded; \$\$ + \$PPID alone is insufficient (pins R1)"
mutate M3 '"$pgrp" == "$self_pgrp"' '"$pgrp" == "__never__"' \
  && expect_red M3 "a same-pgid fork of proc.sh must not be selected"
mutate M4 '    (( seen_wrapper )) || return 1' '    :' \
  && expect_red M4 "a process merely mentioning the pattern must not be selected — the strict no-wrapper rule is what excludes 'grep -rn test-all.sh'"
mutate M5 '  rest="${line##*'"'"') '"'"'}"
  awk -v i="$idx" '"'"'{print $i}'"'"' <<<"$rest"' \
  '  awk -v i="$(( idx + 2 ))" '"'"'{print $i}'"'"' <<<"$line"' \
  && expect_red M5 "a comm containing a space must still resolve its ppid (pins R4)"
mutate M6 "printf 'refuse\\t%s\\n' \"\$pid\"" "printf 'signal\\t%s\\n' \"\$pid\"" \
  && expect_red M6 "the signal/refuse classification fork must be load-bearing"
mutate M7 '    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue' '    :' \
  && expect_red M7 "pid 0 must never be classified — kill -TERM 0 signals the caller's group"
mutate M8 "[[ \"\$cwd\" == *' (deleted)' ]] && return 1" ':' \
  && expect_red M8 "a cwd reported as deleted must be refused, not string-matched"
mutate M9 '_proc_canon "$cwd"' 'printf "%s" "$cwd"' \
  && expect_red M9 "a cwd reaching the worktree through a symlink must still be owned (process-side canonicalization)"
# Evaluated against the SYMLINKED-root oracle on purpose: with an
# already-canonical root this mutation changes nothing, so the default oracle
# would report it SURVIVED and the fix would be to weaken the guard rather than
# to measure it properly.
mutate M10 'root=$(_proc_canon "$PROC_SH_WORKTREE")' 'root="$PROC_SH_WORKTREE"' \
  && expect_red M10 "a symlinked ownership boundary must canonicalize (root-side)" counts_of_linked

# ---------------------------------------------------------------------------
# AC5 — auto-discovery, not hand-registration.
# ---------------------------------------------------------------------------
if git -C "$REPO_ROOT" diff --stat origin/main...HEAD -- scripts/test-all.sh 2>/dev/null | grep -q .; then
  fail "AC5: scripts/test-all.sh was modified — this suite must be auto-globbed, not hand-registered"
else
  pass "AC5: scripts/test-all.sh untouched (suite is auto-globbed)"
fi

# ---------------------------------------------------------------------------
# ASSERTION FLOOR. Absolute, and ratcheted UP by hand when arms are added —
# never derived from a variable this file computes, because a floor that
# descends with the thing it guards is not a floor.
#
# Without this, neutering pass()/fail() to no-ops yields `Total: 0` and exit 0.
# ---------------------------------------------------------------------------
# Set to the FULL current count from a green run, and ratcheted up by hand when
# arms are added. Any slack between the floor and the real count is budget for
# a future edit to delete assertions unnoticed, so there is none.
MIN_ASSERTIONS=49
TOTAL=$((PASS + FAIL))
echo
echo "  Total: $TOTAL  pass: $PASS  FAIL: $FAIL"
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "  FAIL: assertion floor — ran $TOTAL, expected at least $MIN_ASSERTIONS." >&2
  echo "        Assertions were skipped or the reporting helpers were disabled." >&2
  exit 1
fi
if [[ "$HARNESS_OK" != "1" ]]; then
  echo "  FAIL: harness self-test did not observe BOTH counters move." >&2
  echo "        pass() or fail() is disabled; this suite cannot report a failure." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
