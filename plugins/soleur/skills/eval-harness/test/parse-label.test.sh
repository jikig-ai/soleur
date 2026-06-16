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

# --- loadEnum: the var shapes promptfoo actually passes ---
# promptfoo's handling of a `defaultTest.vars` `file://*.json` value is
# version-dependent: it may pass the RESOLVED FILE CONTENTS (JSON array text as a
# string) OR the literal unresolved `file://...` ref. loadEnum must handle BOTH
# (plus a direct array), returning [] (gate fails closed) on anything else. The
# resolved-contents case is the one a prior simplification dropped, vacuuming the
# gate — these cases lock both shapes so it cannot recur.
loadenum() {
  local enumval="$1" want_len="$2" want_first="$3" label="$4"
  local got
  got=$(node -e '
    const { loadEnum } = require(process.argv[1]);
    const v = process.argv[2] === "__ARRAY__"
      ? ["a","b","c"]
      : process.argv[2];
    const e = loadEnum({ enum: v });
    process.stdout.write(JSON.stringify({ len: e.length, first: (e[0] ?? null) }));
  ' "$SKILL_DIR/scripts/parse-label.cjs" "$enumval")
  local got_len got_first
  got_len=$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).len))' "$got")
  got_first=$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).first))' "$got")
  if [[ "$got_len" != "$want_len" || "$got_first" != "$want_first" ]]; then
    echo "FAIL [$label]: enum='$enumval' -> len=$got_len first=$got_first (want len=$want_len first=$want_first)"
    fails=$((fails + 1))
  else
    echo "ok   [$label]: len=$got_len first=$got_first"
  fi
}

# promptfoo's file:// var handling is version-dependent: it may pass the literal
# `file://...` ref OR the RESOLVED FILE CONTENTS (JSON array text). Both must work.
loadenum "file://enums/go-routes.json"     7 "fix" "loadEnum file:// literal ref (one promptfoo shape)"
loadenum "file://enums/triage-levels.json" 3 "P1"  "loadEnum file:// triage-levels"
loadenum "enums/go-routes.json"            7 "fix" "loadEnum bare relative path"
# The resolved-contents shape — what promptfoo actually passes when it resolves a
# defaultTest.vars file:// ref to the file's CONTENTS. Regression guard for the
# gate-vacuous bug (loadEnum must JSON.parse a JSON-array-text string, not treat it
# as a path). JSON array text as a string.
loadenum '["fix","drain","clo-attestation","review","legal-threshold","incident","default"]' 7 "fix" "loadEnum JSON-array-text contents (promptfoo file:// resolved-contents shape)"
loadenum '[ "a", "b", "c" ]'               3 "a"   "loadEnum whitespaced JSON-array-text contents"
loadenum "__ARRAY__"                       3 "a"   "loadEnum direct array passthrough"
loadenum "file://enums/does-not-exist.json" 0 "null" "loadEnum unreadable file -> [] (gate fails closed)"
loadenum "not json and not a path"         0 "null" "loadEnum garbage -> [] (gate fails closed)"
loadenum ""                                0 "null" "loadEnum empty string -> []"

if [[ "$fails" -gt 0 ]]; then
  echo "parse-label: $fails assertion(s) failed"
  exit 1
fi
echo "parse-label: all assertions passed"
