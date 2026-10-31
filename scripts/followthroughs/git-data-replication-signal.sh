#!/usr/bin/env bash
#
# Read-only signal for "zero replication-success markers while sessions are live" (#11704 item 6, CTO ruling F6, Guard 4).
#
# WHAT IT READS. Two kinds of Better Stack row from the two web hosts, aggregated IN SQL so no row body and no host name ever
# reaches this script's output (counts and ages only):
#   * the per-host quiet-window reporter line (apps/web-platform/server/quiet-window.ts), once a minute:
#       agent_sessions_live=N cc_queries=N legacy_sessions=N starting=N new_sessions_paused=<0|1> refused_since_last=N
#   * the replication-success marker (apps/web-platform/server/git-data-replication.ts), once per successful push:
#       git_data_replication_success=1 transient_retried=<0|1>
# The window is the hot table UNION the archive (the hot window is only about 40 minutes).
#
# WHAT IT PRINTS. One `host=<web-1|web-2> host_verdict=<TOKEN> markers=N reporter_rows=N live_rows=N newest_live=N
# last_live_age_s=<N|none>` line per host, then ONE overall line `verdict=<TOKEN> exit=<N> since=<window>`. The overall verdict is
# the worst of the two hosts (a healthy host never masks a silent one). CALLERS BRANCH ON THE FINAL `verdict=<TOKEN> exit=<N> since=...`
# LINE (the token), never on the numeric exit order: the codes are labels, not a severity scale (1 is the alarm, 2 outranks it).
#
# VERDICTS, WORST FIRST, WITH THE EXIT CODE:
#   READ_UNCLEAN                 2  a read failed, its answer was not clean integers, or a host has no reporter row in the window.
#                                   Outranks everything: "could not measure" is a probe fault, never a measurement, and a missing
#                                   reporter row is never read as "no sessions".
#   ZERO_MARKERS_WITH_SESSIONS   1  the alarm: a reporter row with agent_sessions_live>0 in the window, the NEWEST reporter row
#                                   reads 0, the last live row is at least 10 minutes old (the window has settled) and ZERO markers
#                                   on that host. Sessions ended and nothing replicated (or the image lacks the marker).
#   PENDING                      3  a live row and zero markers, but the newest reporter row still reads live or the last live row
#                                   is under 10 minutes old: the sessions may not have ended yet. Re-read later.
#   NO_SESSIONS                  4  inconclusive, NEVER a pass: reporter rows present, no live session in the window, no marker.
#   MARKERS_PRESENT              0  the ONLY positive evidence. Every host that is not silent has markers: a host with markers is
#                                   MARKERS_PRESENT; a host with no live row and no marker is NO_SESSIONS and is set aside only when
#                                   the other host is MARKERS_PRESENT (it has nothing to prove). It is never set aside beside a
#                                   host that is PENDING, ZERO_MARKERS_WITH_SESSIONS or READ_UNCLEAN.
#                                   MARKERS_PRESENT means AT LEAST ONE replication landed on that host in the window. It is not
#                                   evidence for every user or every session: one synthetic account can satisfy it, so a go/no-go
#                                   also needs the per-user read (runbook R3). `markers` is presence evidence, not a count (the
#                                   emitter caps one marker per 60 s per process per transient_retried value).
# Other exits: usage or a missing tool 64; shell tracing with a live credential 78; interrupted 130 (INT) or 143 (TERM/HUP).
# Only MARKERS_PRESENT exits 0.
#
# THE MARKER EXISTS ONLY ON IMAGES FROM THE RELEASE THAT CARRIES IT: read /health first. Before that release this reads
# NO_SESSIONS or ZERO_MARKERS_WITH_SESSIONS, which says nothing about replication. It is meaningful only while the store flag is
# on and for sessions that connected a repository. It never counts a row from a non-web host (a CI job that merely printed the
# phrase is not an occurrence, #6475).
#
# READ-ONLY. One SELECT through scripts/betterstack-query.sh; no write, no dispatch, no Doppler access of its own. An agent may run it
# (counts and ages only; it needs the caller's read-only Doppler prd_terraform access for the Better Stack query credentials). The
# credentials are injected by the caller and travel only in the reader's environment:
#   doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD \
#     --no-exit-on-missing-only-secrets -- scripts/followthroughs/git-data-replication-signal.sh --since 15m
# NOT A FOLLOW-THROUGH PROBE: never enrol it in a tracker (exit 0 here would render as PASS and close an issue).
#
# --since <window>: Nm | Nh | Nd (1-4 digits) or an absolute UTC stamp (YYYY-MM-DDTHH:MM:SSZ or 'YYYY-MM-DD HH:MM:SS').
set -uo pipefail

