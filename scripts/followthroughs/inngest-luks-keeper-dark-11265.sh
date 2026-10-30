#!/usr/bin/env bash
# Follow-through probe for #11265: has the on-host LUKS key-continuity probe gone DARK for 30 days after it last
# MEASURED anything? This is the dead-man CONVERSION TRIGGER, not an independent dead-man, and a 30-day BACKSTOP only:
# the Better Stack dead-man alert (arms at 26 h) stays a blocking prerequisite of the bundle promotion (#11266); this
# probe's blind window is about 28 times wider.
#
# WHY IT EXISTS. ADR-282's paging alert fires on `token=fail_*` rows only; a probe that stops emitting pages nobody.
# The in-Better-Stack dead-man could not be created at the windows tried: four (check, query) tuples were refused 422,
# all at a query_period of 5400 s or more: 300/10800, 900/10800, 3600/10800 and 300/5400. Live alerts created in
# September carry 5400, 86400 and 97200 s. 604800 s and 2592000 s were never tried, so whether a 30-day dead-man can
# exist is unknown. When this probe fires (exit 5) the action is an OWNER DECISION: see the ADR-282 addendum of
# 2026-10-29 (#11265), which defines the "count-variable form" ladder rung and what to do if the API refuses it.
# THIS PROBE DEPENDS ON THE SWEEPER WORKFLOW (scheduled-followthrough-sweeper.yml): if the sweeper stops, so does it.
#
# WHAT IT COUNTS. MEASURED rows only: `SOLEUR_INNGEST_LUKS_KEY_PROBE token=ok` or `token=fail_*`. An `indeterminate`
# row (the probe could not measure) never counts as health and never resets the 30-day window. The marker is anchored
# at message position 1, the same anchor the paging SQL uses (position(JSONExtractString(raw, 'message'), marker) = 1 in
# betterstack-logs-alerts.tf): a webhook or PR body that QUOTES the marker is a row too, but not a producer row.
# The read is scripts/betterstack-query.sh over the hot window AND the archive arm (its default mode; `--raw-only` is
# never passed because it excludes the journald rows, one of the two shipping paths), 60 days back, newest 5000 rows.
# The reader's own `--max-time` bounds each request (the suite pins it); this probe makes no request itself.
# READ-TIME BUDGET (#11572 item 3, measured 2026-10-30 against the live reader, one sample each, not a distribution): the
# 60-day read took about 4 s (`--since 60d`; 30d 5 s, 7d 2 s; 41 rows, hot + archive, default read) against the reader's
# `--max-time 60`, so no timeout change is needed. The probe maps ANY non-zero reader rc to its own exit 3 (CANNOT
# ESTABLISH); a curl timeout (error 28) shows only in the reader's stderr, which the probe discards, so a slow read is the
# honest exit 3, never a false 2 or 5. Re-evaluate on a timeout-class exit 3 reported in a sweeper comment, or when the
# archive arm grows past about 10x today's row count.
# TRUST IN THE READ. (i) Every non-blank reader line must decode to a JSON object carrying a string `dt` and a string
# `raw` (the reader's row shape); one that does not (an HTML 502 page, a ClickHouse `Code: ... DB::Exception` line, or
# the same exception as a JSON object such as {"exception":"Code: 395 ..."}, after a mid-stream failure, which truncates
# the tail = the NEWEST rows) makes the answer untrustworthy: exit 3 before any verdict, even when anchored rows were
# found. An object with both strings whose `raw` does not decode to a message is a different class (U), which never
# blocks a verdict while anchored rows exist. (ii) When the read finds zero anchored rows, ONE companion read through
# the same reader (default mode = hot window plus archive; `--since 24h --until <NOW minus 3 h> --limit 1`; no `--grep`,
# no `--raw-only`) must return at least one {dt, raw} object line, else exit 3 `reader archive arm not live (no rows
# 3-24h back; the hot window cannot answer this)`. The reader applies the WHERE, `--until` included, to both arms
# (remote() UNION ALL s3Cluster()) and the hot window holds only about 40 minutes, so a row 3 to 24 h old can come only
# from the ARCHIVE arm: the canary proves the archive arm, the arm the 60-day main read depends on. Caveat: an archive
# ingest lag above 3 h gives a FALSE exit 3 (the safer failure; widen `--until` to flip it). An empty answer from a
# dead arm must not read as 'no keeper rows'. (iii) A measured row dated more than 1 h in the future, or at or before
# the epoch, is exit 3 (`PARSE: ...`); skew up to 1 h counts as age 0.
#
# NOTIFY-ONLY probe: this tracker is never closed by a script, so nothing here exits 0 or 1
# (followthrough-convention.md, the TRANSIENT sub-vocabulary):
#   2 = NOT YET           the reader is live and either no keeper rows exist (the keeper is deferred, so this is the
#                         state until the owner's bundle lands), OR measured rows exist and the newest is under 30 days
#   3 = CANNOT ESTABLISH  any read or parse failure; an untrustworthy answer (non-object line, future-dated measured
#                         row); a reader whose archive arm is not live; OR only `indeterminate` rows exist (rows=N measured=0
#                         indeterminate=N: a keeper that emits but never measures must not hide behind NOT YET)
#   5 = ACTION REQUIRED   measured rows exist and the newest is 30 days old or older: the newest measured row from
#                         `luks_key_probe_tick` (or the future keeper) is >= 30 days old
#  78 = refused to run under xtrace (#7797), before anything is read
# THE SWEEPER HAS NO DEDUP: EVERY verdict (2 included) posts one comment per open-tracker sweep, about 30 a month. To
# stop them, remove the directive from the issue body or the `follow-through` label.
#
# RESIDUALS, stated plainly. (1) REACH: the archive arm was measured to reach back at least 40 days (the look-back is
# 60 d; retention is 90 d, betterstack-log-query.md). Exit 5 is therefore reachable for days 30 to about 60 of darkness
# and degrades silently afterwards to exit 2 (a keeper dark for longer than the look-back reads 'no keeper rows' while
# the canary passes on other rows). (2) `--limit 5000` keeps the newest 5000 rows that merely CONTAIN the marker, so
# rows that quote it (webhook or PR bodies) could evict the newest measured row; the printed counts are of the rows
# kept only. (3) Inert until the owner's bundle delivery produces the first `token=ok` row (#11266). (4) A verdict from
# anchored rows (exit 2 or 5) does not consult the canary (it runs only when zero anchored rows were found): the rows
# themselves show the reader answered, and a truncated tail is caught by the per-line object check (i), not by the canary.
# A NOT YET (2) whose newest measured row is a `fail` says so: a resolved page is not recovery, only `token=ok` is.
#
# THE SWEEPER POSTS THIS OUTPUT AS A PUBLIC COMMENT (the last 4 KB, run with 2>&1): counts, an age in whole days, the
# newest measured token CLASS (`ok` or `fail`, nothing else) and fixed reason strings only. The reader's own output
# is never printed (it can echo credentials on an auth failure).
#
# CREDENTIAL POSTURE: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD, already bound in
# scheduled-followthrough-sweeper.yml (no workflow edit); this probe makes no request itself, the pinned reader does.
# Directive (added to the #11265 body at ship time, unfenced at column 0, on ONE line):
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-keeper-dark-11265.sh earliest=2026-11-29T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
# `earliest=` is the first sweep day, NOT a deadline: the probe never closes the issue.
#
# RETIREMENT (delete together when #11265 closes or the dead-man exists): this file,
# scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh, their `run_suite` row in scripts/test-all.sh,
# their .github/CODEOWNERS rows, the dark-probe pointer in runbooks/inngest-luks-cutover-6894.md (Key-continuity probe
# subsection), the ADR-282 addendum's probe paragraph, and the tracker directive (or its `follow-through` label).
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;  # [mut:xtrace]
esac
trap 'set -- "$?"; case "$1" in 2|3|5|78) ;; *) echo "CANNOT ESTABLISH: internal error (unexpected exit status, or killed by a signal)"; exit 3 ;; esac' EXIT  # [mut:trap]

