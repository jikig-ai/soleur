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

# Field-isolate on SYSLOG_IDENTIFIER (load-bearing per the betterstack-emitter
# rule): `placement_decision` is also an ordinary word in issue/PR bodies that
# ride the doppler webhook rows to the same source — only the container's own
# journald identifier proves the row is an app emission.
APP_ID="soleur-web-platform"

raw="$("$QUERY" --since "$WINDOW" --grep placement_decision --limit 5000 2>"$qerr")" || {
  rc=$?
  echo "TRANSIENT: betterstack-query.sh exited ${rc}: $(head -c 600 "$qerr")"
  exit 2
}

rows="$(printf '%s\n' "$raw" | jq -r --arg id "$APP_ID" '
  .raw | fromjson | select(.SYSLOG_IDENTIFIER == $id) | .message' \
  | grep 'placement_decision' || true)"

fwd="$(printf '%s\n' "$rows" | grep '"forward"' \
  | grep -cv "\"host_ip\":[[:space:]]*\"${EXEC_HOST_IP}\"" || true)"
exe="$(printf '%s\n' "$rows" | grep '"execute"' \
  | grep -c "\"host_ip\":[[:space:]]*\"${EXEC_HOST_IP}\"" || true)"

if (( fwd > 0 && exe > 0 )); then
  echo "placement_decision split verified (window=${WINDOW}): forward rows off-exec=${fwd}; execute rows on ${EXEC_HOST_IP}=${exe}"
  exit 0
fi

echo "still soaking (window=${WINDOW}): forward-off-exec=${fwd} execute-on-${EXEC_HOST_IP}=${exe} — pinned-call traffic may not have hit the forwarder yet"
exit 1
