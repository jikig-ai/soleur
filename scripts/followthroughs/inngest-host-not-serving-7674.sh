#!/usr/bin/env bash
# #7674 — the dedicated inngest host serves again. Successor to inngest-zot-boot-7462.sh.
#
# TRACKER: **#7674**. It stays OPEN until this reads PASS. scripts/sweep-followthroughs.sh lists
# `--state open`, so hosting a probe on a CLOSED issue is a permanent silent no-op — which is
# exactly what happened to the predecessor and is the reason this file exists.
#
# WHY THE PREDECESSOR WAS RETIRED RATHER THAN RE-POINTED. inngest-zot-boot-7462.sh verifies the
# ZOT-PRIMARY BOOT (`stage=inngest_zot` + `stage=bootstrap-done`) and says so in its own header.
# Its contract was SATISFIED: the host replace fired 2026-08-20T00:52:13Z and the pulled image did
# bootstrap. It returned PASS, the sweeper closed #7462 — and #7462's body was a SIX-STEP
# restoration of which only step 1 had been measured. Probe scope != issue scope. Re-pointing that
# probe here would re-arm a check that passes on a host that serves nothing, so it was de-enrolled
# and this probe measures the thing that is actually outstanding.
#
# WHAT IT VERIFIES — POSITIVELY, NEVER BY ABSENCE. PASS requires an observed
# SOLEUR_INNGEST_SERVER_PROBE row from THIS host carrying BOTH `server_active=active` AND
# `http_code=200`. An absence arm ("no inactive rows") would be FAIL-OPEN in the precise state
# this exists to reject: a host that emits nothing at all would auto-PASS. Absence is used here
# only to DOWNGRADE a positive, never to grant one.
#
# WHY BOTH FIELDS. `server_active=active` alone means systemd considers the unit running; the
# #7674 diagnosis is that the unit can be stopped outright while the host is otherwise healthy,
# and a future variant is a unit that runs but binds nothing. `http_code=200` is the loopback
# proof that it SERVES. Measured 2026-08-25 the host reported `server_active=inactive
# http_code=000` for 5.4 days on one unchanged boot_id.
#
# HOST ISOLATION IS MANDATORY. inngest-server-probe.sh is the SHARED renderer for the dedicated
# host AND web-1, and apps/web-platform/infra/vector.toml states ALL hosts multiplex into the ONE
# Logs source 2457081 with `host_name` the sole discriminator. web-1 legitimately reports
# `cutover_flag=unknown` and, once it is serving, `server_active=active http_code=200` — so a
# probe without the host filter would PASS on web-1's rows and close #7674 while the dedicated
# host is still dark. That is the same "measured the wrong thing and closed the tracker" failure
# the predecessor is being retired for.
#
# AND THE FILTER MUST BE APPLIED AFTER DECODING. ClickHouse stores `raw` DOUBLE-ENCODED, so a
# literal `"host_name":"…"` grep against the outer row matches NOTHING, EVER — the probe would
# read zero rows forever and report TRANSIENT for the life of the issue. Measured against live
# rows: outer match 0/40, post-decode match 40/40.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       an observed row from this host with server_active=active AND http_code=200.
#   2 = TRANSIENT  not serving yet, host silent, credentials unprovisioned, or ANY query/decode
#                  failure. Each prints a DISTINCT reason: an unprovisioned credential must never
#                  read as "not serving yet", because the two have opposite remedies and only one
#                  of them is a wait.
#   1 = FAIL       RESERVED, and deliberately unreachable here. The sweeper comments on exit 1
#                  every run, and "the host has not been cut over yet" is a WAIT, not an
#                  actionable fault. There is no state of this probe that is actionable-now.
#
# `earliest=` IS SET PAST THE CUTOVER WINDOW ON PURPOSE. Step 4b (a durable serving ExecStart) is
# reachable only inside a cutover, which #7674 defers, so this probe legitimately returns 2 until
# then. The sweeper comments TRANSIENT on every run it makes, so "returns 2" and "does not comment
# daily" are jointly satisfiable ONLY via an `earliest=` that has not yet elapsed. Ongoing
# visibility is NOT this probe's job — the */15 dedicated-host arm on
# .github/workflows/scheduled-inngest-health.yml carries that. If the cutover slips, push the date
# rather than weakening an arm.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE and the ban is mechanical, not stylistic: under the
# sweeper's non-interactive shell that word-expansion aborts with status 1, which this contract
# reads as FAIL — so an unprovisioned secret would post a daily false-FAIL forever instead of
# retrying quietly. scripts/lint-followthrough-varq-ban.sh reddens CI on it. Required env is
# therefore named LITERALLY below, because the sweeper runs probes under `env -i`.
#
# NO `set -e`. An errexit abort exits 1, which this contract reads as FAIL — the one status that
# comments daily. Failures are routed explicitly instead.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${INNGEST_SERVING_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"