cannot() { echo "CANNOT ESTABLISH: $1"; exit 3; }

readonly MARKER="SOLEUR_INNGEST_LUKS_KEY_PROBE"  # [mut:marker]
readonly DARK_SECS=$((30 * 86400))  # [mut:window]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="$SCRIPT_DIR/../betterstack-query.sh"  # [mut:query-path]
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW_EPOCH" =~ ^[1-9][0-9]{0,15}$ ]] || cannot "unusable NOW_EPOCH"  # no leading zero: it would be octal inside (( ))
command -v jq >/dev/null 2>&1 || cannot "jq is not available"
[[ -f "$QUERY" ]] || cannot "the Better Stack query script is missing"

# Explicit guards, never `${VAR:?}` (it aborts with status 1). Only the name is ever printed.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  [[ -n "${!v:-}" ]] || cannot "$v is not set in the probe environment"  # [mut:cred-check]
done

OUT=""
read_rows() {
  local RC=0
  # Stderr is discarded (a ClickHouse auth failure body echoes the username, curl -S errors echo the host).
  OUT="$(bash "$QUERY" --since 60d --grep "$MARKER" --limit 5000 2>/dev/null)" || RC=$?
  if (( RC != 0 )); then cannot "Better Stack read failed (exit ${RC})"; fi  # [mut:read-fail]
}
read_rows

