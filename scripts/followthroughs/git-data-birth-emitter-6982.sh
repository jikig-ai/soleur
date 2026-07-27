#!/usr/bin/env bash
#
# Follow-through probe for #6982 — did the git-data boot emitter actually EMIT?
#
# WHY THIS EXISTS. Every gate #6982 ships is STATIC, while the failure class it defends
# against — "green apply, dark host" — is only observable at RUNTIME. Mutation arms prove
# the code CAN go red when neutered; they never prove an event ARRIVES when it is intact.
# The host is unborn at merge, so the only honest close criterion is time-gated: check
# again once a birth has happened.
#
# THREE-STATE CONTRACT (the repo's documented convention — see
# chardevice-wedge-nonrecurrence-5934.sh):
#   0 = PASS      — >= 1 boot_complete event, all four assertions positive.
#   1 = FAIL      — an event exists with a FALSE assertion (the host booted dark).
#   2 = TRANSIENT — the host is still unborn, or the query is unreachable/unauthorised.
#
# "UNBORN IS TRANSIENT, NOT FAIL" IS LOAD-BEARING. Using 1 would post a daily FAIL comment
# from merge+1d until the birth — potentially weeks — byte-identical in kind to the comment
# a genuine post-birth boot failure produces, training the reader to ignore the one signal
# that matters. `REOPEN_MAX` caps only the closed path, so the open path has no brake.
#
# IT READS BETTER STACK, NOT SENTRY, and that is forced rather than chosen: the sweeper
# passes SENTRY_AUTH_TOKEN (from SENTRY_IAC_AUTH_TOKEN), which scripts/sentry-issue.sh's own
# header records as 403-ing on `event:read` — that script needs SENTRY_ISSUE_RO_TOKEN, which
# the sweeper does not pass. The BETTERSTACK_QUERY_* triple below is what the sweeper
# actually has, which is what makes this probe executable AT ALL rather than silently
# failing on an unknown secret name.
#
# It deliberately does NOT read the heartbeat API: `status == "up"` proves reachability,
# the proxy D-HB rejects (a host whose LUKS never mounted still answers on :22).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${REPO_ROOT}/scripts/betterstack-query.sh"

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    echo "TRANSIENT: ${v} is unset — cannot query Better Stack Logs."
    exit 2
  fi
done
[ -x "$QUERY" ] || { echo "TRANSIENT: ${QUERY} not executable"; exit 2; }

# The archive arm is REQUIRED, not belt-and-braces: remote() alone is the ~40-minute hot
# window (measured 2026-07-15), and a once-per-boot marker falls out of it immediately.
# Field isolation via Mode 1 raw SQL — a bare-substring --grep compiles to `raw LIKE '%…%'`
# and the shared source is contaminated by inngest webhook logs quoting issue bodies.
SQL="
  SELECT dt,
         JSONExtractString(raw,'stage')     AS stage,
         JSONExtractString(raw,'host_name') AS host,
         JSONExtractString(raw,'luks_mounted') AS luks_mounted,
         JSONExtractString(raw,'repo_root')    AS repo_root,
         JSONExtractString(raw,'hooks_path')   AS hooks_path,
         JSONExtractString(raw,'provision')    AS provision
  FROM (SELECT * FROM remote(\$BS_TABLE)
        UNION ALL SELECT * FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
  WHERE dt > now() - INTERVAL 30 DAY
    AND JSONExtractString(raw,'stage') = 'boot_complete'
    AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
  ORDER BY dt DESC LIMIT 20"

# Mode 1 (raw SQL) takes the query as the FIRST POSITIONAL and no convenience flags:
# `--since` belongs to Mode 2, and passing both makes the arg parser reject the SQL with
# exit 64 (unknown flag). Measured — the first draft of this probe did exactly that, which
# would have made it exit non-zero forever for a USAGE reason while reading as "still
# waiting". That is the R4 defect (a proven-RED arm satisfied by the wrong cause) in the
# probe written to avoid it. The window therefore lives INSIDE the SQL.
out="$(bash "$QUERY" "$SQL" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "TRANSIENT: betterstack-query.sh exited ${rc} (unreachable or unauthorised)."
  printf '%s\n' "$out" | tail -5
  exit 2
fi

if ! printf '%s' "$out" | grep -q 'boot_complete'; then
  echo "TRANSIENT: no stage:boot_complete from soleur-git-data in the last 30 days."
  echo "The host is presumably still unborn — #6982 shipped the hardening, NOT the birth."
  echo "This flips to PASS on the first birth whose boot emits its completion signal."
  exit 2
fi

# An event with a FALSE assertion is the FAIL case: the bootstrap reached its final stage
# with an invariant unmet, which is precisely the dark boot the interlock exists to catch.
if printf '%s' "$out" | grep -qE '\bno\b'; then
  echo "FAIL: a boot_complete event carries a FALSE assertion — the host booted with an"
  echo "unmet invariant (LUKS mount, repo root, hooksPath or provision wrapper)."
  printf '%s\n' "$out" | head -20
  exit 1
fi

echo "PASS: stage:boot_complete observed from soleur-git-data with all four assertions positive."
printf '%s\n' "$out" | head -5
exit 0
