#!/usr/bin/env bash
# inngest-rearm-reminders.sh — no-SSH cutover re-arm executor (#5450, AC2/B2).
#
# Runs ON THE HOST (delivered via the infra-config push, invoked through the
# /hooks/inngest-rearm-reminders POST hook). Consumes the JSON records emitted by
# inngest-enumerate-reminders.sh (stdin) and re-arms each by POSTing it back to
# the app's POST /api/internal/schedule-reminder route on host loopback. This is
# the half that actually makes a dropped reminder FIRE against the fresh
# Postgres+Redis backend after the cutover.
#
# Why route through schedule-reminder (not a raw inngest.send): the route is the
# existing, validated arming surface — it recomputes the inngest dedup keys
# `id`(=reminder_id) + `ts`(=Date.parse(fire_at)) from the body, so re-arming an
# event that ALSO survived in inngest state dedups instead of double-firing a
# non-idempotent comment (B2-i). It enforces `actor:"platform"` (B2-ii) and the
# action allowlist. Feeding back {reminder_id,fire_at,actor,action} is sufficient.
#
# ORDERING GUARD (B2-iii): the route returns 503 while INNGEST_CUTOVER_QUIESCE is
# set. Re-arm MUST run AFTER the operator clears the flag (cutover step 6). If we
# get a 503 we ABORT LOUD — never swallow it — so a too-early re-arm is a visible
# failure, not a silent reminder loss.
#
# Read path for the Bearer secret: $INNGEST_MANUAL_TRIGGER_SECRET if already in
# env (test/host), else `doppler secrets get` (prod host has the prd config).
# Fails closed if neither yields a secret.
set -euo pipefail
# xtrace refusal (#7797): this script binds a live credential (the Doppler token and the
# INNGEST_MANUAL_TRIGGER_SECRET Bearer) and -x would print it to the webhook's journald stream.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

readonly LOG_TAG="inngest-rearm-reminders"

# --- #7095 re-read for a webhook-executed script -------------------------------------------
# webhook.service still exports the /etc/default/webhook-deploy DOPPLER_TOKEN, revoked
# 2026-07-30T11:19:30Z; the fresh credential is re-delivered by terraform apply at
# /etc/default/soleur-doppler-token (server.tf "WHY THIS FILE EXISTS"). #7095 re-pointed
# ci-deploy.sh (the only other doppler-reading hook target, via its parsed CRED_FILE_STATE
# block) and four long-running units via EnvironmentFile=- drop-ins; infra-config-apply.sh
# DELIVERS the file and never reads Doppler. This script kept reading Doppler on the dead
# token, so every read failed 401 into `2>/dev/null` and the fail-closed branch fired with no
# reason logged (found live 2026-09-13: op=execute cleared 2.0 for the first time and died
# at 2.1 capture).
#
# PARSED, NOT SOURCED — the file's values are terraform-interpolated and this runs as `deploy`,
# which holds NOPASSWD sudo on the installers; `. file` would hand `$(...)` to bash. Four keys
# are taken (the token plus the three baked Sentry DSN components the same file carries, so a
# read failure can page), later-wins over the unit's export, and an EMPTY value is skipped so a
# bare `KEY=` (which the installer's shape check accepts) cannot blank a working one. The
# `|| [[ -n "$k" ]]` keeps a final line without a trailing newline (ci-deploy.sh drops it).
# Every function in this block MUST stay byte-identical to the copy in the sibling webhook
# script — webhook-doppler-token-reread.test.sh pins that, because a helper re-derived per
# file drifts. `SOLEUR_CRED_FILE_STATE` records present|unreadable|absent for the log line.
SOLEUR_CRED_FILE_STATE=absent
SOLEUR_CRED_TOKEN_APPLIED=0
soleur_refresh_doppler_token() {
  local f="${SOLEUR_DOPPLER_TOKEN_FILE:-/etc/default/soleur-doppler-token}" k v
  if [[ -r "$f" ]]; then SOLEUR_CRED_FILE_STATE=present; elif [[ -e "$f" ]]; then SOLEUR_CRED_FILE_STATE=unreadable; return 0; else SOLEUR_CRED_FILE_STATE=absent; return 0; fi
  # `|| return 0` on the loop: a redirect that fails AFTER -r passed (LSM denial, race) must not
  # abort the enclosing `$(read_secret)` before the reason line is emitted.
  while IFS='=' read -r k v || [[ -n "$k" ]]; do
    v="${v%$'\r'}"
    case "$k" in
      DOPPLER_TOKEN)
        # Applied only when it has the shape server.tf's plan-time gate admits (dp.<family>.<body>);
        # a quoted value, an `export `-prefixed line or a CRLF-only `KEY=` leaves the unit's export
        # standing and is reported as token_file=present token_applied=0 — a file-shape defect.
        if [[ "$v" =~ ^dp\.[a-z]{2,}\.[A-Za-z0-9._-]+$ ]]; then export DOPPLER_TOKEN="$v"; SOLEUR_CRED_TOKEN_APPLIED=1; fi ;;
      SENTRY_INGEST_DOMAIN|SENTRY_PROJECT_ID|SENTRY_PUBLIC_KEY)
        # Whitespace-only counts as EMPTY (a CRLF-terminated `KEY=` yields $'\r', which `-n` accepts).
        if [[ -n "${v//[[:space:]]/}" ]]; then printf -v "$k" '%s' "$v"; export "${k?}"; fi ;;
    esac
  done < "$f" 2>/dev/null || return 0
  return 0
}

