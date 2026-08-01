#!/usr/bin/env bash
# Tests the CONSUMER half of the Cloudflare token-drift detector: the
# `scheduled-terraform-drift.yml` step that parses the detector's --json-file and
# derives `verdict` / `causes` / `configs` / `coverage`, plus the email bodies that
# render them.
#
# WHY THIS EXISTS. PR #7134 moved UNVERIFIABLE from one bucket with one static
# remedy to a closed CAUSE vocabulary the workflow branches on, and shipped with the
# emitting side pinned and the consuming side pinned by nothing — stated as a known
# gap in that PR's body rather than papered over. The gap matters because the
# failure it enables is silent: a cause the detector emits but the email never
# renders sends the operator a remedy for a different problem, which is the exact
# defect #7134 existed to remove.
#
# TWO RULES THIS SUITE FOLLOWS, both learned the hard way in #7134:
#
#   1. The parser under test is EXTRACTED FROM THE WORKFLOW, never re-implemented.
#      A hand-copied `python3 -c` would pin the copy, and the workflow could drift
#      away from it while this suite stayed green.
#   2. The expected cause vocabulary is DERIVED FROM THE DETECTOR SOURCE, never
#      restated here. A restated list is a second unsynchronized pin: the detector
#      grows a cause, the list does not, and the parity assertion passes over a
#      cause no email can explain. Deriving it means adding a cause to the detector
#      REDS this suite until the email learns to render it.
#
# Run: bash plugins/soleur/test/token-drift-workflow-causes.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml"
DETECTOR="$REPO_ROOT/scripts/check-cloudflare-token-drift.sh"

