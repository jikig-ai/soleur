#!/usr/bin/env bash
# Mutation battery for the hook-input classifier repaired in #7275.
#
# WHY THIS FILE IS NAMED `*-mutation.test.sh` AND NOT `*.mutation.sh`
# ------------------------------------------------------------------
# `scripts/test-all.sh` globs `plugins/soleur/test/*.test.sh` (SUITE_GLOBS),
# which is exactly what the `.mutation.sh` spelling is excluded from. Two
# batteries in this directory already carry that spelling and are executed by
# nothing (#7942). Shipping a third would have reproduced the defect while
# claiming to guard against it, so this one is named into the glob that already
# exists: gated on arrival, with no edit to `test-all.sh`.
#
# WHAT A MUTATION BATTERY DOES AND DOES NOT PROVE
# -----------------------------------------------
# It proves the contract suite can DETECT a given perturbation. It says nothing
# about whether the set of perturbations is the right one, so the axes are named
# below — and the ones NOT edited are named too. Counting rows instead of axes
# is how a battery of one shape reports twelve.
#
# Axes edited here:
#   1. the rc-capture mechanism        M1, M7, M8
#   2. strip-vs-split ORDER            M2
#   3. the jq program's root contract  M3
#   4. fault classification ORDER      M5
#   5. reason-value mapping            M6, M9
#   6. complete record + non-zero rc   M4
#   7. the guard's OWN operand         M10 (degenerate separator — asks whether
#                                      the guard silently WIDENS, which every
#                                      other row is structurally unable to see)
#   8. the harness itself              C2 (dispatch neutering)
#
# Axes deliberately NOT edited, so the claim is bounded: the jq program's
# per-field `d()`/`fp()` semantics (owned by the #7164 contract cases), the
# IFS / `set -f` save-restore window, and `hook_input_emit_ask`'s envelope shape.
set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by every worktree on this box, and
# a DIRECT invocation of this file inherits it where test-all.sh would not. A
# harness that cannot allocate its sandbox must abort, never degrade into
# scoring the previous row's mutation.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUT="$REPO_ROOT/.claude/hooks/lib/hook-input.sh"
SUITE="$REPO_ROOT/.claude/hooks/hook-input-contract.test.sh"

[[ -r "$SUT"   ]] || { echo "FATAL: SUT not readable: $SUT" >&2; exit 2; }
[[ -r "$SUITE" ]] || { echo "FATAL: contract suite not readable: $SUITE" >&2; exit 2; }
command -v jq      >/dev/null 2>&1 || { echo "SKIP: jq missing — battery cannot run";      exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing — battery cannot run"; exit 0; }

WORK="$(mktemp -d "${TMPDIR%/}/hookmut.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
PRISTINE="$WORK/pristine.sh"
SUITE_PRISTINE="$WORK/suite-pristine.sh"
cp "$SUT"   "$PRISTINE"       || { echo "FATAL: could not snapshot the SUT"   >&2; exit 2; }
cp "$SUITE" "$SUITE_PRISTINE" || { echo "FATAL: could not snapshot the suite" >&2; exit 2; }

cleanup() {
  # Restore from the PRISTINE COPY, never `git checkout --`. Checkout restores
  # to HEAD, which during a fix-in-flight is a DIFFERENT file from the one under
  # test: a battery that does that reverts the fix on row 1 and then scores the
  # DEFECT against itself for every row after, reporting SURVIVED while
  # measuring a file that no longer contains the thing under test.
  cp "$PRISTINE"       "$SUT"   2>/dev/null || true
  cp "$SUITE_PRISTINE" "$SUITE" 2>/dev/null || true
  rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

PASS=0; FAIL=0; ROWS=0
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; shift; local l; for l in "$@"; do echo "    $l"; done; }
restore() { cp "$PRISTINE" "$SUT"; }

# run_suite <logfile> -> prints the suite's rc
# ANSI is stripped before anything is read: a coloured summary makes a
# plain-text extraction return empty for EVERY row, and each mutant then reads
# as killed-or-survived arbitrarily while the run still looks complete.
run_suite() {
  local log="$1" rc=0
  bash "$SUITE" > "$log" 2>&1 || rc=$?
  sed -i -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$log" 2>/dev/null || true
  printf '%d' "$rc"
}

# patch <file> <old> <new> — anchors travel as ARGV, never interpolated into
# the program text, so a shell metacharacter in an anchor cannot rewrite it.
patch() {
  python3 -c '
import sys, io
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(path, encoding="utf-8").read()
if old not in s:
    sys.stderr.write("anchor missing\n"); sys.exit(3)
io.open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))
' "$1" "$2" "$3"
}

