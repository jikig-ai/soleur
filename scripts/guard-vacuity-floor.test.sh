#!/usr/bin/env bash
# Meta-guard: anti-vacuity floors must survive a NEUTERED assertion machinery.
#
# WHY THIS EXISTS. A suite's anti-vacuity floor exists to notice "no assertions ran".
# Many enforced that floor by calling `fail`:
#
#     if [[ "$cases" -lt 75 ]]; then fail "vacuity guard: only $cases ..."; fi
#     ...
#     [[ "$fails" -eq 0 ]]
#
# `fail` increments `fails`, and the exit status reads `fails`. So the detector ran
# THROUGH the thing it detects: neuter `fail` — redefine it, break its arithmetic, lose
# its body to an editing slip — and every row goes quiet AND so does the floor that
# exists to notice the quiet. The suite prints a total and exits 0. A floor enforced
# through the suspect cannot witness the suspect.
#
# There is a second half, and it is the one that actually bites. The floor only catches
# "no assertions RAN". It cannot catch "assertions ran and their verdicts were
# DISCARDED", because the case counter is incremented by the assert HELPERS and never by
# `fail`. Stub `fail` to a no-op in a real suite and the counter stays at full value, the
# floor is satisfied, and the run exits 0 with real failures hidden. Measured on the probe
# suite before its fix: `45 passed, 0 failed (48 assertions)`, RC=0, with a genuine defect
# present. The fix for that half is an accounting-conservation check over a case counter
# incremented at the CALL SITE, so it moves independently of the verdict.
#
# THE POPULATION IS DERIVED, NEVER LISTED. This file used to name two suites. A
# hand-maintained list is the snapshot that goes stale — the same failure class one level
# up. The sweep below enumerates tracked `*.test.sh` RECURSIVELY (never a shell glob:
# `scripts/*.test.sh` is non-recursive and silently excludes `scripts/followthroughs/`)
# and classifies by SHAPE: a `-lt`/`-ge`/`-le` comparison against a counter the file
# itself increments. A suite whose floor this file cannot construct a mutant for is
# reported LOUDLY and counted — never silently skipped.
#
# NOTHING HERE RUNS THE GUARDED SUITES TO COMPLETION. Each mutant is truncated to the
# floor block plus its threshold bindings, so this suite costs seconds and cannot be made
# slow or flaky by the batteries it guards.

export TMPDIR="${TMPDIR:-/var/tmp}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

passes=0
fails=0
cases=0

pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
# Deliberately NOT the mechanism this suite's own floor depends on — see the bottom.
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1"; }

