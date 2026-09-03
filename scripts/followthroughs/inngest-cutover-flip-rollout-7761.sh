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
#   1. The NEW script is actually on the host. Every other observable here — the flag value, the
#      noop markers, the absence of flush transitions — is emitted BYTE-IDENTICALLY by the pre-fix
#      script, so without this the probe would report "delivered" for a replace that silently kept
#      the old image (a digest that never moved, a flip-asset copy that fell through its `|| true`
#      guard). emit_state stamps `guard:<GUARD_REV>`; only the post-#7761 script emits it.
#
#   2. At least two `noop-rolled-back` markers carry timestamps AFTER the replace. Two, not one:
#      one marker proves the host booted and emitted once; two proves the 30-second timer is
#      actually CYCLING, which is the property that makes the flag a live control channel rather
#      than a value nobody is reading. A host with no inbound SSH has no other channel.
#
#   3. No flag drift after the replace. This is what "the flush latch is intact" means in an
#      observable form: the latch file lives on /mnt/data and this repo has no SSH path to read it
#      (hr-no-ssh-fallback-in-runbooks), and in the `rolled-back` terminal state the FSM never
#      consults it. What the latch EXISTS to guarantee is observable — that nothing moved off the
#      terminal state. ANY other post-boundary flag fails, not just the three flush-path ones:
#      `armed` is the state whose NEXT poll stops the server and runs the FLUSHALL, so accepting it
#      would report all-clear on the last quiet moment before the destructive arm.
#
#   4. No seam refusal. A `SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED` marker on the live host means a
#      name in the soleur-inngest/prd Doppler config collided with a fixture seam — the #7761
#      condition itself, occurring. Queried separately because it is a raw string, not emit_state
#      JSON, so the JSON selector below discards it by construction.
#
# WHY THE MARKER GREP IS THE TAG AND NOT A `SOLEUR_` STRING. An earlier revision grepped
# `SOLEUR_INNGEST_CUTOVER`, which compiles to `raw LIKE '%SOLEUR_INNGEST_CUTOVER%'`. emit_state's
# rows are BARE JSON — the identity lives in the syslog tag, not the payload — so that grep matched
# only the four exceptional-path markers, all of which `fromjson?` then discarded. The probe could
# never return PASS and its flush assertion could never return FAIL: a permanent silent no-op, the
# exact failure its own header claims to retire. `SYSLOG_IDENTIFIER` IS present in `raw` (proved by
# betterstack-query.sh's `--raw-only` mode having to exclude it), so the tag is the correct grep.
#
# THE BOUNDARY IS REQUIRED, AND ITS ABSENCE IS NOT A PASS. "After the replace" cannot be evaluated
# without knowing when the replace happened, and a window reaching back past it would be satisfied
# by the OLD host's markers — the probe would certify the rollout using evidence produced by the
# machine the rollout replaced. Read from FLIP_ROLLOUT_AFTER, else the committed `.after` sidecar.
# With neither, TRANSIENT. But a boundary that is OLD with still no markers is a FAIL, not a
# TRANSIENT: at a 30-second cadence "not yet" expires in minutes, and leaving it TRANSIENT forever
# makes a permanently bricked scheduler indistinguishable from a rollout nobody has run.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       new script on host, >=2 post-boundary rolled-back markers, no drift, no refusal.
#   1 = FAIL       a real regression: flag moved, a flush ran, a seam was refused, or the host has
#                  been silent well past the boundary.
#   2 = TRANSIENT  not delivered yet, boundary unknown, credentials unprovisioned, or any
#                  query/decode failure. Nothing was measured; this is never an all-clear.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${FLIP_ROLLOUT_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"
AFTER_FILE="${FLIP_ROLLOUT_AFTER_FILE:-$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.after}"
# Seamed like QUERY so the Doppler arm is drivable by the suite. Without this the corroboration
# branch is unreachable by design and its FAIL arm has no coverage.
DOPPLER_BIN="${FLIP_ROLLOUT_DOPPLER_BIN:-doppler}"