export TMPDIR="${TMPDIR:-/var/tmp}"
PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d) || { echo "FATAL: sandbox"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

for f in "$WF" "$DETECTOR"; do
  [[ -f "$f" ]] || { echo "FATAL: missing $f"; exit 2; }
done

echo "=== token-drift workflow consumer ==="

# ---------------------------------------------------------------------------
# Extract the REAL parser from the workflow. The line is the `python3 -c '...'`
# inside the `read -r dead unver causes configs < <(...)` process substitution.
# ---------------------------------------------------------------------------
PARSER=$(grep -F 'read -r dead unver causes configs < <(python3 -c' "$WF" | head -1)
if [[ -n "$PARSER" ]]; then
  pass "the workflow's verdict-parser line was located for extraction"
else
  fail "could not find the 'read -r dead unver causes configs' parser in $WF — every assertion below would test a copy, not the workflow"
fi

# Run the WHOLE extracted line — including its `|| echo` fallback — by pointing
# $RUNNER_TEMP at a fixture dir. An earlier version extracted only the python
# program and re-added the fallback here; a mutation deleting the workflow's
# fallback then left this suite green, because the suite was testing its own copy.
# That is the precise failure rule 1 in this header names, committed by this file.
run_parser() {
  local fixture_dir="$1"
  local out
  out=$(RUNNER_TEMP="$fixture_dir" bash -c "
    $PARSER
    printf '%s %s %s %s' \"\$dead\" \"\$unver\" \"\$causes\" \"\$configs\"
  " 2>/dev/null)
  printf '%s' "$out"
}

# Coverage derivation, extracted from the workflow so the same drift rule applies.
COVERAGE_SNIPPET=$(grep -F 'coverage=single-config' "$WF" | head -1)
if [[ -n "$COVERAGE_SNIPPET" ]]; then
  pass "the coverage derivation is present in the workflow"
else
  fail "the workflow has no coverage derivation — a single-config scan would report 'clean' with nothing qualifying it"
fi

# Extract the coverage derivation from the workflow (the three lines from
# `coverage=full` through the `unknown` assignment) and evaluate THOSE, for the
# same reason as run_parser: a local re-implementation cannot observe the
# workflow's rule changing underneath it.
COVERAGE_BLOCK=$(awk '/^[[:space:]]*coverage=full$/{f=1} f{print} /coverage=unknown$/{if(f) exit}' "$WF")
derive_coverage() {
  local configs="$1"
  bash -c "configs='$configs'
    $COVERAGE_BLOCK
    printf '%s' \"\$coverage\"" 2>/dev/null
}

# ---------------------------------------------------------------------------
# T1-T5 — the parser's contract.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/two"
cat > "$TMP/two/token-drift.json" <<'JSON'
{"live":3,"dead":0,"unverifiable":3,"probes":4,"configs":7,
 "stale":[],
 "unverifiable_keys":[
   {"key":"A_ID/_SECRET","cause":"probe-failed","reason":"x"},
   {"key":"B_ID/_SECRET","cause":"gate-absent","reason":"y"},
   {"key":"C_ID/_SECRET","cause":"detector-env","reason":"z"}]}
JSON
# These three are chosen so SET iteration order differs from SORTED order
# (set -> "gate-absent,probe-failed,detector-env"; sorted -> "detector-env,...").
# A two-element fixture happened to hash into sorted order, so dropping sorted()
# from the workflow left the assertion green — the sort was asserted by luck.
echo "T1: multiple causes are comma-joined and SORTED (stable for a downstream match)"
got=$(run_parser "$TMP/two")
if [[ "$got" == "0 3 detector-env,gate-absent,probe-failed 7" ]]; then
  pass "three causes -> sorted 'detector-env,gate-absent,probe-failed'"
else
  fail "expected sorted 'detector-env,gate-absent,probe-failed', got '$got' — the workflow's email interpolates this string verbatim, and an unsorted set order makes it unstable run-to-run"
fi

mkdir -p "$TMP/clean"
cat > "$TMP/clean/token-drift.json" <<'JSON'
{"live":9,"dead":0,"unverifiable":0,"probes":9,"configs":13,"stale":[],"unverifiable_keys":[]}
JSON
echo "T2: zero unverifiable rows yield the '-' sentinel, never an empty field"
got=$(run_parser "$TMP/clean")
if [[ "$got" == "0 0 - 13" ]]; then
  pass "empty vocabulary renders '-' so \`read\` still fills all four variables"
else
  fail "expected '0 0 - 13', got '$got' — an empty third field shifts \`configs\` into \`causes\` and the coverage derivation then reads a cause string as a number"
fi

mkdir -p "$TMP/nocause"
cat > "$TMP/nocause/token-drift.json" <<'JSON'
{"live":0,"dead":0,"unverifiable":1,"probes":1,"configs":2,
 "stale":[],"unverifiable_keys":[{"key":"K","reason":"no cause key at all"}]}
JSON
echo "T3: a row with no 'cause' key degrades to 'unknown', not to a crash"
got=$(run_parser "$TMP/nocause")
if [[ "$got" == "0 1 unknown 2" ]]; then
  pass "a malformed row is absorbed as 'unknown'"
else
  fail "expected '0 1 unknown 2', got '$got' — a KeyError here takes the whole step's fallback path and reports the fleet unavailable"
fi

mkdir -p "$TMP/corrupt"
printf '{ this is not json' > "$TMP/corrupt/token-drift.json"
echo "T4: corrupt JSON takes the fallback and is NEVER read as clean"
got=$(run_parser "$TMP/corrupt")
if [[ "$got" == "-1 -1 - -1" ]]; then
  pass "corrupt verdict file -> '-1 -1 - -1' (the workflow maps dead=-1 to 'unavailable')"
else
  fail "expected the '-1 -1 - -1' fallback, got '$got' — anything else risks an unreadable scan being read as a healthy fleet"
fi

mkdir -p "$TMP/missing"
echo "T5: a MISSING verdict file takes the same fallback"
got=$(run_parser "$TMP/missing")
if [[ "$got" == "-1 -1 - -1" ]]; then
  pass "missing verdict file -> fallback"
else
  fail "expected the fallback for a missing file, got '$got'"
fi

# ---------------------------------------------------------------------------
# T6-T8 — coverage derivation. This is the fan-out question, which is separate
# from the verdict question: the detector's own header cites "5 of 7 configs
# stale", and the scheduled run's Doppler token is scoped to ONE config.
# ---------------------------------------------------------------------------
echo "T6: a 1-config scan derives coverage=single-config"
c=$(derive_coverage 1)
if [[ "$c" == "single-config" ]]; then
  pass "configs=1 -> single-config"
else
  fail "configs=1 must derive single-config, got '$c' — a scan that read one config cannot detect a value stale only in a config it never read, and 'clean' would be over-read as fleet-wide"
fi

echo "T7: a multi-config scan derives coverage=full"
c=$(derive_coverage 13)
if [[ "$c" == "full" ]]; then
  pass "configs=13 -> full"
else
  fail "configs=13 must derive full, got '$c'"
fi

echo "T8: an absent configs field derives coverage=unknown, not full"
c=$(derive_coverage -1)
if [[ "$c" == "unknown" ]]; then
  pass "configs=-1 -> unknown (an unmeasured coverage is not a good one)"
else
  fail "configs=-1 must derive unknown, got '$c' — defaulting an unmeasured coverage to 'full' is the silent direction"
fi

# ---------------------------------------------------------------------------
# T9-T11 — VOCABULARY PARITY. The cause set is derived from the detector source,
# so a new cause reds this suite until the workflow email learns to render it.
# ---------------------------------------------------------------------------
mapfile -t CAUSES < <(grep -oE 'UNVERIFIABLE:[a-z-]+' "$DETECTOR" | sed 's/^UNVERIFIABLE://' | sort -u)
# The unmapped-base row is pushed with a literal `|no-probe-configured|` field
# rather than through a PAIR_VERDICT string, so the grep above cannot see it.
grep -q '|no-probe-configured|' "$DETECTOR" && CAUSES+=("no-probe-configured")
mapfile -t CAUSES < <(printf '%s\n' "${CAUSES[@]}" | sort -u)

echo "T9: the cause vocabulary is non-empty (guards a silently-broken extraction)"
if (( ${#CAUSES[@]} >= 4 )); then
  pass "derived ${#CAUSES[@]} causes from the detector: ${CAUSES[*]}"
else
  fail "derived only ${#CAUSES[@]} causes — the extraction regex has drifted from the detector, and every parity assertion below would pass vacuously over an empty set"
fi

# The UNVERIFIABLE email body is the operator's per-cause remedy surface.
UNVER_BODY=$(grep -F 'No conclusion could be drawn about at least one token' -A 2 "$WF" | head -4)
echo "T10: every cause the detector can emit is explained in the UNVERIFIABLE email"
missing=()
for c in "${CAUSES[@]}"; do
  printf '%s' "$UNVER_BODY" | grep -qF "<code>${c}</code>" || missing+=("$c")
done
if (( ${#missing[@]} == 0 )); then
  pass "all ${#CAUSES[@]} causes have a <li><code>cause</code> entry"
else
  fail "causes with no entry in the operator email: ${missing[*]} — the detector can emit these and the email cannot explain them, so the operator receives a remedy for a different problem (the exact defect #7134 removed one layer down)"
fi

echo "T11: the email does not explain a cause the detector cannot emit"
stale_entries=()
while IFS= read -r tok; do
  found=0
  for c in "${CAUSES[@]}"; do [[ "$tok" == "$c" ]] && { found=1; break; }; done
  (( found == 0 )) && stale_entries+=("$tok")
done < <(printf '%s' "$UNVER_BODY" | grep -oE '<code>[a-z-]+</code>' | sed 's/<\/\?code>//g' | sort -u \
         | grep -E '^(no-probe-configured|gate-absent|gate-indeterminate|control-blocked|host-unreachable|probe-failed|refused-unstamped|stamped-non-refusal|unexpected-status|detector-env)$')
if (( ${#stale_entries[@]} == 0 )); then
  pass "no orphaned cause entries in the email"
else
  fail "email explains causes the detector no longer emits: ${stale_entries[*]} — dead remedies train the operator to skim"
fi

# ---------------------------------------------------------------------------
# T12 — the gate-absent arm must fire on CAUSES, not on VERDICT. The ladder is
# first-match (dead > unverifiable > clean), so a security finding gated on the
# verdict is dropped whenever any dead row co-occurs.
# ---------------------------------------------------------------------------
echo "T12: the gate-absent email arm keys on outputs.causes, independent of the verdict ladder"
GATE_ARM=$(grep -F "contains(steps.token_drift.outputs.causes, 'gate-absent')" "$WF" | head -1)
if [[ -n "$GATE_ARM" ]]; then
  pass "gate-absent fires on causes, so a co-occurring dead row cannot pre-empt it"
else
  fail "the gate-absent arm does not key on outputs.causes — with a first-match ladder, a dead row anywhere in the same run silently drops the 'nothing is gating this host' finding"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Deleting every assertion call yields "0/0 passed" and exit 0,
# which test-all.sh (reading only the exit code) cannot distinguish from success.
# A FLOOR, not equality: adding a case must not require editing this line.
if [[ "$((PASS + FAIL))" -lt 13 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 13." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
