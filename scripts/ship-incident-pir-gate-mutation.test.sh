#!/usr/bin/env bash
# ship-incident-pir-gate-mutation.test.sh — the mutation battery for the
# Incident-PIR hypothetical-paragraph strip in scripts/ship-incident-pir-gate.sh (#7801).
#
# WHY THIS EXISTS: the strip is a STATEFUL, ORDERED awk program, and a fixture
# suite alone cannot tell a load-bearing rule from a decorative one. Nine of the
# ten fixtures pass on `main`; only three of them redden without the fix. So the
# question "does each rule of the new stage do anything?" is not answered
# anywhere else, and an ordering defect in particular is invisible to a
# delete-only reading of the diff.
#
# FOUR STRUCTURAL REQUIREMENTS, each closing a named prior defect in this repo:
#
#   1. GREEN BASELINE FIRST. The unmutated control runs before any row and must
#      be GREEN; a red control ABORTS rather than scoring rows, because a red
#      baseline makes every row "flip" vacuously.
#
#   2. PLACEMENT, NOT JUST DIFFERENCE. Every row asserts its edit LANDED and
#      changed the expected number of lines. A mutation that does not land
#      reports the BASELINE, which is byte-indistinguishable from a pass.
#
#   3. A row whose edit produced no change is reported VACUOUS and FAILS the
#      battery — never counted as a pass.
#
#   4. NO MUTATION IS APPLIED INSIDE A COMMAND SUBSTITUTION. A failure inside
#      `$( )` cannot fail the suite.
#
# RESTORE IS FROM A PRISTINE COPY, never `git checkout` — the fix under test may
# be uncommitted, and `git checkout` would restore HEAD and score every later row
# against a file that no longer contains the thing under test.
#
# HARNESS ROWS (H*) edit the BATTERY or use non-canonical inputs, because a
# matrix that only mutates the SUT cannot see a vacuous harness.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIG="$REPO_ROOT/scripts/ship-incident-pir-gate.sh"
FIX="$REPO_ROOT/plugins/soleur/test/fixtures/ship-incident-pir-gate"
TEMPLATE="$REPO_ROOT/plugins/soleur/skills/plan/references/plan-issue-templates.md"

WORK="$(mktemp -d "$TMPDIR/pir-mutbat.XXXXXXXX")" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT
PRISTINE="$WORK/pristine.sh"
cp "$ORIG" "$PRISTINE" || { echo "FATAL: could not copy the SUT"; exit 2; }

fails=0; passes=0; rows=0
pass() { passes=$((passes+1)); printf '[ok]   %s\n' "$1"; }
fail() { fails=$((fails+1));  printf '[FAIL] %s\n' "$1"; }

# --- fixture verdict under an arbitrary gate binary -------------------------
verdict() { # $1=gate $2=fixture-basename -> prints yes|no
  if bash "$1" < "$FIX/$2" >/dev/null 2>&1; then echo yes; else echo no; fi
}

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
real-outage-inside-paragraph-without-actuality-idiom.md:no"

# --- requirement 1: GREEN BASELINE, before any row --------------------------
baseline_bad=0
while IFS=: read -r f want; do
  got="$(verdict "$PRISTINE" "$f")"
  [ "$got" = "$want" ] || { printf 'BASELINE MISMATCH %s want=%s got=%s\n' "$f" "$want" "$got"; baseline_bad=1; }
done <<< "$FIXTURES"
if [ "$baseline_bad" -ne 0 ]; then
  echo "FATAL: unmutated control is RED — aborting rather than scoring rows against it."
  exit 2
fi
echo "[ok]   baseline: all 10 canonical fixtures match under the unmutated gate"
passes=$((passes+1))

# --- the mutation engine ----------------------------------------------------
cat > "$WORK/mutate.py" <<'PYEOF'
import sys, re
mid, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
BLANK   = "       /^[[:space:]]*$/                                 {skip=0; print; next}\n"
HASH    = "       /^[[:space:]]*#+([[:space:]]|$)/                 {skip=0; print; next}\n"
LIST    = "       /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)/ {skip=0; print; next}\n"
ACT     = "       tolower($0) ~ ACTUALITY_RE                       {skip=0; print; next}\n"
SKIPN   = "       skip                                             {next}\n"
def cut(t):
    assert t in s, "anchor missing: " + mid
    return s.replace(t, "", 1)
