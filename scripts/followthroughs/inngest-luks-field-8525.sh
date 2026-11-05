#!/usr/bin/env bash
# #8525 — the ledger's live LUKS verdict flips when the schema-9 probe row says crypto_LUKS.
#
# TRACKER: **#8525**. It stays OPEN until this reads PASS (the sweeper lists `--state open`).
#
# WHAT IT VERIFIES — POSITIVELY, NEVER BY ABSENCE. PASS requires an observed
# SOLEUR_INNGEST_SERVER_PROBE row from THE SERVING dedicated host carrying BOTH
# `probe_schema=9` AND `data_luks=crypto_LUKS` in the SAME row. `probe_schema=9` alone is not
# the verdict (a field that resolved `__UNREADABLE__` still carries schema 9), and
# `data_luks=crypto_LUKS` alone is not the verdict (it must be the schema-9 row's field). The
# pairing is the follow-through condition the issue names.
#
# HOST ISOLATION IS MANDATORY — same reasoning as inngest-host-not-serving-7674.sh: the probe
# renderer is shared, every host multiplexes into the one Logs source, and `host_name` alone
# can lie (#6616 is OPEN), so the host pair is required. web-1's schema-9 rows carry
# `data_luks=n/a`, which cannot satisfy the conjunct by accident — the field's n/a sentinel
# exists for exactly that.
#
# DECODE BEFORE FILTER. ClickHouse stores `raw` DOUBLE-ENCODED; matching `data_luks` against the
# outer row matches nothing ever. Filter on the decoded .message, as the sibling probe does.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       an observed serving-host row with probe_schema=9 AND data_luks=crypto_LUKS.
#   2 = TRANSIENT  host not yet emitting schema 9 (the emitter is a baked carrier — it lands on
#                  the next image+host replace), channel dark, credentials unprovisioned, or any
#                  query/decode failure. Each prints a DISTINCT reason.
#   1 = FAIL       RESERVED, deliberately unreachable: "the replace has not run yet" is a WAIT.
#
# `earliest=` is set to the next replace + 1 day for the same reason as the sibling probe.
#
# THE `${VAR:?msg}` FORM IS BANNED (sweep runs `env -i`; the abort reads as FAIL). Required env
# is named LITERALLY below. NO `set -e` — failures are routed explicitly.
set -uo pipefail

# #7797: refuse to run under xtrace while a live warehouse credential is bound.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QUERY="${INNGEST_SERVING_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"
INNGEST_HOST="${INNGEST_HOST:-soleur-inngest}"
HOST_NAME="${INNGEST_HOST_NAME:-soleur-inngest-prd}"
WINDOW="${FOLLOWTHROUGH_WINDOW:-30d}"
LIMIT="${FOLLOWTHROUGH_LIMIT:-200}"
INNGEST_PROBE_MARKER="SOLEUR_INNGEST_SERVER_PROBE"

# The shared emitter/probe predicates (the same jq def the dark gate and the sibling probe use).
# Same load contract as inngest-host-not-serving-7674.sh: unset the names, source the lib, prove
# the loaded def passes its selftest — a selector that defines nothing is NOT channel_dark.
unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER
_ipr_lib="${INNGEST_PROBE_ROW_LIB:-$REPO_ROOT/scripts/lib/inngest-probe-row.sh}"
# shellcheck source=scripts/lib/inngest-probe-row.sh
if ! source "$_ipr_lib" || ! declare -F inngest_probe_row_selftest >/dev/null || ! inngest_probe_row_selftest; then
  echo "TRANSIENT: reason=selector_unavailable lib=${_ipr_lib} — the probe-row predicate did not load or failed its selftest." >&2
  exit 2
fi

# --- credentials ------------------------------------------------------------------------------
missing=""
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "$(eval "printf '%s' \"\${$v:-}\"")" ]; then missing="${missing:+$missing }$v"; fi
done
if [ -n "$missing" ]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — missing:${missing}." >&2
  echo "           Nothing about the host was measured; the probe could not ask the question." >&2
  exit 2