# The syslog TAG, not a marker substring. See the header.
TAG="${FLIP_ROLLOUT_TAG:-inngest-cutover-flip}"
REFUSAL_MARKER="SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED"
# Two identity fields, both required (#6616 — `host_name` telemetry has been observed lying: a web
# host self-labelled with the sed-rendered dedicated-host literal). `host` is Vector's auto-derived
# OS hostname, which a stale literal cannot forge. A PASS here closes #7761, so a row matching only
# `host_name` would close the tracker on evidence from the wrong machine.
FLIP_HOST="${FLIP_ROLLOUT_HOST:-soleur-inngest}"
FLIP_HOST_NAME="${FLIP_ROLLOUT_HOST_NAME:-soleur-inngest-prd}"
# The liveness window is deliberately NARROW. The tag emits ~2,880 rows/day at a 30s cadence, so a
# 24h window against any sane row limit takes the NEWEST N rows and silently examines a slice —
# reporting a slice as the window is the failure cutover-inngest.sh documents for this same tag.
# Two markers at 30s needs minutes, not hours.
WINDOW="${FLIP_ROLLOUT_WINDOW:-2h}"
LIMIT="${FLIP_ROLLOUT_LIMIT:-500}"
# The drift and refusal queries run over a WIDER window with their own narrow greps, so their row
# counts are tiny and the limit is not binding on them.
DRIFT_WINDOW="${FLIP_ROLLOUT_DRIFT_WINDOW:-24h}"
DOPPLER_PROJECT_NAME="${FLIP_ROLLOUT_DOPPLER_PROJECT:-soleur-inngest}"
DOPPLER_CONFIG_NAME="${FLIP_ROLLOUT_DOPPLER_CONFIG:-prd}"
# The expected terminal flag and the marker threshold are INLINE, not env-overridable. An earlier
# revision exposed them as FLIP_ROLLOUT_EXPECTED_FLAG / _MIN_MARKERS, which is an environment-
# supplied answer key on a probe that authorizes closing a security issue — in a PR whose entire
# thesis is that environment-supplied values are untrusted.
EXPECTED_FLAG="rolled-back"
MIN_MARKERS=2
# The guard revision the post-#7761 script stamps into every emit_state row.
EXPECTED_GUARD="${FLIP_ROLLOUT_EXPECTED_GUARD:-7761}"
# How long after the boundary a silent host stops being "not yet" and becomes a failure.
STALE_AFTER_S="${FLIP_ROLLOUT_STALE_AFTER_S:-3600}"

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
# NOT a hard requirement, and that is a deliberate correction. The sweeper
# (scheduled-followthrough-sweeper.yml) exposes BETTERSTACK_QUERY_* and several other secrets but
# NO Doppler token, so a probe that REQUIRED a Doppler read would return `flag_unreadable` on every
# sweep for the life of the issue — a permanent silent no-op, precisely the failure mode the
# sibling #7674 probe was written to retire. The flag is available on the channel the sweeper DOES
# have: emit_state stamps it into every marker. That reading is the primary source below; a Doppler
# read, when a credential is present, is strictly better evidence for one narrow case — the flag
# changed in Doppler but not yet observed by the host — so it FAILS FAST when available.
doppler_flag=""
if command -v "$DOPPLER_BIN" >/dev/null 2>&1; then
  doppler_flag="$("$DOPPLER_BIN" secrets get INNGEST_CUTOVER_FLIP \
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
# jq is load-bearing for every selector below. Unpreflighted, a missing jq empties the row set and
# the probe blames the HOST ("not reporting") for a local tooling fault.
if ! command -v jq >/dev/null 2>&1; then
  echo "TRANSIENT: reason=jq_unavailable — the decode path is unusable, so nothing was measured." >&2
  exit 2
fi

# mine <window> <grep-term> — decode, then field-isolate on the DECODED object. `-R` plus
# `fromjson?` at BOTH levels is load-bearing rather than defensive habit: without `-R`, ONE
# malformed line aborts the whole jq invocation and every valid row after it is lost — which would
# surface as "the host emits nothing" on a window that in fact contained a clean PASS.
mine() {
  local window="$1" term="$2" rows qrc
  rows="$("$QUERY" --since "$window" --grep "$term" --limit "$LIMIT" 2>/dev/null)"; qrc=$?
  if [[ "$qrc" -ne 0 ]]; then printf '__QUERY_FAILED__%s' "$qrc"; return 0; fi
  printf '%s\n' "$rows" \
    | jq -R -r --arg h "$FLIP_HOST" --arg hn "$FLIP_HOST_NAME" \
         'fromjson? | .raw? | fromjson?
          | select(.host == $h and .host_name == $hn)
          | .message? // empty' 2>/dev/null
}

