#!/usr/bin/env bash
# Deterministic unit test for the GATE assert (scripts/gate-classification.cjs).
# No live LLM: every "model output" is a stubbed string. Asserts the contract:
#   - pass: true  when the parsed label IS a member of the target's enum
#   - pass: false when the parsed label is NOT in the enum (malformed/hallucinated)
#   - exercised for BOTH the 7-route enum AND the P1/P2/P3 enum
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
ASSERT="$SKILL_DIR/scripts/gate-classification.cjs"
fails=0

# run <output> <enum-json> <expect-pass> <label>
run() {
  local output="$1" enumjson="$2" want_pass="$3" label="$4"
  local got_pass
  got_pass=$(node -e '
    const fn = require(process.argv[1]);
    const r = fn(process.argv[2], { vars: { enum: JSON.parse(process.argv[3]) } });
    process.stdout.write(String(r.pass));
  ' "$ASSERT" "$output" "$enumjson" )
  if [[ "$got_pass" != "$want_pass" ]]; then
    echo "FAIL [$label]: output='$output' -> pass=$got_pass (want $want_pass)"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: pass=$got_pass"
  fi
}

GO='["fix","drain","clo-attestation","review","legal-threshold","incident","default"]'
TR='["P1","P2","P3"]'

# --- /go route enum ---
run "fix"                    "$GO" "true"  "in-enum route passes"
run "clo-attestation"        "$GO" "true"  "in-enum hyphenated route passes"
run "The route is review."   "$GO" "true"  "in-enum route in prose passes"
run "banana"                 "$GO" "false" "out-of-enum route fails"
run "P1"                     "$GO" "false" "wrong-namespace label fails"

# --- ticket-triage P-level enum ---
run "P1"                     "$TR" "true"  "in-enum P-level passes"
run "p2"                     "$TR" "true"  "in-enum P-level case-insensitive passes"
run "P9"                     "$TR" "false" "out-of-enum P-level fails"
run "fix"                    "$TR" "false" "wrong-namespace label fails"

# --- file:// enum shape (promptfoo passes defaultTest.vars file:// refs verbatim;
#     the #5358 live-run bug). enum arrives as a RAW STRING, not a parsed array. ---
fileref() {
  local output="$1" enumref="$2" want_pass="$3" label="$4"
  local got
  got=$(node -e '
    const fn = require(process.argv[1]);
    const r = fn(process.argv[2], { vars: { enum: process.argv[3] } });
    process.stdout.write(String(r.pass));
  ' "$ASSERT" "$output" "$enumref")
  if [[ "$got" != "$want_pass" ]]; then
    echo "FAIL [$label]: output='$output' enum='$enumref' -> pass=$got (want $want_pass)"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: pass=$got"
  fi
}
fileref "fix"    "file://enums/go-routes.json"     "true"  "file:// enum + in-enum route passes"
fileref "banana" "file://enums/go-routes.json"     "false" "file:// enum + out-of-enum route fails"
fileref "P1"     "file://enums/triage-levels.json" "true"  "file:// enum + in-enum P-level passes"
# Resolved-contents shape (JSON array text) — what promptfoo actually passes when it
# resolves a defaultTest.vars file:// ref to file CONTENTS. Regression guard for the
# gate-vacuous bug (the enum arrived as JSON-array-text, not a path/literal-ref).
fileref "fix"    '["fix","drain","clo-attestation","review","legal-threshold","incident","default"]' "true"  "contents-string enum + in-enum passes"
fileref "banana" '["fix","drain","clo-attestation","review","legal-threshold","incident","default"]' "false" "contents-string enum + out-of-enum fails"

if [[ "$fails" -gt 0 ]]; then
  echo "gate-classification: $fails assertion(s) failed"
  exit 1
fi
echo "gate-classification: all assertions passed"