fi

# --- one query --------------------------------------------------------------------------------
rows="$("$QUERY" --since "$WINDOW" --grep "$INNGEST_PROBE_MARKER" --limit "$LIMIT" 2>/dev/null)"
qrc=$?
if [[ "$qrc" -ne 0 ]]; then
  echo "TRANSIENT: reason=query_failed rc=${qrc} — the ClickHouse read path did not answer." >&2
  exit 2
fi

# Decode, then isolate on the DECODED object (the sibling probe's two-level fromjson? shape;
# a malformed line must not eat the whole window's rows).
mine="$(printf '%s\n' "$rows" \
  | jq -R -r --arg h "$INNGEST_HOST" --arg hn "$HOST_NAME" \
       "$INNGEST_PROBE_ROW_JQ"'
        fromjson? | .raw? | fromjson?
        | select(type == "object")
        | select(.host == $h and .host_name == $hn)
        | select(inngest_probe_row)
        | .message' 2>/dev/null)"
jrc=$?
if [[ "$jrc" -ne 0 ]]; then
  echo "TRANSIENT: reason=selector_failed jq_rc=${jrc} — the row selector did not run." >&2
  exit 2
fi
if [[ -z "$mine" ]]; then
  echo "TRANSIENT: reason=channel_dark host=${INNGEST_HOST}/${HOST_NAME} window=${WINDOW} — zero ${INNGEST_PROBE_MARKER} rows." >&2
  exit 2
fi

# --- the POSITIVE discriminator ---------------------------------------------------------------
# BOTH tokens in the SAME row, each with its token boundary: `probe_schema=9( |$)` does not match
# `probe_schema=9x`, and `data_luks=crypto_LUKS( |$)` is the exact accepting value the ledger's
# live_verification reads. `data_luks=n/a` (web rows) and `data_luks=__UNREADABLE__` cannot pass.
# The conjunct is read off the NEWEST schema-9 row, not any row in the window —
# an hourly emitter overflows the row limit, so an any-row PASS would keep the
# gate green for days after a replace onto a non-LUKS disk (review P3).
newest9="$(printf '%s\n' "$mine" | grep -E 'probe_schema=9( |$)' | tail -1)"
ok="$(printf '%s' "$newest9" | grep -cE 'data_luks=crypto_LUKS( |$)')"
case "$ok" in ''|*[!0-9]*) ok=0 ;; esac

if [[ "$ok" -gt 0 ]]; then
  echo "PASS: ${HOST_NAME}'s newest schema-9 row carries data_luks=crypto_LUKS."
  echo "      #8525's live verdict holds: /mnt/data rides a LUKS container on the serving host."
  exit 0
fi

# Not met. Name the reading from the newest row so a TRANSIENT says WHICH conjunct failed.
last="$(printf '%s\n' "$mine" | tail -1)"
schema="$(printf '%s' "$last" | grep -oE 'probe_schema=[^ ]+' | head -1)"
luks="$(printf '%s' "$last" | grep -oE 'data_luks=[^ ]+' | head -1)"

echo "TRANSIENT: reason=not_schema9_luks host=${INNGEST_HOST}/${HOST_NAME} ${schema:-probe_schema=?} ${luks:-data_luks=(absent)}" >&2
case "$schema" in
  probe_schema=9)
    echo "           The row IS schema 9, so the emitter replaced already; the data_luks read" >&2
    echo "           itself did not resolve to crypto_LUKS — read the emitted value before" >&2
    echo "           treating this as 'replace not landed'." >&2 ;;
  "")
    echo "           No probe_schema field: the host predates schema-3 emission entirely." >&2 ;;
  *)
    echo "           The emitter is a BAKED carrier: ${schema:-?} means the replace that carries" >&2
    echo "           schema 9 has not reached this host. Replacing on an unbumped pin re-delivers" >&2
    echo "           the same bytes — the pin must carry the emitter first (see #8525)." >&2 ;;
esac
exit 2