# Decode in ONE jq pass (never two `-R` stages: `jq -r` materialises embedded newlines). One output line per NON-BLANK
# input line: kind <TAB> epoch <TAB> token. X = a line that is not a JSON object (untrustworthy read), A = anchored
# producer row (message STARTS with the marker), Q = a row whose message merely contains it, U = an object that
# mentions it but is not {raw: JSON object with a string message}. An object lacking a string `dt` or a string `raw`
# (e.g. {"exception":"Code: 395 ..."}) is not a reader row at all: class X.
JQ_HEAD='select(test("\\S"))
  | ((fromjson? // null) as $r
  | if ($r | type) != "object" or (($r.dt | type) != "string") or (($r.raw | type) != "string") then "X\t-\t-"
    else (
      (try ($r.dt | tostring | sub(" "; "T") | sub("\\.[0-9]+"; "") | sub("Z$"; "") + "Z" | fromdateiso8601) catch "-") as $e
      | (try ($r.raw | fromjson) catch null) as $d
      | if (($d | type) != "object") or (($d.message | type) != "string") then "U\t\($e)\t-"
        elif '
ANCHOR='($d.message | startswith($m))'  # [mut:anchor]
JQ_TAIL=' then "A\t\($e)\t\(([$d.message | capture("token=(?<t>[a-z_]+)") | .t][0]) // "-")"
        else "Q\t\($e)\t-" end
    ) end)'
ROWS="$(printf '%s\n' "$OUT" | jq -R -r --arg m "$MARKER" "${JQ_HEAD}${ANCHOR}${JQ_TAIL}" 2>/dev/null)" || cannot "the rows could not be decoded"

# Measured = token ok or fail_*; indeterminate is counted apart; any other anchored token is a parse failure. A measured
# row dated more than 3600 s after NOW is counted as future-dated (skew up to 1 h is tolerated).
CLASSIFY='$1=="X"{x++} $1=="A"{a++; k=($3=="ok")?"ok":"fail"; if($3=="ok"||$3 ~ /^fail_/){m++; if($2=="-" || $2+0<=0){be++} else {if($2+0>now+3600){fu++}; if($2+0>n){n=$2+0; c=k} else if($2+0==n && k=="fail"){c="fail"}}} else if($3=="indeterminate"){i++} else {b++}} $1=="U"{u++} END{printf "%d %d %d %d %d %d %d %d %d %s\n", a,m,i,b,u,n,be,x,fu,(c==""?"-":c)}'  # [mut:classify]
read -r ANCH MEAS INDET BADTOK UNDEC NEWEST BADEPOCH BADLINE FUTURE NEWCLS < <(printf '%s\n' "$ROWS" | awk -F'\t' -v now="$NOW_EPOCH" "$CLASSIFY")
[[ "$ANCH$MEAS$INDET$BADTOK$UNDEC$NEWEST$BADEPOCH$BADLINE$FUTURE" =~ ^[0-9]+$ ]] || cannot "the rows could not be counted"
case "$NEWCLS" in ok|fail|-) ;; *) cannot "the rows could not be counted" ;; esac