MARKER="SOLEUR_INNGEST_SERVER_PROBE"
HOST_NAME="${INNGEST_SERVING_HOST_NAME:-soleur-inngest-prd}"
WINDOW="${INNGEST_SERVING_WINDOW:-24h}"
LIMIT="${INNGEST_SERVING_LIMIT:-500}"

# --- credentials: absent is TRANSIENT, and must say so in its own words ------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — missing:${missing}." >&2
  echo "           This is NOT 'the host is not serving yet'. The probe could not ask the" >&2
  echo "           question at all, so nothing about the host was measured. Next: confirm the" >&2
  echo "           directive's secrets= clause lists all three and that they are set in the" >&2
  echo "           sweeper workflow env." >&2
  exit 2
fi

# --- one query -------------------------------------------------------------------------------
rows="$("$QUERY" --since "$WINDOW" --grep "$MARKER" --limit "$LIMIT" 2>/dev/null)"
qrc=$?
if [[ "$qrc" -ne 0 ]]; then
  echo "TRANSIENT: reason=query_failed rc=${qrc} — the ClickHouse read path did not answer." >&2
  echo "           Nothing about the host was measured. A rotated connection password and a" >&2
  echo "           network fault both land here; neither is a statement about the host." >&2
  exit 2
fi

# Decode, then field-isolate on the DECODED object. `-R` plus `fromjson?` at BOTH levels is
# load-bearing rather than defensive habit: without `-R`, jq parses the stream itself, so ONE
# malformed line aborts the whole invocation and every valid row after it is lost — which would
# surface as reason=channel_dark ("the host emits nothing") on a window that in fact contained a
# clean PASS. A warehouse read is exactly where a truncated line shows up.
mine="$(printf '%s\n' "$rows" \
  | jq -R -r 'fromjson? | .raw? | fromjson?
              | select(.host_name == "'"$HOST_NAME"'")
              | .message? // empty' 2>/dev/null \
  | grep -F "$MARKER")"

if [[ -z "$mine" ]]; then
  echo "TRANSIENT: reason=channel_dark host=${HOST_NAME} window=${WINDOW} — zero ${MARKER} rows." >&2
  echo "           The host is not reporting, so its serving state is UNKNOWN — not 'healthy'." >&2
  echo "           Check inngest-server-probe.timer and the Vector shipper before reading this" >&2
  echo "           as progress. The */15 dedicated-host arm on scheduled-inngest-health.yml" >&2
  echo "           reports the same condition as probe-unavailable." >&2
  exit 2
fi

# --- the POSITIVE discriminator ----------------------------------------------------------------
# Both fields must hold in the SAME row: a window containing an old active row and a recent
# inactive one must not be assembled into a PASS out of two different moments.
serving="$(printf '%s\n' "$mine" | grep -F 'server_active=active' | grep -cF 'http_code=200')"
case "$serving" in
  ''|*[!0-9]*) serving=0 ;;
esac

if [[ "$serving" -gt 0 ]]; then
  echo "PASS: ${HOST_NAME} served within ${WINDOW} — ${serving} ${MARKER} row(s) carrying BOTH"
  echo "      server_active=active and http_code=200. #7674 step 4 exit criterion met."
  exit 0
fi

# Not serving. Name the cause from the SAME row when the flag explains it — that one field is
# what turns "the host is down" into "the host was told to stop", and it was sitting unread in
# every one of these rows for 5.4 days.
last="$(printf '%s\n' "$mine" | tail -1)"
active="$(printf '%s' "$last" | grep -oE 'server_active=[^ ]+' | head -1)"
code="$(printf '%s' "$last" | grep -oE 'http_code=[^ ]+' | head -1)"
flag="$(printf '%s' "$last" | grep -oE 'cutover_flag=[^ ]+' | head -1)"

echo "TRANSIENT: reason=not_serving host=${HOST_NAME} ${active:-server_active=?} ${code:-http_code=?} ${flag:-cutover_flag=?}" >&2
case "$flag" in
  *rollback|*rolled-back)
    echo "           The flag EXPLAINS the stop: the flip FSM's rollback arm stopped the unit and" >&2
    echo "           parked at a terminal state, and no restart can release it — only a cutover" >&2
    echo "           window can. This is the expected reading until #7674 step 5 runs." >&2 ;;
  *)
    echo "           The flag does NOT explain the stop. This is a genuine diagnosis rather than" >&2
    echo "           the known brake — see the runbook's 'inactive under a standing rollback'" >&2
    echo "           entry for the discriminator." >&2 ;;
esac
exit 2
