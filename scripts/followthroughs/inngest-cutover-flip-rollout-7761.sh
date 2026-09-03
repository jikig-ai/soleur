#!/usr/bin/env bash
# #7761 — the seam-gate + injection-bound reached the dedicated inngest host, and the host is
# still in its safe terminal state afterwards.
#
# TRACKER: **#7761**. It stays OPEN until this reads PASS. scripts/sweep-followthroughs.sh lists
# `--state open`, so hosting a probe on a CLOSED issue is a permanent silent no-op — which is why
# the PR that ships this carries `Ref #7761` and NOT `Closes #7761`.
#
# WHY THIS PROBE IS A COMMITTED DELIVERABLE RATHER THAN AN IN-SESSION CHECK. Merging this fix
# changes NOTHING on the live host. Every on-host asset here is baked into the OCI bootstrap image
# and pulled by a digest literal in `user_data`, which is ForceNew on `hcloud_server.inngest` with
# no `ignore_changes` (ADR-100 addendum 2026-08-25 / #7674). So delivery is a tag -> image build ->
# digest bump -> HOST REPLACE of the fleet's sole scheduler. A production destroy-and-recreate
# whose verification cannot be re-run is an unauditable change, so the verification ships with it.
#
# WHAT IT VERIFIES — POSITIVELY, NEVER BY ABSENCE ALONE.
#
#   1. `INNGEST_CUTOVER_FLIP` still reads `rolled-back`. Read from Doppler, not from telemetry:
#      the flag is the FSM's own input and Doppler is its authority. This also works straight
#      through a Better Stack read-path outage, which was observed in maintenance (HTTP 503) while
#      this change was being built — an outage that says nothing about the host.
#
#   2. At least two `noop-rolled-back` markers carry timestamps AFTER the replace. Two, not one:
#      one marker proves the host booted and emitted once; two proves the 30-second timer is
#      actually CYCLING, which is the property that makes the flag a live control channel rather
#      than a value nobody is reading. A host with no inbound SSH has no other channel.
#
#   3. No flush ever ran after the replace. This is what "the flush latch is intact" means in an
#      observable form. The latch file lives on /mnt/data and this repo has no SSH path to read it
#      (hr-no-ssh-fallback-in-runbooks), and in the `rolled-back` terminal state the FSM never
#      consults it — so asserting the FILE would be asserting something unobservable. What the
#      latch EXISTS to guarantee is observable: that no second FLUSHALL happened. Any marker whose
#      reason names a flush-path transition after the boundary fails this probe loudly.
#
# THE BOUNDARY IS REQUIRED, AND ITS ABSENCE IS NOT A PASS. "After the replace" cannot be evaluated
# without knowing when the replace happened, and a window that reaches back past it would be
# satisfied by the OLD host's markers — the probe would then certify the rollout using evidence
# produced by the machine the rollout replaced. So the boundary is read from
# FLIP_ROLLOUT_AFTER, else from the committed `.after` sidecar written at dispatch time; with
# neither, the probe reports TRANSIENT and says that nothing was measured.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       flag is rolled-back, >=2 post-boundary noop-rolled-back markers, no flush.
#   1 = FAIL       a real regression: the flag moved off rolled-back, or a flush path ran.
#   2 = TRANSIENT  not delivered yet, boundary unknown, host silent, credentials unprovisioned,
#                  or any query/decode failure. Nothing was measured; this is never an all-clear.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${FLIP_ROLLOUT_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"
AFTER_FILE="${FLIP_ROLLOUT_AFTER_FILE:-$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.after}"

MARKER="SOLEUR_INNGEST_CUTOVER"
# Two identity fields, both required (#6616 — `host_name` telemetry has been observed lying: a web
# host self-labelled with the sed-rendered dedicated-host literal). `host` is Vector's auto-derived
# OS hostname, which a stale literal cannot forge. A PASS here closes #7761, so a row matching only
# `host_name` would close the tracker on evidence from the wrong machine.
FLIP_HOST="${FLIP_ROLLOUT_HOST:-soleur-inngest}"
FLIP_HOST_NAME="${FLIP_ROLLOUT_HOST_NAME:-soleur-inngest-prd}"
WINDOW="${FLIP_ROLLOUT_WINDOW:-24h}"
LIMIT="${FLIP_ROLLOUT_LIMIT:-1000}"
DOPPLER_PROJECT_NAME="${FLIP_ROLLOUT_DOPPLER_PROJECT:-soleur-inngest}"
DOPPLER_CONFIG_NAME="${FLIP_ROLLOUT_DOPPLER_CONFIG:-prd}"
EXPECTED_FLAG="${FLIP_ROLLOUT_EXPECTED_FLAG:-rolled-back}"
MIN_MARKERS="${FLIP_ROLLOUT_MIN_MARKERS:-2}"

