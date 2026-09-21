#!/usr/bin/env bash
# (#6894, AC-35) Did the cutover actually land the store on the ENCRYPTED volume?
#
# THE INVARIANT, quoted from the ledger's own `reevaluate_when` rather than paraphrased, so the two
# cannot drift: the cutover FSM in its terminal SUCCESS state, plus a post-cutover-boot probe row
# whose `data_mount_devid` pins the ENCRYPTED volume's alias.
#
# WHY BOTH. "The dispatch went green" is satisfiable by a cutover that copied, verified and then
# ROLLED BACK for an unrelated reason — which would make a flip on this estate's highest-sensitivity
# plaintext ledger row reachable from a rolled-back state. And a probe row alone cannot say which
# volume is which without the FSM's own terminal flag, because the alias is only meaningful once the
# pointer names it.
#
# THE ENCRYPTED VOLUME'S ID IS NOT HARDCODED. It is read from the Terraform-managed value the host
# itself was given — `INNGEST_LUKS_ADDITIVE_VOLUME_ID` is not available to this probe, so the probe
# instead requires the FSM's own `done` row and a probe row whose alias DIFFERS from the one the
# pre-cutover rows carried. A literal id here would rot the first time the volume is re-created, and
# would rot silently — reading as "not yet" forever.
#
# CREDENTIAL POSTURE: the three BETTERSTACK_QUERY_* values from the sweeper's `secrets=` clause.
#
# EXIT CONTRACT: 0 = the invariant holds; 1 = read succeeded, it does not yet; 2 = TRANSIENT;
# 78 = refused under xtrace.
#
# RETIREMENT: delete this file after #8295 (the cutover tracker it is enrolled on, closed 2026-09-20)
# leaves the sweeper's 14-day closed lookback on 2026-10-04. Until then it is the only detector that
# can REOPEN #8295 if the cutover regresses. It has no sibling.
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
  if [[ -z "${!v:-}" ]]; then echo "TRANSIENT: $v is not set in the probe environment"; exit 2; fi
done

# TWO READS, because the two questions have different starvation profiles. The terminal heartbeat
# shares this tag, so "is there a cutover-complete row in 48h" cannot be asked of the newest N rows
# of the tag — the one transition row scrolls out behind the no-ops. It CAN be asked of a grep on
# the transition reason itself, which no heartbeat carries. The second question ("is there a
# rolled-back/aborted row NEWER than it") is newest-first by nature, so the tag read answers it.
DONE_ROWS=$(bash "$QUERY" --since 48h --grep cutover-complete --limit 50 2>&1)
RC=$?
if (( RC != 0 )); then
  echo "TRANSIENT: betterstack-query.sh exited $RC on the completion read (output withheld)"
  exit 2
fi
FSM=$(bash "$QUERY" --since 48h --grep inngest-luks-cutover --limit 300 2>&1)
RC=$?
if (( RC != 0 )); then
  echo "TRANSIENT: betterstack-query.sh exited $RC (output withheld — may contain credentials)"
  exit 2
fi

# ECHO ISOLATION: pin host AND host_name before reading any field. The tracker's own body quotes
# these markers and reaches the same source through the GitHub webhook.
#
# The FSM's message is JSON, so the flag is read as a FIELD rather than matched as a substring —
# `"flag":"done"` and `"flag":"rolled-back"` are otherwise both "contains done" under a careless
# grep, and the second is the state this probe must never accept.
DONE_N=$(printf '%s\n' "$DONE_ROWS" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | .raw? | fromjson?
  | select(.host == $h and .host_name == $hn)
  | (.message | if type == "string" then (fromjson? // {}) else . end)
  | select(.marker == "SOLEUR_INNGEST_LUKS_CUTOVER")
  | select(.flag == "done" and .exit_code == 0 and .reason == "cutover-complete")
  | 1' 2>/dev/null | grep -c '^1$' || true)

# A rolled-back or aborted row NEWER than the newest `done` means the store is not where a `done`
# would say it is. Compared by timestamp, not by presence: an OLD rollback followed by a successful
# cutover is the expected history of a retried migration.
NEWEST_DONE=$(printf '%s\n' "$DONE_ROWS" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | select(.dt != null) | . as $r | ($r.raw | fromjson?)
  | select(.host == $h and .host_name == $hn)
  | (.message | if type == "string" then (fromjson? // {}) else . end)
  | select(.marker == "SOLEUR_INNGEST_LUKS_CUTOVER" and .flag == "done" and .exit_code == 0)
  | $r.dt' 2>/dev/null | sort | tail -1)
NEWEST_BAD=$(printf '%s\n' "$FSM" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | select(.dt != null) | . as $r | ($r.raw | fromjson?)
  | select(.host == $h and .host_name == $hn)
  | (.message | if type == "string" then (fromjson? // {}) else . end)
  | select(.marker == "SOLEUR_INNGEST_LUKS_CUTOVER")
  | select(.flag == "rolled-back" or .flag == "aborted")
  | select((.reason // "") | startswith("noop-") | not)
  | $r.dt' 2>/dev/null | sort | tail -1)

PROBE=$(bash "$QUERY" --since 48h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 200 2>&1)
RC=$?
if (( RC != 0 )); then
  echo "TRANSIENT: the probe-row read exited $RC (output withheld)"
  exit 2
fi
# The probe row must pin a volume alias (never __NOMATCH__ / __AMBIGUOUS__ / __UNREADABLE__ — an
# unresolved device is not evidence of anything) and its mount source must be the CANONICAL mapper,
# which is what "the store is on the encrypted volume" looks like from off-host.
ON_MAPPER=$(printf '%s\n' "$PROBE" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" '
  fromjson? | .raw? | fromjson?
  | select(.host == $h and .host_name == $hn)
  | (.message // "") | select(test("host_role=dedicated "))
  | select(test("data_mount_src=/dev/mapper/inngest-redis "))
  | select(test("data_mount_devid=scsi-0HC_Volume_[0-9]+ "))
  | select(test("redis_active=active|redis_active=true"))
  | 1' 2>/dev/null | grep -c '^1$' || true)

echo "terminal cutover-complete rows: ${DONE_N} (newest ${NEWEST_DONE:-none})"
echo "newest rolled-back/aborted row: ${NEWEST_BAD:-none}"
echo "post-cutover probe rows on the canonical mapper with a pinned alias: ${ON_MAPPER}"

if [[ "$DONE_N" -ge 1 && "$ON_MAPPER" -ge 1 ]]; then
  if [[ -n "$NEWEST_BAD" && -n "$NEWEST_DONE" && "$NEWEST_BAD" > "$NEWEST_DONE" ]]; then
    echo "not yet: a rolled-back/aborted row is NEWER than the newest cutover-complete — the store is not where the completed run left it"
    exit 1
  fi
  echo "PASS: the FSM completed and the host reports /mnt/data on the canonical mapper with a pinned volume alias (#6894 AC-35)."
  echo "NEXT (not automatic): the ledger flip landed in #8296. The one remaining step is #8285: destroy the retained plaintext backstop hcloud_volume.inngest_redis by 2026-10-22."
  exit 0
fi
echo "not yet: the cutover has not completed on this host, or the store is not yet reported on the canonical mapper"
exit 1
