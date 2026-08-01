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
# Run the WHOLE `token_drift` step body, not a grepped line.
#
# v1 extracted one `read -r …` line and a three-line awk window, and its prose spoke
# about "the step". Review mutated the workflow and found 7 survivors living in the
# lines BETWEEN those two fragments — including deleting the ::warning:: and both
# email footers (the PR's entire user-visible deliverable) at a fully green suite,
# and `if [[ "$rc" == "2" || "$dead" == "-1" ]]` -> `if [[ "$rc" == "2" ]]`, which
# routes a corrupt verdict file to `clean` — the exact thing T4's pass-message claims
# to prevent.
#
# So: pull the step's `run:` body out of the YAML, stub ONLY the detector invocation
# (the external dependency), point $RUNNER_TEMP at a fixture dir and $GITHUB_OUTPUT at
# a temp file, and execute it under `bash -eo pipefail` — the shell Actions actually
# uses. Assertions then read the PUBLISHED outputs, which is what every downstream
# consumer sees.
# ---------------------------------------------------------------------------
STEP_BODY=$(python3 - "$WF" <<'PYX'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for job in d["jobs"].values():
    for st in job.get("steps", []):
        if st.get("id") == "token_drift":
            sys.stdout.write(st["run"]); raise SystemExit(0)
raise SystemExit("no step with id: token_drift")
PYX
)
if [[ -n "$STEP_BODY" ]]; then
  pass "the token_drift step body was extracted from the workflow YAML"
else
  fail "could not extract the token_drift step — every assertion below would test nothing. Re-point the extractor rather than deleting this case."
fi

# Stub the detector call, preserving the `|| rc=$?` shape the step depends on.
DETECTOR_CALL='bash scripts/check-cloudflare-token-drift.sh --json-file "$RUNNER_TEMP/token-drift.json"'
if [[ "$STEP_BODY" == *"$DETECTOR_CALL"* ]]; then
  pass "the detector invocation was located for stubbing"
else
  fail "the detector invocation changed shape; the stub below would not apply and the step would shell out for real"
fi

# run_step <fixture-dir> <detector-rc> -> echoes "rc|<published key=value lines, ;-joined>"
run_step() {
  local dir="$1" det_rc="${2:-0}"
  local out; out=$(mktemp)
  local body="${STEP_BODY//$DETECTOR_CALL/bash -c \"exit $det_rc\"}"
  local step_rc=0
  STEP_STDOUT=$(mktemp)
  RUNNER_TEMP="$dir" GITHUB_OUTPUT="$out" bash -eo pipefail -c "$body" >"$STEP_STDOUT" 2>&1 || step_rc=$?
  printf '%s|%s' "$step_rc" "$(tr '\n' ';' < "$out")"
  rm -f "$out"
}

# Read one published output value from a run_step result.
out_val() { printf '%s' "$1" | sed 's/^[0-9]*|//' | tr ';' '\n' | sed -n "s/^$2=//p" | head -1; }

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
r=$(run_step "$TMP/two" 1)
got="$(out_val "$r" causes)"
if [[ "$got" == "detector-env,gate-absent,probe-failed" ]]; then
  pass "three causes -> sorted 'detector-env,gate-absent,probe-failed' (published output)"
else
  fail "expected sorted 'detector-env,gate-absent,probe-failed', got '$got' — the workflow's email interpolates this string verbatim, and an unsorted set order makes it unstable run-to-run"
fi

mkdir -p "$TMP/clean"
cat > "$TMP/clean/token-drift.json" <<'JSON'
{"live":9,"dead":0,"unverifiable":0,"probes":9,"configs":13,"stale":[],"unverifiable_keys":[]}
JSON
echo "T2: zero unverifiable rows yield the '-' sentinel, never an empty field"
r=$(run_step "$TMP/clean" 0)
got="$(out_val "$r" causes) $(out_val "$r" configs) $(out_val "$r" verdict)"
if [[ "$got" == "- 13 clean" ]]; then
  pass "empty vocabulary publishes causes='-', configs=13, verdict=clean"
else
  fail "expected '0 0 - 13', got '$got' — an empty third field shifts \`configs\` into \`causes\` and the coverage derivation then reads a cause string as a number"
fi

mkdir -p "$TMP/nocause"
cat > "$TMP/nocause/token-drift.json" <<'JSON'
{"live":0,"dead":0,"unverifiable":1,"probes":1,"configs":2,
 "stale":[],"unverifiable_keys":[{"key":"K","reason":"no cause key at all"}]}
JSON
echo "T3: a row with no 'cause' key degrades to 'unknown', not to a crash"
r=$(run_step "$TMP/nocause" 1)
got="$(out_val "$r" causes) $(out_val "$r" configs)"
if [[ "$got" == "unknown 2" ]]; then
  pass "a malformed row is absorbed as 'unknown'"
else
  fail "expected '0 1 unknown 2', got '$got' — a KeyError here takes the whole step's fallback path and reports the fleet unavailable"
fi

