#!/usr/bin/env bash
# Deterministic unit test for the MEASUREMENT assert (scripts/measure-classification.cjs).
# No live LLM: every "model output" is a stubbed string. Asserts the contract:
#   - ALWAYS pass: true (the measurement records, never gates)
#   - score 1.0 when the parsed label matches golden_label, 0.0 otherwise
#   - works for BOTH a /go route AND a ticket-triage P-level
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
ASSERT="$SKILL_DIR/scripts/measure-classification.cjs"
fails=0

# run <output> <golden_label> <enum-json> <expect-pass> <expect-score> <label>
run() {
  local output="$1" golden="$2" enumjson="$3" want_pass="$4" want_score="$5" label="$6"
  local result
  result=$(node -e '
    const fn = require(process.argv[1]);
    const r = fn(process.argv[2], { vars: { golden_label: process.argv[3], enum: JSON.parse(process.argv[4]) } });
    process.stdout.write(JSON.stringify({ pass: r.pass, score: r.score }));
  ' "$ASSERT" "$output" "$golden" "$enumjson" )
  local got_pass got_score
  got_pass=$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).pass))' "$result")
  got_score=$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).score))' "$result")
  if [[ "$got_pass" != "$want_pass" || "$got_score" != "$want_score" ]]; then
    echo "FAIL [$label]: output='$output' golden='$golden' -> pass=$got_pass score=$got_score (want pass=$want_pass score=$want_score)"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: pass=$got_pass score=$got_score"
  fi
}

GO='["fix","drain","clo-attestation","review","legal-threshold","incident","default"]'
TR='["P1","P2","P3"]'

# --- /go route cases ---
run "fix"                     "fix"     "$GO" "true" "1" "route exact match"
run "The route is \`fix\`."   "fix"     "$GO" "true" "1" "route embedded in prose"
run "default"                 "fix"     "$GO" "true" "0" "route mismatch scores 0 but still passes"
run "incident"                "incident" "$GO" "true" "1" "non-default route match"
run "banana"                  "fix"     "$GO" "true" "0" "hallucinated route scores 0 but still passes"

# --- ticket-triage P-level cases ---
run "P1"                      "P1"      "$TR" "true" "1" "P-level exact match"
run "Priority: P2"            "P2"      "$TR" "true" "1" "P-level embedded in prose"
run "p3"                      "P3"      "$TR" "true" "1" "P-level case-insensitive match"
run "P1"                      "P3"      "$TR" "true" "0" "P-level mismatch scores 0 but still passes"

# --- file:// enum shape (the promptfoo defaultTest.vars shape — #5358 regression).
#     enum arrives as a RAW STRING; loadEnum must read the SSOT file to score. ---
fileref() {
  local output="$1" golden="$2" enumref="$3" want_score="$4" label="$5"
  local got
  got=$(node -e '
    const fn = require(process.argv[1]);
    const r = fn(process.argv[2], { vars: { golden_label: process.argv[3], enum: process.argv[4] } });
    process.stdout.write(String(r.score));
  ' "$ASSERT" "$output" "$golden" "$enumref")
  if [[ "$got" != "$want_score" ]]; then
    echo "FAIL [$label]: output='$output' enum='$enumref' -> score=$got (want $want_score)"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: score=$got"
  fi
}
fileref "fix" "fix" "file://enums/go-routes.json"     "1" "file:// enum + correct route scores 1"
fileref "P2"  "P2"  "file://enums/triage-levels.json" "1" "file:// enum + correct P-level scores 1"

if [[ "$fails" -gt 0 ]]; then
  echo "measure-classification: $fails assertion(s) failed"
  exit 1
fi
echo "measure-classification: all assertions passed"