LIVE="$(mine "$WINDOW" "$TAG")"
case "$LIVE" in
  __QUERY_FAILED__*)
    echo "TRANSIENT: reason=query_failed rc=${LIVE#__QUERY_FAILED__} — the ClickHouse read path did not answer." >&2
    echo "           Nothing about the host's liveness was measured. Observed 2026-09-03: this" >&2
    echo "           source answers 503 'under maintenance', which is a read-path outage and says" >&2
    echo "           nothing about the host." >&2
    exit 2 ;;
esac

# --- how stale is the boundary? ---------------------------------------------------------------
# Used only to decide whether silence is "not yet" or "never". Computed before the marker counts
# so both the empty and the insufficient arms can consult it.
now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
after_epoch="$(date -u -d "$AFTER" +%s 2>/dev/null || echo 0)"
boundary_age=0
if [[ "$now_epoch" -gt 0 && "$after_epoch" -gt 0 ]]; then boundary_age=$(( now_epoch - after_epoch )); fi
stale_note="the boundary is ${boundary_age}s old; a silent host stops being 'not yet' after ${STALE_AFTER_S}s"

if [[ -z "$LIVE" ]]; then
  if [[ "$boundary_age" -gt "$STALE_AFTER_S" ]]; then
    echo "FAIL: reason=channel_dark_past_deadline host=${FLIP_HOST}/${FLIP_HOST_NAME} — zero rows" >&2
    echo "      in ${WINDOW}, and ${stale_note}." >&2
    echo "      At a 30-second cadence this is not a host that has yet to boot; it is a host that" >&2
    echo "      is not running the unit. Check for a mount-namespace setup failure from the" >&2
    echo "      ReadWritePaths/StateDirectory directives, which kills the unit on every fire and" >&2
    echo "      emits nothing at all." >&2
    exit 1
  fi
  echo "TRANSIENT: reason=channel_dark host=${FLIP_HOST}/${FLIP_HOST_NAME} window=${WINDOW} — zero rows." >&2
  echo "           The host is not reporting, so its FSM state is UNKNOWN — not 'healthy'. If the" >&2
  echo "           apply has just run, the host may still be booting (${stale_note})." >&2
  exit 2
fi

# --- 2. liveness, and 1. the delivery discriminator -------------------------------------------
# `.start_ts` is compared as a STRING, so a row whose stamp is not a date must be excluded rather
# than sorted: inngest-cutover-flip.sh falls back to the literal `unknown` when `date` fails, and
# "unknown" > "2026-…" lexicographically — so a broken-clock row, INCLUDING one from the replaced
# host, would otherwise count as post-boundary evidence toward the PASS.
post_ok="$(printf '%s\n' "$LIVE" \
  | jq -R -r --arg after "$AFTER" --arg want "$EXPECTED_FLAG" --arg guard "$EXPECTED_GUARD" \
       'fromjson?
        | select(.start_ts | type == "string" and test("^[0-9]{4}-"))
        | select(.start_ts > $after)
        | select(.reason == "noop-\($want)" and .guard == $guard)
        | .start_ts' 2>/dev/null | grep -c . || true)"
case "$post_ok" in ''|*[!0-9]*) post_ok=0 ;; esac