mkdir -p "$TMP/corrupt"
printf '{ this is not json' > "$TMP/corrupt/token-drift.json"
echo "T4: corrupt JSON takes the fallback and is NEVER read as clean"
r=$(run_step "$TMP/corrupt" 1)
got="$(out_val "$r" verdict)"
if [[ "$got" == "unavailable" ]]; then
  pass "corrupt verdict file publishes verdict=unavailable — never 'clean'"
else
  fail "expected the '-1 -1 - -1' fallback, got '$got' — anything else risks an unreadable scan being read as a healthy fleet"
fi

mkdir -p "$TMP/missing"
echo "T5: a MISSING verdict file takes the same fallback"
r=$(run_step "$TMP/missing" 1)
got="$(out_val "$r" verdict)"
if [[ "$got" == "unavailable" ]]; then
  pass "missing verdict file publishes verdict=unavailable"
else
  fail "expected the fallback for a missing file, got '$got'"
fi

# ---------------------------------------------------------------------------
# T6-T8 — coverage derivation. This is the fan-out question, which is separate
# from the verdict question: the detector's own header cites "5 of 7 configs
# stale", and the scheduled run's Doppler token is scoped to ONE config.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/one" "$TMP/two_cfg"
printf '{"live":1,"dead":0,"unverifiable":0,"probes":1,"configs":1,"stale":[],"unverifiable_keys":[]}' > "$TMP/one/token-drift.json"
printf '{"live":2,"dead":0,"unverifiable":0,"probes":2,"configs":2,"stale":[],"unverifiable_keys":[]}' > "$TMP/two_cfg/token-drift.json"
echo "T6: a 1-config scan derives coverage=single-config"
c=$(out_val "$(run_step "$TMP/one" 0)" coverage)
if [[ "$c" == "single-config" ]]; then
  pass "configs=1 -> single-config"
else
  fail "configs=1 must derive single-config, got '$c' — a scan that read one config cannot detect a value stale only in a config it never read, and 'clean' would be over-read as fleet-wide"
fi

echo "T7: a 2-config scan is enough to leave the single-config state"
c=$(out_val "$(run_step "$TMP/two_cfg" 0)" coverage)
if [[ "$c" == "multi-config" ]]; then
  pass "configs=2 -> multi-config"
else
  fail "configs=2 must derive multi-config, got '$c'"
fi

echo "T8: every UNPARSEABLE configs value derives unknown, never the confident state"
# -1 is the documented fallback sentinel; the rest are the fail-open family found in
# review. The first version of the derivation defaulted to the confident state and
# moved off it on two guarded assignments, so `None` (a JSON null reaching
# d.get("configs", -1)), a negative, a word, or any field-shift out of `read -r`'s
# greedy last variable ALL asserted fleet-wide coverage. Pinning only -1 could not
# see that: it was the one input that already worked.
_t8=1
for bad in -1 -2 None abc null; do
  mkdir -p "$TMP/bad"
  printf '{"live":0,"dead":0,"unverifiable":0,"probes":0,"configs":%s,"stale":[],"unverifiable_keys":[]}' \
    "$([[ "$bad" =~ ^(-?[0-9]+|null)$ ]] && printf '%s' "$bad" || printf '"%s"' "$bad")" > "$TMP/bad/token-drift.json"
  c=$(out_val "$(run_step "$TMP/bad" 0)" coverage)
  [[ "$c" == "unknown" ]] || { _t8=0; echo "    configs='$bad' derived '$c'"; }
done
if [[ "$_t8" == "1" ]]; then
  pass "-1, -2, None, abc, empty and a field-shift all derive unknown"
else
  fail "an unparseable configs value derived something other than 'unknown' — the confident state must never be the default for a number we could not read, because the email then reassures the operator with that word"
fi

echo "T8b: a parseable multi-config count derives multi-config, not 'full'"
c=$(out_val "$(run_step "$TMP/clean" 0)" coverage)
if [[ "$c" == "multi-config" ]]; then
  pass "13 -> multi-config (counts configs READ, which is not the number that EXISTS)"
else
  fail "expected multi-config, got '$c' — naming this state 'full' claims a completeness the count has no denominator for: the config list is itself scope-filtered by the same token"
fi

# ---------------------------------------------------------------------------
# T9-T11 — VOCABULARY PARITY. The cause set is derived from the detector source,
# so a new cause reds this suite until the workflow email learns to render it.
# ---------------------------------------------------------------------------
mapfile -t CAUSES < <(grep -oE 'UNVERIFIABLE:[a-z-]+' "$DETECTOR" | sed 's/^UNVERIFIABLE://' | sort -u)
# The unmapped-base row is pushed with a literal `|no-probe-configured|` field
# rather than through a PAIR_VERDICT string, so the grep above cannot see it.
grep -q '|no-probe-configured|' "$DETECTOR" && CAUSES+=("no-probe-configured")
# `unknown` originates in the WORKFLOW's parser (r.get("cause","unknown")), not in the
# detector — so a detector-only derivation is blind to it, which is exactly where T3's
# fixture lives. T3 pins it as contract; the email must therefore explain it.
grep -qF 'r.get("cause","unknown")' "$WF" && CAUSES+=("unknown")
mapfile -t CAUSES < <(printf '%s\n' "${CAUSES[@]}" | sort -u)