SUITE_TMP="$(mktemp -d "${TMPDIR}/vacuity-floor-meta.XXXXXXXX")" || {
  echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup_suite() { [[ -n "${SUITE_TMP:-}" && -d "$SUITE_TMP" ]] && rm -rf "$SUITE_TMP" || true; return 0; }
trap cleanup_suite EXIT

# ---------------------------------------------------------------------------------------
# DERIVATION
# ---------------------------------------------------------------------------------------

# A suite's counter variables are exactly those it increments by one. Two shapes cover the
# corpus: `X=$((X + 1))` and `((X++))`. `grep -a` because one tracked suite carries bytes
# grep classifies as binary, and a "binary file matches" line would otherwise be parsed as
# a counter name.
counters_of() { # <file>
  {
    { grep -aoE '\b[A-Za-z_][A-Za-z0-9_]*=\$\(\( *[A-Za-z_][A-Za-z0-9_]* *\+ *1 *\)\)' "$1" || true; } | cut -d= -f1
    { grep -aoE '\(\( *[A-Za-z_][A-Za-z0-9_]*\+\+ *\)\)' "$1" || true; } | tr -d '()+ '
  } | sort -u | grep -v '^$' || true
}

# Floor candidates: `-lt`/`-ge`/`-le` comparisons referencing a counter, or a variable
# derived from counters in one step (`total=$((passes + fails))`).
#
# Variables inside an arithmetic expansion appear WITHOUT a leading `$` — `$((PASS + FAIL))`
# — so the reference test matches on a WORD BOUNDARY, not on `\$VAR`. Anchoring on `$` was
# measured to drop `plugins/soleur/test/terraform-drift-step-order.test.sh` and
# `preflight-check10-suite-integrity.test.sh` from the population entirely.
#
# Both `[[ ]]` and `[ ]` are matched: `apps/web-platform/infra/git-data-emit.test.sh`
# writes its floor as `if [ "$total" -lt 44 ]`, and a `[[`-only pattern misses it.
floor_lines_of() { # <file> -> "lineno:text" per candidate
  local f="$1" base derived all alt c
  base="$(counters_of "$f")"
  [[ -n "$base" ]] || return 0
  derived=""
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    derived+="$( { grep -aoE "\b[A-Za-z_][A-Za-z0-9_]*=\\\$\\(\\([^)]*\\b${c}\\b[^)]*\\)\\)" "$f" || true; } | cut -d= -f1)"$'\n'
  done <<< "$base"
  # `{ grep || true; }` — the BRACE form, inside the pipeline. A no-match here is a normal
  # answer (a file whose only counters are undeclared), not an error. A trailing `|| true`
  # on the whole pipeline would bind to `sort` alone and leave this exact trap open: under
  # `set -euo pipefail` a zero-match `grep` exits 1, pipefail promotes it, and `set -e`
  # kills the script AT THIS ASSIGNMENT — so the `[[ -n "$alt" ]]` guard two lines below is
  # unreachable and the suite dies closed but silent.
  all="$(printf '%s\n%s\n' "$base" "$derived" | { grep -v '^$' || true; } | sort -u)"
  alt="$(printf '%s' "$all" | paste -sd'|' -)"
  [[ -n "$alt" ]] || return 0
  { grep -anE '(\[\[|\[)[^]]*(-lt|-ge|-le)[^]]*\]' "$f" || true; } | grep -aE "\b(${alt})\b" || true
}

is_floor_bearing() { [[ -n "$(floor_lines_of "$1")" ]]; }

# The repo-wide sweep. Recursive over TRACKED files, so a new floor-bearing suite in a
# directory nobody anticipated is found rather than missed.
ALL_SUITES="$SUITE_TMP/all.txt"
git ls-files '*.test.sh' > "$ALL_SUITES"

FLOOR_ALL="$SUITE_TMP/floor-all.txt"
: > "$FLOOR_ALL"
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  is_floor_bearing "$f" && printf '%s\n' "$f" >> "$FLOOR_ALL"
done < "$ALL_SUITES"

# COVERED scope: the two directories this guard mutation-tests.
COVERED_DIRS='^(scripts/|plugins/soleur/test/)'

# DEFERRED scope: an EXPLICITLY DECLARED directory ledger. These carry floors this PR does
# not mutation-test — `apps/web-platform/infra/` is a different subsystem with its own
# runner (`run-registered-suites.sh`) — but they are counted, not forgotten.
#
# DECLARING these is load-bearing and was a real defect when it was not. The first version
# derived DEFERRED as "everything that is not COVERED", which makes
# `covered + deferred == total` an IDENTITY BY CONSTRUCTION: the two sets partition the
# same list, so the sum always equals the total and the arm can never fail. Caught by
# mutation — adding a floor-bearing suite under `apps/cla-evidence/scripts/` (a directory
# in neither scope) left the guard GREEN. With the ledger declared, that suite lands in
# UNCLASSIFIED and the guard reddens naming the file, which is the entire point.
DEFERRED_DIRS='^(apps/web-platform/infra/|apps/web-platform/scripts/|apps/web-platform/test/infra/|\.claude/hooks/|plugins/soleur/skills/[^/]+/test/)'