# (#7797) Shell tracing would echo the credentials once expanded. `${VAR:+x}` tests non-emptiness without expanding the value.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797). Unset it to trace safely.\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS

for _tool in jq timeout date mktemp; do
  command -v "$_tool" >/dev/null 2>&1 || { printf 'FATAL: required tool missing: %s\n' "$_tool" >&2; exit 64; }
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BSQ="${ROOT}/scripts/betterstack-query.sh"

# shellcheck source=../lib/betterstack-sources.sh
source "${ROOT}/scripts/lib/betterstack-sources.sh" || { echo "FATAL: cannot load betterstack-sources.sh" >&2; exit 64; }
# shellcheck source=../lib/betterstack-read-classify.sh
source "${ROOT}/scripts/lib/betterstack-read-classify.sh" || { echo "FATAL: cannot load betterstack-read-classify.sh" >&2; exit 64; }

# The 10-minute settle rule (CTO F6): the window is settled once the last live reporter row is at least this old.
readonly SETTLE_S=600

usage() {
  printf 'usage: %s --since <Nm|Nh|Nd|YYYY-MM-DDTHH:MM:SSZ>\n' "$(basename "$0")" >&2
  exit 64
}

SINCE=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --since) SINCE="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[[ -n "$SINCE" ]] || usage

# The window literal is built ONLY from a value that matched one of these shapes (no quote or free text can reach the SQL).
LOWER=""
if [[ "$SINCE" =~ ^([0-9]{1,4})([mhd])$ ]]; then
  _n="${BASH_REMATCH[1]}"
  case "${BASH_REMATCH[2]}" in m) _u=MINUTE ;; h) _u=HOUR ;; d) _u=DAY ;; esac
  (( 10#$_n >= 1 )) || usage
  LOWER="now() - INTERVAL $((10#$_n)) ${_u}"
elif [[ "$SINCE" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[T\ ]([0-9]{2}:[0-9]{2}:[0-9]{2})Z?$ ]]; then
  _stamp="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  date -u -d "$_stamp" >/dev/null 2>&1 || usage
  LOWER="toDateTime('${_stamp}', 'UTC')"
else
  usage
fi

WORK="$(mktemp -d -t gd-replication-signal.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 64; }
case "$WORK" in /?*) : ;; *) echo "FATAL: scratch dir is not absolute" >&2; exit 64 ;; esac
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Real host names live only inside the SQL. web-1's source host is `soleur-web-platform`, and `soleur-inngest-prd` until the #6616
# recreate lands (the cutover workflow's per-host readback matches both for the same reason); web-2 is `soleur-web-2`.
REPORTER_RE='agent_sessions_live=[0-9]+ cc_queries=[0-9]+ legacy_sessions=[0-9]+ starting=[0-9]+ new_sessions_paused=[01] refused_since_last=[0-9]+'
MARKER_RE='git_data_replication_success=1 transient_retried=[01]'

sql="SELECT leg,
  countIf(is_marker) AS markers,
  countIf(is_reporter) AS reporter_rows,
  countIf(is_reporter AND live > 0) AS live_rows,
  argMaxIf(live, dt, is_reporter) AS newest_live,
  dateDiff('second', maxIf(dt, is_reporter AND live > 0), now()) AS last_live_age_s
FROM (
  SELECT dt,
    multiIf(JSONExtractString(raw,'host_name') IN ('soleur-web-platform','soleur-inngest-prd'),'web-1', JSONExtractString(raw,'host_name') = 'soleur-web-2','web-2','') AS leg,
    match(raw,'${MARKER_RE}') AS is_marker,
    match(raw,'${REPORTER_RE}') AS is_reporter,
    toUInt32OrZero(extract(raw,'agent_sessions_live=([0-9]+)')) AS live
  FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= ${LOWER}
        UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= ${LOWER})
  WHERE dt >= ${LOWER}
)
WHERE leg != ''
GROUP BY leg ORDER BY leg FORMAT JSONEachRow"

