#!/usr/bin/env bash
# (#6894, AC-33 + AC-34) Did the additive volume actually get STAGED on the host, without
# disturbing the live store?
#
# WHAT IT ASSERTS, and why each half is required:
#   (a) a `SOLEUR_INNGEST_LUKS_STAGE stage=staging_verify` row FROM THIS HOST carrying its
#       MEASUREMENTS — the staging mount's resolved source is the staging mapper, the mapper's
#       sysfs backing is the additive volume's device, and the LIVE mount's source differs. A row
#       whose only content is a stage NAME proves the stage ran, which stays true while the staging
#       path is a directory on the root disk under a mountpoint shadow. That is a recorded root
#       cause in this estate, so the name alone is not accepted.
#   (b) the same host's probe row still pins the PLAINTEXT volume in `data_mount_devid` with Redis
#       active — i.e. the staging arm moved nothing. Without (b), a probe that "passed" would be
#       equally consistent with the staging arm having taken over /mnt/data.
#
# CREDENTIAL POSTURE: the three BETTERSTACK_QUERY_* values, injected by the sweeper's `secrets=`
# clause. No GitHub token is needed and none is used; the probe makes no git call.
#
# EXIT CONTRACT (followthrough-convention.md): 0 = both halves hold; 1 = read succeeded and they do
# not (the normal state until the replace lands); 2 = TRANSIENT; 78 = refused under xtrace.
#
# RETIREMENT: when #6894's staging tracker closes, delete this file and its sibling
# `inngest-luks-cutover-6894.sh`. Nothing else references either.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
HOST="soleur-inngest"
HOST_NAME="soleur-inngest-prd"

if [[ ! -r "$QUERY" ]]; then echo "TRANSIENT: $QUERY missing"; exit 2; fi
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  # Never `: "${VAR:?}"` — that aborts with status 1, which this contract reads as FAIL.
  if [[ -z "${!v:-}" ]]; then echo "TRANSIENT: $v is not set in the probe environment"; exit 2; fi
done

# 48h: retention on this source is 3 days, and a replace is an event an operator watches, so a
# longer window would only admit rows from a PREVIOUS host generation.
ROWS=$(bash "$QUERY" --since 48h --grep SOLEUR_INNGEST_LUKS_STAGE --limit 200 2>&1)
RC=$?
if (( RC != 0 )); then
  # The captured stream includes stderr, and a ClickHouse auth failure echoes the username; the
  # sweeper posts this stdout verbatim as a PUBLIC comment. Only the code may leave this branch.
  echo "TRANSIENT: betterstack-query.sh exited $RC (output withheld — may contain credentials)"
  exit 2
fi

# ECHO ISOLATION. `--grep` compiles to an unanchored LIKE over the one source every host
# multiplexes into, and GitHub webhook payloads reach it — so this issue's own body, quoting the
# marker, is a row. Every row is therefore decoded and pinned to host AND host_name, which a
# webhook payload does not carry, before any field of it is read.
STAGING_OK=$(printf '%s\n' "$ROWS" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | .raw? | fromjson?
  | select(.host == $h and .host_name == $hn)
  | select(.SYSLOG_IDENTIFIER == "inngest-luks-stage")
  | (.message // "") | select(test("stage=staging_verify"))
  | select(test("stg_src=/dev/mapper/inngest-redis-staging"))
  | select(test("stg_backing=[a-z0-9]+"))
  | select(test("stg_dev=[a-z0-9]+"))
  | select(test("live_src="))
  | 1' 2>/dev/null | grep -c '^1$' || true)

# The mapper's backing must BE the additive volume's device, and the live mount must NOT be the
# staging mapper. Both are read off the same row, so they cannot be satisfied by two different boots.
CONSISTENT=$(printf '%s\n' "$ROWS" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | .raw? | fromjson?
  | select(.host == $h and .host_name == $hn)
  | (.message // "") | select(test("stage=staging_verify"))
  | . as $m
  | ($m | capture("stg_backing=(?<b>[^ ]+)").b) as $back
  | ($m | capture("stg_dev=(?<d>[^ ]+)").d) as $dev
  | ($m | capture("live_src=(?<l>[^ ]+)").l) as $live
  | select($back == $dev and ($live | test("inngest-redis-staging") | not))
  | 1' 2>/dev/null | grep -c '^1$' || true)

PROBE_ROWS=$(bash "$QUERY" --since 48h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 200 2>&1)
RC=$?
if (( RC != 0 )); then
  echo "TRANSIENT: the probe-row read exited $RC (output withheld)"
  exit 2
fi
# (b) the live store was NOT disturbed: a dedicated-host row whose data_mount_devid still pins a
# volume alias and whose Redis is active. The alias is not compared to a literal here — the probe
# cannot know the id — but a staging takeover would show the MAPPER, which has no by-id alias at
# all and reports __NOMATCH__.
UNDISTURBED=$(printf '%s\n' "$PROBE_ROWS" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | .raw? | fromjson?
  | select(.host == $h and .host_name == $hn)
  | (.message // "") | select(test("host_role=dedicated "))
  | select(test("redis_active=active|redis_active=true"))
  | select(test("data_mount_devid=scsi-0HC_Volume_[0-9]+ "))
  | 1' 2>/dev/null | grep -c '^1$' || true)

echo "staging_verify rows (with measurements): ${STAGING_OK}"
echo "…of which internally consistent (backing == device, live != staging): ${CONSISTENT}"
echo "undisturbed dedicated probe rows (plaintext alias pinned, redis active): ${UNDISTURBED}"

if [[ "$STAGING_OK" -ge 1 && "$CONSISTENT" -ge 1 && "$UNDISTURBED" -ge 1 ]]; then
  echo "PASS: the additive volume is staged, measured, and the live store is untouched (#6894 AC-33/34)"
  exit 0
fi
echo "not yet: the replace that stages the additive volume has not produced a measured staging_verify row from this host (or the live store no longer reads plaintext+active)"
exit 1
