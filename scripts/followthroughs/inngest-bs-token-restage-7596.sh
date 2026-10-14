#!/usr/bin/env bash
# #7596 — the boot-trace allowlist (`inngest-boot-phone-home`,
# `inngest-bs-token-restage`) reaches the inngest host ONLY inside a baked
# image through `apply_target=inngest-host-replace`; this host's vector.toml is
# never redelivered by terraform_data.journald_persistent. This probe is the
# issue's measured close condition: an observed journald row
#
#   SYSLOG_IDENTIFIER="inngest-bs-token-restage"
#   host="soleur-inngest"  AND  host_name="soleur-inngest-prd"
#   message contains "SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1"
#
# in Better Stack. The RESTAGE identifier is the positive control —
# `inngest-boot-phone-home` is silent-on-success by design (every logger call
# sits in a failure arm, journald-config.test.sh CF-4c), so on a healthy host
# an ABSENCE of phone-home rows proves nothing. The restage unit logs on
# success once per boot; its row arriving means (a) the allowlist accepts the
# identifier, and (b) the Doppler token re-stage itself succeeded — the full
# channel #7596 cares about.
#
#   exit 0 = PASS        the positive row was observed — close evidence for #7596
#   exit 1 = FAIL        deliberately unreachable — until a future
#                        `inngest-host-replace` delivers the baked allowlist
#                        this probe's only honest states are PASS (the replace
#                        landed and emitted) and TRANSIENT (nothing/too-little
#                        evidence yet). A FAIL that can never discriminate is
#                        a misfire under the sweeper.
#   exit 2 = TRANSIENT   credentials unprovisioned, query failure, no rows yet,
#                        or rows present but the restage outcome not yet ok=1.
#
# Both filter fields are isolated POST-DECODE — Better Stack stores `raw`
# double-encoded, so a literal `"host":"…"` grep on the outer row matches
# nothing, ever. Field isolation first, content check second: a missing row
# is silence, not a verdict — TRANSIENT, never FAIL.
#
# TRACKER: #7596 — `host=soleur-inngest` AND `host_name=soleur-inngest-prd`
# are both required: a web-1 row under a stale `host_name` is a real shape the
# shared renderer can produce (#6616), and an inert-on-web-1 identifier
# shipping a row was the exact false-close the issue names. Only BOTH fields
# naming the dedicated host proves delivery.
#
# Tracker directive (goes in the issue body; a deferred operator step — the
# probe is inert until enrolled):
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-bs-token-restage-7596.sh earliest=<replace-date> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# Secrets clause: BETTERSTACK_QUERY_HOST / BETTERSTACK_QUERY_USERNAME /
# BETTERSTACK_QUERY_PASSWORD are already wired into the sweeper env (the
# sibling #7674/#7500 probes' clause); none is a prd-terraform credential. No
# `${VAR:?}` — the vault provision order is not guaranteed and that lint
# bans the form here.
set -uo pipefail

# xtrace refusal (the probes' credential discipline, #7797): a traced run
# would print the Better Stack credentials to the log.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${RESTAGE_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"
INNGEST_HOST="${RESTAGE_HOST:-soleur-inngest}"
HOST_NAME="${RESTAGE_HOST_NAME:-soleur-inngest-prd}"
WINDOW="${RESTAGE_WINDOW:-${SOLEUR_FT_WINDOW:-7d}}"
LIMIT="${RESTAGE_LIMIT:-${SOLEUR_FT_LIMIT:-500}}"
IDENT='inngest-bs-token-restage'
MARKER='SOLEUR_INNGEST_BS_TOKEN_RESTAGED'
# The SQL prefilter uses the PREFIX, not the D-suffixed marker: the failure
# emit is SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED, which never contains
# RESTAGED — a full-prefix grep is what lets restage_not_ok fire on the real
# failure shape instead of misreporting it as channel_dark.
MARKER_PREFIX='SOLEUR_INNGEST_BS_TOKEN_RESTAGE'


# --- credentials: absent = TRANSIENT, never ${VAR:?} ------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  printf 'TRANSIENT: reason=credentials_unprovisioned — missing:%s. The sweeper env or doppler -c prd_terraform provides these; retry once provisioned.\n' \
    "$missing" >&2
  exit 2
