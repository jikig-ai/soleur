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
  # Under $TMP so the EXIT trap reclaims it. `mktemp` put one file per call in TMPDIR
  # (exported to /var/tmp above) and never removed it — ~20 leaked strays per run.
  STEP_STDOUT="$TMP/step-stdout.$$"
  RUNNER_TEMP="$dir" GITHUB_OUTPUT="$out" bash -eo pipefail -c "$body" >"$STEP_STDOUT" 2>&1 || step_rc=$?
  printf '%s|%s' "$step_rc" "$(tr '\n' ';' < "$out")"
  rm -f "$out"
}

# Read one published output value from a run_step result.
out_val() { printf '%s' "$1" | sed 's/^[0-9]*|//' | tr ';' '\n' | sed -n "s/^$2=//p" | head -1; }

# step_field <step-name-prefix> <if|run> -> that step's parsed field, or exit 1.
#
# WHY THIS EXISTS. T12/T13/T14 originally grepped the WHOLE workflow for a literal, which
# pins spelling, not behavior — and this PR simultaneously added a comment block quoting
# those same literals, so a comment satisfies the assertion. All three were measured
# green under mutations that reproduced the exact defect each one names:
#   T13  `always()` -> `failure()` on the coverage arm   (step skipped on every clean run)
#   T13  `if:` replaced, literal preserved in a comment  (cq-assert-anchor-not-bare-token)
#   T14  `exit 0` deleted under the short-circuit        (~730 duplicate issues a year)
#   T12  gate-absent re-gated onto the verdict ladder    (security finding pre-empted)
# Extracting the step by NAME and asserting inside ITS OWN parsed field is the shape the
# sibling detector suite's W10 adopted for the same reason. A comment cannot survive
# yaml.safe_load, and a missing step is a hard failure rather than a silent zero-match.
step_field() {
  python3 - "$WF" "$1" "$2" <<'PYF'
import sys, yaml
wf, want, field = sys.argv[1], sys.argv[2], sys.argv[3]
for job in yaml.safe_load(open(wf))["jobs"].values():
    for st in job.get("steps", []) or []:
        if str(st.get("name", "")).startswith(want):
            v = st.get(field)
            if v is None:
                raise SystemExit(f"step '{want}' has no '{field}:'")
            sys.stdout.write(str(v))
            raise SystemExit(0)
raise SystemExit(f"no step named '{want}'")
PYF
}

COVERAGE_STEP="Open an action-required issue (token drift — narrow scan coverage)"

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
# DERIVE FROM THE EMITTED LITERAL, not from the internal state string. `UNVERIFIABLE:
# <cause>` is the PAIR_VERDICT map VALUE; what actually reaches the JSON the workflow
# parses is the second field of an `UNVERIFIABLE_ROWS+=(...)` push, produced by a `case`
# that translates the first into the second. Deriving from PAIR_VERDICT pinned the wrong
# side: renaming ONE row literal (`|probe-failed|` -> `|probe-timeout|`) while leaving
# its PAIR_VERDICT string intact left this suite fully green while the detector emitted
# a cause the email had no <li> for — the exact defect this file exists to catch.
# Verified by mutation.
mapfile -t CAUSES < <(grep -oE 'UNVERIFIABLE_ROWS\+=\("\$\{base\}_ID/_SECRET\|[a-z-]+\|' "$DETECTOR" \
                      | grep -oE '\|[a-z-]+\|' | tr -d '|' | sort -u)