# The verdict table, WORST FIRST as "TOKEN:exit". Position is the rank (the worse a verdict, the earlier it sits); the number is the exit
# code. An unknown token reads as READ_UNCLEAN.
VERDICT_TABLE=("READ_UNCLEAN:2" "ZERO_MARKERS_WITH_SESSIONS:1" "PENDING:3" "NO_SESSIONS:4" "MARKERS_PRESENT:0")
verdict_rc() { # <verdict> -> exit code
  local e
  for e in "${VERDICT_TABLE[@]}"; do
    [[ "${e%%:*}" == "$1" ]] && { echo "${e#*:}"; return; }
  done
  echo 2
}
verdict_rank() { # <verdict> -> higher is worse
  local i n=${#VERDICT_TABLE[@]}
  for ((i = 0; i < n; i++)); do
    [[ "${VERDICT_TABLE[i]%%:*}" == "$1" ]] && { echo $((n - i)); return; }
  done
  echo "$n"
}

finish() { # <verdict> [detail] -- prints the overall line and exits with the verdict's code
  local rc
  rc="$(verdict_rc "$1")"
  printf 'verdict=%s exit=%s since=%s%s\n' "$1" "$rc" "$SINCE" "${2:+ $2}"
  exit "$rc"
}

# --- the single read ----------------------------------------------------------------------------------------------------
rc=0
BS_TABLE="$BS_CONTROL_TABLE" BS_TABLE_S3="$BS_CONTROL_TABLE_S3" timeout -k 5 150 bash "$BSQ" "$sql" >"${WORK}/bs.out" 2>"${WORK}/bs.err" || rc=$?
if (( rc != 0 )); then
  # The reader's credential-refusal marker is value-free and is the only stderr line surfaced.
  grep -m1 '^SOLEUR_CREDENTIAL_REFUSED' "${WORK}/bs.err" >&2 || true
  finish READ_UNCLEAN "read_class=bs-$(bs_read_classify "$rc" "${WORK}/bs.out")"
fi

# --- parse: integers only; anything else is an unclean read ---------------------------------------------------------------
# One compact row per leg: leg markers reporter_rows live_rows newest_live last_live_age_s. A value that is not a non-negative
# integer (number or numeric string), an unknown or duplicated leg, or a non-object line makes jq exit non-zero (`error`), and a
# non-zero jq is an unclean read, never a zero.
rows_tsv="${WORK}/rows.tsv"
if ! jq -r -s '
    def isint: ((type == "number" and . >= 0 and . == floor) or (type == "string" and test("^[0-9]{1,12}$")));
    def keys5: ["markers","reporter_rows","live_rows","newest_live","last_live_age_s"];
    if ([.[] | type == "object"] | all)
       and ([.[] | .leg] | (length == (unique | length)))
       and ([.[] | ((.leg // "") | . == "web-1" or . == "web-2")] | all)
       and ([.[] | . as $r | keys5 | all(. as $k | $r[$k] | isint)] | all)
    then .[] | [.leg, (.markers|tonumber), (.reporter_rows|tonumber), (.live_rows|tonumber), (.newest_live|tonumber),
                (.last_live_age_s|tonumber)] | @tsv
    else error("unclean") end
  ' "${WORK}/bs.out" >"$rows_tsv" 2>/dev/null; then
  finish READ_UNCLEAN "read_class=bs-response-shape"
fi

# --- per-host verdicts ---------------------------------------------------------------------------------------------------
overall="MARKERS_PRESENT"
overall_rank="$(verdict_rank MARKERS_PRESENT)"
any_present=0
declare -a LINES=()
for leg in web-1 web-2; do
  row="$(awk -F'\t' -v l="$leg" '$1 == l { print; exit }' "$rows_tsv")"
  if [[ -z "$row" ]]; then
    # No row at all for this host: the reporter is silent (or the host never shipped). Never NO_SESSIONS.
    LINES+=("host=${leg} host_verdict=READ_UNCLEAN markers=none reporter_rows=0 live_rows=none newest_live=none last_live_age_s=none")
    hv="READ_UNCLEAN"
  else
    IFS=$'\t' read -r _l markers reporter live_rows newest_live last_live_age <<<"$row"
    if (( reporter == 0 )); then
      # Markers without a reporter row cannot be set against live sessions; a missing reporter is a read fault.
      hv="READ_UNCLEAN"
    elif (( markers > 0 )); then
      hv="MARKERS_PRESENT"
    elif (( live_rows == 0 )); then
      hv="NO_SESSIONS"
    elif (( newest_live > 0 || last_live_age < SETTLE_S )); then
      hv="PENDING"
    else
      hv="ZERO_MARKERS_WITH_SESSIONS"
    fi
    if (( live_rows == 0 )); then lla="none"; else lla="$last_live_age"; fi
    LINES+=("host=${leg} host_verdict=${hv} markers=${markers} reporter_rows=${reporter} live_rows=${live_rows} newest_live=${newest_live} last_live_age_s=${lla}")
  fi
  [[ "$hv" == "MARKERS_PRESENT" ]] && any_present=1
  r="$(verdict_rank "$hv")"
  if (( r > overall_rank )); then overall="$hv"; overall_rank=$r; fi
done

# A host with no live session and no marker has nothing to prove: it never lowers a verdict that another host positively earned,
# but it IS the verdict when no host earned one (NO_SESSIONS is inconclusive, never a pass).
if [[ "$overall" == "NO_SESSIONS" ]] && (( any_present )); then overall="MARKERS_PRESENT"; fi

for l in "${LINES[@]}"; do printf '%s\n' "$l"; done
finish "$overall"
