#!/usr/bin/env bash
# Mutation battery for scripts/battery-tag-authorship.test.sh.
#
# WHAT A BATTERY IS WORTH IS THE NUMBER OF DISTINCT AXES IT PERTURBS, not the number of rows.
# N mutations of one shape is one mutation. The axes below are named per row and the set is
# stated in the summary, so a reader can see what this battery does NOT cover rather than
# inferring completeness from a row count.
#
# THREE INSTRUMENT RULES, each of which this battery's own subject learned the hard way
# (2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md):
#
#   1. CONTROL FIRST. An unmutated copy must be GREEN through the same harness that runs the
#      rows. A red control voids every row, and the rows will still print verdicts.
#   2. ASSERT THE MUTATION LANDED, against a pristine copy. A mutation that does not land
#      reports the BASELINE, which is indistinguishable from a pass. Byte-identical => UN-RUN,
#      which is a FAILURE of the row, never a pass.
#   3. A row asserts the guard's OWN diagnostic, not a bare non-zero exit. Any bug exits
#      non-zero; only the message says the guard caught the thing this row planted.
#
# The subject is driven through its BATTERY_TAG_REPO_ROOT / BATTERY_TAG_RUNNER seam so every
# row grades the same program that produces the live census. Verified once, as row CONTROL:
# the seamed unmutated copy's census is identical to the live run's.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { printf 'ERROR: cannot cd to REPO_ROOT (%s)\n' "$REPO_ROOT" >&2; exit 2; }
SUBJECT="$REPO_ROOT/scripts/battery-tag-authorship.test.sh"

passes=0
fails=0
asserted=0
ck() { asserted=$((asserted + 1)); }
pass() { passes=$((passes + 1)); printf '  PASS: %s\n' "$1"; }
# ROWS_LOG is the APPEND-ONLY observable the final verdict re-derives from. It starts at
# /dev/null because fail() is driven by the instrument self-test below, before WORK exists.
ROWS_LOG=/dev/null
fail() { fails=$((fails + 1)); printf '  FAIL: %s\n' "$1" >&2; printf '  FAIL: %s\n' "$1" >> "$ROWS_LOG"; }

# Instrument self-test — drives both helpers, reports through neither.
_p=$passes; _f=$fails; _a=$asserted
{ pass "instrument self-test (expected)"; fail "instrument self-test (expected — subtracted)"; ck; } >/dev/null 2>&1
if (( passes != _p + 1 || fails != _f + 1 || asserted != _a + 1 )); then
  printf '[FATAL] instrument self-test: helpers did not each move their own counter\n' >&2
  exit 1
fi
passes=$_p; fails=$_f; asserted=$_a