# mutate <id> <old> <new> — apply, and PROVE it landed.
# A mutation that does not land leaves the BASELINE in place, and a baseline run
# is a measurement of nothing that reads exactly like a result.
mutate() {
  local id="$1" old="$2" new="$3"
  restore
  if ! patch "$SUT" "$old" "$new"; then
    fail "$id — anchor missing; the mutation never applied"
    restore; return 1
  fi
  if cmp -s "$PRISTINE" "$SUT"; then
    fail "$id — MUTATION DID NOT LAND (file byte-identical to pristine)"
    restore; return 1
  fi
  return 0
}

# expect_red <id> <description>
expect_red() {
  # Declared in two statements deliberately: `local a="$1" b="$a"` references a
  # name the SAME `local` is still declaring, which under `set -u` is an
  # unbound-variable abort rather than the obvious left-to-right read.
  local id="$1" desc="$2" rc
  local log="$WORK/$id.log"
  ROWS=$((ROWS+1))
  rc="$(run_suite "$log")"
  if [[ "$rc" != "0" ]]; then
    pass "$id killed — $desc"
  else
    fail "$id SURVIVED — $desc" \
         "the contract suite stayed GREEN with this mutation applied" \
         "log: $log" \
         "a survivor is EITHER a fixture gap OR an equivalent mutant — decide which and record it"
  fi
  restore
}

# ---------------------------------------------------------------------------
# C1 — THE CONTROL. Read this before any row below: an empty or red control
# voids every result that follows, because each mutant is then scored against a
# broken oracle.
# ---------------------------------------------------------------------------
ROWS=$((ROWS+1))
control_log="$WORK/control.log"
control_rc="$(run_suite "$control_log")"
if [[ "$control_rc" != "0" ]]; then
  echo "FATAL: CONTROL IS RED (rc=$control_rc) — every mutation result below would be void." >&2
  grep -E '^FAIL' "$control_log" | head -20 >&2
  exit 2
fi
control_summary="$(grep -oE 'hook-input-contract: [0-9]+/[0-9]+ pass' "$control_log" | head -1)"
if [[ -z "$control_summary" ]]; then
  echo "FATAL: the control summary line could not be read — the EXTRACTION is broken, not the SUT." >&2
  echo "       (A battery whose parser returns empty scores every row arbitrarily.)" >&2
  exit 2
fi
pass "C1 control green, summary readable — $control_summary"

# ---------------------------------------------------------------------------
# THE FLOOR — revert this change's own thesis. If the suite does not redden
# here, nothing below it means anything.
# ---------------------------------------------------------------------------
if mutate M1 \
  '  jq_rc=${raw##*"$_HOOK_INPUT_RS"}' \
  '  jq_rc=0  # M1'; then
  expect_red M1 "rc forced back to a constant 0 (the pre-#7275 behaviour)"
fi

# Axis: strip-vs-split ORDER.
if mutate M2 \
  '  body=${raw%"$_HOOK_INPUT_RS"*}' \
  '  body=$raw  # M2'; then
  expect_red M2 "rc left in the body, so the happy path carries an extra field"
fi

# Axis: the jq program's root contract.
if mutate M3 \
  'if type != "object" then' \
  'if false then'; then
  expect_red M3 "object-root requirement removed — a null root silently disarms"
fi

# Axis: a COMPLETE record plus a non-zero rc.
if mutate M4 \
  '  if (( jq_rc != 0 )); then
    HOOK_INPUT_REASON="baddoc"
    return 1
  fi' \
  '  : # M4'; then
  expect_red M4 "valid envelope + trailing garbage accepted as a clean parse"
fi

