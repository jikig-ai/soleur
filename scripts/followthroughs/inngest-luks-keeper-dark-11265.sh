#!/usr/bin/env bash
# Follow-through probe for #11265: has the on-host LUKS key-continuity probe gone DARK for 30 days after it last
# MEASURED anything? This is the dead-man CONVERSION TRIGGER, not an independent dead-man.
#
# WHY IT EXISTS. ADR-282's paging alert fires on `token=fail_*` rows only; a probe that stops emitting pages nobody.
# The in-Better-Stack dead-man (a 30-day `query_period`) cannot be created today: Better Stack refuses every
# `query_period` above 900 s (four 422s, recorded in betterstack-logs-alerts.tf), so this read-only probe may be the
# only 30-day coverage there is. When it fires, the owner converts to the "count-variable form" defined in the
# ADR-282 addendum of 2026-10-29 (#11265): the last rung of the fallback ladder, a Terraform variable defaulting to
# false and flipped by the owner, replacing the data-derived self-arm. THIS PROBE DEPENDS ON THE SWEEPER WORKFLOW
# (scheduled-followthrough-sweeper.yml): if the sweeper stops, so does this probe.
#
# WHAT IT COUNTS. MEASURED rows only: `SOLEUR_INNGEST_LUKS_KEY_PROBE token=ok` or `token=fail_*`. An `indeterminate`
# row (the probe could not measure) never counts as health and never resets the 30-day window. The marker is anchored
# at message position 1, the same anchor the paging SQL uses (position(JSONExtractString(raw, 'message'), marker) = 1 in
# betterstack-logs-alerts.tf): a webhook or PR body that QUOTES the marker is a row too, but not a producer row.
# The read is scripts/betterstack-query.sh over the hot window AND the archive arm (its default mode; `--raw-only` is
# never passed because it excludes the journald rows, one of the two shipping paths), 60 days back, newest 5000 rows.
#
# NOTIFY-ONLY probe: this tracker is never closed by a script, so nothing here exits 0 or 1
# (followthrough-convention.md, the TRANSIENT sub-vocabulary):
#   2 = NOT YET           no rows of any kind (the keeper is deferred, so this is the state until the owner's bundle
#                         lands), OR measured rows exist and the newest is under 30 days old
#   3 = CANNOT ESTABLISH  any read or parse failure; OR only `indeterminate` rows exist (rows=N measured=0
#                         indeterminate=N: a keeper that emits but never measures must not hide behind NOT YET)
#   5 = ACTION REQUIRED   measured rows exist and the newest is 30 days old or older
#  78 = refused to run under xtrace (#7797), before anything is read
# THE SWEEPER HAS NO DEDUP: exits 3 and 5 repeat in the daily comment until the directive is removed from the issue
# body or the `follow-through` label is removed.
#
# RESIDUALS, stated plainly. (1) Zero rows after the source retention expires (90 days, betterstack-log-query.md) looks
# exactly like "never started"; a keeper dark for longer than the 60-day look-back reads NOT YET, not ACTION REQUIRED.
# (2) A reader that succeeds with an empty body is indistinguishable from zero rows (JSONEachRow has no envelope), so
# an empty answer reads NOT YET; only a non-zero reader exit reads CANNOT ESTABLISH. (3) The 5000-row cap keeps the
# NEWEST rows, which is what the newest-measured-row decision needs; the printed counts are of those rows only.
# (4) Inert until the owner's bundle delivery produces the first `token=ok` row (#11266).
#
# THE SWEEPER POSTS THIS OUTPUT AS A PUBLIC COMMENT (the last 4 KB, run with 2>&1): counts, an age in whole days and
# fixed reason strings only. The reader's own output is never printed (it can echo credentials on an auth failure).
#
# CREDENTIAL POSTURE: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD, already bound in
# scheduled-followthrough-sweeper.yml (no workflow edit); this probe makes no request itself, the pinned reader does.
# Directive (added to the #11265 body at ship time, unfenced at column 0):
#   soleur:followthrough script=scripts/followthroughs/inngest-luks-keeper-dark-11265.sh earliest=2026-11-29T00:00:00Z
#   secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD
# `earliest=` is the first sweep day, NOT a deadline: the probe never closes the issue.
#
# RETIREMENT (delete together when #11265 closes or the dead-man exists): this file,
# scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh, their two `run_suite` rows in scripts/test-all.sh,
# their .github/CODEOWNERS rows, the dark-probe pointer in runbooks/inngest-luks-cutover-6894.md (Key-continuity probe
# subsection), the ADR-282 addendum's probe paragraph, and the tracker directive.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;  # [mut:xtrace]
esac

