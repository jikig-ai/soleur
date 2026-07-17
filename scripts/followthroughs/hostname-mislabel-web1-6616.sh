#!/usr/bin/env bash
# Follow-through verification for #6616 — host_name telemetry mislabel (a web host
# self-labels the dedicated Inngest node's host_name in Better Stack source 2457081).
#
# WHAT IT PROVES. web-1 booted in the pre-#6344 co-located-Inngest era and runs an
# inngest-owned vector.service whose config was sed-rendered `host_name=soleur-inngest-prd`
# (inngest-bootstrap.sh). Under `lifecycle{ignore_changes=[user_data]}` it never re-ran
# cloud-init to pick up #6396's per-host `host_name`, and the web-install skip-guard refuses
# to re-render while the inngest-owned unit exists. So web-1 ships its telemetry stamped
# `host_name=soleur-inngest-prd` while its OS hostname (`host`, Vector auto-derived) is
# `soleur-web-platform` — colliding with the dedicated Inngest node on the sole per-host
# discriminator. The physical fix is a web-1 immutable recreate (blocked: no web-1-recreate
# dispatch target; cx33 unorderable; ADR-119 §(e)); this follow-through auto-closes #6616
# once that recreate lands and the stale label clears.
#
# IDENTITY, NOT CARDINALITY (and NOT the plan's assumed constant). The #6616 diagnosis
# (2026-07-17, live) refuted the deepened plan's assumption that the dedicated node's
# telemetry `host` = `soleur-inngest-server-prd` (that is the Hetzner *resource* name from
# inngest.tf:291 and NEVER appears in telemetry). The dedicated node's real OS hostname is
# `soleur-inngest`, authoritatively identified by its service fingerprint (it ships the
# `inngest-heartbeat` service). A pure allowlist keyed on the dedicated node would false-FAIL
# forever on that node's own generic early-boot rows (`host=Ubuntu-2404-noble-64-minimal`,
# kernel-only, reappears every reboot before the hostname is set). So the check keys FAIL on
# the authoritative WEB-host identities (server.tf:225) that must never wear the Inngest
# label — the exact bug the issue names — and requires a positive dedicated-node liveness
# marker before any PASS (#5934 vacuous-GREEN guard).
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (soleur-inngest-prd emitted only by the dedicated node AND the dedicated
#                   node is live in-window; sweeper closes #6616)
#   1 = FAIL       (a web host — soleur-web-platform/soleur-web-2 — still emits
#                   soleur-inngest-prd; the collision is live; sweeper leaves #6616 open)
#   2 = TRANSIENT  (creds/query fault, OR no dedicated-node liveness marker in-window —
#                   source dark / `host` field renamed → all-empty; never a false PASS)
#
# Read-only: this script NEVER mutates GitHub state (the sweeper posts the comment/close).
#
# Required env (read by scripts/betterstack-query.sh): BETTERSTACK_QUERY_HOST,
#   BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD (already wired in
#   scheduled-followthrough-sweeper.yml). Optional: HOSTNAME_MISLABEL_WINDOW (Nh/Nm/Nd,
#   default 24h), HOSTNAME_MISLABEL_BQ (path to the query script, for tests).
#
# Directive for the tracking issue (#6616) body:
#   <!-- soleur:followthrough script=scripts/followthroughs/hostname-mislabel-web1-6616.sh
#     earliest=<merge+90d UTC> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

set -uo pipefail

# --- Pinned identities (authoritative sources, NOT the possibly-poisoned query output) ---
MISLABEL_HOST_NAME="soleur-inngest-prd"          # the stale literal (inngest-bootstrap.sh sed)
DEDICATED_HOST="soleur-inngest"                  # dedicated node OS hostname (live inngest-heartbeat fingerprint, 2026-07-17)
# Web-host OS-hostname/host_name map from apps/web-platform/infra/server.tf:225
# (name/host_name = each.key=="web-1" ? "soleur-web-platform" : "soleur-${each.key}").
WEB_HOSTS=("soleur-web-platform" "soleur-web-2")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BQ="${HOSTNAME_MISLABEL_BQ:-$SCRIPT_DIR/../betterstack-query.sh}"
WINDOW="${HOSTNAME_MISLABEL_WINDOW:-24h}"

if ! [[ "$WINDOW" =~ ^([0-9]+)([hmd])$ ]]; then
  echo "TRANSIENT: invalid HOSTNAME_MISLABEL_WINDOW '$WINDOW' (expected Nh/Nm/Nd)" >&2
  exit 2
fi
case "${BASH_REMATCH[2]}" in h) IVL="HOUR";; m) IVL="MINUTE";; d) IVL="DAY";; esac
WIN_N="${BASH_REMATCH[1]}"

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# Identity query — host_name × host × count over the window (hot + s3 archive, deduped via
# _row_type=1 per betterstack-query.sh §Query mechanics). Raw-SQL mode substitutes
# $BS_TABLE / $BS_TABLE_S3. FORMAT JSONEachRow → one object per line.
ROWS="$("$BQ" "
  SELECT JSONExtractString(raw,'host_name') AS host_name,
         JSONExtractString(raw,'host')      AS host,
         count() AS n
  FROM ( SELECT raw FROM remote(\$BS_TABLE) WHERE dt > now() - INTERVAL ${WIN_N} ${IVL}
         UNION ALL
         SELECT raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt > now() - INTERVAL ${WIN_N} ${IVL} )
  GROUP BY host_name, host ORDER BY host_name, n DESC FORMAT JSONEachRow" 2>/dev/null)"
