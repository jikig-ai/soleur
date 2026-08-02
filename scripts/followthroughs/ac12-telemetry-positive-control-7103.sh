#!/usr/bin/env bash
# Follow-through verification for #7103 R3 — the AC12 telemetry re-verification soak.
#
# WHY THIS EXISTS AS A SOAK RATHER THAN A PRE-MERGE AC.
#
# AC12 asserts zero `Doppler Error: Invalid Auth token` events on web-1. Its measurement path
# runs physically through vector.service — the component R2 repairs. Verifying it before that
# repair has landed AND applied would re-record the exact reading that made it unverifiable in
# the first place: "zero rows" that is indistinguishable from "the channel is not shipping".
# So it is a post-apply follow-through, not a pre-merge gate.
#
# Three guards, each closing a way this probe could PASS while proving nothing:
#
#   1. ELAPSED-TIME SELF-GUARD. Reads start_ts from /hooks/infra-config-status and refuses to
#      grade until at least 1h has passed since the apply. A wrong `earliest=` in the directive
#      would otherwise let this run on merge day and pass against a window that predates the
#      fix. iso_to_epoch returns 0 on anything date -u -d rejects, so a placeholder earliest
#      silently disables the soak gate — this guard is what makes that non-fatal.
#
#   2. SUBJECT-MUST-HAVE-RUN. Requires at least 3 SOLEUR_DEPLOY_INVOCATION rows in the window.
#      The events AC12 looks for are ci-deploy-correlated, so a window with no deploys makes the
#      absence half trivially true — while the canary, emitted by an independent 60s timer,
#      satisfies the control. That combination yields clean -> PASS -> issue closed, with both
#      #7103 hypotheses still ungraded. This is the vacuity the whole plan exists to refuse.
#
#   3. A DARK CHANNEL IS A FAILURE. betterstack-assert-absence.sh exits 2 (unshipping) and 3
#      (unknown); both map to 1 (FAIL) here. The sweeper comments TRANSIENT on any exit other
#      than 0/1 and never escalates, so exits 2/3 would accrete daily comments forever while
#      the channel stayed dark. Transient is reserved for things that genuinely retry.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (absence confirmed against a provably live channel; sweeper closes the issue)
#   1 = FAIL       (events present, OR the channel is dark/unanswerable, OR the subject never ran)
#   * = TRANSIENT  (this script's own prerequisites missing; retry next sweep)
#
# Required env (LITERAL names — the sweeper matches by exact variable name, not glob; all three
# already exist in scheduled-followthrough-sweeper.yml):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSERT="$REPO_ROOT/scripts/betterstack-assert-absence.sh"

HOST="${AC12_HOST:-soleur-web-platform}"
WINDOW="${AC12_WINDOW:-6h}"
STATUS_URL="${AC12_STATUS_URL:-https://deploy.soleur.ai/hooks/infra-config-status}"
MIN_ELAPSED_SECS=3600
MIN_DEPLOY_ROWS=3

[[ -x "$ASSERT" ]] || { echo "TRANSIENT: $ASSERT not executable"; exit 2; }
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  [[ -n "${!v:-}" ]] || { echo "TRANSIENT: $v is not injected (wire it in scheduled-followthrough-sweeper.yml)"; exit 2; }
done

# --- Guard 1: has the apply actually settled? ---------------------------------------------
# A read failure here is TRANSIENT, not a pass: not knowing when the apply happened is not
# evidence that enough time has elapsed.
status_body="$(curl -sS --max-time 20 "$STATUS_URL" 2>&1)" || {
  echo "TRANSIENT: could not read $STATUS_URL"
  printf '%s\n' "$status_body" | head -c 300
  exit 2
}
start_ts="$(printf '%s' "$status_body" | jq -r '.start_ts // empty' 2>/dev/null)"
if ! [[ "$start_ts" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: no numeric start_ts in the infra-config status payload"
  printf '%s\n' "$status_body" | head -c 300
  exit 2
fi
now="$(date +%s)"
elapsed=$(( now - start_ts ))
if [[ "$elapsed" -lt "$MIN_ELAPSED_SECS" ]]; then
  echo "FAIL: only ${elapsed}s since the last infra-config apply (need >= ${MIN_ELAPSED_SECS}s). Refusing to grade AC12 against a window that overlaps the apply — a day-0 pass here would certify the fix using data from before it landed."
  exit 1
fi

# --- Guard 2: did the subject run at all? -------------------------------------------------
# SOLEUR_DEPLOY_INVOCATION is R1's per-invocation self-report. Its presence is what makes the
# absence assertion non-vacuous: without deploys there are no ci-deploy-correlated events to be
# absent, and "zero" would mean "nothing happened", not "nothing broke".
deploy_rows_rc=0
deploy_out="$(bash "$ASSERT" --host "$HOST" --absence 'SOLEUR_DEPLOY_INVOCATION' --since "$WINDOW" 2>&1)" || deploy_rows_rc=$?
case "$deploy_rows_rc" in
  1) : ;;  # `present` — deploys DID run, which is what we want here
  2) echo "FAIL: the telemetry channel for $HOST is not shipping (unshipping). An absence assertion cannot be graded through a dark channel."
     printf '%s\n' "$deploy_out" | head -5
     exit 1 ;;
  3) echo "FAIL: the telemetry query did not answer (unknown). Not treating an unanswered query as an absence."
     printf '%s\n' "$deploy_out" | head -5
     exit 1 ;;
  0) echo "FAIL: ZERO SOLEUR_DEPLOY_INVOCATION rows for $HOST in $WINDOW. The subject never ran, so the AC12 absence below would be trivially true. Waiting for real deploys rather than certifying on an empty window."
     exit 1 ;;
  *) echo "TRANSIENT: unexpected exit $deploy_rows_rc from the absence helper"; exit 2 ;;
esac
deploy_rows="$(printf '%s' "$deploy_out" | sed -n 's/.*absence_rows=\([0-9]*\).*/\1/p' | head -1)"
if ! [[ "$deploy_rows" =~ ^[0-9]+$ ]] || [[ "$deploy_rows" -lt "$MIN_DEPLOY_ROWS" ]]; then
  echo "FAIL: only ${deploy_rows:-?} SOLEUR_DEPLOY_INVOCATION row(s) in $WINDOW; AC12 is stated across the next ${MIN_DEPLOY_ROWS} ci-deploy invocations. Not enough of the subject has run to grade it."
  exit 1
fi

# --- The assertion itself ------------------------------------------------------------------
rc=0
out="$(bash "$ASSERT" --host "$HOST" \
        --absence 'Doppler Error: Invalid Auth token' \
        --since "$WINDOW" 2>&1)" || rc=$?
printf '%s\n' "$out"
case "$rc" in
  0) echo "PASS: zero 'Doppler Error: Invalid Auth token' events for $HOST across ${deploy_rows} ci-deploy invocation(s) in $WINDOW, with the Source-4 positive control confirmed live at the sink. AC12 re-verified."
     exit 0 ;;
  1) echo "FAIL: 'Doppler Error: Invalid Auth token' events are still present for $HOST — the credential channel has regressed."
     exit 1 ;;
  2) echo "FAIL: positive control returned zero rows — the channel is dark, so absence proves nothing."
     exit 1 ;;
  3) echo "FAIL: the query did not answer; refusing to report an unanswered query as an absence."
     exit 1 ;;
  *) echo "TRANSIENT: unexpected exit $rc from the absence helper"; exit 2 ;;
esac
