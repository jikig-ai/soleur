#!/usr/bin/env bash
# follow-through probe: AC12 live placement verification for #9137 / PR #12554.
#
# Asserts Better Stack `placement_decision` rows (feature=inngest-exec-placement)
# show the intended split after the forwarder deploys:
#   * at least one row with decision=forward AND host_ip != 10.0.1.10 — a pinned
#     step call that LANDED on a non-exec host was forwarded;
#   * at least one row with decision=execute AND host_ip = 10.0.1.10 — the exec
#     host executed (directly or via the marked forward).
#
# Exit 0 = evidence present (the sweeper may close the tracker).
# Exit 1 = still soaking (no qualifying rows yet).
# Exit 2 = TRANSIENT (query layer failed; do not grade the product).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${PLACEMENT_FT_QUERY:-${REPO_ROOT}/scripts/betterstack-query.sh}"
WINDOW="${PLACEMENT_FT_WINDOW:-24h}"
EXEC_HOST_IP="10.0.1.10"

[[ -x "$QUERY" ]] || { echo "TRANSIENT: ${QUERY} is not executable"; exit 2; }

qerr=$(mktemp)
trap 'rm -f "$qerr"' EXIT

# Field-isolate on CONTAINER_NAME (load-bearing per the betterstack-emitter
# rule): `placement_decision` is also an ordinary word in issue/PR bodies that
# ride the doppler webhook rows to the same source — only a container-emitted
# row proves an app emission. The app runs `--log-driver journald` with no
# `--log-opt tag`, so journald SYSLOG_IDENTIFIER is the rotating container
# short ID (a new value every deploy), while CONTAINER_NAME carries the
# declared `--name` and is absent on host-journald rows (doppler included).
# The structured payload is `.message_json` (the vector-parsed pino object);
# `.message` in these rows is an unrelated deprecation/quotation line.
APP_ID="soleur-web-platform"

raw="$("$QUERY" --since "$WINDOW" --grep placement_decision --limit 5000 2>"$qerr")" || {
  rc=$?
  echo "TRANSIENT: betterstack-query.sh exited ${rc}: $(head -c 600 "$qerr")"
  exit 2
}

# The filter is TOTAL (the zot-log-channel-7440 idiom): `fromjson?` at both
# levels and `objects` guards mean one malformed or non-JSON `.raw` line drops
# that row instead of aborting the stream mid-window — rows are dt-ASC, so an
# abort would silently drop the NEWEST evidence and grade a decode failure as
# exit-1 "still soaking". Predicate decisions in jq, not grep: failed forwards
# (`.err` present, placement.forward_failed) are excluded — a broken forwarder
# must not satisfy the forward arm — and host_ip must be a landed string so a
# null never counts as off-exec. Output is exact FWD/EXE labels only.
rows="$(printf '%s\n' "$raw" | jq -Rr --arg id "$APP_ID" --arg exec "$EXEC_HOST_IP" '
  fromjson? | .raw? | fromjson? | objects
    | select(.CONTAINER_NAME == $id)
    | (.message_json // {}) | objects
    | select(.event == "placement_decision")
    | select(has("err") | not)
    | select(.host_ip? | type == "string")
    | if .decision == "forward" and .host_ip != $exec then "FWD"
      elif .decision == "execute" and .host_ip == $exec then "EXE"
      else empty end')" || {
  echo "TRANSIENT (window=${WINDOW}): placement_decision row decode failed"
  exit 2
}

fwd="$(printf '%s\n' "$rows" | grep -c '^FWD$' || true)"
exe="$(printf '%s\n' "$rows" | grep -c '^EXE$' || true)"

if (( fwd > 0 && exe > 0 )); then
  echo "placement_decision split verified (window=${WINDOW}): forward rows off-exec=${fwd}; execute rows on ${EXEC_HOST_IP}=${exe}"
  exit 0
fi

echo "still soaking (window=${WINDOW}): forward-off-exec=${fwd} execute-on-${EXEC_HOST_IP}=${exe} — pinned-call traffic may not have hit the forwarder yet"
exit 1
