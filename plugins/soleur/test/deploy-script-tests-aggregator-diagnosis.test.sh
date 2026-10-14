#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard for #8736/#8735 — the `deploy-script-tests-done` aggregator names the
# MEASURED cause.
#
# WHAT THIS EXISTS TO CATCH. The aggregator is the single verdict
# notify-main-failure reads. Its classifier must discriminate the two shapes
# that render identically (`cancelled`): a leg killed by its own
# `timeout-minutes` (sibling concluded) and a superseded run (whole run
# cancelled, pull_request-only). This harness is the sibling of
# ci-test-aggregator-diagnosis.test.sh — same contract, different step.
#
# WHY THE BODY IS EXECUTED, NOT GREPPED. A grep over the workflow source cannot
# tell "the classifier emits this line" from "the classifier never looked" —
# both are the same bytes on disk. So this harness EXTRACTS the step's `run:`
# body and EXECUTES it under the shell GitHub Actions actually uses:
#     bash --noprofile --norc -eo pipefail {0}
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
WF="$REPO_ROOT/.github/workflows/infra-validation.yml"
STEP_NAME="Aggregate deploy-script-tests results"

[ -f "$WF" ] || { printf 'FAIL: %s not found\n' "$WF" >&2; exit 2; }

SANDBOX=$(mktemp -d -t dst-aggr-diag.XXXXXXXX) || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to extract the step body\n' >&2; exit 2; }

echo "=== Guard: deploy-script-tests-done names the measured cause (#8736/#8735) ==="

# ── Extraction ───────────────────────────────────────────────────────────────
BODY="$SANDBOX/body.aggregate"
extract_body() {
  python3 - "$1" "$2" "$STEP_NAME" <<'PY'
import sys, yaml
wf, dst, want = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(wf))
found = []
for jname, job in (doc.get("jobs") or {}).items():
    for step in (job.get("steps") or []):
        if step.get("name") == want and "run" in step:
            found.append((jname, step["run"]))
if len(found) != 1:
    sys.stderr.write("expected exactly 1 step named %r, found %d\n" % (want, len(found)))
    sys.exit(3)
open(dst, "w").write(found[0][1])
PY
}

if ! extract_body "$WF" "$BODY" 2>"$SANDBOX/extract.err"; then
  printf 'FAIL: could not extract the %s step body: %s\n' \
    "$STEP_NAME" "$(cat "$SANDBOX/extract.err")" >&2
  exit 2
fi
[ -s "$BODY" ] || { printf 'FAIL: extracted body is empty\n' >&2; exit 2; }
cp "$BODY" "$SANDBOX/body.pristine"

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — this row proves fail() increments)"
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test — pass()/fail() did not both move\n' >&2
  exit 2
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# ── Execution harness ────────────────────────────────────────────────────────
run_body() {  # $1=body $2=matrix $3=fixed $4=event ; sets OUT/RC
  OUT="$SANDBOX/out.$RANDOM.$RANDOM"
  ( MATRIX_RESULT="$2" FIXED_RESULT="$3" EVENT_NAME="$4" \
      bash --noprofile --norc -eo pipefail "$1" ) >"$OUT" 2>&1
  RC=$?
}

expect_line() {  # $1=label $2=body $3=matrix $4=fixed $5=event $6=needle $7=want_rc
  local label="$1" body="$2" m="$3" f="$4" ev="$5" needle="$6" want_rc="$7"
  run_body "$body" "$m" "$f" "$ev"
  local ok=1
  grep -qF -- "$needle" "$OUT" || ok=0
  [ "$RC" -eq "$want_rc" ] || ok=0
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — pair=($m,$f) event=$ev: expected a line containing '$needle' and rc=$want_rc; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}

# ── CONTROL ──────────────────────────────────────────────────────────────────
_c0=$fails
expect_line "CONTROL all-green" "$BODY" success success push \
  "all succeeded" 0
if [ "$fails" -ne "$_c0" ]; then
  printf '\nCONTROL ROW FAILED — the battery is VOID, not failing.\n' >&2
  exit 1
fi

