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
# IT RUNS IN A SANDBOX, AND THAT IS NOT A STYLE CHOICE
# ----------------------------------------------------
# The first revision of this file mutated `.claude/hooks/lib/hook-input.sh` IN
# THE WORKING TREE. That file is sourced by 22 hooks, 19 of which fire on every
# Bash tool call. Measured: ~11 s per contract run x 12 rows = a ~140-second
# window per invocation during which the live guard library was deliberately
# broken - including the row that removes the object-root check, i.e. the
# silent-total-disarm this change exists to close. `trap ... EXIT INT TERM HUP`
# does not cover SIGKILL, and `scripts/test-all.sh` ships a `[KILLED]` taxonomy
# precisely because suites on this box do get signal-killed; an OOM inside that
# window left the tracked file mutated with a dirty `git status` as the only
# evidence. Naming the file into SUITE_GLOBS made it worse, not better: the two
# ungated siblings only ran when someone chose to.
#
# The contract suite resolves the library through `BASH_SOURCE`, so a copied
# tree runs correctly. Everything below happens inside $WORK; the real tree is
# read once and never written.
#
# WHAT A MUTATION BATTERY DOES AND DOES NOT PROVE
# -----------------------------------------------
# It proves the contract suite can DETECT a given perturbation. It says nothing
# about whether the set of perturbations is the right one. Count AXES, not rows:
# a previous revision of this file banked two rows (M7, M10) that were measured
# to be the SAME mutant - both degenerated the parser to "always return 1", and
# both reddened the identical 22 assertions.
#
# Axes edited here, one row each unless noted:
#   1. rc capture           C1 (never captured), C2 (never leaves the subshell)
#   2. rc POLARITY          P1 (every non-zero rc blamed on the payload)
#   3. jq root contract     R1
#   4. classification order O1
#   5. reason mapping       M1 (internal arms collapsed), M2 (empty/baddoc swap)
#   6. complete record+rc   F1
#   7. field-count boundary B1 (the `n > 6` guard widened)
#   8. multi-document arm   D1
#   9. THE HARNESS ITSELF   H1 (want() cannot fail), H2 (bad() cannot count)
#
# Thirteen rows: one control plus twelve mutations across those nine axes.
#
# Axes deliberately NOT edited, so the claim is bounded: the jq program's
# per-field `d()`/`fp()` semantics (owned by the #7164 cases), the IFS / `set -f`
# save-restore window, and `hook_input_emit_ask`'s envelope shape. A review pass
# drove all three and confirmed the existing suite covers them.
set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by every worktree on this box, and
# a DIRECT invocation of this file inherits it where test-all.sh would not. A
# harness that cannot allocate its sandbox must abort, never degrade into
# scoring the previous row's mutation.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v jq      >/dev/null 2>&1 || { echo "SKIP: jq missing — battery cannot run";      exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing — battery cannot run"; exit 0; }
command -v git     >/dev/null 2>&1 || { echo "SKIP: git missing — cannot build the sandbox"; exit 0; }

# P1b (#7708): `mktemp -d` inherits TMPDIR, and a RELATIVE TMPDIR yields a relative
# root — after which the `rm -rf` below resolves against whatever directory the trap
# happens to fire in. The body is a byte-exact COPY of the canonical definition in
# plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh asserts the
# equality, so do not reword it here alone.
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