# Classify a failed/empty Doppler read into a closed vocabulary. The real CLI prints its cause
# LAST (`Unable to fetch secrets` then `Doppler Error: …`, coloured, behind two `Using
# DOPPLER_* from the environment` notices under this unit), so the head line is a constant.
soleur_doppler_read_class() {
  local rc="$1" errfile="$2" out="$3"
  if [[ "$rc" == 127 ]]; then printf 'binary_absent'; return 0; fi
  if [[ -r "$errfile" ]] && LC_ALL=C grep -qa 'Invalid Auth token' "$errfile"; then printf 'invalid_auth'; return 0; fi
  if [[ -r "$errfile" ]] && LC_ALL=C grep -qa 'Could not find requested secret' "$errfile"; then printf 'secret_not_found'; return 0; fi
  if [[ -r "$errfile" ]] && LC_ALL=C grep -qaE 'dial tcp|no such host|i/o timeout|TLS handshake|connection refused|Get "https' "$errfile"; then printf 'transport'; return 0; fi
  if [[ "$rc" == 0 && -z "$out" ]]; then printf 'empty_value'; return 0; fi
  printf 'other'
}

# One line to journald (-> Better Stack) AND to stderr (-> the hook's response body -> the
# cutover run log) saying WHY a Doppler read came back empty, so the next reader does not need
# SSH to tell a revoked token from a missing binary. The `Doppler Error:` line if present, else
# the LAST stderr line; control/ANSI bytes stripped in the C locale; credential-shaped tokens
# scrubbed with ci-deploy.sh's `dp\.[a-z]{2,}\.` shape; 160 bytes — never the value. Then a
# Sentry event (class enum only, never stderr) when the three DSN components were read. This
# runs INSIDE `$(read_secret)`, whose stdout IS the secret — so nothing here may write stdout
# (the beacon's curl is `>/dev/null`; a mock curl that printed its status code proved the point).
soleur_log_doppler_read_failure() {
  local rc="$1" errfile="$2" out="${3-}" class why="" payload
  class="$(soleur_doppler_read_class "$rc" "$errfile" "$out")"
  if [[ -r "$errfile" ]]; then
    why="$( { LC_ALL=C grep -a -m1 'Doppler Error:' "$errfile" || tail -n 1 "$errfile"; } 2>/dev/null \
      | LC_ALL=C sed -E 's/\x1b\[[0-9;]*m//g' \
      | LC_ALL=C tr -c '[:print:]' ' ' \
      | LC_ALL=C tr '"' "'" \
      | LC_ALL=C sed -E 's/dp\.[a-z]{2,}\.[A-Za-z0-9._-]+/dp.**.REDACTED/g' \
      | LC_ALL=C cut -c1-160 )" || why=""
  fi
  # token_applied=0 with token_file=present means the file was read but carried no usable
  # DOPPLER_TOKEN (quoted value, `export ` prefix, empty) — a different fix from a revoked one.
  local line="SOLEUR_DEPLOY_CRED_FAIL secret=INNGEST_MANUAL_TRIGGER_SECRET rc=${rc} class=${class} token_file=${SOLEUR_CRED_FILE_STATE} token_applied=${SOLEUR_CRED_TOKEN_APPLIED} err=\"${why:-<empty>}\""
  logger -t "${LOG_TAG:-webhook-script}" "$line" 2>/dev/null || true
  printf 'ERROR: %s\n' "$line" >&2
  # Destination pinned by SHAPE (#7873): the three values are parsed from a root-owned file, but a
  # credentialed request must refuse any host that is not a Sentry ingest domain regardless.
  local dom="${SENTRY_INGEST_DOMAIN:-}" pid="${SENTRY_PROJECT_ID:-}"
  if [[ "$dom" =~ ^[a-z0-9]+\.ingest\.([a-z]{2}\.)?sentry\.io$ && "$pid" =~ ^[0-9]+$ && -n "${SENTRY_PUBLIC_KEY:-}" ]] && command -v jq >/dev/null 2>&1; then
    payload="$(jq -nc --arg logger "${LOG_TAG:-webhook-script}" --arg class "$class" --arg rc "$rc" --arg tf "$SOLEUR_CRED_FILE_STATE" --arg ta "$SOLEUR_CRED_TOKEN_APPLIED" \
      '{message: ("doppler read failed for INNGEST_MANUAL_TRIGGER_SECRET (" + $class + ")"), level: "error", platform: "other", logger: $logger,
        tags: {feature: "inngest-cutover", op: "doppler-read-failed", class: $class},
        extra: {rc: $rc, token_file: $tf, token_applied: $ta}}')" || payload=""
    if [[ -n "$payload" ]]; then
      curl --disable --noproxy '*' -s -o /dev/null --max-time 10 -X POST \
        "https://${dom}/api/${pid}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
        -d "$payload" >/dev/null 2>&1 || true
    fi
  fi
}
REARM_URL="${SCHEDULE_REMINDER_URL:-http://127.0.0.1:3000/api/internal/schedule-reminder}"

