#!/usr/bin/env bash
# dispatch-web-redeploy/track.sh — Guard 7 (#7226 / #5914, ADR-237, plan D6).
#
# After a git-data birth or replace publishes a new GIT_DATA_SSH_HOST_KEY to Doppler prd,
# the running web app still holds the OLD pin until a release redeploys it (ci-deploy.sh
# re-downloads prd at deploy time). This script forces that redeploy and succeeds ONLY if
# some web-platform-release run NEWER than the pre-dispatch baseline has a `deploy` job
# that concluded `success`. It is the single decision point; the composite action around
# it only prints the pin fingerprint.
#
#   1. Baseline: the databaseId of the latest web-platform-release.yml run (any event).
#      databaseId is monotonic per repository, so "strictly greater" identifies a newer
#      run with no clock comparison. An unreadable or non-numeric baseline fails CLOSED,
#      BEFORE dispatching: a 0 would make every historical run "newer".
#   2. Dispatch: `gh workflow run web-platform-release.yml --ref main -f bump_type=patch`.
#      A dispatched release is forced past reusable-release.yml's check_changed ("Release
#      forced (workflow_dispatch or force_run)"), so it deploys with no app change. The
#      workflow has no release-note input; the pin-rotation context lives in this job's
#      summary instead.
#   3. Poll ANY-event runs with databaseId > baseline. `gh workflow run` returns no run id
#      and exits 0 on mere acceptance, so we never try to identify "our" run: a push-
#      triggered release that deploys after the pin was published loads it just as well.
#      Qualifies: the job named exactly `deploy` concluded `success`. `skipped`,
#      `cancelled`, `failure`, a missing or renamed job, or an ambiguous (duplicate) name
#      never qualify. A cancelled dispatched run is tolerated when a later run qualifies.
#   4. Timeout: ::error:: naming the baseline databaseId and the last one seen.
#
# Env (interval/timeout are env so the test suite runs in seconds):
#   REDEPLOY_POLL_INTERVAL_S  seconds between polls (default 30)
#   REDEPLOY_TIMEOUT_S        give-up bound in seconds (default 4200 = 70 min, inside the
#                             job's 75-minute timeout-minutes so the named error, not a
#                             runner kill, is what the operator sees)
#   GH_TOKEN / GH_REPO        consumed by gh itself (actions: write to dispatch).
#
# Recovery on failure: RE-RUN THIS JOB. Do not replace git-data again; the pin is already
# published, only its load into the app is missing.
set -euo pipefail

WORKFLOW="web-platform-release.yml"
DEPLOY_JOB="deploy"
INTERVAL="${REDEPLOY_POLL_INTERVAL_S:-30}"
TIMEOUT="${REDEPLOY_TIMEOUT_S:-4200}"

_summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY" || true; }

for v in INTERVAL TIMEOUT; do
  if [[ ! "${!v}" =~ ^[0-9]+$ ]] || (( ${!v} < 1 )); then
    echo "::error::dispatch-web-redeploy: ${v} must be a positive integer (got '${!v}')."
    exit 2
  fi
done

# --- 1. Baseline (fail closed) -------------------------------------------------------
baseline=""
if raw="$(gh run list --workflow "$WORKFLOW" --limit 1 --json databaseId 2>/dev/null)"; then
  baseline="$(jq -r 'if type == "array" and length > 0 then (.[0].databaseId | tostring) else "" end' \
                <<<"$raw" 2>/dev/null || true)"
fi
if [[ ! "$baseline" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::dispatch-web-redeploy: could not read the pre-dispatch baseline databaseId of ${WORKFLOW} (got '${baseline}'). Refusing to dispatch: without a baseline the poll cannot tell a new deploy from an old one, and the app would be reported as carrying the new git-data host-key pin when it may not."
  exit 1
fi
echo "baseline databaseId=${baseline} (${WORKFLOW})"

# --- 2. Dispatch ---------------------------------------------------------------------
if ! gh workflow run "$WORKFLOW" --ref main -f bump_type=patch; then
  echo "::error::dispatch-web-redeploy: 'gh workflow run ${WORKFLOW}' was rejected. The new git-data host-key pin is published to Doppler prd but NOT loaded by the app. Re-run this job."
  exit 1
fi
echo "dispatched ${WORKFLOW} (ref main, bump_type=patch): pin rotation, no code change"

# --- 3. Poll -------------------------------------------------------------------------
start=$SECONDS
last_seen="$baseline"
declare -A FINAL=()   # run id -> terminal non-success deploy conclusion (no re-query)

while :; do
  ids=""
  if raw="$(gh run list --workflow "$WORKFLOW" --limit 50 --json databaseId,status,conclusion,event 2>/dev/null)"; then
    ids="$(jq -r --argjson b "$baseline" \
             '[.[]? | select((.databaseId | type) == "number" and .databaseId > $b) | .databaseId] | sort | .[]' \
             <<<"$raw" 2>/dev/null || true)"
  else
    echo "::warning::dispatch-web-redeploy: 'gh run list' failed this tick; retrying."
  fi

  for id in $ids; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    (( id > last_seen )) && last_seen="$id"
    [[ -n "${FINAL[$id]:-}" ]] && continue
    jobs="$(gh run view "$id" --json jobs 2>/dev/null)" || continue
    concl="$(jq -r --arg n "$DEPLOY_JOB" \
               '[.jobs[]? | select(.name == $n)] | if length == 1 then (.[0].conclusion // "") else "" end' \
               <<<"$jobs" 2>/dev/null)" || continue
    case "$concl" in
      success)
        echo "run databaseId=${id} (> baseline ${baseline}): job '${DEPLOY_JOB}' concluded success. The app now loads the published git-data host-key pin."
        _summary "- Redeploy confirmed: web-platform-release run \`${id}\` (baseline \`${baseline}\`) deployed successfully."
        exit 0
        ;;
      skipped|cancelled|failure|timed_out|action_required|neutral|stale|startup_failure)
        FINAL[$id]="$concl"
        echo "run databaseId=${id}: job '${DEPLOY_JOB}' concluded ${concl}; does not count, still waiting for a later run."
        ;;
      *) ;;   # in progress, or no uniquely-named deploy job yet
    esac
  done

  if (( SECONDS - start >= TIMEOUT )); then
    echo "::error::dispatch-web-redeploy: no ${WORKFLOW} run newer than baseline databaseId=${baseline} had a '${DEPLOY_JOB}' job conclude success within ${TIMEOUT}s (last seen databaseId=${last_seen}). The new git-data host-key pin is in Doppler prd but the app is still running with the OLD pin, so git-data SSH from the app will fail host-key verification. Recovery: re-run this job (do NOT replace git-data again)."
    _summary "- Redeploy NOT confirmed within ${TIMEOUT}s: baseline \`${baseline}\`, last seen \`${last_seen}\`. Re-run this job."
    exit 1
  fi
  sleep "$INTERVAL"
done