COVERED="$SUITE_TMP/covered.txt"
DEFERRED="$SUITE_TMP/deferred.txt"
UNCLASSIFIED="$SUITE_TMP/unclassified.txt"
{ grep -E "$COVERED_DIRS" "$FLOOR_ALL" || true; } > "$COVERED"
{ grep -E "$DEFERRED_DIRS" "$FLOOR_ALL" || true; } > "$DEFERRED"
# Anything floor-bearing that matches NEITHER declared scope.
{ grep -vE "$COVERED_DIRS" "$FLOOR_ALL" || true; } | { grep -vE "$DEFERRED_DIRS" || true; } > "$UNCLASSIFIED"
# And anything counted TWICE would satisfy the identity while covering nothing.
DOUBLE="$SUITE_TMP/double.txt"
{ grep -E "$COVERED_DIRS" "$FLOOR_ALL" || true; } | { grep -E "$DEFERRED_DIRS" || true; } > "$DOUBLE"

n_total=$(wc -l < "$FLOOR_ALL")
n_covered=$(wc -l < "$COVERED")
n_deferred=$(wc -l < "$DEFERRED")
n_unclassified=$(wc -l < "$UNCLASSIFIED")
n_double=$(wc -l < "$DOUBLE")

# ---------------------------------------------------------------------------------------
# MUTANT CONSTRUCTION — no declarations, no per-suite contract lines
# ---------------------------------------------------------------------------------------
#
# `command_not_found_handle() { return 0; }` neuters EVERY helper name at once. The mutant
# carries only the floor block, never the suite's helper definitions, so `fail`, `bad`,
# `nope` and every other verdict name are unfound commands. That is strictly stronger than
# a declared list of helper names, which can be under-declared — and it is why no suite
# needs to carry a `# vacuity-contract:` line for this guard to work on it.
#
# The slice is widened BACKWARD over contiguous simple assignments so threshold bindings
# (`MIN_ASSERTS=26`) are bound. Without that widening the mutant dies at an unbound
# variable BEFORE reaching the floor, exits non-zero, and a bare `rc != 0` oracle scores
# that crash as a pass. Measured: 8 of 11 target floors behaved exactly that way, which
# made them equivalent mutants — the arm proved nothing about them.
#
# Only COUNTER variables are zeroed. Thresholds keep their real values: zeroing a
# threshold inverts a `-ge` floor's polarity and destroys discrimination.
build_mutant() { # <suite> <floor-lineno> <out>
  local src="$1" ln="$2" out="$3" ifline indent end start prev t
  ifline="$(sed -n "${ln}p" "$src")"
  indent="$(printf '%s' "$ifline" | sed -E 's/^([[:space:]]*).*/\1/')"
  end="$(awk -v s="$ln" -v ind="^${indent}fi[[:space:]]*$" 'NR>=s && $0 ~ ind {print NR; exit}' "$src")"
  [[ -n "$end" ]] || return 1
  start="$ln"
  while [[ "$start" -gt 1 ]]; do
    prev=$((start - 1))
    t="$(sed -n "${prev}p" "$src")"
    if printf '%s' "$t" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^;]*$' \
       && ! printf '%s' "$t" | grep -qE '\$\('; then
      start="$prev"
    else
      break
    fi
  done
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    # THE NEUTERING. This is the fault under test.
    printf '%s\n' 'command_not_found_handle() { return 0; }'
    counters_of "$src" | while IFS= read -r c; do printf '%s=0\n' "$c"; done
    sed -n "${start},${end}p" "$src"
    # Appended rather than reconstructing each suite's trailer: this tests the property
    # directly — does the floor block ITSELF exit non-zero?
    printf '%s\n' 'exit 0'
  } > "$out"
  return 0
}

# THE ORACLE ASSERTS THE REASON, NOT THE EXIT CODE.
# A mutant that dies at an unbound variable also exits non-zero. Scoring that as a pass is
# how 8 of 11 floors came to be untested. Three outcomes, and the crash is its own loud
# class rather than either colour:
#   FIRES        -> non-zero AND a floor-shaped sentinel on stderr
#   NO_FIRE      -> exit 0: the floor is enforced THROUGH the machinery it guards
#   CONSTRUCTION -> non-zero with a shell-error signature and no sentinel
classify_mutant() { # <mutant> -> prints FIRES|NO_FIRE|CONSTRUCTION
  local m="$1" errf rc=0
  errf="${m}.err"
  bash "$m" >/dev/null 2>"$errf" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    printf 'NO_FIRE\n'
    return 0
  fi
  if grep -qaE 'unbound variable|command not found|syntax error|unexpected (EOF|end of file)' "$errf" \
     || [[ "$rc" -eq 2 ]]; then
    printf 'CONSTRUCTION\n'
    return 0
  fi
  if grep -qaiE 'FATAL|vacuity|cardinality|assertion floor|only .* (ran|dispatched)|did not execute' "$errf"; then
    printf 'FIRES\n'
    return 0
  fi
  printf 'CONSTRUCTION\n'
}