read_secret() {
  if [[ -n "${INNGEST_MANUAL_TRIGGER_SECRET:-}" ]]; then
    printf '%s' "$INNGEST_MANUAL_TRIGGER_SECRET"
    return 0
  fi
  # INNGEST_REARM_SKIP_DOPPLER lets tests assert the fail-closed path without a
  # doppler binary on PATH.
  if [[ "${INNGEST_REARM_SKIP_DOPPLER:-0}" != "1" ]]; then
    soleur_refresh_doppler_token
    if ! command -v doppler >/dev/null 2>&1; then soleur_log_doppler_read_failure 127 /dev/null ""; return 0; fi
    local out="" err rc=0
    # A bare `mktemp` is an abort vector under `set -e` on a full /tmp (ci-deploy.sh notes the
    # same); degrade to /dev/null so a missing scratch file loses the stderr, never the read.
    err="$(mktemp 2>/dev/null)" || err=/dev/null
    # The RETURN trap owns the scratch file (lint-trap-tempfile-ownership rule c): it is removed
    # on every exit from this function, including an abort between allocation and the rm below.
    # shellcheck disable=SC2064  # $err is expanded at trap-registration time on purpose
    if [[ "$err" != /dev/null ]]; then
      trap "rm -f -- '$err'" RETURN
    fi
    out="$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain 2>"$err")" || rc=$?
    if [[ "$rc" -ne 0 || -z "$out" ]]; then soleur_log_doppler_read_failure "$rc" "$err" "$out"; out=""; fi
    # Only an rc-0 value is the secret: partial stdout from a failed CLI must never be returned.
    printf '%s' "$out"
  fi
}

SECRET="$(read_secret)"
if [[ -z "$SECRET" ]]; then
  logger -t "$LOG_TAG" "FATAL: INNGEST_MANUAL_TRIGGER_SECRET unavailable — refusing to re-arm" 2>/dev/null || true
  echo "ERROR: INNGEST_MANUAL_TRIGGER_SECRET unavailable (env + doppler both empty)" >&2
  exit 1
fi

