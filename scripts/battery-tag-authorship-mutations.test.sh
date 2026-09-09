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
cd "$REPO_ROOT"
SUBJECT="$REPO_ROOT/scripts/battery-tag-authorship.test.sh"

passes=0
fails=0
asserted=0
ck() { asserted=$((asserted + 1)); }
pass() { passes=$((passes + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# Instrument self-test — drives both helpers, reports through neither.
_p=$passes; _f=$fails; _a=$asserted
{ pass "instrument self-test (expected)"; fail "instrument self-test (expected — subtracted)"; ck; } >/dev/null 2>&1
if (( passes != _p + 1 || fails != _f + 1 || asserted != _a + 1 )); then
  printf '[FATAL] instrument self-test: helpers did not each move their own counter\n' >&2
  exit 1
fi
passes=$_p; fails=$_f; asserted=$_a

WORK="$(mktemp -d -t battagmut.XXXXXXXX)"
PRISTINE="$WORK/pristine.sh"
cp "$SUBJECT" "$PRISTINE"
trap 'rm -rf "$WORK"' EXIT

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
  # Measured: without the placeholder all 14 rows reported "mutation did NOT land", which is
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
    elif { grep -qF "$expect" "$WORK/out"; }; then
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
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/__absent__.sh\")|" -e "s/offenders + 1/offenders + 0/g" "$1"'

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
row R4a "fixture-direction/control" RED "undeclared tag-authoring command" \
  'sed -i "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/__absent__.sh\")|" "$1"'

row R4b "fixture-direction/conjunct" GREEN "" \
  'sed -i -e "s|^FIXTURE_EXCLUSION=.*|FIXTURE_EXCLUSION=(\"scripts/__absent__.sh\")|" -e "/tagOpt) \]\] \&\& return 1/d" "$1"'

# Axis: MEMBER CARDINALITY — empty the exemption ledger; every declared site must resurface.
row R5 "ledger/empty" RED "undeclared tag-authoring command" \
  'python3 - "$1" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"LEDGER=\(\n.*?\n\)\n","LEDGER=()\n",s,count=1,flags=re.S)
open(p,"w").write(s)
PY'

# Axis: THE GUARD'S OWN OPERAND — a ghost entry must be caught as an ORPHAN, i.e. the
# bijection is checked in BOTH directions, not just ledger-covers-sites.
row R6 "ledger/orphan" RED "orphan ledger" \
  'python3 - "$1" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("LEDGER=(\n","LEDGER=(\n  '"'"'nonexistent/file.sh|git fetch origin ghost'"'"'\n",1)
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

# --- summary --------------------------------------------------------------------------------
printf '\n'
printf 'AXES PERTURBED: offender-arm, dispatch(fail), dispatch(ck), suppress-negative-conjunct,\n'
printf '  ledger-empty, ledger-orphan, ledger-ceiling, ceiling-ADR-parity, roots-floor,\n'
printf '  occurrence-array-spelling, source-coverage-witness, degenerate-root, unclassified-accounting,\n'
printf '  plus one must-pass inert edit.\n'
printf 'AXES NOT PERTURBED, stated rather than implied: the closure fixpoint depth bound, the\n'
printf '  heredoc/comment approximations, and the nested-runner delegation. Those are declared\n'
printf '  approximations in the subject header and are not asserted here.\n\n'

BATTERY_TAG_MUT_MIN_ASSERTIONS=16
printf 'battery-tag-authorship-mutations: %d passed, %d failed, %d assertion(s) executed\n' \
  "$passes" "$fails" "$asserted"

if (( asserted < BATTERY_TAG_MUT_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < BATTERY_TAG_MUT_MIN_ASSERTIONS=%d\n' "$asserted" "$BATTERY_TAG_MUT_MIN_ASSERTIONS" >&2
  exit 1
fi
if (( passes + fails != asserted )); then
  printf '[FATAL] accounting conservation: passes(%d) + fails(%d) != asserted(%d)\n' "$passes" "$fails" "$asserted" >&2
  exit 1
fi

(( fails == 0 )) || exit 1
exit 0
