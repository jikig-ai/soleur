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
# against a SYNTHESIZED procfs (the scripts/test-contention.test.sh fixture
# pattern) with PROC_SH_DRY_RUN=1, so no `kill` is ever issued against a pid
# that merely happens to exist. The one arm that really signals (T3) spawns its
# own `setsid sleep` inside a fresh mktemp sandbox and scopes the worktree
# boundary to that sandbox, so no other process on the machine can be selected.

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
# /proc/<pid>/stat: field 1 = pid, field 2 = comm (parenthesized), field 3 =
# state, field 4 = ppid, field 5 = pgrp. After stripping through the LAST ') ',
# ppid is field 2 and pgrp is field 3.
#
# comm is deliberately "(te) st)" — it contains BOTH a space and an INNER
# close-paren, so a parser that splits on whitespace, or strips through the
# FIRST ') ' rather than the last, mis-indexes and reddens. That is the exact
# defect in the /proc recipe currently recommended in git-worktree/SKILL.md
# (`awk '{print $4}'`), and M5 below pins it.
#
# An EMPTY cwd argument omits the `cwd` symlink, reproducing the real
# <unreadable> case (readlink fails; the lib substitutes the literal).
# ---------------------------------------------------------------------------
make_fake_proc() {
  local root="$1" pid="$2" cwd="$3" argv0="$4" tok="$5" ppid="$6" pgrp="$7"
  mkdir -p "$root/$pid" || return 1
  # NUL-separated argv, exactly as the kernel presents it.
  printf '%s\0%s\0' "$argv0" "$tok" > "$root/$pid/cmdline" || return 1
  # Filler fields 4..19 so the layout matches a real stat line.
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
mkdir -p "$WT" "${WT}-two" "$FAKE_PROC" || { echo "ERROR: fixture mkdir failed" >&2; exit 2; }

SELF_PID=9999   # pgrp 7777
# 9999 <- 9998 <- 9997 : a THREE-deep invocation chain. 9998 shares self's pgrp
# (so it is excluded twice over), but 9997 does NOT — which is what makes M2
# meaningful: under a $$+$PPID-only exclusion, 9997 becomes visible.
make_fake_proc "$FAKE_PROC" 9999 "$WT"        bash scripts/test-all.sh 9998 7777 || exit 2
make_fake_proc "$FAKE_PROC" 9998 "$WT"        bash scripts/test-all.sh 9997 7777 || exit 2
make_fake_proc "$FAKE_PROC" 9997 "$WT"        bash scripts/test-all.sh 1    6666 || exit 2
# Owned by THIS worktree — the positive control for the synthesized arms.
make_fake_proc "$FAKE_PROC" 1001 "$WT"        bash scripts/test-all.sh 1    5000 || exit 2
# Sibling worktree at <ROOT>-two — the M1 prefix-boundary fixture.
make_fake_proc "$FAKE_PROC" 1002 "${WT}-two"  bash scripts/test-all.sh 1    5001 || exit 2
# Merely MENTIONS the pattern (`grep -rn test-all.sh …`) — the M4 fixture.
make_fake_proc "$FAKE_PROC" 1003 "$WT"        grep test-all.sh         1    5002 || exit 2
# Shares the invoker's process group — the M3 / T7 fixture.
make_fake_proc "$FAKE_PROC" 1004 "$WT"        bash scripts/test-all.sh 1    7777 || exit 2
# No cwd symlink → <unreadable> — the T8 fixture.
make_fake_proc "$FAKE_PROC" 1005 ""           bash scripts/test-all.sh 1    5003 || exit 2

# The one line every mutation must change. Derived from the fixture above:
#   9999/9998/9997 excluded by ancestry; 1001 signalled; 1002 (sibling) and
#   1005 (<unreadable>) refused; 1003 not matched; 1004 skipped on pgid.
#   scanned counts all eight /proc/<pid> entries.
BASELINE_COUNTS='killed=1 refused=2 skipped_same_pgroup=1 scanned=8'

# Runs proc.sh's CLI against the synthesized procfs, never signalling anything.
run_fake() {
  local helper="$1"; shift
  env PROC_SH_ROOT="$FAKE_PROC" \
      PROC_SH_SELF_PID="$SELF_PID" \
      PROC_SH_WORKTREE="$WT" \
      PROC_SH_DRY_RUN=1 \
      PROC_SH_DRY_RUN_LOG=/dev/null \
      bash "$helper" "$@"
}

counts_of() { run_fake "$1" kill_mine test-all.sh 2>/dev/null | grep -E '^killed=' | tail -1; }

echo "== proc.sh =="

# --- AC1: sources cleanly, defines both verbs, executes nothing -------------
out=$(bash -c "source '$HELPER' && declare -F list_runs kill_mine" 2>&1)
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'list_runs' <<<"$out" && grep -q 'kill_mine' <<<"$out"; then
  pass "AC1: sources cleanly and defines list_runs + kill_mine"
else
  fail "AC1: source/declare failed (rc=$rc): $out"
fi

# --- AC8: single kill chokepoint (Guard 1), asserted over CODE only ---------
# The comment strip is required: the header deliberately discusses pkill and the
# kill semantics, so counting the whole file would make this fail on a correct
# implementation. [^_[:alnum:]] keeps kill_mine and killed= from matching.
n=$(grep -vE '^[[:space:]]*#' "$HELPER" | grep -cE '(^|[^_[:alnum:]])kill[[:space:]]+-')
if [[ "$n" == "1" ]]; then
  pass "AC8: exactly one kill invocation in code (single chokepoint)"
else
  fail "AC8: expected exactly 1 kill invocation in code, found $n"
fi

# --- T1: neither verb self-matches, even though the pattern is in our argv --
# `bash proc.sh list_runs test-all.sh` carries `test-all.sh` as a whitespace-free
# later token under a shell argv[0] — i.e. proc.sh's own command line matches
# proc.sh's own predicate. This is the whole reason the exclusions exist.
out=$(run_fake "$HELPER" list_runs test-all.sh 2>/dev/null)
if grep -qE "^(9999|9998|9997)	" <<<"$out"; then
  fail "T1: self/ancestor pid reported by list_runs"
else
  pass "T1: no self or ancestor pid reported (pattern present in own argv)"
fi
if [[ -d "/proc/$$" ]]; then
  pass "T1b: invoking shell survived list_runs"
else
  fail "T1b: invoking shell did not survive list_runs"
fi

# --- T2 / T8 / T7: refusal classes are reported, never silently dropped -----
if grep -qE "^1002	foreign	" <<<"$out"; then
  pass "T2: sibling worktree at <ROOT>-two classified foreign (prefix boundary)"
else
  fail "T2: sibling worktree not classified foreign: $out"
fi
if grep -qE "^1005	foreign	<unreadable>" <<<"$out"; then
  pass "T8: <unreadable> cwd refused AND printed"
else
  fail "T8: <unreadable> cwd not reported as foreign: $out"
fi
if grep -qE "^1004	skipped	same-process-group" <<<"$out"; then
  pass "T7: same-pgroup target reported as skipped, not absorbed into silence"
else
  fail "T7: same-pgroup target not reported as skipped: $out"
fi

# --- T5: a process merely MENTIONING the pattern is not selected ------------
if grep -qE "^1003	" <<<"$out"; then
  fail "T5: process that merely mentions the pattern was selected"
else
  pass "T5: process merely mentioning the pattern not selected (argv position)"
fi

# --- T-baseline: the counter line every mutation must move ------------------
got=$(counts_of "$HELPER")
if [[ "$got" == "$BASELINE_COUNTS" ]]; then
  pass "T-baseline: counters are '$BASELINE_COUNTS'"
else
  fail "T-baseline: expected '$BASELINE_COUNTS', got '$got'"
fi

# --- T-D6: the counter line is printed on EVERY kill_mine invocation --------
# Including one that selects nothing: a bare silence would read as "nothing to
# kill" and send the operator back to pkill.
got_empty=$(run_fake "$HELPER" kill_mine no-such-pattern-xyz 2>/dev/null | grep -cE '^killed=0 refused=0 skipped_same_pgroup=0 scanned=8$')
if [[ "$got_empty" == "1" ]]; then
  pass "T-D6: counter line printed even when nothing matched"
else
  fail "T-D6: counter line missing/wrong on a zero-match run"
fi

# --- T9: no ownership boundary => fail loudly, signal nothing ---------------
NOGIT="$(mktemp -d -t proc-nogit.XXXXXXXX)" || exit 2
ROOTS+=("$NOGIT")
out9=$(cd "$NOGIT" && env -u PROC_SH_WORKTREE -u GIT_DIR -u GIT_WORK_TREE \
  PROC_SH_ROOT="$FAKE_PROC" PROC_SH_SELF_PID="$SELF_PID" \
  bash "$HELPER" kill_mine test-all.sh 2>&1)
rc9=$?
if [[ $rc9 -ne 0 ]] && ! grep -qE '^killed=[1-9]' <<<"$out9"; then
  pass "T9: outside a git repo with no PROC_SH_WORKTREE, fails loudly and signals nothing"
else
  fail "T9: expected loud non-zero failure, got rc=$rc9: $out9"
fi

# --- AC7: mirrored primitives pinned against drift from test-contention.sh --
# Code-anchored greps (cq-assert-anchor-not-bare-token), not bare tokens.
if [[ -r "$CONTENTION_LIB" ]]; then
  drift=0
  for anchor in 'rest="${line##*'"'"') '"'"'}"' 'guard < 64'; do
    grep -qF -- "$anchor" "$CONTENTION_LIB" || { fail "AC7: anchor absent from test-contention.sh: $anchor"; drift=1; }
    grep -qF -- "$anchor" "$HELPER" || { fail "AC7: anchor absent from proc.sh: $anchor"; drift=1; }
  done
  [[ "$drift" == "0" ]] && pass "AC7: mirrored /proc primitives match test-contention.sh anchors"
else
  fail "AC7: $CONTENTION_LIB not readable"
fi

# --- AC11: this suite issues no kill against a pid it did not create --------
# Structural: every `kill ` in this file targets $p from SPAWNED, or is inside
# the cleanup trap. Assert the SPAWNED array is the only source of kill targets.
if [[ "$(grep -cE '(^|[^_[:alnum:]])kill[[:space:]]+-' "${BASH_SOURCE[0]}")" == "2" ]]; then
  pass "AC11: exactly two kill sites in this suite (cleanup trap + T3 teardown)"
else
  fail "AC11: unexpected number of kill sites in this suite"
fi

# ---------------------------------------------------------------------------
# T3 — POSITIVE CONTROL, and the only arm that really signals.
#
# Anti-vacuity: any mutation that makes the walk emit nothing fails this. It
# also exercises the REAL kill path, which the dry-run arms above cannot.
#
# Blast radius is zero by construction: the worktree boundary is a fresh
# mktemp sandbox, so no process outside it can classify as `signal`. setsid is
# load-bearing — without a new process group the spawned sleep would share the
# invoker's pgid and be correctly SKIPPED by the guard under test.
# ---------------------------------------------------------------------------
SANDBOX="$(mktemp -d -t proc-real.XXXXXXXX)" || exit 2
ROOTS+=("$SANDBOX")
(cd "$SANDBOX" && exec setsid sleep 300) >/dev/null 2>&1 &

SLEEP_PID=""
for _ in $(seq 1 60); do
  SLEEP_PID=$(env PROC_SH_WORKTREE="$SANDBOX" bash "$HELPER" list_runs sleep 2>/dev/null \
    | awk -F'\t' '$2 == "mine" { print $1; exit }')
  [[ -n "$SLEEP_PID" ]] && break
  sleep 0.1
done

if [[ -z "$SLEEP_PID" ]]; then
  fail "T3: fixture error — spawned sleep never appeared in list_runs (cannot test the kill path)"
else
  SPAWNED+=("$SLEEP_PID")
  real=$(env PROC_SH_WORKTREE="$SANDBOX" bash "$HELPER" kill_mine sleep 2>/dev/null | grep -E '^killed=' | tail -1)
  if [[ "$real" == killed=1\ * ]]; then
    pass "T3: positive control — worktree-owned process signalled (killed=1)"
  else
    fail "T3: expected killed=1, got '$real'"
  fi
  gone=0
  for _ in $(seq 1 40); do
    kill -0 "$SLEEP_PID" 2>/dev/null || { gone=1; break; }
    sleep 0.1
  done
  if [[ "$gone" == "1" ]]; then
    pass "T3b: the signalled process actually terminated (real kill path works)"
  else
    fail "T3b: process $SLEEP_PID survived kill_mine"
  fi
fi
if [[ -d "/proc/$$" ]]; then
  pass "T3c: invoking shell survived kill_mine"
else
  fail "T3c: invoking shell did not survive kill_mine"
fi

# ---------------------------------------------------------------------------
# Mutation battery M1-M5.
#
# Each mutation is applied to a COPY of the REAL proc.sh, proven landed with
# `diff -q` against a pristine backup, and run in the SAME harness that produced
# the GREEN baseline above. A surviving mutant is a RESULT with two readings —
# either the fixtures do not exercise the property, or the mutant is equivalent.
# None here are equivalent: every row moves BASELINE_COUNTS.
# ---------------------------------------------------------------------------
MUT_DIR="$(mktemp -d -t proc-mut.XXXXXXXX)" || exit 2
ROOTS+=("$MUT_DIR")
cp "$HELPER" "$MUT_DIR/pristine.sh" || { echo "ERROR: mutation backup failed" >&2; exit 2; }

# python3 rather than sed: it asserts the anchor is PRESENT before replacing, so
# an anchor that drifts fails loudly instead of silently no-opping into a
# mutation that never landed and a mutant that "survives".
mutate() {
  local name="$1" old="$2" new="$3"
  local target="$MUT_DIR/$name.sh"
  cp "$MUT_DIR/pristine.sh" "$target" || return 1
  OLD="$old" NEW="$new" python3 - "$target" <<'PY' || return 1
import os, sys
p = sys.argv[1]
old, new = os.environ["OLD"], os.environ["NEW"]
s = open(p).read()
assert old in s, f"mutation anchor absent: {old!r}"
open(p, "w").write(s.replace(old, new, 1))
PY
  # Prove the mutation actually landed.
  if diff -q "$MUT_DIR/pristine.sh" "$target" >/dev/null 2>&1; then
    fail "$name: mutation did not land (files identical)"
    return 1
  fi
  printf '%s' "$target"
}

expect_red() {
  local name="$1" why="$2" target="$3"
  local got
  got=$(counts_of "$target")
  if [[ "$got" == "$BASELINE_COUNTS" ]]; then
    fail "$name SURVIVED — $why (counters unchanged: '$got')"
  else
    pass "$name: drove RED as required — $why"
  fi
}

if t=$(mutate M1 '"$cwd" == "$root"/*' '"$cwd" == "$root"*'); then
  expect_red M1 "sibling worktree <ROOT>-two must not be selected when the / boundary is dropped" "$t"
fi
if t=$(mutate M2 'guard < 64' 'guard < 2'); then
  expect_red M2 "a 3-deep wrapper must still be excluded; \$\$ + \$PPID alone is insufficient (pins R1)" "$t"
fi
if t=$(mutate M3 '"$pgrp" == "$self_pgrp"' '"$pgrp" == "__never__"'); then
  expect_red M3 "a same-pgid fork of proc.sh must not be selected" "$t"
fi
if t=$(mutate M4 '*) return 1 ;;' '*) ;;'); then
  expect_red M4 "a process merely mentioning the pattern must not be selected" "$t"
fi
if t=$(mutate M6 "printf 'refuse\\t%s\\t%s\\n' \"\$pid\" \"\$cwd\"" "printf 'signal\\t%s\\t%s\\n' \"\$pid\" \"\$cwd\""); then
  expect_red M6 "the signal/refuse classification fork must be load-bearing, not asserted by reading" "$t"
fi
if t=$(mutate M5 \
  '  rest="${line##*'"'"') '"'"'}"
  awk -v i="$idx" '"'"'{print $i}'"'"' <<<"$rest"' \
  '  awk -v i="$(( idx + 2 ))" '"'"'{print $i}'"'"' <<<"$line"'); then
  expect_red M5 "a comm containing a space must still resolve its ppid (pins R4)" "$t"
fi

# ---------------------------------------------------------------------------
# AC5 — auto-discovery, not hand-registration.
# ---------------------------------------------------------------------------
if git -C "$REPO_ROOT" diff --stat origin/main...HEAD -- scripts/test-all.sh 2>/dev/null | grep -q .; then
  fail "AC5: scripts/test-all.sh was modified — this suite must be auto-globbed, not hand-registered"
else
  pass "AC5: scripts/test-all.sh untouched (suite is auto-globbed)"
fi

echo
echo "  Total: $((PASS + FAIL))  pass: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