# The two vocabularies must agree. They are separate literals in separate lines of the
# detector, so either can drift alone: a PAIR_VERDICT state with no `case` arm emits
# nothing (dead code), and an emitted cause with no PAIR_VERDICT state means the `case`
# invented one. Cardinality is the cheap cross-check — a member either extraction cannot
# see is otherwise silently exempt from every parity assertion below, and that exemption
# is invisible on a green run.
mapfile -t _PAIR_CAUSES < <(grep -oE 'UNVERIFIABLE:[a-z-]+' "$DETECTOR" | sed 's/^UNVERIFIABLE://' | sort -u)
# The unmapped-base row is pushed with a literal `|no-probe-configured|` field and has no
# PAIR_VERDICT state at all, so it is expected in CAUSES and not in _PAIR_CAUSES.
echo "T9a: the emitted cause vocabulary and the internal PAIR_VERDICT vocabulary agree"
_only_pair=()
for c in "${_PAIR_CAUSES[@]}"; do
  printf '%s\n' "${CAUSES[@]}" | grep -qx "$c" || _only_pair+=("$c")
done
if (( ${#_only_pair[@]} == 0 )); then
  pass "every PAIR_VERDICT state has a matching emitted row literal (${#_PAIR_CAUSES[@]} states, ${#CAUSES[@]} emitted)"
else
  fail "PAIR_VERDICT states with no matching emitted row literal: ${_only_pair[*]} — the case translating state to row has drifted, so the detector either emits a cause name nothing derived or drops one entirely"
fi
# `unknown` originates in the WORKFLOW's parser (r.get("cause","unknown")), not in the
# detector — so a detector-only derivation is blind to it, which is exactly where T3's
# fixture lives. T3 pins it as contract; the email must therefore explain it.
grep -qF 'r.get("cause","unknown")' "$WF" && CAUSES+=("unknown")
mapfile -t CAUSES < <(printf '%s\n' "${CAUSES[@]}" | sort -u)

# FLOOR AT THE CURRENT COUNT, not far below it. This was `>= 5` against 11 derived —
# six free slots, and a floor that slack cannot distinguish "the extraction broke" from
# "it worked". Measured: refactoring four detector cause literals behind a variable
# (invisible to the extraction) AND deleting their four email remedies left this suite
# 22/22 green, with T10 then checking 7 of 11 causes and the parity claim silently
# covering less. A DROP below this number means the extraction drifted; raise it when
# the detector legitimately grows a cause.
echo "T9: the cause vocabulary is complete (guards a silently-broken extraction)"
if (( ${#CAUSES[@]} >= 11 )); then
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
# NO membership filter on the input. The first version piped through
# `grep -E "^(${CAUSES[*]}|unknown)$"` — which keeps ONLY tokens already in CAUSES — and
# then asked whether each survivor was in CAUSES. `found` was always 1 and this assertion
# could not fail in either direction. Measured: injecting <code>bogus-orphan</code> into
# the email body left the suite 22/22 green.
#
# Anchored on `<li><code>` rather than a bare `<code>`, because the same body legitimately
# uses <code> for non-cause spans (access_hostname_for(), the script path, multi-config)
# and those are not orphaned remedies. Cause entries are always at list-item position,
# optionally as a `<code>a</code> / <code>b</code>` pair sharing one remedy.
done < <(printf '%s' "$UNVER_BODY" \
         | grep -oE '<li><code>[a-z-]+</code>( / <code>[a-z-]+</code>)?' \
         | grep -oE '<code>[a-z-]+</code>' | sed 's/<\/\?code>//g' | sort -u)
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
GATE_IF=$(step_field "Email notification (token drift — ACCESS GATE MISSING)" if) || GATE_IF=""
if grep -qF "contains(steps.token_drift.outputs.causes, 'gate-absent')" <<<"$GATE_IF" \
   && ! grep -qE "outputs\.verdict *==" <<<"$GATE_IF"; then
  pass "gate-absent fires on causes, so a co-occurring dead row cannot pre-empt it"
else
  fail "the gate-absent arm does not key on outputs.causes (its if: is '${GATE_IF}') — with a first-match ladder, a dead row anywhere in the same run silently drops the 'nothing is gating this host' finding"
fi

echo "T13: narrow coverage has a delivery channel that survives a GREEN clean run"
COV_IF=$(step_field "$COVERAGE_STEP" if) || COV_IF=""
# Three properties, all load-bearing, asserted on the step's OWN parsed `if:`:
#   always()          — a clean single-config run exits 0, so failure()/success()-implicit
#                       would skip the step on exactly the runs it exists for
#   single-config     — the state this channel's title, body and remedy describe
#   NO bare `!=`      — `token_drift` is matrix-gated, so on the other leg every output is
#                       '' and `'' != 'multi-config'` is TRUE; the step then fires from a
#                       leg that never scanned, with a blank body, and create-only locks
#                       it in. Positive polarity is what makes it skip-safe.
if grep -qF 'always()' <<<"$COV_IF" \
   && grep -qF "steps.token_drift.outputs.coverage == 'single-config'" <<<"$COV_IF" \
   && ! grep -qF 'coverage !=' <<<"$COV_IF"; then
  pass "an arm fires on coverage alone, positively, independent of verdict/outcome"
else
  fail "the coverage arm's if: is '${COV_IF}' — it must be always() AND test coverage POSITIVELY. A single-config scan yields verdict=clean, rc=0, outcome=success, so no email arm matches and enforce is skipped; and a negative test also matches the empty output published by the matrix leg where the detector never ran"
fi

echo "T13b: the coverage arm also covers 'unknown', which no email arm reaches"
if grep -qF "steps.token_drift.outputs.coverage == 'unknown'" <<<"$COV_IF"; then
  pass "an unmeasurable coverage still reaches the issue channel"
else
  fail "coverage=unknown has no channel. It is reachable with a CLEAN verdict (well-formed JSON that simply lacks 'configs'), and no email arm fires on clean — the verdict=='unavailable' email only covers the crash path"
fi

echo "T14: that arm is CREATE-ONLY (the condition holds on every run until fixed)"
COV_RUN=$(step_field "$COVERAGE_STEP" run) || COV_RUN=""
# Assert the CONTROL FLOW, not the log sentence. `create-only, not commenting` is an echo
# string: keeping it and deleting the `exit 0` beneath it left the suite green while the
# step filed a fresh duplicate every run. And the dedup query literal is no longer unique
# to this step — the DEAD filer contains it too (count went 1 -> 2 on this branch), so a
# file-wide grep for it says nothing about this step at all.
if grep -qF 'gh issue list --label "$LABEL" --state open' <<<"$COV_RUN" \
   && grep -qE '^ *exit 0$' <<<"$COV_RUN" \
   && ! grep -qF 'gh issue comment' <<<"$COV_RUN"; then
  pass "an existing open coverage issue short-circuits instead of re-commenting"
else
  fail "the coverage arm must query open issues, exit 0 on a hit, and never comment: coverage is single-config on EVERY scheduled run until the token scope is widened, so create-or-comment posts ~730 comments a year and trains the operator to filter the label"
fi

echo "T14b: a failed create is reported, not swallowed"
if grep -qF '::error::token_drift_coverage_escalation_failed' <<<"$COV_RUN" \
   && ! grep -qE 'gh issue create.*\| *tail' <<<"$COV_RUN"; then
  pass "gh issue create's status is branched on and a failure annotates"
else
  fail "a failed 'gh issue create' leaves a GREEN step on a GREEN cron run with no issue and no annotation. Coverage has no email arm, so that is total loss of the only channel this step exists to be (hr-no-dashboard-eyeball-pull-data-yourself)"
fi

echo "T14c: a failed dedup QUERY fails closed, rather than filing a duplicate"
if grep -qF 'token_drift_coverage_list_failed' <<<"$COV_RUN"; then
  pass "an errored 'gh issue list' declines to create instead of reading empty as 'none open'"
else
  fail "the dedup query's failure is indistinguishable from 'no issue open', and create-only reads empty as 'file one' — so every transient API fault adds a permanent duplicate"
fi

echo "T14d: the issue is closed automatically when coverage recovers"
CLOSE_IF=$(step_field "Close the coverage issue once the fan-out is restored" if) || CLOSE_IF=""
CLOSE_RUN=$(step_field "Close the coverage issue once the fan-out is restored" run) || CLOSE_RUN=""
if grep -qF "steps.token_drift.outputs.coverage == 'multi-config'" <<<"$CLOSE_IF" \
   && grep -qF 'gh issue close' <<<"$CLOSE_RUN"; then
  pass "coverage recovery closes the standing issue without an operator step"
else
  fail "nothing closes the coverage issue. Its stated closing condition is 'a scheduled run reports coverage: multi-config' — a fact observable only by opening a GREEN cron run's step log, which is the same problem the file arm exists to solve"
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

echo "T16b: an UNMEASURABLE coverage emits its own, differently-worded annotation"
# The `unknown` branch of the ::warning:: was unpinned while its sibling was pinned —
# measured: deleting the branch entirely, and widening the single-config branch's test to
# `!= "multi-config"` (which makes an unreadable verdict file announce "scanned -1 Doppler
# config(s)"), both left the suite green. That is T15's own defect one branch over.
run_step "$TMP/corrupt" 0 >/dev/null
if grep -q '::warning::.*could not measure its own coverage' "$STEP_STDOUT" \
   && ! grep -q '::warning::.*scanned -1 Doppler' "$STEP_STDOUT"; then
  pass "an unreadable verdict file says so, rather than reporting a narrow scan"
else
  fail "coverage=unknown did not emit its own annotation — a detector that could not run is being described to the operator as a narrow scan, whose remedy (widen the Doppler token) is unperformable on that path, so the state never clears"
fi

echo "T17: the coverage threshold is '< 2', not '== 1'"
mkdir -p "$TMP/zero"
printf '{"live":0,"dead":0,"unverifiable":0,"probes":0,"configs":0,"stale":[],"unverifiable_keys":[]}' > "$TMP/zero/token-drift.json"
c=$(out_val "$(run_step "$TMP/zero" 0)" coverage)
# NOTE ON REACHABILITY: configs=0 cannot arrive from today's detector — it exits 2 at
# `if [[ ${#CONFIGS[@]} -eq 0 ]]` roughly 460 lines before emit_json, so a real 0-config
# run publishes no verdict file at all and lands on the `-1` fallback, i.e. `unknown`
# (T5 covers that path). This case pins the THRESHOLD SHAPE as defence-in-depth against a
# future path that reaches emit_json with an empty CONFIGS; it is not evidence about a
# reachable production state, and the pass message said otherwise.
if [[ "$c" == "single-config" ]]; then
  pass "configs=0 -> single-config (pins '< 2'; not a reachable state today, see note)"
else
  fail "configs=0 derived '$c' — a threshold of '== 1' rather than '< 2' would let a future path that reaches emit_json with no configs report the confident state, which is the silent direction"
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
# The caveat is the same sentence, in the same medium, for the same reader, in two email
# bodies — and nothing pinned the copies to each other. A presence-only check stays green
# while one is reworded and the other is not, leaving the DEAD and UNVERIFIABLE emails
# disagreeing about what coverage means, in the one sentence whose entire job is to stop
# `clean` being over-read. Same two-copies-one-pin shape as the #7134 defect this suite
# exists for, so: assert the copies are byte-identical.
mapfile -t _CAVEATS < <(grep -oP '<em>Scan coverage:.*?</em>' "$WF" | sort -u)
if (( ${#_CAVEATS[@]} != 1 )); then
  _t19=0
  echo "    the coverage caveat has ${#_CAVEATS[@]} distinct wordings across the email bodies; expected exactly 1"
fi
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
#
# SET AT THE CURRENT COUNT, not below it. At 20 against 22 running there were two free
# slots — measured: deleting the T15 AND T16 blocks, i.e. the PR's only in-run
# deliverable, reported "20/20 passed" and exit 0. A floor with slack licenses the
# deletion of exactly the assertions under review. Raise it when adding a case; that edit
# is the point, because it is what makes a REMOVAL visible in the diff.
if [[ "$((PASS + FAIL))" -lt 28 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 28." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
