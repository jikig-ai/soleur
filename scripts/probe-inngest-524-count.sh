#!/usr/bin/env bash
# Discoverability probe for the #8611 inngest-step-524 alert: prints `count=<n>`, the number of
# inngest-server journald rows in the last 24 h whose message.error carries a proxy-timeout
# literal. `count=0` is the healthy steady state after #8611.
#
# Why this is a script and not an inline command: preflight Check 10 executes the plan's
# `discoverability_test.command` via `bash -c` inside a bwrap sandbox and rejects every
# shell-active token (`|`, `>`, `&&`, …). A raw betterstack-query.sh call returns JSONEachRow,
# which needs a pipe to reduce to one line; this wrapper does the reduction itself.
#
# SINGLE SOURCE. The unit scope and the needle array are read from the alert's own SQL local
# (`inngest_step_524_sql` in apps/web-platform/infra/betterstack-logs-alerts.tf), so this probe and
# the paging rule can never count different things. The alert queries `{{source}}`; this probe
# queries the same source's hot table UNION ALL its S3 archive, because `remote()` alone covers only
# the last hour or so (runbooks/betterstack-log-query.md).
#
# Credentials: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}, e.g.
#   doppler run -p soleur -c prd_terraform -- bash scripts/probe-inngest-524-count.sh
#
# Exit: 0 with `count=<n>` on a measured answer; non-zero with NO count line when the answer could
# not be measured (missing creds, query failure, unparseable result, or the SQL local not found).
# A failed measurement never prints `count=0`.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

TF=apps/web-platform/infra/betterstack-logs-alerts.tf
SQL_BODY="$(awk '/^[[:space:]]*inngest_step_524_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
UNIT="$(printf '%s\n' "$SQL_BODY" | grep -oE "JSONExtractString\(raw, '_SYSTEMD_UNIT'\) = '[a-z0-9.@-]+'" | head -1)"
NEEDLES="$(printf '%s\n' "$SQL_BODY" | grep -oE "multiSearchAny\(JSONExtractString\(raw, 'message', 'error'\), \[[^]]+\]\)" | head -1)"
if [ -z "$UNIT" ] || [ -z "$NEEDLES" ]; then
  printf 'probe-inngest-524-count: could not read the unit scope / needle array from %s (inngest_step_524_sql)\n' "$TF" >&2
  exit 2
fi

QUERY="SELECT count() AS n FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1) WHERE dt > now() - INTERVAL 24 HOUR AND ${UNIT} AND ${NEEDLES} FORMAT JSONEachRow"

OUT="$(bash scripts/betterstack-query.sh "$QUERY")"
rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'probe-inngest-524-count: betterstack-query.sh exited %s — no measurement\n' "$rc" >&2
  exit "$rc"
fi

N="$(printf '%s\n' "$OUT" | python3 -c 'import json,sys
rows=[json.loads(l) for l in sys.stdin if l.strip()]
assert len(rows)==1, f"expected one row, got {len(rows)}"
n=int(rows[0]["n"])
assert n>=0
print(n)')"
prc=$?
if [ "$prc" -ne 0 ] || [ -z "$N" ]; then
  printf 'probe-inngest-524-count: unparseable result — no measurement\n' >&2
  exit 3
fi
printf 'count=%s\n' "$N"