if   mid == "M1":
    i = s.index("  | awk -v ACTUALITY_RE="); j = s.index("{print}' \\\n", i) + len("{print}' \\\n")
    s = s[:i] + s[j:]
elif mid == "M2": s = cut(ACT)
elif mid == "M3": s = cut(BLANK)
elif mid == "M4":
    assert HASH in s; s = s.replace(HASH, "       /^[[:space:]]*#/                                 {skip=0; print; next}\n", 1)
elif mid == "M5": s = cut(HASH)
elif mid == "M6": s = cut(LIST)
elif mid == "M7":                                  # ORDERING: skip{next} above the re-admit
    assert ACT in s and SKIPN in s
    s = s.replace(SKIPN, "", 1).replace(ACT, SKIPN + ACT, 1)
elif mid == "M8":                                  # un-anchor the trigger
    old = "tolower($0) ~ /^[[:space:]]*([-*+]"
    assert old in s; s = s.replace(old, "tolower($0) ~ /[[:space:]]*([-*+]", 1)
elif mid == "M9":                                  # revert the fence boundary
    old = "{f=!f; print \"\"; next}"
    assert old in s; s = s.replace(old, "{f=!f; next}", 1)
elif mid == "M10":                                 # revert the empty-haystack guard arm
    old = " || [ \"$?\" -eq 1 ]; }"
    assert old in s; s = s.replace(old, "; }".replace("; }", ""), 1)
    s = s.replace("  | { grep -vaiE", "  | grep -vaiE", 1)
else:
    sys.exit("unknown mutation " + mid)
open(dst, "w").write(s)
PYEOF

# --- row runner -------------------------------------------------------------
# args: id  expected-changed-lines  "fixture:expected-verdict-under-mutant,..."  why
run_row() {
  local id="$1" want_lines="$2" checks="$3" why="$4"
  rows=$((rows+1))
  local mut="$WORK/$id.sh"
  if ! python3 "$WORK/mutate.py" "$id" "$PRISTINE" "$mut" 2>"$WORK/$id.err"; then
    fail "$id: mutation engine failed — $(tr -d '\n' < "$WORK/$id.err" | tail -c 160)"
    return
  fi
  # requirement 2+3: the edit must have LANDED, and by the expected amount.
  if cmp -s "$PRISTINE" "$mut"; then
    fail "$id: VACUOUS — the mutation produced no change (a non-landing mutant reports the baseline)"
    return
  fi
  local changed
  changed=$(diff "$PRISTINE" "$mut" | grep -c '^[<>]' || true)
  if [ "$changed" -ne "$want_lines" ]; then
    fail "$id: mutation changed $changed lines, expected $want_lines (edit landed somewhere unintended)"
    return
  fi
  local ok=1 detail=""
  local IFSsave="$IFS"; IFS=,
  for chk in $checks; do
    IFS="$IFSsave"
    local f="${chk%%:*}" want="${chk##*:}" got
    got="$(verdict "$mut" "$f")"
    [ "$got" = "$want" ] || { ok=0; detail="$detail ${f%.md}(want=$want got=$got)"; }
    IFS=,
  done
  IFS="$IFSsave"
  if [ "$ok" -eq 1 ]; then pass "$id: $why"; else fail "$id: did NOT redden as required —$detail"; fi
}

run_row M1  23 "precedent-citation-inside-hypothetical-paragraph.md:yes" \
  "deleting the paragraph-strip stage re-opens the reported bug"
run_row M2  1 "real-outage-claimed-inside-hypothetical-paragraph.md:no" \
  "deleting the ACTUALITY_RE re-admit silences a real outage claim inside the paragraph"
run_row M3  1 "real-outage-after-hypothetical-paragraph.md:no" \
  "deleting the blank-line boundary runs the window to EOF"
run_row M4  2 "reflowed-citation-with-issue-ref-continuation.md:yes" \
  "loosening the hash rule lets a #NNNN continuation reopen the window — the fix fails on a reflow of its own target class"