bq_rc=$?
if [[ "$bq_rc" -ne 0 ]]; then
  echo "TRANSIENT: Better Stack query failed (exit $bq_rc — creds unset / auth / network / query fault)" >&2
  exit 2
fi

# Collision rows: host_name == the mislabel literal AND host is a KNOWN WEB identity.
# The WEB_HOSTS bash array is marshalled into a jq array via --argjson; empty ROWS → jq
# reads empty stdin → prints nothing (→ no collision, correct).
COLLISIONS="$(printf '%s\n' "$ROWS" | jq -r \
  --arg m "$MISLABEL_HOST_NAME" \
  --argjson web "$(printf '%s\n' "${WEB_HOSTS[@]}" | jq -R . | jq -s .)" \
  'select(.host_name == $m and (.host as $h | $web | index($h))) | .host' 2>/dev/null | sort -u)"

# Schema-liveness marker: >=1 row whose host == the dedicated node (present, non-empty).
# Guards the "source dark" and "host field renamed → all-empty → vacuous GREEN" false-closes.
LIVENESS="$(printf '%s\n' "$ROWS" | jq -r \
  --arg d "$DEDICATED_HOST" 'select(.host == $d) | .host' 2>/dev/null | grep -c . || true)"

# FAIL takes precedence: a live web-host collision is unambiguous regardless of liveness
# (covers the single-emitter case where the dedicated node is momentarily silent).
if [[ -n "$COLLISIONS" ]]; then
  COLLISION_LIST="$(printf '%s' "$COLLISIONS" | tr '\n' ' ')"
  echo "FAIL: host_name=${MISLABEL_HOST_NAME} is still emitted by web host(s) [${COLLISION_LIST}] in the last ${WINDOW} — the #6616 collision is live. Resolution is a web-1 immutable recreate (deferred; blocked per ADR-119 §(e))."
  exit 1
fi

# Liveness gate on the PASS path — never PASS on a dark source / drifted schema.
if [[ "$LIVENESS" -eq 0 ]]; then
  echo "TRANSIENT: no dedicated-node liveness marker (host=${DEDICATED_HOST}) in the last ${WINDOW} — source dark or 'host' field drifted/empty; cannot confirm a clean state without vacuous GREEN (#5934)" >&2
  exit 2
fi

echo "PASS: host_name=${MISLABEL_HOST_NAME} emitted only by the dedicated node (host=${DEDICATED_HOST}) over the last ${WINDOW}; no web-host collision. web-1 recreate cleared the stale label — closing #6616."
exit 0
