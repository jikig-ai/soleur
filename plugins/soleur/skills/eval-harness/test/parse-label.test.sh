#!/usr/bin/env bash
# Deterministic unit test for the shared label parser (scripts/parse-label.cjs).
# Pins the documented three-tier contract:
#   1. exact (case-insensitive) match against the whole trimmed output
#   2. word-boundary search → the EARLIEST-occurring allowed label (not enum order)
#   3. fallback → the raw first non-empty line (so the gate can reject it)
# Also pins the documented limitations: hyphenated labels are not split, a label
# that is a strict substring of a longer token does not match, and hedged/negated
# prose resolves to the first-mentioned label.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
PARSER="$SKILL_DIR/scripts/parse-label.cjs"
fails=0

# run <output> <enum-json> <expected-label> <case-label>
run() {
  local output="$1" enumjson="$2" want="$3" label="$4"
  local got
  got=$(node -e '
    const { extractLabel } = require(process.argv[1]);
    process.stdout.write(String(extractLabel(process.argv[2], JSON.parse(process.argv[3]))));
  ' "$PARSER" "$output" "$enumjson")
  if [[ "$got" != "$want" ]]; then
    echo "FAIL [$label]: output='$output' -> '$got' (want '$want')"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: '$got'"
  fi
}

# run_empty <enum-json> <expected> <case-label>  (output is the empty/undefined case)
run_empty() {
  local enumjson="$1" want="$2" label="$3"
  local got
  got=$(node -e '
    const { extractLabel } = require(process.argv[1]);
    const out = process.argv[3] === "__NULL__" ? null : process.argv[3];
    process.stdout.write(String(extractLabel(out, JSON.parse(process.argv[2]))));
  ' "$PARSER" "$enumjson" "$4")
  if [[ "$got" != "$want" ]]; then
    echo "FAIL [$label]: -> '$got' (want '$want')"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: '$got'"
  fi
}

GO='["fix","drain","clo-attestation","review","legal-threshold","incident","default"]'
TR='["P1","P2","P3"]'

# --- Tier 1: exact match ---
run "fix"                     "$GO" "fix"             "tier1 exact route"
run "P1"                      "$TR" "P1"              "tier1 exact P-level"
run "p2"                      "$TR" "P2"              "tier1 exact case-insensitive"
run "  review  "              "$GO" "review"          "tier1 exact after trim"

# --- Tier 2: word-boundary, EARLIEST-occurrence wins (not enum order) ---
run "The route is review."    "$GO" "review"          "tier2 single label in prose"
run "review, not fix"         "$GO" "review"          "tier2 earliest wins over enum order (fix precedes review in enum)"
run "default, or maybe fix"   "$GO" "default"         "tier2 earliest wins (default precedes fix in text)"
run "Route: incident"         "$GO" "incident"        "tier2 label after prompt label"
run "clo-attestation"         "$GO" "clo-attestation" "tier2 hyphenated label not split"
run "use legal-threshold here" "$GO" "legal-threshold" "tier2 hyphenated label in prose"
# Documented limitation: negation resolves to the first-mentioned label.
run "not P1, use P2"          "$TR" "P1"              "tier2 documented negation limitation (first-mentioned)"

# --- Tier 2 substring safety: a strict substring of a longer token must NOT match ---
run "P10"                     "$TR" "P10"             "tier2 P1 not matched inside P10 (falls to raw)"

# --- Tier 3: fallback to raw first non-empty line (gate will reject) ---
run "banana"                  "$GO" "banana"          "tier3 out-of-enum raw token"
run $'   \nfirst junk line\nsecond' "$GO" "first junk line" "tier3 first non-empty line"

# --- Null / empty handling ---
run_empty "$GO" "" "empty string output" ""
run_empty "$GO" "" "null output" "__NULL__"

if [[ "$fails" -gt 0 ]]; then
  echo "parse-label: $fails assertion(s) failed"
  exit 1
fi
echo "parse-label: all assertions passed"
