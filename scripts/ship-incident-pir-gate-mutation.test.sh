#!/usr/bin/env bash
# ship-incident-pir-gate-mutation.test.sh — the mutation battery for the Incident-PIR
# hypothetical-paragraph strip in scripts/ship-incident-pir-gate.sh (#7801).
#
# WHY THIS EXISTS: the strip is a STATEFUL awk program, and a fixture suite alone cannot tell a
# load-bearing rule from a decorative one — SEVEN of the original ten fixtures pass on `main`
# unchanged (F1, F9 and F10 are the three that redden). So
# "does each rule of this stage do anything?" is answered nowhere else.
#
# FIVE STRUCTURAL REQUIREMENTS, each closing a defect this repo has already paid for:
#
#   1. GREEN BASELINE FIRST. The unmutated control runs before any row and must be GREEN; a red
#      control ABORTS rather than scoring rows, because every row would "flip" vacuously.
#
#   2. PLACEMENT VIA CONTENT ANCHOR, NOT A LINE COUNT. An earlier revision asserted "this mutation
#      changes exactly 23 lines", which fails on a comment-only edit inside the stage and says
#      nothing about WHERE the edit landed. Each row now names a grep anchor and the count it must
#      have in the mutant (`cq-cite-content-anchor-not-line-number`).
#
#   3. A row whose edit produced no change is reported VACUOUS and FAILS — never counted as a pass.
#
#   4. NO MUTATION IS APPLIED INSIDE A COMMAND SUBSTITUTION. A failure inside `$( )` cannot fail
#      the suite.
#
#   5. A POSITIVE CONTROL drives pass() and fail() once each and refuses to continue unless BOTH
#      counters moved. An assertion-count floor cannot see a rewritten fail() that still counts,
#      and the floor is emitted directly rather than through the helper it backstops.
#
# RESTORE IS FROM A PRISTINE COPY, never `git checkout` — the fix under test may be uncommitted,
# and `git checkout` would restore HEAD and score every later row against a file that no longer
# contains the thing under test.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIG="$REPO_ROOT/scripts/ship-incident-pir-gate.sh"
FIX="$REPO_ROOT/plugins/soleur/test/fixtures/ship-incident-pir-gate"

WORK="$(mktemp -d "$TMPDIR/pir-mutbat.XXXXXXXX")" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT
PRISTINE="$WORK/pristine.sh"
cp "$ORIG" "$PRISTINE" || { echo "FATAL: could not copy the SUT"; exit 2; }

fails=0; passes=0; rows=0; asserted=0
pass() { passes=$((passes+1)); asserted=$((asserted+1)); printf '[ok]   %s\n' "$1"; }
fail() { fails=$((fails+1));  asserted=$((asserted+1)); printf '[FAIL] %s\n' "$1"; }

# --- requirement 5: positive control, BEFORE anything depends on the helpers ----------------
_p0=$passes; _f0=$fails
pass "positive control: pass() increments"
# stdout suppressed so this deliberate call cannot be mistaken for a real failure by a reader
# or by a `grep -c '^\[FAIL\]'` check; the counters still move, which is the whole assertion.
fail "positive control: fail() increments" >/dev/null
if [ "$passes" -ne $((_p0+1)) ] || [ "$fails" -ne $((_f0+1)) ]; then
  printf 'FATAL: assertion helpers do not both count — every verdict below would be meaningless\n' >&2
  exit 2
fi
fails=$((fails-1)); asserted=$((asserted-1))   # retract BOTH counters the control's deliberate FAIL moved
pass "positive control: fail() increments (verified via counters, line suppressed)"