# Post-boundary rows that are well-formed but carry the WRONG guard rev (or none) — i.e. the
# pre-#7761 script is still running. Distinguished from "no rows" so the operator is told the
# replace kept the old image rather than that the host is silent.
post_oldrev="$(printf '%s\n' "$LIVE" \
  | jq -R -r --arg after "$AFTER" --arg guard "$EXPECTED_GUARD" \
       'fromjson?
        | select(.start_ts | type == "string" and test("^[0-9]{4}-"))
        | select(.start_ts > $after)
        | select((.guard // "") != $guard)
        | .start_ts' 2>/dev/null | grep -c . || true)"
case "$post_oldrev" in ''|*[!0-9]*) post_oldrev=0 ;; esac

if [[ "$post_oldrev" -gt 0 && "$post_ok" -eq 0 ]]; then
  echo "FAIL: reason=stale_image — ${post_oldrev} post-boundary marker(s) carry no guard=${EXPECTED_GUARD} stamp." >&2
  echo "      The host is alive and polling, but it is running the PRE-#7761 script. The replace" >&2
  echo "      did not deliver the fix: check that BOTH image digest pins in cloud-init-inngest.yml" >&2
  echo "      moved to the digest the Phase 8 build produced, and that the flip-asset copy in the" >&2
  echo "      bootstrap did not fall through its || true guard. The seam exposure is still live." >&2
  exit 1
fi

# --- 3. flag drift, over the WIDE window with its own narrow grep ------------------------------
# ANY post-boundary flag other than the expected terminal one fails. Enumerating only the three
# flush-path states would let `armed` through — the state whose next poll runs the FLUSHALL.
DRIFT_ROWS="$(mine "$DRIFT_WINDOW" "$TAG")"
case "$DRIFT_ROWS" in
  __QUERY_FAILED__*)
    echo "TRANSIENT: reason=drift_query_failed rc=${DRIFT_ROWS#__QUERY_FAILED__} — the safety half was not measured." >&2
    exit 2 ;;
esac
drift="$(printf '%s\n' "$DRIFT_ROWS" \
  | jq -R -r --arg after "$AFTER" --arg want "$EXPECTED_FLAG" \
       'fromjson?
        | select(.start_ts | type == "string" and test("^[0-9]{4}-"))
        | select(.start_ts > $after) | select(.flag != $want)
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

# --- 4. seam refusals -------------------------------------------------------------------------
# Queried separately: the refusal marker is a RAW string, not emit_state JSON, so every selector
# above discards it by construction. Without this the single most interesting thing this PR can
# emit has no reader at all.
REFUSALS="$(mine "$DRIFT_WINDOW" "$REFUSAL_MARKER")"
case "$REFUSALS" in
  __QUERY_FAILED__*) REFUSALS="" ;;  # already reported by the drift arm; do not double-fail
esac
refusal_count="$(printf '%s\n' "$REFUSALS" | grep -cF "$REFUSAL_MARKER" || true)"
case "$refusal_count" in ''|*[!0-9]*) refusal_count=0 ;; esac
if [[ "$refusal_count" -gt 0 ]]; then
  echo "FAIL: reason=seam_refused count=${refusal_count} — the gate refused a fixture seam on the LIVE host." >&2
  echo "      That means a name in the ${DOPPLER_PROJECT_NAME}/${DOPPLER_CONFIG_NAME} Doppler config" >&2
  echo "      collided with a fixture seam name: the #7761 condition itself, occurring. The gate" >&2
  echo "      held, so nothing was executed — but rename the offending secret before it collides" >&2
  echo "      with a name the gate does not cover." >&2
  exit 1
fi

if [[ "$post_ok" -ge "$MIN_MARKERS" ]]; then
  corroboration="doppler read skipped (no credential in this environment)"
  [[ -n "$doppler_flag" ]] && corroboration="doppler corroborates: ${doppler_flag}"
  echo "PASS: #7761 delivered. ${post_ok} '${EXPECTED_FLAG}' marker(s) after ${AFTER} carrying"
  echo "      guard=${EXPECTED_GUARD} (so the NEW script is on the host, not merely a host that"
  echo "      booted after the timestamp); >= ${MIN_MARKERS}, so the 30s timer is cycling rather"
  echo "      than having booted once; no flag drift; no seam refusal; ${corroboration}."
  exit 0
fi

if [[ "$boundary_age" -gt "$STALE_AFTER_S" ]]; then
  echo "FAIL: reason=insufficient_post_replace_markers_past_deadline count=${post_ok}" >&2
  echo "      want>=${MIN_MARKERS} after ${AFTER}, and ${stale_note}." >&2
  echo "      The flag is correct and nothing flushed, but the host has not been observed POLLING" >&2
  echo "      since the replace. At a 30-second cadence that is not 'not yet'." >&2
  exit 1
fi
echo "TRANSIENT: reason=insufficient_post_replace_markers count=${post_ok}" >&2
echo "           want>=${MIN_MARKERS} after ${AFTER} (window ${WINDOW}); ${stale_note}." >&2
echo "           The flag is correct and nothing flushed, but the host has not yet been observed" >&2
echo "           POLLING since the replace. At a 30-second cadence this resolves within minutes." >&2
exit 2