# Source the re-arm records. DEFAULT (webhook path): self-enumerate on the host
# via inngest-enumerate-reminders.sh — adnanh/webhook does NOT pipe the request
# body to the command's stdin, so relying on stdin here would hang; self-enumerate
# also keeps comment bodies on-host (never transiting the workflow log, P2-sec-a).
# INNGEST_REARM_STDIN=1 switches to reading records from stdin (manual/test).
ENUMERATE_CMD="${INNGEST_ENUMERATE_CMD:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/inngest-enumerate-reminders.sh}"

# Cutover capture bridge (#5542). The FIRST SQLite→Postgres cutover replaces the
# inngest event store, so a post-deploy self-enumerate queries the NEW (empty)
# Redis queue and would re-arm NOTHING — silently losing every armed reminder
# (verdict 0.2: the armed-event queue lives in Redis; the new durable Redis starts
# empty). To bridge the gap WITHOUT transiting comment bodies through the workflow
# (P2-sec-a). The mode is a TRISTATE (INNGEST_REARM_MODE, from the hook payload):
#   capture            — self-enumerate the OLD server and persist records to
#                        CAPTURE_FILE on-host (run BEFORE the deploy).
#   rearm-from-capture — CUTOVER re-arm: the capture file is the ONLY valid source.
#                        A missing/empty/corrupt capture is FATAL — never a silent
#                        downgrade to self-enumerating the post-deploy EMPTY backend
#                        (that is the precise reminder-loss this feature prevents).
#                        Deletes the file on full success.
#   rearm (default)    — STEADY-STATE re-arm: self-enumerate the live backend.
#                        Deliberately IGNORES any capture file, so an orphaned
#                        capture from an aborted cutover cannot hijack a routine
#                        re-arm and replay a stale snapshot.
# CAPTURE_FILE lives under the --sqlite-dir volume, which survives the cutover's
# systemd restart (a config change, not a host re-provision).
MODE="${INNGEST_REARM_MODE:-rearm}"
CAPTURE_FILE="${INNGEST_CUTOVER_CAPTURE_FILE:-/var/lib/inngest/cutover-capture.json}"

if [[ "$MODE" == "capture" ]]; then
  cap="$("$ENUMERATE_CMD")" || { echo "ERROR: capture: enumeration failed; nothing persisted" >&2; exit 1; }
  if ! echo "$cap" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: capture: enumerate did not return a JSON array" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$CAPTURE_FILE")" || { echo "ERROR: capture: cannot create $(dirname "$CAPTURE_FILE")" >&2; exit 1; }
  # Atomic write: a partial/truncated capture that survived the cutover restart
  # would otherwise be read back as corrupt. Write to a temp file + rename so the
  # capture is either fully present or absent — never half-written.
  cap_tmp="$(mktemp "${CAPTURE_FILE}.XXXXXX")" || { echo "ERROR: capture: mktemp failed" >&2; exit 1; }
  if ! printf '%s' "$cap" > "$cap_tmp" || ! mv -f "$cap_tmp" "$CAPTURE_FILE"; then
    rm -f "$cap_tmp"; echo "ERROR: capture: failed to persist $CAPTURE_FILE" >&2; exit 1
  fi
  cap_count=$(echo "$cap" | jq 'length')
  cap_ids=$(echo "$cap" | jq -r '[.[].reminder_id] | join(",")')
  logger -t "$LOG_TAG" "captured $cap_count reminder(s) to $CAPTURE_FILE" 2>/dev/null || true
  # Status object to stdout — ids only, NEVER comment bodies (P2-sec-a); the
  # webhook response carries this. Mirrors the enumerate/inventory purity contract.
  jq -nc --argjson n "$cap_count" --arg ids "$cap_ids" --arg f "$CAPTURE_FILE" \
    '{captured: $n, reminder_ids: ($ids | split(",") | map(select(length > 0)) | sort), capture_file: $f}'
  exit 0
fi

# Records source by mode. stdin (test/manual) overrides everything.
FROM_CAPTURE=0
if [[ "${INNGEST_REARM_STDIN:-0}" == "1" ]]; then
  records="$(cat)"