echo "T9: the cause vocabulary is non-empty (guards a silently-broken extraction)"
if (( ${#CAUSES[@]} >= 5 )); then
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
         | grep -E "^($(IFS='|'; printf '%s' "${CAUSES[*]}")|unknown)$")
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

echo "T13: narrow coverage has a delivery channel that survives a GREEN clean run"
ARM=$(grep -F "steps.token_drift.outputs.coverage != 'multi-config'" "$WF" | head -1)
if [[ -n "$ARM" ]]; then
  pass "an arm fires on coverage alone, independent of verdict/outcome"
else
  fail "nothing fires on coverage alone. A single-config scan yields verdict=clean, rc=0, outcome=success — so NO email arm matches and the enforce step is skipped, leaving a ::warning:: on a green cron run as the only artifact. Nobody opens a green cron run (hr-no-dashboard-eyeball-pull-data-yourself)"
fi

echo "T14: that arm is CREATE-ONLY (the condition holds on every run until fixed)"
if grep -q 'create-only, not commenting' "$WF" && grep -qF 'gh issue list --label "$LABEL" --state open' "$WF"; then
  pass "an existing open coverage issue short-circuits instead of re-commenting"
else
  fail "the coverage arm must not comment on an existing issue: coverage is single-config on EVERY scheduled run until the token scope is widened, so create-or-comment posts ~730 comments a year and trains the operator to filter the label"
fi

echo "T15: a single-config scan EMITS the ::warning:: annotation"
run_step "$TMP/one" 0 >/dev/null
if grep -q '::warning::.*Doppler config' "$STEP_STDOUT"; then
  pass "the annotation is emitted, not merely derivable"
else
  fail "no ::warning:: on a single-config scan — deriving coverage correctly and showing it to nobody is the whole defect this PR exists to fix; the derivation was previously pinned while its only in-run surface was not"
fi

echo "T16: a multi-config scan does NOT emit the warning (no hedge when there is nothing to hedge)"
run_step "$TMP/clean" 0 >/dev/null
if ! grep -q '::warning::.*Doppler config' "$STEP_STDOUT"; then
  pass "a full-fan-out scan is quiet"
else
  fail "the warning fired on a multi-config scan — an unconditional hedge is the defect the enforce step's own comment records removing ('a hedge that fires when there is nothing to hedge makes a true alarm look uncertain')"
fi

echo "T17: a 0-config scan is not the confident state"
mkdir -p "$TMP/zero"
printf '{"live":0,"dead":0,"unverifiable":0,"probes":0,"configs":0,"stale":[],"unverifiable_keys":[]}' > "$TMP/zero/token-drift.json"
c=$(out_val "$(run_step "$TMP/zero" 0)" coverage)
if [[ "$c" == "single-config" ]]; then
  pass "configs=0 -> single-config (nothing read is not fleet-wide)"
else
  fail "configs=0 derived '$c' — a threshold of '== 1' rather than '< 2' lets a scan that read NOTHING report the confident state, which is the silent direction"
fi

echo "T18: unverifiable rows publish verdict=unverifiable (the ladder branch actually fires)"
v=$(out_val "$(run_step "$TMP/two" 1)" verdict)
if [[ "$v" == "unverifiable" ]]; then
  pass "unver>0 with dead=0 publishes verdict=unverifiable"
else
  fail "expected verdict=unverifiable, got '$v' — widening the ladder's unver threshold silently disables the UNVERIFIABLE email arm entirely"
fi

echo "T19: both verdict-bearing email bodies carry the coverage caveat"
_t19=1
# Anchor on text that lives in the BODY. 'No conclusion could be drawn' is the
# UNVERIFIABLE step's SUBJECT, so anchoring there matched a line with no body: and
# reported a caveat missing from a body that has one — the assertion was wrong, not
# the workflow. Verified by auditing every body: line before changing anything.
for phrase in 'no longer accepted by Cloudflare' 'No token was found stale'; do
  line=$(grep -F "$phrase" "$WF" | grep -F 'body:' | head -1)
  printf '%s' "$line" | grep -q 'Scan coverage:' || { _t19=0; echo "    missing caveat in the body containing: $phrase"; }
done
if [[ "$_t19" == "1" ]]; then
  pass "the DEAD and UNVERIFIABLE bodies both render coverage"
else
  fail "a verdict-bearing email lost its coverage caveat — the reader is told a finding without being told how much of the fleet was actually looked at"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Deleting every assertion call yields "0/0 passed" and exit 0,
# which test-all.sh (reading only the exit code) cannot distinguish from success.
# A FLOOR, not equality: adding a case must not require editing this line.
if [[ "$((PASS + FAIL))" -lt 20 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 20." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