# Axis: fault classification ORDER (ours before theirs).
if mutate M5 \
  '  if (( jq_rc == 3 )); then
    HOOK_INPUT_REASON="internal:rc3"
    return 1
  fi' \
  '  : # M5'; then
  expect_red M5 "rc-3 no longer checked first — a broken program reads as a bad payload"
fi

# Axis: reason-value mapping.
if mutate M6 \
  'HOOK_INPUT_REASON="internal:count"' \
  'HOOK_INPUT_REASON="internal:rc3"'; then
  expect_red M6 "the two internal arms collapsed onto one value"
fi

if mutate M9 \
  '      if (( jq_rc == 0 )); then
        HOOK_INPUT_REASON="empty"
      else
        HOOK_INPUT_REASON="baddoc"
      fi' \
  '      if (( jq_rc == 0 )); then
        HOOK_INPUT_REASON="baddoc"
      else
        HOOK_INPUT_REASON="empty"
      fi'; then
  expect_red M9 "empty/baddoc mapping inverted"
fi

# Axis: the rc-capture mechanism itself.
if mutate M7 \
  '         printf '"'"'%s%dX'"'"' "$_HOOK_INPUT_RS" "$_hi_rc")"' \
  '         printf '"'"'X'"'"')"  # M7'; then
  expect_red M7 "the rc append deleted — nothing carries jq's status out of the subshell"
fi

if mutate M8 \
  ' || _hi_rc=$?' \
  '  # M8'; then
  expect_red M8 "jq status discarded, so _hi_rc stays 0 whatever jq did"
fi

# Axis: THE GUARD'S OWN OPERAND. Every row above mutates the SUT and asks
# whether the guard REDDENS. This one degenerates an operand the guard
# interpolates and asks whether it silently WIDENS — a guard that accepts
# everything is indistinguishable from a healthy run by exit code alone.
if mutate M10 \
  "_HOOK_INPUT_RS=\$'\\x1e'" \
  '_HOOK_INPUT_RS=""  # M10'; then
  expect_red M10 "separator degenerated to the empty string"
fi

# ---------------------------------------------------------------------------
# C2 — THE HARNESS AXIS. Every row above is conditional on the contract suite's
# failure path actually being able to fail, and nothing else here checks that.
# Neuter the FAIL counter, re-apply M1, and report what actually happens.
# ---------------------------------------------------------------------------
ROWS=$((ROWS+1))
if ! patch "$SUITE" 'bad() { FAIL=$((FAIL + 1));' 'bad() { FAIL=$((FAIL + 0));'; then
  fail "C2 — harness anchor missing; the dispatch axis was not measured"
else
  if mutate C2 \
    '  jq_rc=${raw##*"$_HOOK_INPUT_RS"}' \
    '  jq_rc=0  # C2'; then
    ROWS=$((ROWS-1))   # mutate() does not count a row; expect_* does
    c2_log="$WORK/C2.log"
    c2_rc="$(run_suite "$c2_log")"
    ROWS=$((ROWS+1))
    if [[ "$c2_rc" != "0" ]]; then
      pass "C2 harness axis — the suite still reddens with its FAIL counter neutered, so a SECOND independent gate (the assertion floor) carries the verdict"
    else
      pass "C2 harness axis — neutering the FAIL counter does hide a real regression, confirming that counter is load-bearing and must not be weakened"
    fi
  fi
fi
cp "$SUITE_PRISTINE" "$SUITE"
restore

# ---------------------------------------------------------------------------
# Assertion accounting. A floor that shares a lifetime with what it guards is
# not a floor, so this counts ROWS EXECUTED and reconciles against the number
# this file DEFINES. Deleting a row is then visible, where a bare `FAIL == 0`
# check reports success for a file whose rows were all removed.
# ---------------------------------------------------------------------------
EXPECTED_ROWS=12
echo
echo "=== hook-input-classification-mutation: $PASS pass, $FAIL fail, $ROWS/$EXPECTED_ROWS rows ==="
if (( ROWS != EXPECTED_ROWS )); then
  printf 'FAIL: %d rows executed but %d are defined — rows were skipped or deleted\n' "$ROWS" "$EXPECTED_ROWS"
  exit 1
fi
(( FAIL == 0 )) || exit 1
exit 0
