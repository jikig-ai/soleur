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

if [[ "$fails" -gt 0 ]]; then
  echo "gate-classification: $fails assertion(s) failed"
  exit 1
fi
echo "gate-classification: all assertions passed"