elif [[ "$MODE" == "rearm-from-capture" ]]; then
  # Cutover re-arm: the capture file is the ONLY valid source. Missing/empty/corrupt
  # is FATAL — a self-enumerate here would query the post-deploy empty backend and
  # lose every reminder. An empty JSON array ([]) IS valid (capture found none); a
  # zero-byte/truncated/non-array file is the corruption case and fails loud.
  if [[ ! -s "$CAPTURE_FILE" ]] || ! jq -e 'type == "array"' < "$CAPTURE_FILE" >/dev/null 2>&1; then
    echo "ERROR: rearm-from-capture: $CAPTURE_FILE missing/empty/corrupt — refusing to self-enumerate the post-deploy backend (would silently lose reminders). Re-run op=capture against the OLD server before deploy." >&2
    logger -t "$LOG_TAG" "FATAL: rearm-from-capture but capture file invalid; refusing silent self-enumerate" 2>/dev/null || true
    exit 1
  fi
  records="$(cat "$CAPTURE_FILE")"
  FROM_CAPTURE=1
  logger -t "$LOG_TAG" "consuming cutover capture file $CAPTURE_FILE" 2>/dev/null || true
else
  # Steady-state self-enumerate. Ignores any capture file by design (a stale orphan
  # from an aborted cutover must NOT hijack a routine re-arm).
  records="$("$ENUMERATE_CMD")" || { echo "ERROR: enumeration failed; cannot source re-arm records" >&2; exit 1; }
fi
if ! echo "$records" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "ERROR: re-arm records are not a JSON array" >&2
  exit 1
fi

count=$(echo "$records" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  logger -t "$LOG_TAG" "no reminders to re-arm (empty record set)" 2>/dev/null || true
  echo "inngest-rearm-reminders: nothing to re-arm" >&2
  # A fully-consumed empty capture is a clean no-op success — remove it so it does
  # not linger as an orphan for a later re-arm.
  if [[ "$FROM_CAPTURE" == "1" ]]; then rm -f "$CAPTURE_FILE"; fi
  exit 0
fi

rearmed=0
failed=0
for i in $(seq 0 $((count - 1))); do
  rec=$(echo "$records" | jq -c ".[$i]")
  rid=$(echo "$rec" | jq -r '.reminder_id')
  # The route's body is exactly {reminder_id, fire_at, actor, action}.
  body=$(echo "$rec" | jq -c '{reminder_id, fire_at, actor, action}')
  http_code=$(curl --disable --noproxy '*' -s --max-time 15 \
    -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SECRET}" \
    --data-binary "$body" \
    "$REARM_URL" || echo "000")

  case "$http_code" in
    202)
      rearmed=$((rearmed + 1))
      logger -t "$LOG_TAG" "re-armed reminder_id=$rid" 2>/dev/null || true
      ;;
    503)
      # Quiesce ordering guard — abort loud, do NOT continue (B2-iii).
      logger -t "$LOG_TAG" "ABORT: 503 on reminder_id=$rid — INNGEST_CUTOVER_QUIESCE still set" 2>/dev/null || true
      echo "ERROR: re-arm got 503 for reminder_id=$rid — INNGEST_CUTOVER_QUIESCE is still set." >&2
      echo "       Clear it (cutover step 6: doppler secrets set INNGEST_CUTOVER_QUIESCE= ...) THEN re-run re-arm." >&2
      echo "       $rearmed re-armed before abort; reminder_id=$rid and any after it were NOT re-armed." >&2
      exit 1
      ;;
    *)
      failed=$((failed + 1))
      logger -t "$LOG_TAG" "FAILED re-arm reminder_id=$rid http_code=$http_code" 2>/dev/null || true
      echo "ERROR: re-arm failed for reminder_id=$rid (HTTP $http_code)" >&2
      ;;
  esac
done

echo "inngest-rearm-reminders: re-armed=$rearmed failed=$failed total=$count" >&2
logger -t "$LOG_TAG" "done: re-armed=$rearmed failed=$failed total=$count" 2>/dev/null || true

# On a fully-successful re-arm sourced from the cutover capture, delete the file so
# a later steady-state re-arm self-enumerates the LIVE backend instead of replaying
# a stale capture. Keep it on ANY failure so a retry can finish the set.
if [[ "$FROM_CAPTURE" == "1" && "$failed" -eq 0 ]]; then
  rm -f "$CAPTURE_FILE"
  logger -t "$LOG_TAG" "consumed + removed capture file $CAPTURE_FILE" 2>/dev/null || true
fi

[[ "$failed" -gt 0 ]] && exit 1 || exit 0