_finish() {
  local rc=$?
  case "$rc" in 2|3|5|78) ;; *) echo "CANNOT ESTABLISH: internal error (unexpected exit status ${rc})"; exit 3 ;; esac
}
trap _finish EXIT  # [mut:trap]

cannot() { echo "CANNOT ESTABLISH: $1"; exit 3; }

readonly MARKER="SOLEUR_INNGEST_LUKS_KEY_PROBE"
readonly DARK_SECS=$((30 * 86400))  # [mut:window]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The seam exists for the suite's stub; under the sweeper's `env -i` launcher it is never set.
QUERY="${LUKS_KEEPER_QUERY_SCRIPT:-$SCRIPT_DIR/../betterstack-query.sh}"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || cannot "unusable NOW_EPOCH"
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

# Decode in ONE jq pass (never two `-R` stages: `jq -r` materialises embedded newlines). One output line per input
# row: kind <TAB> epoch <TAB> token. A = anchored producer row (message STARTS with the marker), Q = a row whose
# message merely contains it, U = a line that mentions it but does not decode to {raw: JSON object with a string message}.
JQ_HEAD='(fromjson? // null) as $r | select(($r | type) == "object")
  | (try ($r.dt | tostring | sub(" "; "T") | sub("\\.[0-9]+"; "") | sub("Z$"; "") + "Z" | fromdateiso8601) catch "-") as $e
  | (try ($r.raw | fromjson) catch null) as $d
  | if (($d | type) != "object") or (($d.message | type) != "string") then "U\t\($e)\t-"
    elif '
ANCHOR='($d.message | startswith($m))'  # [mut:anchor]
JQ_TAIL=' then "A\t\($e)\t\(([$d.message | capture("token=(?<t>[a-z_]+)") | .t][0]) // "-")"
    else "Q\t\($e)\t-" end'
ROWS="$(printf '%s\n' "$OUT" | jq -R -r --arg m "$MARKER" "${JQ_HEAD}${ANCHOR}${JQ_TAIL}" 2>/dev/null)" || cannot "the rows could not be decoded"

# Measured = token ok or fail_*; indeterminate is counted apart; any other anchored token is a parse failure.
CLASSIFY='$1=="A"{a++; if($3=="ok"||$3 ~ /^fail_/){m++; if($2=="-"){be++} else if($2+0>n){n=$2+0}} else if($3=="indeterminate"){i++} else {b++}} $1=="U"{u++} END{printf "%d %d %d %d %d %d %d\n", a,m,i,b,u,n,be}'  # [mut:classify]
read -r ANCH MEAS INDET BADTOK UNDEC NEWEST BADEPOCH < <(printf '%s\n' "$ROWS" | awk -F'\t' "$CLASSIFY")
[[ "$ANCH$MEAS$INDET$BADTOK$UNDEC$NEWEST$BADEPOCH" =~ ^[0-9]+$ ]] || cannot "the rows could not be counted"

(( BADTOK == 0 )) || cannot "PARSE: ${BADTOK} anchored row(s) carry an unrecognised token"  # [mut:badtoken]
(( BADEPOCH == 0 )) || cannot "PARSE: a measured row has an unreadable timestamp"

if (( MEAS > 0 )); then
  age=$(( NOW_EPOCH - NEWEST ))
  echo "inngest-luks keeper dark probe (#11265): rows=${ANCH} measured=${MEAS} indeterminate=${INDET} newest_measured_age_days=$(( age / 86400 ))"
  if (( age >= DARK_SECS )); then  # [mut:threshold]
    echo "ACTION REQUIRED: the newest measured key-continuity row is 30 days old or older, so the keeper has gone dark. Convert the dead-man to the count-variable form (ADR-282 addendum 2026-10-29, #11265) or investigate the host. The tracker is NOT closed by the probe: close it and remove its follow-through label by hand."
    exit 5  # [mut:action]
  fi
  echo "NOT YET: the newest measured row is under 30 days old."
  exit 2
fi

if (( INDET > 0 )); then  # [mut:indet]
  echo "inngest-luks keeper dark probe (#11265): rows=${INDET} measured=0 indeterminate=${INDET}"
  cannot "only indeterminate rows exist: the keeper emits but has never measured; an unmeasured verdict is not health and never resets the 30-day window"
fi

if (( ANCH == 0 && UNDEC > 0 )); then  # [mut:drift]
  cannot "SHAPE_DRIFT: ${UNDEC} line(s) mention ${MARKER} but none decodes as a producer row; the stored message shape may have changed (re-measure it against a live row)"
fi

echo "inngest-luks keeper dark probe (#11265): rows=0 measured=0 indeterminate=0"
echo "NOT YET: no keeper rows in the last 60 days. The probe is inert until the owner's bundle delivery produces the first token=ok row; zero rows after retention expiry looks the same as never started."
exit 2