WORK="$(mktemp -d "${TMPDIR%/}/hookmut.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
cleanup() { assert_fixture_dir "$WORK"; rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP

# --- build the sandbox ------------------------------------------------------
# Working-tree contents of every TRACKED file, so an in-flight fix is under test
# rather than whatever HEAD happens to hold. A setup failure ABORTS: a harness
# that cannot build its sandbox must not degrade into scoring the previous row.
if ! ( cd "$REPO_ROOT" && git ls-files -z | tar --null -T - -cf - ) 2>/dev/null | tar -x -C "$WORK" 2>/dev/null; then
  echo "FATAL: could not populate the sandbox from tracked files" >&2; exit 2
fi
SUT="$WORK/.claude/hooks/lib/hook-input.sh"
SUITE="$WORK/.claude/hooks/hook-input-contract.test.sh"
[[ -r "$SUT" && -r "$SUITE" ]] || { echo "FATAL: sandbox is missing the SUT or the suite" >&2; exit 2; }

PRISTINE_SUT="$WORK/.pristine-sut"
PRISTINE_SUITE="$WORK/.pristine-suite"
cp "$SUT" "$PRISTINE_SUT"     || { echo "FATAL: could not snapshot the SUT" >&2; exit 2; }
cp "$SUITE" "$PRISTINE_SUITE" || { echo "FATAL: could not snapshot the suite" >&2; exit 2; }

PASS=0; FAIL=0; ROWS=0
# `fail()` writes to an APPEND-ONLY ledger as well as incrementing, so the final
# verdict does not rest on a counter one edit can silence.
LEDGER="$WORK/.failures"; : > "$LEDGER"
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" | tee -a "$LEDGER"; shift; local l; for l in "$@"; do echo "    $l"; done; }
restore() { assert_fixture_dir "$SUT"; assert_fixture_dir "$SUITE"; cp "$PRISTINE_SUT" "$SUT"; cp "$PRISTINE_SUITE" "$SUITE"; }

# run_suite <logfile> -> prints the suite's rc
# ANSI is stripped before anything is read: a coloured summary makes a
# plain-text extraction return empty for EVERY row, and each mutant then reads
# as killed-or-survived arbitrarily while the run still looks complete.
run_suite() {
  local log="$1" rc=0
  assert_fixture_dir "$log"
  ( cd "$WORK" && bash "$SUITE" ) > "$log" 2>&1 || rc=$?
  sed -i -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$log" 2>/dev/null || true
  printf '%d' "$rc"
}

# patch <file> <old> <new> — anchors travel as ARGV, never interpolated into the
# program text, and the anchor must occur EXACTLY ONCE. Presence alone is not
# enough: `replace(..., 1)` takes the first match, and in this repo the first
# match of a code anchor is routinely the COMMENT that documents it three lines
# above. That lands the mutation on prose, changes bytes (so a file-level
# "did it land" check passes), leaves the suite green, and reports SURVIVED.
patch() {
  python3 -c '
import sys, io
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(path, encoding="utf-8").read()
n = s.count(old)
if n == 0:
    sys.stderr.write("anchor missing\n"); sys.exit(3)
if n != 1:
    sys.stderr.write("anchor is AMBIGUOUS (%d occurrences) — first-match would be arbitrary\n" % n)
    sys.exit(4)
io.open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))
' "$1" "$2" "$3"
}

# mutate <id> <file> <old> <new> — apply, and PROVE it landed.
mutate() {
  local id="$1" file="$2" old="$3" new="$4"
  restore
  if ! patch "$file" "$old" "$new"; then
    fail "$id — anchor missing or ambiguous; the mutation never applied"
    restore; return 1
  fi
  return 0
}

# expect_red <id> <assertion-pattern> <description>
# Routing on `rc != 0` ALONE credits a kill to whatever reddened — including a
# mutant that merely crashes the suite, or a blast-radius mutant that breaks the
# parser for every input. A row must show that the assertion it NAMES failed.
expect_red() {
  local id="$1" want_pat="$2" desc="$3" rc log fails
  log="$WORK/$id.log"
  ROWS=$((ROWS+1))
  rc="$(run_suite "$log")"
  if [[ "$rc" == "0" ]]; then
    fail "$id SURVIVED — $desc" \
         "the contract suite stayed GREEN with this mutation applied" \
         "log: $log" \
         "a survivor is EITHER a fixture gap OR an equivalent mutant — decide which and record it"
    restore; return
  fi
  if ! grep -E '^(FAIL|FATAL)' "$log" | grep -qE "$want_pat"; then
    fails="$(grep -cE '^FAIL' "$log" || true)"
    fail "$id reddened, but NOT on the property it names — $desc" \
         "expected a FAIL/FATAL line matching: $want_pat" \
         "got $fails failing assertion(s); first few:" \
         "$(grep -E '^(FAIL|FATAL)' "$log" | head -3 | tr '\n' '|')" \
         "a row credited to the wrong assertion measures the SUT being alive, not the property"
    restore; return
  fi
  pass "$id killed by its named assertion — $desc"
  restore
}