WORK="$(mktemp -d -t battagmut.XXXXXXXX)" || { printf 'FATAL: cannot create scratch root\n' >&2; exit 2; }
# An empty WORK would make "$WORK/pristine.sh" resolve to /pristine.sh and `rm -rf "$WORK"` a
# silent no-op. The subject enforces exactly this invariant on REPO_ROOT; so does the sibling
# `scripts/lib/repo-write-boundary.test.sh` on its own scratch root.
[[ "$WORK" == /* && -d "$WORK" ]] || { printf 'FATAL: scratch root is not an absolute directory (%s)\n' "$WORK" >&2; exit 2; }
ROWS_LOG="$WORK/rows"
: > "$ROWS_LOG"
PRISTINE="$WORK/pristine.sh"
cp "$SUBJECT" "$PRISTINE"
# THE VERDICT LIVES IN THE EXIT TRAP, not only in a tail line, and that is the whole point.
# Measured before this existed: deleting the file's final one-line verdict made the
# battery print "7 passed, 9 failed" and exit 0 — nine real row failures, green suite. Nothing in
# the repo notices: `run_suite` judges on the child rc alone, and `guard-vacuity-floor.test.sh`
# states outright that it never runs a guarded suite to completion. A tail line is one deletion
# away from silence; a trap has to be deleted TOO, and the trap re-derives the verdict from an
# APPEND-ONLY observable (the printed FAIL lines) rather than from the counter the rows move, so
# neutering the counter alone leaves the log disagreeing with it and that disagreement is fatal.
_battery_exit_verdict() {
  local rc=$?
  local printed=0
  [[ -n "${ROWS_LOG:-}" && -f "$ROWS_LOG" ]] && printed=$({ grep -cE '^  FAIL: ' "$ROWS_LOG" || true; })
  [[ -n "${WORK:-}" ]] && rm -rf "$WORK"
  if (( printed != fails )); then
    printf '[FATAL] verdict channel: %d printed FAIL line(s) but fails=%d — one of the two is lying\n' \
      "$printed" "$fails" >&2
    exit 1
  fi
  (( printed > 0 || fails > 0 )) && exit 1
  exit "$rc"
}
trap _battery_exit_verdict EXIT INT TERM

# run_subject <file> -> writes stdout+stderr to $WORK/out, prints rc
run_subject() {
  local f="$1" rc=0
  BATTERY_TAG_REPO_ROOT="$REPO_ROOT" BATTERY_TAG_RUNNER="$REPO_ROOT/scripts/test-all.sh" \
    timeout 400 bash "$f" > "$WORK/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# row <id> <axis> <want RED|GREEN> <expect-substring> <sed-or-python mutation applied to $m>
row() {
  local id="$1" axis="$2" want="$3" expect="$4" mut="$5"
  local m="$WORK/m.sh" rc
  cp "$PRISTINE" "$m"
  # apply
  # `bash -c <script> arg` binds arg to $0, NOT $1 — so a mutation written against "$1" edits
  # nothing and the row silently measures the baseline. Pass an explicit $0 placeholder.
  # Measured: without the placeholder all 20 rows reported "mutation did NOT land", which is
  # rule 2 working as designed — the alternative was 14 rows scoring an unmutated file.
  bash -c "$mut" _mutation "$m" >/dev/null 2>&1 || true
  ck
  # RULE 2: assert the mutation LANDED. Byte-identical is UN-RUN, never a pass.
  if cmp -s "$PRISTINE" "$m"; then
    fail "$id [$axis] — mutation did NOT land (byte-identical to pristine): this row measured NOTHING"
    return
  fi
  rc="$(run_subject "$m")"
  if [[ "$want" == RED ]]; then
    if [[ "$rc" == "0" ]]; then
      fail "$id [$axis] — guard stayed GREEN under a mutation that must red it"
    elif { grep -vE '^  \[ok\] ' "$WORK/out" | grep -qF "$expect"; }; then
      pass "$id [$axis] — guard red with its own diagnostic"
    else
      fail "$id [$axis] — guard red, but NOT for the planted reason (expected: $expect)"
      { grep -E '^\s*\[FAIL\]' "$WORK/out" || true; } | head -3 | sed 's/^/        /' >&2
    fi
  else
    if [[ "$rc" == "0" ]]; then
      pass "$id [$axis] — guard stayed GREEN as required"
    else
      fail "$id [$axis] — guard red on a mutation that changes no property it asserts"
      { grep -E '^\s*\[FAIL\]' "$WORK/out" || true; } | head -3 | sed 's/^/        /' >&2
    fi
  fi
}

# FIXTURE for R4a/R4b. NEVER CALLED. Its command carries --no-tags AND --tags, which is the
# shape the guard's negative conjunct refuses to grade SUPPRESSED (git does not document that
# precedence, so guessing it would be a fail-open). This file is excluded from the guard's scan
# by FIXTURE_EXCLUSION; R4a/R4b remove that exclusion so the fixture becomes reachable.
_fixture_positive_tag_request() {
  git fetch --no-tags --tags origin main
}

# The other two fixtures live in their OWN files under tests/scripts/fixtures/ — see
# tests/scripts/fixtures/battery-tag-bare-fetch.sh and
# tests/scripts/fixtures/battery-tag-marker-no-ledger.sh. FIXTURE_EXCLUSION is keyed by PATH, so
# fixtures sharing a file become visible together and no row could isolate one. Measured: putting
# all three here made R4b red for a reason it does not test.

printf '=== battery-tag-authorship mutation battery ===\n'

# --- CONTROL (rule 1) -----------------------------------------------------------------------
ck
control_rc="$(run_subject "$PRISTINE")"
if [[ "$control_rc" == "0" ]]; then
  pass "CONTROL — unmutated subject is GREEN through the seam, so every row below scores a real mutation"
else
  fail "CONTROL — unmutated subject is RED (rc=$control_rc). EVERY ROW BELOW IS VOID."
  { grep -E '^\s*\[FAIL\]' "$WORK/out" || true; } | head -5 | sed 's/^/        /' >&2
  printf '\nbattery-tag-authorship-mutations: control failed; refusing to report row verdicts\n' >&2
  exit 1
fi

# --- rows -----------------------------------------------------------------------------------
# Axis: THE FLOOR ITSELF — is the offender COUNTER load-bearing?
#
# This row went through two honest failures worth recording, because each looked like something
# it was not.
#
#   (1) The mutation would not LAND. `python3 - "$1" <<PY` inside a single-quoted bash string
#       leaves the heredoc UNQUOTED, so bash expanded `$((offenders + 1))` to `1` before python
#       saw it and the search string never existed. Rewriting it as `<<'PY'` does NOT fix that:
#       bash consumes the quotes as string concatenation and reassembles `<<PY`. The durable fix
#       is an anchor carrying no `$`.
#   (2) Once it landed, the guard stayed GREEN — and that was CORRECT. Phase 4 closed every
#       offender, so `offenders` is already 0 and neutering its increment changes nothing
#       observable. The mutant was EQUIVALENT in the post-GREEN tree, not survived-because-weak.
#
# So the row is paired, exactly like R4: the fixture supplies the offender that the tree no
# longer has. R4a (exclusion removed, everything else intact) is this row's positive control
# too — it proves the fixture reaches the guard at all. Then neutering the counter must turn
# that RED into a GREEN, which is what makes the counter load-bearing rather than decorative.
row R1 "offender-counter/load-bearing" GREEN "" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/__absent__.sh\" \"tests/scripts/fixtures/battery-tag-bare-fetch.sh\" \"tests/scripts/fixtures/battery-tag-marker-no-ledger.sh\")|" -e "s/offenders + 1/offenders + 0/g" "$1"'

# Axis: DISPATCH — neuter the assertion helpers; the floor must catch it, not the helpers.
row R2 "dispatch/fail" RED "helper self-test" \
  'sed -i "s/^fail() { fails=\$((fails + 1));/fail() { fails=\$((fails + 0));/" "$1"'

# Axis: DISPATCH — neuter ck(); the pre-case self-test must catch it before any case runs.
row R3 "dispatch/ck" RED "helper self-test" \
  'sed -i "s/^ck() { asserted=\$((asserted + 1)); }/ck() { :; }/" "$1"'

# Axis: FIXTURE DIRECTION — the negative conjunct, exercised by a REAL fixture.
#
# This row was a SURVIVING mutant on the first run, and the honest reading was fixture
# inadequacy rather than an equivalent mutant: removing the conjunct changed no verdict because
# NO SITE IN THE TREE carries a positive tag request alongside --no-tags. The conjunct is still
# load-bearing — `git fetch --no-tags` with an explicit refs/tags refspec fetches tags anyway,
# and `--no-tags --tags` precedence is NOT documented, so the guard refuses to guess.
#
# The fixture is _fixture_positive_tag_request() above: an UNCALLED function whose command
# carries both flags. This file is normally invisible to the guard (FIXTURE_EXCLUSION), so both
# rows first remove that exclusion. Two rows, because either alone proves nothing:
#   R4a — exclusion removed, conjunct INTACT  -> guard must RED (the fixture reaches it)
#   R4b — exclusion removed, conjunct REMOVED -> guard goes GREEN (the conjunct is what caught it)
# R4a is R4b's positive control: without it, R4b's green is indistinguishable from a fixture the
# guard never saw in the first place.
row R4a "fixture-direction/control" RED "undeclared tag-authoring command(s)" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/__absent__.sh\" \"tests/scripts/fixtures/battery-tag-bare-fetch.sh\" \"tests/scripts/fixtures/battery-tag-marker-no-ledger.sh\")|" "$1"'

row R4b "fixture-direction/conjunct" GREEN "" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/__absent__.sh\" \"tests/scripts/fixtures/battery-tag-bare-fetch.sh\" \"tests/scripts/fixtures/battery-tag-marker-no-ledger.sh\")|" -e "/tagOpt) \]\] \&\& return 1/d" "$1"'

# Axis: MEMBER CARDINALITY — empty the exemption ledger; every declared site must resurface.
row R5 "ledger/empty" RED "undeclared tag-authoring command(s)" \
  'python3 - "$1" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"LEDGER=\(\n.*?\n\)\n","LEDGER=()\n",s,count=1,flags=re.S)
open(p,"w").write(s)
PY'

# The ghost key deliberately names NO git verb. It used to read `git fetch origin ghost`, which
# made this row's own text a tag-authoring occurrence in any row that lifts this file's exclusion
# — R4a then reddened partly for the ghost rather than for its fixture, and R4b (which must go
# GREEN) reddened outright. An orphan is detected by the key having no matching SITE; the key's
# text never needed to look like a command.
# Axis: THE GUARD'S OWN OPERAND — a ghost entry must be caught as an ORPHAN, i.e. the
# bijection is checked in BOTH directions, not just ledger-covers-sites.
row R6 "ledger/orphan" RED "orphan ledger" \
  'python3 - "$1" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("LEDGER=(\n","LEDGER=(\n  '"'"'nonexistent/file.sh|ghost-entry-with-no-site'"'"'\n",1)
open(p,"w").write(s)
PY'

# Axis: POPULATION GROWTH — a ceiling that cannot bind is not a ceiling.
row R7 "ledger/ceiling" RED "exceeds ceiling" \
  'sed -i "s/^LEDGER_CEILING=12$/LEDGER_CEILING=3/" "$1"'

# Axis: AUTHORITY/ROOT INPUT — the ceiling has ONE home; drift from it must red.
row R8 "ceiling/adr-parity" RED "ceiling drift" \
  'sed -i "s/^LEDGER_CEILING=12$/LEDGER_CEILING=13/" "$1"'

# Axis: AUTHORITY/ROOT INPUT — a collapsed root set must red BEFORE any classification.
row R9 "roots/floor" RED "root set collapsed" \
  'sed -i "s/^MIN_ROOTS=400$/MIN_ROOTS=99999/" "$1"'

# Axis: REGION BOUNDARIES / fail-OPEN — drop the array-form occurrence pattern so the TS site
# goes unseen. Before AC31's named witnesses existed this row was VACUOUS: the guard simply went
# green while seeing less, and no assertion could tell. The witness is what makes a silent loss
# loud, which is why the row expects RED on the witness message specifically.
row R10 "occurrence/array-spelling" RED "LOST its named witness for the array spelling" \
  'sed -i "s|^ARRAY_RE=.*|ARRAY_RE='"'"'__NEVER_MATCHES__'"'"'|" "$1"'

# Axis: SOURCE COVERAGE — remove a witness from the root set assertion.
row R11 "witness/source-coverage" RED "witness MISSING" \
  'python3 - "$1" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("for w in scripts/lib/repo-write-boundary.test.sh","for w in scripts/NO_SUCH_WITNESS.test.sh",1)
open(p,"w").write(s)
PY'

# Axis: THE GUARD'S OWN OPERAND — degenerate REPO_ROOT must be REFUSED, not accepted as "/".
row R12 "root/degenerate" RED "not absolute" \
  'sed -i "s|^REPO_ROOT=\"\${BATTERY_TAG_REPO_ROOT:-.*|REPO_ROOT=\"relative/path\"|" "$1"'

# Axis: ACCOUNTING — empty the out-of-class ledger. The shape it covers must then surface as
# UNCLASSIFIED rather than being silently dropped: AC6's two-places-and-no-third rule.
row R13 "accounting/out-of-class" RED "UNCLASSIFIED" \
  'python3 - "$1" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"OUT_OF_CLASS=\(\n.*?\n\)\n","OUT_OF_CLASS=()\n",s,count=1,flags=re.S)
open(p,"w").write(s)
PY'

# MUST-PASS: an edit that changes no property the guard asserts must NOT red it. Without this
# row every RED above is consistent with a guard that reds on anything at all.
row MUSTPASS "must-pass/inert-edit" GREEN "" \
  'printf "\n# inert trailing comment added by the mutation battery\n" >> "$1"'

# --- fail-open survivors found by review, each now paired -------------------------------------
# Every row below follows the R4a/R4b discipline: a CONTROL proving the fixture reaches the
# guard at all, then the mutation, whose GREEN is only meaningful because the control was RED.
# All three components these pin were measured SURVIVING a mutation before these rows existed.

# Axis: THE VERB SET — is `fetch|pull` in VERB_RE load-bearing? Measured surviving: dropping it
# took occurrences 41 -> 13 and the guard stayed GREEN over a live unsuppressed fetch.
row R14a "verb-set/control" RED "undeclared tag-authoring command(s)" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/battery-tag-authorship-mutations.test.sh\" \"scripts/__absent__.sh\" \"tests/scripts/fixtures/battery-tag-marker-no-ledger.sh\")|" "$1"'

row R14b "verb-set/fetch-pull" GREEN "" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/battery-tag-authorship-mutations.test.sh\" \"scripts/__absent__.sh\" \"tests/scripts/fixtures/battery-tag-marker-no-ledger.sh\")|" -e "s/(fetch|pull|remote\[\[:space:\]\]+update|tag|update-ref)/(remote[[:space:]]+update|tag|update-ref)/" "$1"'

# Axis: THE SUPPRESSION PREDICATE's FIRST conjunct. R4b already pins the negative conjunct;
# this pins the `--no-tags` requirement itself. Measured surviving: without it a bare
# `git fetch origin main` grades SUPPRESSED despite carrying no suppression at all.
row R15 "suppress/no-tags-conjunct" GREEN "" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/battery-tag-authorship-mutations.test.sh\" \"scripts/__absent__.sh\" \"tests/scripts/fixtures/battery-tag-marker-no-ledger.sh\")|" -e "/=~ --no-tags/d" "$1"'

# Axis: THE LEDGER-MEMBERSHIP PREDICATE. R5 and R6 mutate the ledger's CONTENTS; neither touches
# the `in_ledger` test that reads it. Measured surviving: making it unconditional graded a
# marker-without-entry site EXEMPT — exactly the copy-pasted-marker case the two-key design
# exists to stop.
row R16a "ledger/membership-control" RED "undeclared tag-authoring command(s)" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/battery-tag-authorship-mutations.test.sh\" \"tests/scripts/fixtures/battery-tag-bare-fetch.sh\" \"scripts/__absent__.sh\")|" "$1"'

row R16b "ledger/membership-predicate" GREEN "" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/battery-tag-authorship-mutations.test.sh\" \"tests/scripts/fixtures/battery-tag-bare-fetch.sh\" \"scripts/__absent__.sh\")|" -e "s/if (( in_ledger )); then/if (( 1 )); then/" "$1"'

# --- summary --------------------------------------------------------------------------------
printf '\n'
printf 'AXES PERTURBED: offender-arm, dispatch(fail), dispatch(ck), suppress-negative-conjunct,\n'
printf '  suppress-no-tags-conjunct, verb-set(fetch|pull), ledger-empty, ledger-orphan,\n'
printf '  ledger-ceiling, ledger-MEMBERSHIP-predicate, ceiling-ADR-parity, roots-floor,\n'
printf '  occurrence-array-spelling, source-coverage-witness, degenerate-root,\n'
printf '  unclassified-accounting, plus one must-pass inert edit.\n'
printf 'AXES NOT PERTURBED, stated rather than implied — a count of rows is not a count of axes,\n'
printf '  and each of these is a place a future regression could hide:\n'
printf '    - the string-literal parity skip (_in_string_literal). It is the ONE arm that REMOVES\n'
printf '      occurrences, so it is the one place a false green can hide, and no row drives it.\n'
printf '    - the Stage B reference regex (which path spellings become closure members).\n'
printf '    - MIN_ROOTS and MIN_CLOSURE downward; neither has an authority parity like the\n'
printf '      ledger ceiling has against ADR-207.\n'
printf '    - NESTED_RUNNERS / MIN_INFRA_DERIVED, and the -B2 marker context window.\n'
printf '    - the heredoc/comment approximations, declared in the subject header.\n'
printf '  The fixpoint depth bound WAS unperturbed and is now asserted directly by the subject\n'
printf '  (it distinguishes converged from exhausted), so it no longer needs a row here.\n\n'

printf 'battery-tag-authorship-mutations: %d passed, %d failed, %d assertion(s) executed\n' \
  "$passes" "$fails" "$asserted"

# THE BINDING BELOW SITS FLUSH AGAINST THE `if`, WITH NO BLANK LINE OR COMMENT BETWEEN THEM,
# for the reason the SUBJECT's own floor comment gives: `scripts/guard-vacuity-floor.test.sh`
# builds its mutant by slicing the floor block and widening BACKWARD over CONTIGUOUS simple
# assignments, stopping at the first line that is not one. This file previously declared the
# threshold four lines up, behind a `printf` and a blank line, so the mutant lost the binding,
# died at an unbound variable under `set -u` BEFORE reaching the floor, and was scored
# CONSTRUCTION — an UNCOVERED floor, which is the opposite of what a floor is for. The subject
# documented the rule and this file, its sibling, broke it.
BATTERY_TAG_MUT_MIN_ASSERTIONS=21
if (( asserted < BATTERY_TAG_MUT_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < BATTERY_TAG_MUT_MIN_ASSERTIONS=%d\n' "$asserted" "$BATTERY_TAG_MUT_MIN_ASSERTIONS" >&2
  exit 1
fi
if (( passes + fails != asserted )); then
  printf '[FATAL] accounting conservation: passes(%d) + fails(%d) != asserted(%d)\n' "$passes" "$fails" "$asserted" >&2
  exit 1
fi

# HARNESS RED-PATH SELF-CHECK. Everything above proves the SUBJECT reddens; nothing proved that
# THIS file can. Measured: deleting the verdict line below made the battery print
# "7 passed, 9 failed" and exit 0, with nine real row failures — and no gate in the repo notices,
# because `run_suite` judges on the child rc alone and `guard-vacuity-floor.test.sh` states it
# never runs a guarded suite to completion. So the verdict is re-derived here from an
# APPEND-ONLY observable (the printed FAIL lines) rather than from the same counter the rows
# move, and a disagreement between the two is itself fatal.
# Defence in depth: the EXIT trap above is the load-bearing verdict, this is the ordinary one.
# Deleting EITHER alone leaves the other reporting.
(( fails == 0 )) || exit 1
exit 0
