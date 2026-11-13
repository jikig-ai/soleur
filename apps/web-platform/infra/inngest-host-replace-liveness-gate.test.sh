#!/usr/bin/env bash
# Structural guard for the post-replace liveness gate (#12708) — the step that keeps
# "terraform apply succeeded" from being read as "the new host is alive".
#
# WHAT THIS PINS (each was a measured defect or review finding on this PR):
#   1. `set +e` — Actions runs a bare `run:` block as `bash -e {0}` (ADR-170). Without it the
#      FIRST rc=4 read (the expected state for the first minutes of every healthy replace)
#      kills the step at the read line; the poll loop is dead code. lint-workflow-errexit-
#      capture.py flags the bare form; this pins the fix in the body itself.
#   2. `--instance-id "$INNGEST_NEW_IID"` on the read — dropping it re-opens the #12695 shape:
#      the destroyed host's in-window rows mask the replacement's silence and the gate greens
#      on a dead host.
#   3. The 1200s deadline, the rc==0 -> exit 0 arm, `env -u` seam-stripping (INNGEST_STATE_QUERY
#      / INNGEST_PROBE_ROW_LIB / INNGEST_STATE_SINCE are reader overrides doppler run would
#      otherwise inject), and `timeout-minutes: 40` on the job (the poll's bound).
#   4. `verdict_reads` — a window of pure instrument faults must report UNMEASURED, not "the
#      host is not emitting" (a host verdict on an unmeasured state).
#
# METHOD: the step body is extracted from PARSED YAML by job+step name (a grep would pass on a
# commented-out line). One mutation arm deletes the --instance-id call shape in a sandbox copy
# and requires THIS suite to notice — a structural pin that cannot fail is vacuous.
#
# Run: bash apps/web-platform/infra/inngest-host-replace-liveness-gate.test.sh
# Presence under apps/web-platform/infra/ IS registration - derived and run by run-registered-suites.sh (#8736).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
JOB="inngest_host_replace"
STEP_NAME="Post-replace liveness gate — first probe row on the new iid (#12708)"

passes=0; fails=0
pass() { passes=$((passes+1)); printf 'PASS: %s\n' "$1"; }
fail() { fails=$((fails+1)); printf 'FAIL: %s\n' "$1" >&2; }

python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }
command -v terraform >/dev/null 2>&1 && : # not required

SANDBOX="$(mktemp -d "${TMPDIR}/inngest-liveness-gate.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# extract_gate <workflow> <outdir>: writes <outdir>/body.sh + <outdir>/meta (job timeout).
extract_gate() {
  local wf="$1" out="$2"
  python3 - "$wf" "$out" "$JOB" "$STEP_NAME" <<'PY'
import sys, yaml
wf, out, job, step_name = sys.argv[1:5]
doc = yaml.safe_load(open(wf))
j = doc["jobs"][job]
body = None
for st in j.get("steps", []):
    if st.get("name") == step_name:
        body = st.get("run")
        break
assert body is not None, f"step {step_name!r} not found in job {job!r}"
open(out + "/body.sh", "w").write(body)
open(out + "/meta", "w").write(f"timeout_minutes={j.get('timeout-minutes')}\n")
PY
}

extract_gate "$WF" "$SANDBOX" || { printf 'FAIL SETUP: gate step extraction failed\n' >&2; exit 1; }
BODY="$SANDBOX/body.sh"

# --- structural pins ---------------------------------------------------------
grep -qF 'set +e' "$BODY" \
  && pass "the poll runs under set +e (bash -e would kill the step on the first rc=4 read)" \
  || fail "set +e missing — errexit kills the gate at the first expected-nonzero read (ADR-170)"

grep -qF -- '--instance-id "$INNGEST_NEW_IID"' "$BODY" \
  && pass "the read is pinned to the NEW host's iid" \
  || fail "--instance-id \"\$INNGEST_NEW_IID\" missing — an unpinned read greens on the destroyed host's rows"

grep -qE 'SECONDS *\+ *1200' "$BODY" \
  && pass "the poll is deadline-bounded at 1200s" \
  || fail "the 1200s deadline is missing or drifted"

grep -qE 'last_rc.{0,4}-eq 0' "$BODY" \
  && pass "rc==0 reaches the pass arm" \
  || fail "no rc==0 pass arm — the gate can never green"

for seam in INNGEST_STATE_QUERY INNGEST_PROBE_ROW_LIB INNGEST_STATE_SINCE; do
  grep -qF -- "-u $seam" "$BODY" \
    && pass "env -u strips $seam (doppler injects every config key into the reader env)" \
    || fail "env -u $seam missing — the read path is overridable from the Doppler config"
done

grep -qF 'verdict_reads' "$BODY" \
  && pass "verdict_reads distinguishes an all-instrument-fault window from a dark host" \
  || fail "verdict_reads missing — an all-rc=6 window would be reported as host silence"

grep -qF 'UNMEASURED' "$BODY" \
  && pass "the instrument-fault terminal message says UNMEASURED, not a host verdict" \
  || fail "no UNMEASURED arm — an instrument fault reads as a dark host"

grep -qF 'timeout_minutes=40' "$SANDBOX/meta" \
  && pass "job timeout-minutes is 40 (holds the 20-min poll + apply)" \
  || fail "timeout-minutes drifted from 40 — meta: $(cat "$SANDBOX/meta")"

# --- mutation arm: the pins must be able to fail -----------------------------
WF_MUT="$SANDBOX/apply-web-platform-infra.yml"
cp "$WF" "$WF_MUT"
python3 - "$WF_MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = '--instance-id "$INNGEST_NEW_IID"'
assert needle in s, "mutation anchor missing — the workflow drifted; fix the test"
open(p, "w").write(s.replace(needle, '', 1))
PY
mkdir -p "$SANDBOX/mut"
extract_gate "$WF_MUT" "$SANDBOX/mut"
if grep -qF -- '--instance-id "$INNGEST_NEW_IID"' "$SANDBOX/mut/body.sh"; then
  fail "the --instance-id pin did not notice its own deletion — the assertion is vacuous"
else
  pass "deleting --instance-id is observable (the pin's assertion would fire)"
fi

printf '\nliveness-gate guard: %d pass / %d fail\n' "$passes" "$fails"
[ "$fails" -eq 0 ]