# ---------------------------------------------------------------------------
# CONTROL. An empty or red control voids every result below, because each mutant
# is then scored against a broken oracle.
# ---------------------------------------------------------------------------
ROWS=$((ROWS+1))
control_log="$WORK/control.log"
control_rc="$(run_suite "$control_log")"
if [[ "$control_rc" != "0" ]]; then
  echo "FATAL: CONTROL IS RED (rc=$control_rc) — every mutation result below would be void." >&2
  grep -E '^(FAIL|FATAL)' "$control_log" | head -20 >&2
  exit 2
fi
control_summary="$(grep -oE 'hook-input-contract: [0-9]+/[0-9]+ pass' "$control_log" | head -1)"
if [[ -z "$control_summary" ]]; then
  echo "FATAL: the control summary line could not be read — the EXTRACTION is broken, not the SUT." >&2
  exit 2
fi
pass "CONTROL green in the sandbox, summary readable — $control_summary"

# --- axis 1: the rc capture ------------------------------------------------
if mutate C1 "$SUT" \
  '         exit "$_hi_rc")" || jq_rc=$?' \
  '         exit "$_hi_rc")" || true'; then
  expect_red C1 'A20e|A19b' "the rc is never captured (the pre-#7275 blindness)"
fi

if mutate C2 "$SUT" \
  '         exit "$_hi_rc")"' \
  '         exit 0)"'; then
  expect_red C2 'A20e|A19b' "the rc never leaves the subshell"
fi

# --- axis 2: rc POLARITY (the review finding this file exists to pin) -------
if mutate P1 "$SUT" \
  '  if (( jq_rc == 5 )); then
    rc_fault="payload"' \
  '  if (( jq_rc != 0 )); then
    rc_fault="payload"'; then
  expect_red P1 'A20e rc (2|3|126|137)' "every non-zero rc blamed on the payload — #7275's collapse, one code over"
fi

# --- axis 3: the jq program's root contract --------------------------------
if mutate R1 "$SUT" 'if type != "object" then' 'if false then'; then
  expect_red R1 'A19d|A19e|A19f' "object-root requirement removed — a null root silently disarms"
fi

# --- axis 4: classification ORDER (ours before theirs) ---------------------
if mutate O1 "$SUT" \
  '  if [[ $rc_fault == "ours" ]]; then
    HOOK_INPUT_REASON="internal:rc${jq_rc}"
    return 1
  fi' \
  '  : # O1'; then
  expect_red O1 'A20a|A20e rc (2|3|126|137)' "our-fault check no longer runs first"
fi

# --- axis 5: reason mapping -------------------------------------------------
if mutate M1 "$SUT" 'HOOK_INPUT_REASON="internal:count"' 'HOOK_INPUT_REASON="internal:rc3"'; then
  expect_red M1 'A20b|A20c' "the two internal arms collapsed onto one value"
fi

if mutate M2 "$SUT" \
  '      if [[ $rc_fault == "payload" ]]; then
        HOOK_INPUT_REASON="baddoc"
      else
        HOOK_INPUT_REASON="empty"
      fi' \
  '      if [[ $rc_fault == "payload" ]]; then
        HOOK_INPUT_REASON="empty"
      else
        HOOK_INPUT_REASON="baddoc"
      fi'; then
  expect_red M2 'A19a|A19b' "empty/baddoc mapping inverted"