(( BADLINE == 0 )) || cannot "PARSE: ${BADLINE} reader line(s) are not a JSON object (an error body or a truncated read); the answer is untrustworthy"  # [mut:object-check]
(( BADTOK == 0 )) || cannot "PARSE: ${BADTOK} anchored row(s) carry an unrecognised token"  # [mut:badtoken]
(( BADEPOCH == 0 )) || cannot "PARSE: a measured row has an unreadable timestamp"
(( FUTURE == 0 )) || cannot "PARSE: future-dated measured row"  # [mut:future]

if (( MEAS > 0 )); then
  age=$(( NOW_EPOCH - NEWEST ))  # a negative age (skew within the 1 h tolerance) truncates to 0 whole days
  echo "inngest-luks keeper dark probe (#11265): rows=${ANCH} measured=${MEAS} indeterminate=${INDET} newest_measured_age_days=$(( age / 86400 )) newest_measured_token=${NEWCLS}"  # [mut:tokclass]
  if (( age >= DARK_SECS )); then  # [mut:threshold]
    echo "ACTION REQUIRED: the newest measured key-continuity row is 30 days old or older (the on-host probe, or the future keeper, has gone dark). Owner decision: see the ADR-282 addendum of 2026-10-29 (#11265). The tracker is NOT closed by the probe: close it and remove its follow-through label by hand."
    exit 5  # [mut:action]
  fi
  echo "NOT YET: the newest measured row is under 30 days old."
  if [[ "$NEWCLS" == "fail" ]]; then echo "The newest measured row is a FAILED verdict: a resolved page is not recovery, only a token=ok row is."; fi
  exit 2
fi

if (( INDET > 0 )); then
  echo "inngest-luks keeper dark probe (#11265): rows=${INDET} measured=0 indeterminate=${INDET}"
  cannot "only indeterminate rows exist: the keeper emits but has never measured; an unmeasured verdict is not health and never resets the 30-day window"  # [mut:indet]
fi

if (( ANCH == 0 && UNDEC > 0 )); then  # [mut:drift]
  cannot "SHAPE_DRIFT: ${UNDEC} line(s) mention ${MARKER} but none decodes as a producer row; the stored message shape may have changed (re-measure it against a live row)"
fi

# Zero anchored rows: prove the ARCHIVE arm is live before reading emptiness as 'no keeper rows'. The canary is the
# reader's default mode (hot + archive) over 24 h but ending 3 h ago, one row, no filter: the hot window holds only about
# 40 minutes, so any row it returns came from the archive arm, and any live Logs source has one (an archive ingest lag
# above 3 h gives a false exit 3: the safer failure).
read_canary() {
  local CRC=0 CAN="" verdict="" until_iso=""
  until_iso="$(date -u -d "@$((NOW_EPOCH - 10800))" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  [[ -n "$until_iso" ]] || cannot "could not format the canary window end"
  CAN="$(bash "$QUERY" --since 24h --until "$until_iso" --limit 1 2>/dev/null)" || CRC=$?
  (( CRC == 0 )) || cannot "reader archive arm not live (no rows 3-24h back; the hot window cannot answer this)"  # [mut:canary-rc]
  verdict="$(printf '%s\n' "$CAN" | jq -R -s -r 'split("\n") | map(select(test("\\S")) | ((fromjson? // null) | if type == "object" then ((.dt | type) == "string" and (.raw | type) == "string") else false end)) | if (length > 0) and all then "live" else "dead" end' 2>/dev/null)"
  [[ "$verdict" == "live" ]] || cannot "reader archive arm not live (no rows 3-24h back; the hot window cannot answer this)"  # [mut:canary-shape]
}
read_canary  # [mut:canary]

echo "inngest-luks keeper dark probe (#11265): rows=0 measured=0 indeterminate=0"
echo "NOT YET: no keeper rows in the last 60 days. The probe is inert until the owner's bundle delivery produces the first token=ok row; zero rows after the look-back looks the same as never started."
exit 2