# Best outcome across every candidate floor in a file. A file may carry several counter
# comparisons; the suite passes if ANY of them is a floor that fires. Quantifying over the
# first match alone was measured to misclassify `verify-marketplace-ruleset` (its first
# candidate sits inside a helper that reads `$1`).
classify_suite() { # <suite> -> FIRES|NO_FIRE|CONSTRUCTION
  local f="$1" best="CONSTRUCTION" ln verdict m i=0
  while IFS= read -r ln; do
    [[ -n "$ln" ]] || continue
    i=$((i + 1))
    m="$SUITE_TMP/mut.$$.${i}.sh"
    if ! build_mutant "$f" "$ln" "$m"; then continue; fi
    verdict="$(classify_mutant "$m")"
    case "$verdict" in
      FIRES) printf 'FIRES\n'; return 0 ;;
      NO_FIRE) best="NO_FIRE" ;;
    esac
  done < <(floor_lines_of "$f" | cut -d: -f1)
  printf '%s\n' "$best"
}

FIRES_LIST="$SUITE_TMP/fires.txt"; : > "$FIRES_LIST"
NOFIRE_LIST="$SUITE_TMP/nofire.txt"; : > "$NOFIRE_LIST"
CONSTRUCT_LIST="$SUITE_TMP/construct.txt"; : > "$CONSTRUCT_LIST"

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case "$(classify_suite "$f")" in
    FIRES) printf '%s\n' "$f" >> "$FIRES_LIST" ;;
    NO_FIRE) printf '%s\n' "$f" >> "$NOFIRE_LIST" ;;
    *) printf '%s\n' "$f" >> "$CONSTRUCT_LIST" ;;
  esac
done < "$COVERED"

n_fires=$(wc -l < "$FIRES_LIST")
n_nofire=$(wc -l < "$NOFIRE_LIST")
n_construct=$(wc -l < "$CONSTRUCT_LIST")

printf '=== derived population ===\n'
printf '  repo-wide floor-bearing : %d\n' "$n_total"
printf '  covered (mutation-arm)  : %d\n' "$n_covered"
printf '  deferred (declared)     : %d\n' "$n_deferred"
printf '  unclassified (must be 0): %d\n' "$n_unclassified"
printf '  floor fires             : %d\n' "$n_fires"
printf '  floor does NOT fire     : %d\n' "$n_nofire"
printf '  mutant not constructible: %d\n' "$n_construct"
printf '\n'

# --- ARM 1: no covered suite may have a floor that fails to fire -------------------------
# This is the regression the guard exists to catch, and it needs no hardcoded suite list:
# a suite that regresses to a `fail`-routed floor lands here by derivation.
cases=$((cases + 1))
if [[ "$n_nofire" -eq 0 ]]; then
  pass "every covered floor survives a neutered assertion machinery ($n_fires suites)"
else
  fail "$n_nofire covered suite(s) have a floor that EXITS 0 under a neutered assertion machinery — the floor is enforced THROUGH the machinery it guards:"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$NOFIRE_LIST"
fi

# --- ARM 2: construction failures are counted and may only shrink ------------------------
# A floor whose mutant is not a runnable program (it reads state computed by surrounding
# code) is NOT silently skipped: it is named here and capped by a hand-ratcheted maximum.
# Ratcheting DOWN-only means new suites cannot quietly join the uncovered set.
MAX_CONSTRUCTION_FAILURES=17
cases=$((cases + 1))
if [[ "$n_construct" -le "$MAX_CONSTRUCTION_FAILURES" ]]; then
  pass "mutant-construction failures within the ratchet ($n_construct <= $MAX_CONSTRUCTION_FAILURES)"