# ── Classification rows ──────────────────────────────────────────────────────
# A failing leg names itself.
expect_line "R1 matrix failure" "$BODY" failure success push \
  "deploy-script-tests: FAILED" 1
expect_line "R2 fixed failure" "$BODY" success failure push \
  "deploy-script-tests-fixed: FAILED" 1
# The cancelled discrimination — the #8735 payload.
expect_line "R3 superseded on pull_request" "$BODY" cancelled cancelled pull_request \
  "SUPERSEDED" 1
expect_line "R4 all-cancelled on push is NOT supersession" "$BODY" cancelled cancelled push \
  "supersession cannot occur" 1
expect_line "R5 leg-timeout shape: cancelled beside concluded sibling" \
  "$BODY" cancelled success push \
  "its own declared timeout-minutes" 1
expect_line "R6 skipped" "$BODY" skipped success push \
  "SKIPPED" 1
expect_line "R7 unclassified result" "$BODY" potato success push \
  "UNCLASSIFIED" 1

# ── W: the env→needs wiring feeds the RIGHT results ──────────────────────────
# The classifier reads MATRIX_RESULT/FIXED_RESULT — but the wiring lives in the
# step's env: block, which the body extraction strips. Assert the mapping here
# or a crossed wire (matrix env fed by -fixed's result) executes a perfect
# classifier on swapped verdicts.
WF_ENV="$(python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
job = (doc.get("jobs") or {}).get("deploy-script-tests-done") or {}
for step in (job.get("steps") or []):
    if step.get("name") == "Aggregate deploy-script-tests results":
        for k, v in (step.get("env") or {}).items():
            print("%s=%s" % (k, v))
PY
)"
if grep -qE 'MATRIX_RESULT=\$\{\{[[:space:]]*needs\.deploy-script-tests\.result' <<<"$WF_ENV" \
   && grep -qE 'FIXED_RESULT=\$\{\{[[:space:]]*needs\.deploy-script-tests-fixed\.result' <<<"$WF_ENV" \
   && ! grep -qE 'MATRIX_RESULT=.*-fixed' <<<"$WF_ENV"; then
  pass
else
  fail "W env wiring: MATRIX_RESULT/FIXED_RESULT do not map to their own needs.*.result — got: $(tr '\n' '|' <<<"$WF_ENV")"
fi

# ── Mutants — the arms must actually discriminate ────────────────────────────
# M1: drop the cancelled arm — the timeout/superseded discrimination dies.
sed '/cancelled)$/,/;;$/d' "$BODY" > "$SANDBOX/body.nocancelled"
if cmp -s "$BODY" "$SANDBOX/body.nocancelled"; then
  fail "M1 setup: cancelled-arm sed produced an identical body (drifted)"
else
  expect_line "M1 cancelled arm deleted" "$SANDBOX/body.nocancelled" \
    cancelled success push "UNCLASSIFIED" 1
fi

# M2: drop the pull_request check — a push cancelled pair would claim
# SUPERSEDED, which cannot happen on push.
sed 's/if \[\[ "\$EVENT_NAME" == "pull_request" \]\]; then/if [[ "push" == "pull_request" ]]; then/' \
  "$BODY" > "$SANDBOX/body.nosupersede"
if cmp -s "$BODY" "$SANDBOX/body.nosupersede"; then
  fail "M2 setup: event-guard sed produced an identical body (drifted)"
else
  expect_line "M2 supersession arm unreachable on pull_request" \
    "$SANDBOX/body.nosupersede" cancelled cancelled pull_request \
    "CANCELLED — the whole run was cancelled on a 'pull_request' event" 1
fi

echo ""
# Anti-vacuity floor — a dispatch layer that stops emitting keeps printing
# 0 failed while certifying nothing. Exits DIRECTLY: a floor that routes
# through the counters it guards exits 0 when the counters are neutered
# (guard-vacuity-floor measured exactly this on this file's first shape).
MIN_ASSERTS=10
if (( passes + fails < MIN_ASSERTS )); then
  printf 'FAIL: assertion floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$((passes + fails))" "$MIN_ASSERTS" >&2
  exit 1
fi
echo "=== deploy-script-tests-done aggregator: $passes passed, $fails failed ==="
(( fails == 0 ))