fi

# --- axis 6: a COMPLETE record plus a non-zero rc --------------------------
if mutate F1 "$SUT" \
  '  if [[ $rc_fault == "payload" ]]; then
    HOOK_INPUT_REASON="baddoc"
    return 1
  fi

  if [[ ${_hi_s[0]} == "nonobject" ]]; then' \
  '  if [[ ${_hi_s[0]} == "nonobject" ]]; then'; then
  expect_red F1 'A19c' "valid envelope + trailing garbage accepted as a clean parse"
fi

# --- axis 7: the field-count boundary --------------------------------------
# The previous revision's "does the guard WIDEN" row degenerated the separator
# to "" and tripped a guard BEFORE the split, so it never reached the boundary
# at all. This widens the boundary itself, which is what that axis claimed.
if mutate B1 "$SUT" '    if (( n > 6 )); then' '    if (( n > 7 )); then'; then
  expect_red B1 'A19i|A19-rc separator' "the forged-separator boundary widened by one"
fi

# --- axis 8: the multi-document arm ----------------------------------------
if mutate D1 "$SUT" '      if (( n % 6 == 0 )) && [[ -z $rc_fault ]]; then' '      if false; then'; then
  expect_red D1 'A19k' "concatenated documents reported as a forged separator"
fi

# --- axis 9: THE HARNESS ITSELF --------------------------------------------
# Every row above is scored THROUGH the contract suite's helpers. These two ask
# whether those helpers can fail at all. H1 is the one a previous revision could
# not see: it neutered bad()'s COUNTER, which is the single edit that leaves
# ok() and TOTAL intact, so `want()` — the single point of failure for 90 of the
# suite's assertions — went unmutated. Measured on the previous revision:
# `want(){ ok "$1 → $3"; }` produced a byte-identical `95/95 pass`, exit 0.
if mutate H1 "$SUITE" \
  'want(){ if [[ "$2" == "$3" ]]; then ok "$1 → $3"; else bad "$1" "want: $2" "got:  $3"; fi; }' \
  'want(){ ok "$1 → $3"; }'; then
  expect_red H1 'FATAL: want\(\) DID NOT FAIL' "want() can no longer fail — must be caught by the suite's own helper self-test"
fi

if mutate H2 "$SUITE" 'bad() { FAIL=$((FAIL + 1));' 'bad() { FAIL=$((FAIL + 0));'; then
  expect_red H2 'FATAL: want\(\) DID NOT FAIL|only [0-9]+ assertions ran' \
    "bad() can no longer count — must be caught by the self-test or the floor"
fi

# ---------------------------------------------------------------------------
# Accounting. The verdict reads an APPEND-ONLY ledger as well as the counter, so
# silencing the verdict means deleting evidence rather than moving a number; and
# ROWS is reconciled against the number of rows this file DEFINES, so a deleted
# row is visible where a bare `FAIL == 0` reports success for an empty file.
# ---------------------------------------------------------------------------
EXPECTED_ROWS=13
ledger_lines="$(wc -l < "$LEDGER" | tr -d ' ')"
echo
echo "=== hook-input-classification-mutation: $PASS pass, $FAIL fail, $ROWS/$EXPECTED_ROWS rows ==="
if (( ROWS != EXPECTED_ROWS )); then
  printf 'FAIL: %d rows executed but %d are defined — rows were skipped or deleted\n' "$ROWS" "$EXPECTED_ROWS"
  exit 1
fi
if (( FAIL != ledger_lines )); then
  printf 'FAIL: counter says %d failures, ledger holds %d — the accounting disagrees with itself\n' "$FAIL" "$ledger_lines"
  exit 1
fi
(( FAIL == 0 && ledger_lines == 0 )) || exit 1
exit 0