verdict() { if bash "$1" < "$FIX/$2" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# Canonical expectations under the UNMUTATED gate.
FIXTURES="precedent-citation-inside-hypothetical-paragraph.md:no
real-outage-claimed-inside-hypothetical-paragraph.md:yes
real-outage-after-hypothetical-paragraph.md:yes
real-outage-in-sibling-bullet.md:yes
real-outage-after-heading-boundary.md:yes
real-outage-in-nested-sub-bullet.md:yes
real-outage-after-fenced-block-abutting-paragraph.md:yes
midsentence-conditional-does-not-open-a-paragraph.md:yes
reflowed-citation-with-issue-ref-continuation.md:no
real-outage-inside-paragraph-without-actuality-idiom.md:no
bulleted-label-consumed-by-trigger.md:no
actuality-occurred-inflection.md:yes
actuality-outranks-conditional-clause.md:yes
unbalanced-fence-does-not-swallow-the-tail.md:yes
negated-outage-only.md:no
denial-specimen-8334.md:no
two-tokens-both-denied.md:no
actuality-line-only-token-denied.md:no
negation-cue-not.md:no
negation-cue-rather-than.md:no
negation-in-prior-clause-real-report.md:yes
negated-and-real-token-same-line.md:yes
no-alert-when-prod-went-down.md:yes
didnt-notice-deploy-was-blocked.md:yes
real-report-with-unrelated-negation.md:yes
cue-two-words-from-token-still-signals.md:yes"

# --- the baseline TABLE is itself a claim -----------------------------------------------------
# The table is hand-maintained, so the baseline block proves only that whatever it lists behaves.
# Deleting entries used to shrink the guarded set with no signal at all. Assert its CARDINALITY
# against the fixture set this class introduced, and that every named file exists — a count alone
# cannot see a substitution.
FIXTURE_MIN=26
table_n=$(printf '%s\n' "$FIXTURES" | grep -c ':')
if [ "$table_n" -lt "$FIXTURE_MIN" ]; then
  fail "baseline table lists $table_n fixtures, floor is $FIXTURE_MIN — entries were removed from the guarded set"
else
  pass "baseline table lists $table_n fixtures (floor $FIXTURE_MIN)"
fi
missing=0
while IFS=: read -r f _; do [ -f "$FIX/$f" ] || { missing=$((missing+1)); echo "  MISSING FIXTURE: $f"; }; done <<< "$FIXTURES"
if [ "$missing" -eq 0 ]; then pass "every fixture named in the baseline table exists on disk"
else fail "$missing fixture(s) named in the baseline table are absent"; fi

# --- requirement 1: GREEN BASELINE, before any row ------------------------------------------
baseline_bad=0
while IFS=: read -r f want; do
  got="$(verdict "$PRISTINE" "$f")"
  [ "$got" = "$want" ] || { printf 'BASELINE MISMATCH %s want=%s got=%s\n' "$f" "$want" "$got"; baseline_bad=1; }
done <<< "$FIXTURES"
if [ "$baseline_bad" -ne 0 ]; then
  echo "FATAL: unmutated control is RED — aborting rather than scoring rows against it."
  exit 2
fi
pass "baseline: all $table_n canonical fixtures match under the unmutated gate"

cat > "$WORK/mutate.py" <<'PYEOF'
import sys
mid, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
BLANK = "       /^[[:space:]]*$/                                 {skip=0}\n"
HASH  = "       /^[[:space:]]*#+([[:space:]]|$)/                 {skip=0}\n"
TRIG  = "       tolower($0) ~ /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?[*_]*if this (lands|leaks)/ {skip=1; next}\n"
LIST  = "       /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)/ {skip=0}\n"
ACT   = "       tolower($0) ~ ACTUALITY_RE                       {skip=0; print neg_strip($0); next}\n"
DROP  = "       tolower($0) ~ DROP_RE    { if (!noted && tolower($0) ~ OUTAGE_RE) { noted=1; print SENTINEL } next }\n"
def one(t):
    assert s.count(t) == 1, "anchor not unique for " + mid
    return s.replace(t, "", 1)
if   mid == "M1":                                    # delete the whole paragraph stage
    i = s.index("  | awk -v ACTUALITY_RE="); j = s.index("{print neg_strip($0)}')\"; then\n", i)
    s = s[:i] + "  )\"; then\n" + s[j + len("{print neg_strip($0)}')\"; then\n"):]
elif mid == "M2": s = one(ACT)
elif mid == "M3": s = one(BLANK)
elif mid == "M4":
    assert s.count(HASH) == 1; s = s.replace(HASH, "       /^[[:space:]]*#/                                 {skip=0}\n", 1)
elif mid == "M5": s = one(HASH)
elif mid == "M6": s = one(LIST)
elif mid == "M7":                                    # re-admit BELOW the skip sink
    assert s.count(ACT) == 1 and s.count("       skip                     { if (!noted") == 1
    s = s.replace(ACT, "", 1).replace(DROP, ACT + DROP, 1)
elif mid == "M8":                                    # un-anchor the trigger
    old = "tolower($0) ~ /^[[:space:]]*([-*+]"
    assert s.count(old) == 1; s = s.replace(old, "tolower($0) ~ /[[:space:]]*([-*+]", 1)
elif mid == "M9":                                    # revert the fence boundary
    old = '{f=!f; print ""; next}'
    assert s.count(old) == 1; s = s.replace(old, "{f=!f; next}", 1)
elif mid == "M10":                                   # delete the fail-toward-PIR guard
    # Anchor tracks the production line. It was `$(cat \` until #7987 moved corpus
    # construction into the script (`--pr` mode); the mutation's SEMANTICS are
    # unchanged -- delete the fail-toward-PIR guard -- only the literal moved.
    # The assert is what caught the rename: the row reported "mutation engine
    # failed" rather than passing on an un-applied mutation.
    assert s.count("if ! haystack=\"$(emit_corpus \\") == 1
    s = s.replace("if ! haystack=\"$(emit_corpus \\", "haystack=\"$(emit_corpus \\", 1)
    i = s.index("{print neg_strip($0)}')\"; then\n")
    j = s.index("fi\n", i) + len("fi\n")
    s = s[:i] + "{print neg_strip($0)}')\"\n" + s[j:]
elif mid == "M12":                                   # revert the unbalanced-fence re-emit
    old = "\n         END{ if (f) for (i=1; i<=n; i++) print buf[i] }"
    assert s.count(old) == 1; s = s.replace(old, "", 1)
elif mid == "M11":                                   # DROP_RE above the re-admit
    assert s.count(DROP) == 1 and s.count(ACT) == 1
    s = s.replace(DROP, "", 1).replace(ACT, DROP + ACT, 1)
# --- Guard 2, the negation strip (#8334). Each literal is asserted unique before it is edited.
elif mid.startswith("N"):
    FALL = "{print neg_strip($0)}')\"; then\n"
    def sub(old, new):
        global s
        assert s.count(old) == 1, "anchor not unique for " + mid
        s = s.replace(old, new, 1)
    if   mid == "N1": sub(FALL, "{print}')\"; then\n")                   # fall-through site only
    elif mid == "N2": sub("           while (match(pre, /[.;:!?,]/)) pre = substr(pre, RSTART + 1)\n", "")
    elif mid == "N3": sub("out = substr(out, 1, st - 1) sp substr(out, st + len)",
                          "out = \"\"; for (i = 0; i < length(s); i++) out = out \" \"")
    elif mid == "N4": sub("while (match(rest, OUTAGE_RE) && RLENGTH > 0)", "if (match(rest, OUTAGE_RE) && RLENGTH > 0)")
    elif mid == "N5": sub("[^a-z]+([a-z]+[^a-z]+)?$'", "[^a-z].*$'")
    elif mid == "N9": sub("[^a-z]+([a-z]+[^a-z]+)?$'", "[^a-z]+([a-z]+[^a-z]+)?([a-z]+[^a-z]+)?$'")
    elif mid == "N6": sub("if (pre ~ NEG_CUE_RE || pre ~ NEG_PHRASE_RE)", "if (pre ~ NEG_CUE_RE)")
    elif mid == "N7": sub("      continue\n", "      _l=\"${_l#\"$NEG_SENTINEL\"}\"\n")   # strip the marker only
    elif mid == "N8": sub("{skip=0; print neg_strip($0); next}", "{skip=0; print; next}")   # re-admit site only
    elif mid == "N10":
        i = s.index('      echo "ship-incident-pir-gate: PIR-OUTAGE-NEGATION-SUPPRESSED'); j = s.index("\n", i) + 1
        s = s[:i] + s[j:]
    else:
        sys.exit("unknown mutation " + mid)
else:
    sys.exit("unknown mutation " + mid)
open(dst, "w").write(s)
PYEOF

# args: id  anchor-regex  expected-count-in-mutant  "fixture:verdict,..."  why
run_row() {
  local id="$1" anchor="$2" want_n="$3" checks="$4" why="$5"
  rows=$((rows+1))
  local mut="$WORK/$id.sh"
  if ! python3 "$WORK/mutate.py" "$id" "$PRISTINE" "$mut" 2>"$WORK/$id.err"; then
    fail "$id: mutation engine failed — $(tr -d '\n' < "$WORK/$id.err" | tail -c 140)"; return
  fi
  if cmp -s "$PRISTINE" "$mut"; then
    fail "$id: VACUOUS — the mutation produced no change (a non-landing mutant reports the baseline)"; return
  fi
  # ORDER mode: a REORDER changes no counts, so a count anchor cannot distinguish moved from
  # untouched (measured: M7/M11 anchors were satisfied by the unmutated file). `ORDER%A%B` asserts
  # A precedes B in the pristine and follows it in the mutant — the reorder itself.
  if [[ "$anchor" == ORDER%* ]]; then
    local a="${anchor#ORDER%}"; local pa="${a%%\%*}" pb="${a#*%}"
    local p1 p2 m1 m2
    p1=$(grep -nE -- "$pa" "$PRISTINE" | head -1 | cut -d: -f1); p2=$(grep -nE -- "$pb" "$PRISTINE" | head -1 | cut -d: -f1)
    m1=$(grep -nE -- "$pa" "$mut"      | head -1 | cut -d: -f1); m2=$(grep -nE -- "$pb" "$mut"      | head -1 | cut -d: -f1)
    if [ -z "$p1" ] || [ -z "$p2" ] || [ -z "$m1" ] || [ -z "$m2" ]; then
      fail "$id: ORDER anchor did not resolve in one of the files (pristine $p1/$p2, mutant $m1/$m2)"; return
    fi
    if ! { [ "$p1" -lt "$p2" ] && [ "$m1" -gt "$m2" ]; }; then
      fail "$id: ORDER not inverted (pristine $p1 vs $p2, mutant $m1 vs $m2) — the reorder did not land"; return
    fi
  else
  local n p; n=$(grep -cE -- "$anchor" "$mut" || true); p=$(grep -cE -- "$anchor" "$PRISTINE" || true)
  # The anchor must MOVE. Counting it only in the mutant cannot distinguish "the edit removed it"
  # from "the anchor never matched anything" — measured: a nonsense anchor passed every want_n=0 row.
  if [ "$p" -eq "$want_n" ]; then
    fail "$id: anchor '$anchor' already occurs $want_n time(s) in the PRISTINE file — it cannot distinguish mutated from untouched"; return
  fi
  if [ "$n" -ne "$want_n" ]; then
    fail "$id: anchor '$anchor' occurs $n time(s) in the mutant, expected $want_n (edit landed elsewhere)"; return
  fi
  fi
  # ONE ASSERTION PER FIXTURE CHECK. Emitting one per ROW made the floor count rows rather than
  # discrimination: emptying every check list, truncating an all-of-2 row to 1-of-1, or deleting
  # fixtures from FIXTURES all printed the byte-identical headline. Measured, before this fix, a
  # battery asserting NOTHING about behaviour reported `20 passed, 0 failed (11 rows, 20
  # assertions)` — the exact vacuity this file claims to police.
  if [ -z "$checks" ]; then
    fail "$id: NO fixture checks — a row that asserts nothing is the vacuity this battery exists to prevent"
    return
  fi
  local IFSsave="$IFS"
  IFS=,
  for chk in $checks; do
    IFS="$IFSsave"
    local f="${chk%%:*}" want="${chk##*:}" got; got="$(verdict "$mut" "$f")"
    if [ "$got" = "$want" ]; then pass "$id/${f%.md}: $why"
    else fail "$id/${f%.md}: did NOT redden — want=$want got=$got"; fi
    IFS=,
  done
  IFS="$IFSsave"
}

# shellcheck disable=SC2016  # the run_row anchors are literal ERE patterns, no expansion wanted
run_row M1  'ACTUALITY_RE=\"\$ACTUALITY_RE\"' 0 "precedent-citation-inside-hypothetical-paragraph.md:yes" \
  "deleting the paragraph stage re-opens the reported bug"
# shellcheck disable=SC2016  # literal ERE anchor, no expansion wanted
run_row M2  'ACTUALITY_RE +\{skip=0; print neg_strip\(\$0\); next\}' 0 "real-outage-claimed-inside-hypothetical-paragraph.md:no,actuality-occurred-inflection.md:no" \
  "deleting the re-admit silences a real claim inside the paragraph — both idiom inflections"
run_row M3  '\^\[\[:space:\]\]\*\$/ +\{skip=0\}' 0 "real-outage-after-hypothetical-paragraph.md:no" \
  "deleting the blank-line boundary runs the window to EOF"
run_row M4  '#\+\(\[\[:space:\]\]\|\$\)' 0 "reflowed-citation-with-issue-ref-continuation.md:yes" \
  "loosening the hash rule lets a #NNNN continuation reopen the window — the fix fails on a reflow of its own target class"
run_row M5  '#\+\(\[\[:space:\]\]\|\$\)' 0 "real-outage-after-heading-boundary.md:no" \
  "deleting the hash boundary swallows a claim after a real heading"
run_row M6  '\[-\*\+\]\[\[:space:\]\]\+\|\[0-9\]\+\[\.\)\]' 1 "real-outage-in-sibling-bullet.md:no,real-outage-in-nested-sub-bullet.md:no" \
  "deleting the list boundary swallows both sibling and nested blocks"
# shellcheck disable=SC2016  # literal ERE anchor, no expansion wanted
run_row M7  'ORDER%ACTUALITY_RE +\{skip=0; print neg_strip\(\$0\); next\}%^ +skip +\{ if \(!noted' 0 "real-outage-claimed-inside-hypothetical-paragraph.md:no" \
  "moving the re-admit BELOW the skip sink disarms it — the one ordering measured load-bearing"
# shellcheck disable=SC2016  # literal ERE anchor, no expansion wanted
run_row M8  'tolower\(\$0\) ~ /\[\[:space:\]\]\*\(\[-\*\+\]' 1 "midsentence-conditional-does-not-open-a-paragraph.md:no" \
  "un-anchoring the trigger lets one subordinate clause silence a whole paragraph"
run_row M9  'print \"\"; next' 0 "real-outage-after-fenced-block-abutting-paragraph.md:no" \
  "reverting the fence boundary merges the paragraph with what follows the fence"
# shellcheck disable=SC2016  # literal ERE anchor, no expansion wanted
run_row M11 'ORDER%ACTUALITY_RE +\{skip=0; print neg_strip\(\$0\); next\}%tolower\(\$0\) ~ DROP_RE' 0 "actuality-outranks-conditional-clause.md:no" \
  "moving DROP_RE above the re-admit restores the two-stage incoherence: one conditional clause silences a stated actuality"

# shellcheck disable=SC2016  # literal ERE anchor, no expansion wanted
run_row M12 'END\{ if \(f\)' 0 "unbalanced-fence-does-not-swallow-the-tail.md:no" \
  "reverting the unbalanced-fence re-emit silently swallows the document tail"

# --- Guard 2: the negation strip (#8334). N1 and N8 edit the same call at two sites, so each
# anchor names ITS site (the `{print ...}` fall-through vs the ACTUALITY_RE re-admit), never a
# bare `neg_strip(` count, which either mutant would satisfy.
# shellcheck disable=SC2016  # literal ERE anchors, no expansion wanted
run_row N1  "^ +\{print neg_strip\(\\\$0\)\}'" 0 "negated-outage-only.md:yes,two-tokens-both-denied.md:yes,denial-specimen-8334.md:yes" \
  "dropping neg_strip at the fall-through lets a denied token reach the verdict"
# shellcheck disable=SC2016
run_row N2  'match\(pre, /\[\.;:!\?,\]/\)' 0 "negation-in-prior-clause-real-report.md:no" \
  "without clause boundaries a cue in the PRIOR clause silences a real report"
# shellcheck disable=SC2016
run_row N3  'substr\(out, st \+ len\)' 0 "negated-and-real-token-same-line.md:no" \
  "line-scoped blanking takes the real token down with its denied neighbour"
# shellcheck disable=SC2016
run_row N4  'while \(match\(rest, OUTAGE_RE\)' 0 "two-tokens-both-denied.md:yes" \
  "judging only the first occurrence lets the second denied token through"
# shellcheck disable=SC2016
run_row N5  'NEG_CUE_RE=.*\[\^a-z\]\.\*' 1 "no-alert-when-prod-went-down.md:no,real-report-with-unrelated-negation.md:no" \
  "a clause-wide cue window swallows a real report whose cue governs another word"
# shellcheck disable=SC2016
run_row N9  '\)\?\(\[a-z\]\+\[\^a-z\]\+\)\?' 1 "cue-two-words-from-token-still-signals.md:no" \
  "a two-word cue window swallows the two-words-away report the one-word window keeps"
# shellcheck disable=SC2016
run_row N6  'pre ~ NEG_PHRASE_RE' 0 "denial-specimen-8334.md:yes,negation-cue-rather-than.md:yes" \
  "without rule (b) the #8334 specimen and the rather-than denial signal again"
# shellcheck disable=SC2016
run_row N7  '^ +continue$' 0 "negated-outage-only.md:yes" \
  "stripping only the marker leaves the payload, which re-injects the denied token"
# shellcheck disable=SC2016
run_row N8  'ACTUALITY_RE +\{skip=0; print neg_strip' 0 "actuality-line-only-token-denied.md:yes" \
  "dropping neg_strip at the re-admit lets a denied token on an actuality line through"

# M10's observable is a pipeline failure, not a fixture verdict.
rows=$((rows+1))
if python3 "$WORK/mutate.py" M10 "$PRISTINE" "$WORK/M10.sh" 2>/dev/null; then
  d=$(mktemp -d "$TMPDIR/pir-awkstub.XXXXXXXX"); printf '#!/bin/sh\nexit 2\n' > "$d/awk"; chmod +x "$d/awk"
  if printf 'nothing\n' | PATH="$d:$PATH" bash "$WORK/M10.sh" >/dev/null 2>&1; then
    fail "M10: a broken strip stage still signalled without the guard — the guard is not load-bearing"
  else
    pass "M10: deleting the fail-toward-PIR guard makes a broken strip stage fall SILENT (exit 1)"
  fi
  if printf 'nothing\n' | PATH="$d:$PATH" bash "$PRISTINE" >/dev/null 2>&1; then
    pass "M10-control: the shipped guard fires on a broken strip stage"
  else
    fail "M10-control: the shipped guard did NOT fire on a broken strip stage"
  fi
  rm -rf "$d"
else
  fail "M10: mutation engine failed"
fi

# N10's observable is the stderr note, which verdict() discards — so it is captured here.
rows=$((rows+1))
if python3 "$WORK/mutate.py" N10 "$PRISTINE" "$WORK/N10.sh" 2>/dev/null && ! cmp -s "$PRISTINE" "$WORK/N10.sh"; then
  n10_m=$(grep -c 'PIR-OUTAGE-NEGATION-SUPPRESSED — ' "$WORK/N10.sh" || true)
  n10_p=$(grep -c 'PIR-OUTAGE-NEGATION-SUPPRESSED — ' "$PRISTINE" || true)
  if [ "$n10_p" -ne 1 ] || [ "$n10_m" -ne 0 ]; then
    fail "N10: anchor did not move (pristine $n10_p, mutant $n10_m)"
  else
    bash "$WORK/N10.sh" < "$FIX/negated-outage-only.md" >/dev/null 2>"$WORK/N10.err"
    if grep -q 'PIR-OUTAGE-NEGATION-SUPPRESSED' "$WORK/N10.err"; then
      fail "N10: deleting the echo still printed the note — the stderr assertion cannot see it"
    else
      pass "N10: deleting the echo makes a suppression silent (the note vanishes from stderr)"
    fi
  fi
  bash "$PRISTINE" < "$FIX/negated-outage-only.md" >/dev/null 2>"$WORK/N10p.err"; n10_rc=$?
  if [ "$n10_rc" -eq 1 ] && grep -q 'PIR-OUTAGE-NEGATION-SUPPRESSED — "' "$WORK/N10p.err"; then
    pass "N10-control: the shipped gate exits 1 and names the suppressed line on stderr"
  else
    fail "N10-control: the shipped gate did not disclose the suppression (rc=$n10_rc)"
  fi
else
  fail "N10: mutation engine failed or produced no change"
fi

# --- empty haystack: structurally clean now the pipeline terminates in awk -------------------
for probe in "" $'\n\n' $'If this lands broken\n'; do
  if printf '%s' "$probe" | bash "$PRISTINE" >/dev/null 2>&1; then
    fail "empty/filtered haystack SIGNALLED — the merged pipeline must exit 1, not report an incident"
  else
    pass "empty/filtered haystack is a clean no-signal (no terminal grep, so no exit-code arm needed)"
  fi
done

# --- dispatch + floor, emitted directly (never through the helper it backstops) --------------
# A FLOOR, not an equality — the row count is developer-incremented, and this file argues exactly
# that for MIN_ASSERTIONS two blocks down. An equality here would make every added row a failure.
if [ "$rows" -ge 22 ]; then pass "dispatch: $rows mutation rows ran (floor 22)"
else fail "dispatch: only $rows rows ran, floor is 22"; fi

# This battery never writes to $ORIG (mutants go to $WORK), so the old `cmp $ORIG $PRISTINE`
# assertion was unfailable by construction while still counting toward the floor. Assert the
# INSTRUMENT instead: the pristine copy must still be a working gate, which a corrupted or
# truncated $WORK would fail.
if [ -s "$PRISTINE" ] && bash "$PRISTINE" < "$FIX/precedent-citation-inside-hypothetical-paragraph.md" >/dev/null 2>&1; then
  fail "instrument check: the pristine copy SIGNALS on a known-negative — every verdict above is void"
else
  pass "instrument check: the pristine copy is a working gate (known-negative still reads no-signal)"
fi

# The floor is DERIVED from a measured green run, not from the number I expected — an expected
# number is how a floor ends up one above what the suite can reach. Raise it in lockstep when
# assertions are added; it is a floor, never an equality (an equality makes every new assertion
# a spurious failure). Emitted directly, never through the helper it backstops.
MIN_ASSERTIONS=40
if [ "$asserted" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FATAL: only %d assertions ran, floor is %d — the battery is vacuous\n' "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [ $((passes + fails)) -ne "$asserted" ]; then
  printf 'FATAL: %d passes + %d fails != %d asserted — a counter is stalled\n' "$passes" "$fails" "$asserted" >&2
  exit 1
fi

printf '\n=== %d passed, %d failed (%d mutation rows, %d assertions) ===\n' "$passes" "$fails" "$rows" "$asserted"
[ "$fails" -eq 0 ] || exit 1
exit 0