else
  fail "mutant-construction failures GREW to $n_construct (ratchet is $MAX_CONSTRUCTION_FAILURES). A new floor joined the uncovered set:"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$CONSTRUCT_LIST"
fi

# --- ARM 3: the firing population may only grow ------------------------------------------
# Absolute and hand-ratcheted. Never derived from a variable this file computes: a floor
# that descends with the thing it guards is not a floor.
MIN_FIRING_SUITES=20
cases=$((cases + 1))
if [[ "$n_fires" -ge "$MIN_FIRING_SUITES" ]]; then
  pass "firing-floor population at or above the ratchet ($n_fires >= $MIN_FIRING_SUITES)"
else
  fail "firing-floor population SHRANK to $n_fires (ratchet is $MIN_FIRING_SUITES) — a floor stopped being mutation-tested"
fi

# --- ARM 4: closure over the repository --------------------------------------------------
# Every floor-bearing suite is either COVERED or in the DECLARED deferral ledger. The
# `total` is swept INDEPENDENTLY over the whole repo from floor shape, and both scopes are
# declared regexes — so a new floor-bearing suite in a directory nobody anticipated lands
# in neither and is NAMED here rather than disappearing.
cases=$((cases + 1))
if [[ "$n_unclassified" -eq 0 ]]; then
  pass "closure holds: every floor-bearing suite is covered ($n_covered) or declared-deferred ($n_deferred), total $n_total"
else
  fail "closure BROKEN: $n_unclassified floor-bearing suite(s) are in NEITHER the covered scope nor the declared deferral ledger:"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$UNCLASSIFIED"
fi

# --- ARM 5: no suite is counted in both scopes -------------------------------------------
# Double-counting would satisfy an arithmetic identity while covering nothing.
cases=$((cases + 1))
if [[ "$n_double" -eq 0 ]]; then
  pass "no suite is counted in both the covered scope and the deferral ledger"
else
  fail "$n_double suite(s) match BOTH scopes — double-counted, so the ledger overstates coverage"
fi

# --- ARM 5b: the sweep's scope is strictly wider than the covered scope ------------------
# Without this the whole closure check is satisfiable by sweeping only the covered
# directories, which would make it trivially true and prove nothing.
cases=$((cases + 1))
if [[ "$n_deferred" -gt 0 && "$n_total" -gt "$n_covered" ]]; then
  pass "the repo-wide sweep reaches outside the covered directories ($n_deferred declared-deferred)"
else
  fail "the repo-wide sweep found nothing outside the covered directories — the closure check has become circular"
fi

# --- ARM 6: population floor (the guard's own dispatch) ----------------------------------
cases=$((cases + 1))
MIN_POPULATION=30
if [[ "$n_covered" -ge "$MIN_POPULATION" ]]; then
  pass "derived population is non-empty and above its floor ($n_covered >= $MIN_POPULATION)"
else
  fail "derived population collapsed to $n_covered (floor $MIN_POPULATION) — the sweep is returning (almost) nothing and every arm above is vacuous"
fi

# --- ARM 7: NEGATIVE CONTROL --------------------------------------------------------------
# The arms above must be CAPABLE of failing. This builds the PRE-FIX shape by hand — a
# floor that reports through `fail` — and asserts it exits 0 under the same neutering. If
# this control ever turns non-zero, the arms above have stopped discriminating and this
# whole file is decorative.
control="$SUITE_TMP/prefix-shape.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'command_not_found_handle() { return 0; }'
  printf '%s\n' 'passes=0; fails=0; cases=0'
  # `-lt 1` deliberately, not a copy of a real floor: cases=0 fires any positive threshold,
  # so restating 75/121 here would only go stale when a floor is ratcheted.
  printf '%s\n' 'if [[ "$cases" -lt 1 ]]; then'
  printf '%s\n' '  fail "vacuity guard: only $cases assertions ran"'
  printf '%s\n' 'fi'
  printf '%s\n' 'exit 0'
} > "$control"
cases=$((cases + 1))
control_verdict="$(classify_mutant "$control")"
if [[ "$control_verdict" == "NO_FIRE" ]]; then
  pass "negative control: the pre-fix fail()-routed floor DOES exit 0 when neutered (so the arms above discriminate)"