# --- the boundary -----------------------------------------------------------------------------
AFTER="${FLIP_ROLLOUT_AFTER:-}"
if [[ -z "$AFTER" && -r "$AFTER_FILE" ]]; then
  AFTER="$(tr -d '[:space:]' < "$AFTER_FILE" 2>/dev/null || true)"
fi
if [[ -z "$AFTER" ]]; then
  echo "TRANSIENT: reason=boundary_unknown — no replace timestamp supplied." >&2
  echo "           Phase 8 (tag -> image build -> digest bump -> apply_target=inngest-host) has" >&2
  echo "           not recorded a replace time, so 'after the replace' cannot be evaluated and" >&2
  echo "           NOTHING about the rollout was measured. This is not 'the rollout failed'." >&2
  echo "           Next: write the apply's completion time (ISO-8601 UTC, e.g." >&2
  echo "           2026-09-03T12:00:00Z) to ${AFTER_FILE}, or set FLIP_ROLLOUT_AFTER." >&2
  exit 2
fi
if ! [[ "$AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "TRANSIENT: reason=boundary_unparseable value='${AFTER}' — expected ISO-8601 UTC" >&2
  echo "           (YYYY-MM-DDTHH:MM:SSZ). A boundary that cannot be parsed must not be" >&2
  echo "           silently widened to 'any time', which would let pre-replace markers pass." >&2
  exit 2
fi

# --- 1. the flag, CORROBORATED from Doppler when a credential happens to be present ------------
#
# NOT a hard requirement, and that is a deliberate correction made while writing this probe. The
# sweeper (scheduled-followthrough-sweeper.yml) exposes BETTERSTACK_QUERY_* and several other
# secrets but NO Doppler token, so a probe that REQUIRED a Doppler read would return
# `flag_unreadable` on every single sweep for the life of the issue — a permanent silent no-op,
# which is precisely the failure mode the sibling #7674 probe was written to retire.
#
# The flag is available on the channel the sweeper DOES have: emit_state stamps the FSM flag into
# every marker it emits, so the host's own observation of its flag rides the marker stream. That
# reading is used as the primary source below. A Doppler read, when a credential is present, is
# strictly better evidence for one narrow case — the flag having been changed in Doppler but not
# yet observed by the host — so it is used to FAIL FAST when available and skipped otherwise.
# Neither path can fail open: with no marker rows at all the probe reports channel_dark.
doppler_flag=""
if command -v doppler >/dev/null 2>&1; then
  doppler_flag="$(doppler secrets get INNGEST_CUTOVER_FLIP \
                    -p "$DOPPLER_PROJECT_NAME" -c "$DOPPLER_CONFIG_NAME" --plain 2>/dev/null || true)"
  doppler_flag="$(printf '%s' "$doppler_flag" | tr -d '[:space:]')"
fi
if [[ -n "$doppler_flag" && "$doppler_flag" != "$EXPECTED_FLAG" ]]; then
  echo "FAIL: the FSM flag in ${DOPPLER_PROJECT_NAME}/${DOPPLER_CONFIG_NAME} reads" >&2
  echo "      '${doppler_flag}', expected '${EXPECTED_FLAG}'." >&2
  echo "      The host was braked and serving nothing before this rollout; a flag that has moved" >&2
  echo "      means either someone armed a cutover or the replace resumed a transient. Do NOT" >&2
  echo "      re-dispatch the apply until this is explained — the armed path ends in FLUSHALL." >&2
  exit 1
fi

# --- credentials for the marker read ----------------------------------------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — missing:${missing}." >&2
  echo "           The flag read above passed, but the liveness half was never asked. That is" >&2
  echo "           NOT a PASS: a correct flag on a host that stopped polling is exactly the" >&2
  echo "           twelve-day false-'done' shape ADR-100 records (#7228)." >&2
  exit 2
fi

# --- 2 + 3. the marker stream -----------------------------------------------------------------
rows="$("$QUERY" --since "$WINDOW" --grep "$MARKER" --limit "$LIMIT" 2>/dev/null)"
qrc=$?
if [[ "$qrc" -ne 0 ]]; then
  echo "TRANSIENT: reason=query_failed rc=${qrc} — the ClickHouse read path did not answer." >&2
  echo "           Nothing about the host's liveness was measured. Observed 2026-09-03: this" >&2
  echo "           source answers 503 'under maintenance', which is a read-path outage and says" >&2
  echo "           nothing about the host." >&2
  exit 2
fi

# Decode, then field-isolate on the DECODED object. `-R` plus `fromjson?` at BOTH levels is
# load-bearing rather than defensive habit: without `-R`, ONE malformed line aborts the whole jq
# invocation and every valid row after it is lost — which would surface as reason=channel_dark
# ("the host emits nothing") on a window that in fact contained a clean PASS.
mine="$(printf '%s\n' "$rows" \
  | jq -R -r --arg h "$FLIP_HOST" --arg hn "$FLIP_HOST_NAME" \
       'fromjson? | .raw? | fromjson?
        | select(.host == $h and .host_name == $hn)
        | .message? // empty' 2>/dev/null)"

if [[ -z "$mine" ]]; then
  echo "TRANSIENT: reason=channel_dark host=${FLIP_HOST}/${FLIP_HOST_NAME} window=${WINDOW} — zero rows." >&2
  echo "           The host is not reporting, so its FSM state is UNKNOWN — not 'healthy'. Check" >&2
  echo "           inngest-cutover-flip.timer and the Vector shipper before reading this as" >&2
  echo "           progress. If the apply has just run, the host may still be booting." >&2
  exit 2
fi

# The flip script's markers are emit_state's JSON, carrying `reason` and `start_ts`. Select on the
# DECODED message so the boundary is compared against the script's own UTC stamp rather than
# against an ingestion time, which can lag a boot by minutes.
post_boundary_rolled_back="$(printf '%s\n' "$mine" \
  | jq -R -r --arg after "$AFTER" \
       'fromjson? | select(.reason == "noop-rolled-back" and .start_ts > $after) | .start_ts' 2>/dev/null \
  | grep -c . || true)"
case "$post_boundary_rolled_back" in ''|*[!0-9]*) post_boundary_rolled_back=0 ;; esac

# ANY post-boundary flag other than the expected terminal one is a hard FAIL — not merely the three
# flush-path states. Enumerating only {flipping, flushed, done} would let `armed` through, and
# `armed` is the state whose very next poll STOPS the server and runs FLUSHALL: the probe would
# report PASS on the last quiet moment before the destructive arm. The flush-path states are still
# named separately because they mean the flush has ALREADY happened, which is a different
# operator response from "a cutover is queued".
drift="$(printf '%s\n' "$mine" \
  | jq -R -r --arg after "$AFTER" --arg want "$EXPECTED_FLAG" \
       'fromjson? | select(.start_ts > $after) | select(.flag != $want)
        | "flag=\(.flag) reason=\(.reason) at=\(.start_ts)"' 2>/dev/null)"
if [[ -n "$drift" ]]; then
  if printf '%s\n' "$drift" | grep -qE 'flag=(flipping|flushed|done)'; then
    echo "FAIL: a flush-path transition ran after the replace — the latch guarantee is broken." >&2
    printf '%s\n' "$drift" | sed 's/^/      /' >&2
    echo "      The host was braked; nothing should have moved off '${EXPECTED_FLAG}'. Treat the" >&2
    echo "      Redis contents as suspect and do not re-dispatch." >&2
  else
    echo "FAIL: the FSM flag moved off '${EXPECTED_FLAG}' after the replace." >&2
    printf '%s\n' "$drift" | sed 's/^/      /' >&2
    echo "      If this reads flag=armed, a cutover is QUEUED and the next 30s poll stops the" >&2
    echo "      server and runs FLUSHALL. Establish who armed it before doing anything else." >&2
  fi
  exit 1
fi

if [[ "$post_boundary_rolled_back" -ge "$MIN_MARKERS" ]]; then
  corroboration="doppler read skipped (no credential in this environment)"
  [[ -n "$doppler_flag" ]] && corroboration="doppler corroborates: ${doppler_flag}"
  echo "PASS: #7761 delivered. ${post_boundary_rolled_back} '${EXPECTED_FLAG}' marker(s) after"
  echo "      ${AFTER} (>= ${MIN_MARKERS}, so the 30s timer is cycling rather than having booted"
  echo "      once); no flag drift after the boundary; ${corroboration}."
  exit 0
fi

echo "TRANSIENT: reason=insufficient_post_replace_markers count=${post_boundary_rolled_back}" >&2
echo "           want>=${MIN_MARKERS} after ${AFTER} (window ${WINDOW})." >&2
echo "           The flag is correct and nothing flushed, but the host has not yet been observed" >&2
echo "           POLLING since the replace. At a 30-second cadence this resolves within minutes;" >&2
echo "           if it does not, the unit is failing to start — check for a mount-namespace" >&2
echo "           failure from the new ReadWritePaths/StateDirectory directives, which would kill" >&2
echo "           the unit on every fire and emit nothing at all." >&2
exit 2