fi
[[ -x "$QUERY" || -f "$QUERY" ]] || {
  printf 'TRANSIENT: reason=query_tool_missing — %s not found.\n' "$QUERY" >&2
  exit 2
}

# --- query: marker prefilter, decode, host+identity isolation ----------------
qrc=0
rows="$("$QUERY" --since "$WINDOW" --grep "$MARKER_PREFIX" --limit "$LIMIT" 2>/dev/null)" || qrc=$?
if [[ "$qrc" -ne 0 ]]; then
  printf 'TRANSIENT: reason=query_failed rc=%s — the Better Stack read failed; no verdict can be formed this pass.\n' "$qrc" >&2
  exit 2
fi

# `select()`s are SEQUENCED — one per pipe — so each field is isolated after
# decode: a row matching on message text from the wrong host or identifier is
# dropped by the isolation selects, never counted.
jrc=0
mine="$(printf '%s\n' "$rows" \
  | jq -R -r \
      --arg h "$INNGEST_HOST" --arg hn "$HOST_NAME" \
      --arg id "$IDENT" --arg m "$MARKER" '
        fromjson? | .raw? | fromjson?
        | select(type == "object")
        | select(.SYSLOG_IDENTIFIER == $id)
        | select(.host == $h)
        | select(.host_name == $hn)
        | select((.message // "") | contains($m))
        | (.message // "")' 2>/dev/null)" || jrc=$?
if [[ "$jrc" -ne 0 ]]; then
  printf 'TRANSIENT: reason=selector_failed rc=%s — jq failed to decode; the Better Stack raw shape may have changed.\n' "$jrc" >&2
  exit 2
fi

if [[ -z "$mine" ]]; then
  # Distinguish "no marker rows at all" (channel dark — the expected state
  # until a replace) from "the identifier emits but never restaged ok=1" —
  # different remediation (still-waiting vs a failed re-stage).
  ident_rows="$(printf '%s\n' "$rows" \
    | jq -R -r --arg h "$INNGEST_HOST" --arg hn "$HOST_NAME" --arg id "$IDENT" '
        fromjson? | .raw? | fromjson?
        | select(type == "object")
        | select(.SYSLOG_IDENTIFIER == $id)
        | select(.host == $h)
        | select(.host_name == $hn)
        | .message' 2>/dev/null)"
  if [[ -n "$ident_rows" ]]; then
    printf 'TRANSIENT: reason=restage_not_ok — %s rows ARE arriving from %s/%s (the allowlist is live) but none carries %s ok=1; read the emitted reason= row for the failure class.\n' \
      "$IDENT" "$INNGEST_HOST" "$HOST_NAME" "$MARKER" >&2
  else
    printf 'TRANSIENT: reason=channel_dark — zero %s rows from %s/%s in %s. Expected until the next inngest-host-replace bakes and boots the #7457 allowlist; do NOT rekey on web-1 rows, which are live-but-inert by design (#7596).\n' \
      "$IDENT" "$INNGEST_HOST" "$HOST_NAME" "$WINDOW" >&2
  fi
  exit 2
fi

n_rows=$(printf '%s\n' "$mine" | grep -cF "$MARKER" || true)
n_ok=$(printf '%s\n' "$mine" | grep -cE "$MARKER ok=1(\$|[[:space:]])" || true)
if [[ "$n_ok" -ge 1 ]]; then
  printf 'PASS: observed %s ok=1 (%s marker row(s) in window %s) from SYSLOG_IDENTIFIER=%s host=%s host_name=%s — the #7457 allowlist is live on the inngest host; #7596 close evidence.\n' \
    "$MARKER" "$n_rows" "$WINDOW" "$IDENT" "$INNGEST_HOST" "$HOST_NAME"
  printf '%s\n' "$mine"
  exit 0
fi

printf 'TRANSIENT: reason=restage_not_ok — %s marker row(s) from %s/%s but none carries ok=1.\n' \
  "$n_rows" "$INNGEST_HOST" "$HOST_NAME" >&2
printf '%s\n' "$mine" >&2
exit 2