else
  fail "negative control classified $control_verdict, expected NO_FIRE — this suite can no longer tell the two forms apart"
fi

# --- ARM 8: CONSTRUCTION-FAILURE CONTROL --------------------------------------------------
# The oracle must report a crash as a crash, never as a pass. This is the regression pin
# for the equivalent-mutant class: a floor whose threshold is unbound dies before the
# comparison, exits non-zero, and a bare `rc != 0` oracle would score it green.
crashctl="$SUITE_TMP/crash-shape.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'command_not_found_handle() { return 0; }'
  printf '%s\n' 'cases=0'
  printf '%s\n' 'if [[ "$cases" -lt "$MIN_NEVER_BOUND" ]]; then'
  printf '%s\n' '  printf "[FATAL] floor\\n" >&2; exit 1'
  printf '%s\n' 'fi'
  printf '%s\n' 'exit 0'
} > "$crashctl"
cases=$((cases + 1))
crash_verdict="$(classify_mutant "$crashctl")"
if [[ "$crash_verdict" == "CONSTRUCTION" ]]; then
  pass "construction control: an unbound threshold is reported as a construction failure, never as a fired floor"
else
  fail "construction control classified $crash_verdict, expected CONSTRUCTION — a crash is indistinguishable from a fired floor and the mutation arm is vacuous"
fi

# --- ARM 9: SYNTHESIZED OUT-OF-POPULATION MUST-PASS CONTROL -------------------------------
# Counter and helper names that appear nowhere else in the repo, and NOT named `*.test.sh`
# so it sits outside the derived population by construction. A control that is also a
# subject is not a control — the two suites previously used here were population members
# already exercised by the main loop.
FIXTURE="$REPO_ROOT/scripts/fixtures/vacuity-contract-control.sh"
cases=$((cases + 1))
if [[ -f "$FIXTURE" ]]; then
  pass "synthesized control fixture is present"
else
  fail "synthesized control fixture is missing at $FIXTURE — the must-PASS arm below is vacuous"
fi

cases=$((cases + 1))
if [[ -f "$FIXTURE" ]] && bash "$FIXTURE" >/dev/null 2>&1; then
  pass "synthesized control fixture runs green unmodified (the guard accepts a compliant shape it did not author)"
else
  fail "synthesized control fixture does not run green — the contract is not satisfiable by a third naming scheme"
fi

cases=$((cases + 1))
if [[ -f "$FIXTURE" ]] && ! grep -qE '^(scripts/fixtures/)' "$COVERED" 2>/dev/null; then
  pass "synthesized control sits OUTSIDE the derived population (it is a control, not a subject)"
else
  fail "the synthesized control has entered the derived population — it is no longer an independent control"
fi

# Its floor must fire under the same machinery, proving the derivation generalises past the
# names it was written against.
cases=$((cases + 1))
fixture_verdict="CONSTRUCTION"
if [[ -f "$FIXTURE" ]]; then
  fx_ln="$(floor_lines_of "$FIXTURE" | head -1 | cut -d: -f1)"
  if [[ -n "$fx_ln" ]] && build_mutant "$FIXTURE" "$fx_ln" "$SUITE_TMP/fixture.mutant.sh"; then
    fixture_verdict="$(classify_mutant "$SUITE_TMP/fixture.mutant.sh")"
  fi
fi
if [[ "$fixture_verdict" == "FIRES" ]]; then
  pass "synthesized control's floor FIRES under neutering despite third-party counter names (tally/good/bad_n)"
else
  fail "synthesized control's floor classified $fixture_verdict — the derivation only works against names it was written for"
fi