run_row M5  1 "real-outage-after-heading-boundary.md:no" \
  "deleting the hash boundary swallows a claim after a real heading"
run_row M6  1 "real-outage-in-sibling-bullet.md:no,real-outage-in-nested-sub-bullet.md:no" \
  "deleting the list-item boundary swallows both sibling and nested blocks"
run_row M7  2 "real-outage-claimed-inside-hypothetical-paragraph.md:no" \
  "REORDERING skip{next} above the re-admit disarms it — an ordering defect a delete-only battery cannot see"
run_row M8  2 "midsentence-conditional-does-not-open-a-paragraph.md:no" \
  "un-anchoring the trigger lets one subordinate clause silence a whole paragraph"
run_row M9  2 "real-outage-after-fenced-block-abutting-paragraph.md:no" \
  "reverting the fence boundary merges the paragraph with what follows the fence"
run_row M10 2 "" \
  "reverting the empty-haystack guard arm (checked separately below)"

# M10's observable is not a fixture verdict — it is a non-fixture input.
m10="$WORK/M10.sh"
if [ -f "$m10" ]; then
  if printf '' | bash "$m10" >/dev/null 2>&1; then
    pass "M10: reverting the guard arm makes an EMPTY haystack signal (the false positive the arm closes)"
  else
    fail "M10: empty stdin did not signal under the bare guard — the arm is not load-bearing"
  fi
  if printf '' | bash "$PRISTINE" >/dev/null 2>&1; then
    fail "M10-control: empty stdin signals under the UNMUTATED gate (the guard is broken)"
  else
    pass "M10-control: empty stdin is a clean no-signal under the shipped gate"
  fi
fi

# --- H1: the battery's own dispatch ----------------------------------------
# A battery reporting "0 mutations" and exiting 0 is exactly the vacuity it
# exists to prevent, so the row count is asserted rather than trusted.
if [ "$rows" -eq 10 ]; then pass "H1: battery dispatched all 10 mutation rows"
else fail "H1: battery dispatched $rows rows, expected 10 (dispatch is broken)"; fi

# --- H2: must-PASS, non-canonical ------------------------------------------
# A suite whose only must-PASS input is the canonical fixture cannot detect a
# strip that rejects everything. F3 is the same sentence one blank line down and
# must carry the OPPOSITE verdict to F1; F11 is generated at runtime from a file
# this PR does not edit.
if [ "$(verdict "$PRISTINE" precedent-citation-inside-hypothetical-paragraph.md)" = no ] \
   && [ "$(verdict "$PRISTINE" real-outage-after-hypothetical-paragraph.md)" = yes ]; then
  pass "H2a: the canonical and its one-blank-line-down variation carry OPPOSITE verdicts"
else
  fail "H2a: the strip is not discriminating between the canonical and its permitted variation"
fi

if [ -r "$TEMPLATE" ]; then
  trig="$(grep -m1 -E '^- \*\*If this lands broken' "$TEMPLATE")"
  if [ -n "$trig" ]; then
    { printf '# p\n\n## User-Brand Impact\n\n%s\n' "$trig"
      printf '  The 2026-08-16 apex outage took the production site down.\n'; } > "$WORK/F11.md"
    if bash "$PRISTINE" < "$WORK/F11.md" >/dev/null 2>&1; then
      fail "H2b: runtime-generated F11 (from the live plan template) SIGNALS — the anchor has drifted off the template's wording"
    else
      pass "H2b: runtime-generated F11 from the live plan template does not signal"
    fi
  else
    fail "H2b: could not extract a trigger line from the plan template — the anchor's source has drifted"
  fi
else
  fail "H2b: plan template unreadable at $TEMPLATE"
fi

# --- requirement: the SUT on disk is untouched ------------------------------
if cmp -s "$ORIG" "$PRISTINE"; then pass "restore check: the SUT on disk is byte-identical to the pristine copy"
else fail "restore check: the SUT ON DISK WAS MODIFIED by this battery"; fi

printf '\n=== %d passed, %d failed (%d mutation rows) ===\n' "$passes" "$fails" "$rows"
[ "$fails" -eq 0 ] || exit 1
exit 0