# --- ARM 10: conservation is non-tautological ---------------------------------------------
# `passes + fails == cases` is load-bearing ONLY when `cases` moves independently of the
# verdict. A counter incremented INSIDE both verdict helpers moves WITH the verdict, so
# stubbing `fail` drops the row and its count together and the identity still holds under
# the exact fault it exists to catch. Measured on the `ok`/`bad` shape before the fix:
# `conservation GREEN — defect hidden`, RC=0.
#
# Checked statically and structurally: no suite carrying a conservation check may increment
# its case counter inside a verdict helper body. Static because running 40 full suites here
# would make this guard as slow and flaky as the batteries it guards.
CONSERVING="$SUITE_TMP/conserving.txt"; : > "$CONSERVING"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if grep -qaE '\[FATAL\] accounting' "$f"; then printf '%s\n' "$f" >> "$CONSERVING"; fi
done < "$COVERED"
n_conserving=$(wc -l < "$CONSERVING")

MIN_CONSERVING=7
cases=$((cases + 1))
if [[ "$n_conserving" -ge "$MIN_CONSERVING" ]]; then
  pass "suites carrying an accounting-conservation check: $n_conserving (>= $MIN_CONSERVING)"
else
  fail "only $n_conserving suite(s) carry a conservation check, ratchet is $MIN_CONSERVING — a conservation check was removed"
fi

# Every conserving suite must report its conservation failure DIRECTLY. A conservation
# check that calls `fail` has the same defect as a floor that calls `fail`.
tautological=""
direct_ok=1
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  # the accounting sentinel must be on a printf that redirects to stderr
  if ! grep -qaE "printf.*\[FATAL\] accounting" "$f"; then
    direct_ok=0; tautological="$tautological $f(not-direct)"
  fi
done < "$CONSERVING"
cases=$((cases + 1))
if [[ "$direct_ok" -eq 1 ]]; then
  pass "every conservation check reports directly, never through the suite's own verdict helpers"
else
  fail "conservation check(s) not reported directly:$tautological"
fi

# No conserving suite may increment its case counter inside a verdict helper body, and none
# may increment inside a command substitution (a subshell discards it). `$\([^(]` is the
# COMMAND substitution `$(`; a pattern without the `[^(]` also matches the arithmetic `$((`
# and is unsatisfiable for any file that increments a counter at all.
subshell_offenders=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if grep -qaE '\$\([^(][^)]*[A-Za-z_]*(cases|ASSERTED|asserts|tally)[A-Za-z_]*[^)]*\+ 1' "$f"; then
    subshell_offenders="$subshell_offenders $f"
  fi
done < "$CONSERVING"
cases=$((cases + 1))
if [[ -z "$subshell_offenders" ]]; then
  pass "no case-counter increment sits inside a command substitution (a subshell would discard it)"
else
  fail "case-counter increment inside a command substitution — discarded to a subshell:$subshell_offenders"
fi

printf '\n'

# ---------------------------------------------------------------------------------------
# THIS SUITE'S OWN FLOOR. The same rule it enforces on the others: reported directly, never
# through `fail`, so it cannot be silenced by the fault it exists to catch. Ratcheted by
# hand; never derived from a variable this file computes, because a floor that descends
# with the thing it guards is not a floor.
# ---------------------------------------------------------------------------------------
MIN_META_CASES=16
if [[ "$cases" -lt "$MIN_META_CASES" ]]; then
  printf '\n[FATAL] meta-guard vacuity: only %d assertion(s) ran; expected >= %d.\n' \
    "$cases" "$MIN_META_CASES" >&2
  printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
  exit 1
fi

# ACCOUNTING CONSERVATION — the arm that actually catches a neutered `fail()`.
# The floor above catches "no assertions RAN". It cannot catch "assertions ran and their
# verdicts were discarded", because `cases` is incremented at the CALL SITE and never by
# `fail` — so stubbing `fail` leaves `cases` at full value, the floor is satisfied, and the
# suite exits 0 with real failures silenced.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  if [[ $((passes + fails)) -lt "$cases" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it.\n' >&2
  fi
  exit 1
fi

printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
