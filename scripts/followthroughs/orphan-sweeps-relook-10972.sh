#!/usr/bin/env bash
# Follow-through probe for #10972 (the 14-day re-look at the scheduled-orphan-sweeps Sentry monitor).
#
# Question answered: did the orphan-sweeps aggregator check in `ok` for EVERY 12-hour slot of the pinned
# window, with no `missed`, `timeout` or `error` check-in at all? The monitor is `scheduled-orphan-sweeps`
# (cron `0 6,18 * * *` UTC); its aggregator job is `orphan-sweeps-checkin` in scheduled-terraform-drift.yml
# (#10952).
#
# PINNED WINDOW. Start 2026-10-26T06:00:00Z (the first live slot), end 2026-11-09T06:00:00Z (exclusive),
# 14 days = 28 slots. Both are literals here, not read from the tracker. The sweeper re-reads the
# issue-body `earliest=` directive on every run and hands it to probes as SOLEUR_FT_EARLIEST, so an edit
# there WOULD bring a sweep forward: this probe never reads that value and refuses to judge before the
# window has closed (exit 2, NOT YET) whatever the directive says. Once the window has closed, the evaluated
# set of rows is immutable, so the verdict does not drift with later check-ins.
#
# SLOT COVERAGE. Slot k is the 12-hour bucket k = floor((t - start) / 43200), taken from the row's own
# `dateAdded` (or `dateCreated`). Exit 0 needs every bucket 0..27 to hold at least one `ok` row. A duplicate
# `ok` row (a manual re-dispatch, a re-run) can only re-cover a bucket that already has one, so it cannot make
# up for a slot that has none. Accepted residual: a manual re-dispatch inside a bucket whose scheduled run
# was lost covers that bucket, because a real sweep ran and reported `ok`. Accepted residual in the other
# direction: a run queued in the `terraform-drift` concurrency group can start so late that its check-in lands
# past the monitor's 60-minute margin (or a pending slot run can be replaced by a newer dispatch and never start);
# Sentry may then record a `missed` row, and this probe's exit 1 is permanent, so the owner closes #10972 by hand.
#
# WAIVER (CTO ruling D7, 2026-10-26). Slot bucket 1 (the 2026-10-26T18:00Z slot, run 40373916062) posted an `error`
# check-in because three jobs of that run failed a download in the same minute (step `Install Doppler CLI (pinned)`,
# exit 22, and a credential load); that is a transient infrastructure failure outside this change, and that slot ran
# before the monitor was routed, so no Sentry email was due. An `error` row inside bucket 1 (and only there) is read
# as `waived`: it is not a bad row and it covers bucket 1. Everything else is unchanged: an `error` row in any
# other bucket is exit 1, `missed`, `timeout` and an unrecognised status in bucket 1 stay bad, and a bucket 1 with
# neither an `ok` nor a waived row is uncovered (exit 3). The count is printed as `waived=<n>`.
#
# Exit semantics (scripts/sweep-followthroughs.sh contract):
#   0 = PASS    no missed/timeout/error row in the window AND every one of the 28 slots has an `ok` row
#               (sweeper closes #10972)
#   1 = FAIL    at least one missed/timeout/error row in the window. PERMANENT: a bad slot cannot un-happen,
#               so every later sweep also exits 1 and the tracker stays open until the owner closes it.
#   2 = NOT YET the window has not closed (no request is sent)
#   3 = CANNOT ESTABLISH  a read or integrity failure: zero rows, a reply that is not exactly one JSON array,
#               an unparseable row, an unrecognised in-window status, a full page that does not reach the
#               window start (truncation), a slot with no `ok` row, an unpinned destination, an unusable
#               token, an HTTP/auth failure, an unusable clock. Never 0 and never 1.
#   78 = refused to run under xtrace with a live credential (#7797)
#   `in_progress` rows are ignored (not a verdict). Rows outside the window are ignored.
#   Statuses are matched after lowercasing, with no trimming (CTO ruling D3): `ok`, `in_progress`, `missed`,
#   `timeout`, `timed_out` (printed as `timeout`), `error`. Anything else in the window is `other` and is exit 3,
#   because an unknown word means this probe's vocabulary has a gap, not that a slot failed.
#
# Credential posture: ONE credential, SENTRY_ACTIONS_RO_TOKEN (the org-level read-only `actions-read-prd`
# integration, ADR-031; rotation: knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md).
# No GitHub token. The org and API host are PINNED literals (Rule D, ADR-202): an env override that does not
# equal the pin is refused, never followed. The bearer rides curl's stdin config channel, never its argv.
#
# Output never echoes the response body (the sweeper posts this output to a public issue comment and the
# Actions log is public): only counts, statuses from a closed set (ok, in_progress, missed, timeout, error,
# other) and timestamps.
#
# NOT DEFENDED: the public write-only ingest key can post a spoofed `ok` check-in (true of every Sentry
# monitor; stated in the workflow); the `environment` field is not filtered (the aggregator posts its
# check-in without one, so there is nothing to filter on). NOT MEASURED: the Sentry issue state of the
# monitor, the routing, and whether any alert email reached a person. A PASS means check-in health only.
#
# ORDER: the truncation guard assumes Sentry lists check-ins newest first (its default).
# PAGE LIMIT: one request, per_page=100, no pagination. The newest 100 rows cover about 50 days at two
# slots a day, so the window stays reachable for about 36 days after it closes; after that the read is a
# truncation (exit 3) and the owner re-reads by hand. The reply is capped at 5 MiB where curl enforces
# --max-filesize for a body of unknown size (curl 8.4 and later); on older curl, --max-time 30 is the bound.
#
# RETIREMENT: when #10972 closes, delete this probe, its suite orphan-sweeps-relook-10972.test.sh, the
# run_suite line for it in scripts/test-all.sh, its rows in the two generated manifests
# scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv (python3 scripts/regenerate-shard-manifest.py
# --incremental --write), and remove the `follow-through` label from #10972.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Tracing echoes commands AFTER expansion, so a credential is printed
# the moment it is used. `${VAR:+x}` tests non-emptiness WITHOUT expanding the value (`${VAR:-}` would
# print it here). Tracing stays available with the credential unset.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_ACTIONS_RO_TOKEN). Unset it to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

readonly ORG_PINNED="jikigai-eu"
readonly API_HOST_PINNED="de.sentry.io"
readonly MONITOR_SLUG="scheduled-orphan-sweeps"
readonly PER_PAGE=100
readonly MAX_FILESIZE=5242880
readonly WIN_START_ISO="2026-10-26T06:00:00Z"
readonly WIN_END_ISO="2026-11-09T06:00:00Z"
readonly SLOT_SECONDS=43200
readonly WAIVED_SLOT=1 # slot bucket 1 = 2026-10-26T18:00Z up to (not including) 2026-10-27T06:00Z; see WAIVER above

cannot() { echo "CANNOT ESTABLISH: $1" >&2; exit 3; }
closing() { echo "Note: the Sentry issue state, the routing and any alert delivery were not measured; this probe reads check-in rows only (#10972)."; }

# Token-shape guard (empty, or any char outside the allowlist, e.g. a newline that would inject a curl
# config directive on the stdin channel below). Never echoes the value.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
if ! _bearer_ok "${SENTRY_ACTIONS_RO_TOKEN:-}"; then cannot "SENTRY_ACTIONS_RO_TOKEN unusable"; fi

ORG="${SENTRY_ORG:-$ORG_PINNED}"
API_HOST="${SENTRY_API_HOST:-$API_HOST_PINNED}"
if [[ "$ORG" != "$ORG_PINNED" || "$API_HOST" != "$API_HOST_PINNED" ]]; then
  cannot "refusing an unpinned Sentry destination (pinned to ${ORG_PINNED} / ${API_HOST_PINNED})"
fi

# A leading-zero number is octal to bash arithmetic (`[[ 08 -lt N ]]` errors and falls through), so every
# number that reaches an arithmetic test is shape-checked first.
_epoch_ok() { [[ "${1:-}" =~ ^[1-9][0-9]{0,15}$ ]]; }

WIN_START=$(jq -n -r --arg t "$WIN_START_ISO" '$t | fromdateiso8601' 2>/dev/null)
WIN_END=$(jq -n -r --arg t "$WIN_END_ISO" '$t | fromdateiso8601' 2>/dev/null)
if ! _epoch_ok "$WIN_START" || ! _epoch_ok "$WIN_END"; then cannot "could not compute the window bounds"; fi
SLOT_FLOOR=$(( (WIN_END - WIN_START) / SLOT_SECONDS ))

NOW=$(date -u +%s 2>/dev/null)
if ! _epoch_ok "$NOW"; then cannot "could not read the clock"; fi
if [[ "$NOW" -lt "$WIN_END" ]]; then
  echo "NOT YET: the pinned window closes at ${WIN_END_ISO}; no request sent (#10972)"
  exit 2
fi

URL="https://${API_HOST}/api/0/organizations/${ORG}/monitors/${MONITOR_SLUG}/checkins/?per_page=${PER_PAGE}"

rc=0
RESP=$(curl --disable --noproxy '*' --proto '=https' --max-time 30 --max-filesize "$MAX_FILESIZE" -sS \
  -w '\nHTTP_STATUS:%{http_code}' \
  -H "Accept: application/json" \
  --config - "$URL" \
  < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_ACTIONS_RO_TOKEN")) || rc=$?
if [[ "$rc" -ne 0 ]]; then cannot "the Sentry request failed (curl rc ${rc})"; fi

HTTP_STATUS="${RESP##*$'\n'HTTP_STATUS:}"
BODY="${RESP%$'\n'HTTP_STATUS:*}"
if ! [[ "$HTTP_STATUS" =~ ^[0-9]{3}$ ]]; then cannot "the Sentry reply carried no readable HTTP status"; fi
if [[ "$HTTP_STATUS" != "200" ]]; then cannot "Sentry checkins API returned HTTP ${HTTP_STATUS} (body not echoed)"; fi

# Exactly ONE JSON document, and it is an array of objects. The evaluation below reads the same single
# document, so a body of several concatenated documents can never be judged on one and shape-checked on another.
if ! jq -s -e 'length == 1 and (.[0] | type == "array" and all(.[]; type == "object"))' <<<"$BODY" >/dev/null 2>&1; then
  cannot "the checkins reply is not exactly one JSON array of objects (body not echoed)"
fi

# One evaluation over the one response: per-status counts inside the window (statuses mapped to a closed
# set), the oldest row's time over ALL rows (for the truncation test), the offending rows and the slots
# with no `ok` row. Every verdict below reads this object.
rc=0
RESULT=$(jq -s -c --argjson ws "$WIN_START" --argjson we "$WIN_END" --argjson slot "$SLOT_SECONDS" \
  --argjson slots "$SLOT_FLOOR" --argjson waived "$WAIVED_SLOT" '
  def ts: (.dateAdded // .dateCreated // null)
          | if type == "string" then (sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) else null end;
  def st: (.status | if type == "string" then ascii_downcase else null end) as $s
          | if $s == "ok" or $s == "in_progress" or $s == "missed" or $s == "timeout" or $s == "error" then $s
            elif $s == "timed_out" then "timeout"
            else "other" end;
  def isbad: .s == "missed" or .s == "timeout" or .s == "error";
  .[0] | [ .[] | { s: st, t: ts } ] as $r
  | [ $r[] | select(.t != null and .t >= $ws and .t < $we)
          | . + { b: ((.t - $ws) / $slot | floor) }
          | if .s == "error" and .b == $waived then .s = "waived" else . end ] as $w
  | ([ $w[] | select(.s == "ok" or .s == "waived") | .b ] | unique) as $cov
  | ([ range(0; $slots) ] - $cov | map($ws + . * $slot | todate)) as $uncovered
  | {
      n: ($r | length),
      unparseable: ([ $r[] | select(.t == null) ] | length),
      oldest: ([ $r[] | .t | select(. != null) ] | min // 0),
      ok: ([ $w[] | select(.s == "ok") ] | length),
      bad: ([ $w[] | select(isbad) ] | length),
      other: ([ $w[] | select(.s == "other") ] | length),
      uncovered_n: ($uncovered | length),
      uncovered: ($uncovered | .[0:10]),
      counts: ($w | group_by(.s) | map({ key: .[0].s, value: length }) | from_entries),
      bad_list: ([ $w[] | select(isbad) ] | sort_by(.t) | .[0:10] | map("\(.s) @ \(.t | todate)"))
    }' <<<"$BODY" 2>/dev/null) || rc=$?
if [[ "$rc" -ne 0 || -z "$RESULT" ]]; then cannot "could not evaluate the check-in rows"; fi

rc=0
FIELDS=$(jq -r '[.n, .unparseable, .oldest, .ok, .bad, .other, .uncovered_n] | @tsv' <<<"$RESULT" 2>/dev/null) || rc=$?
if [[ "$rc" -ne 0 ]]; then cannot "could not read the evaluation result"; fi
read -r N UNPARSEABLE OLDEST OK_COUNT BAD_COUNT OTHER_COUNT UNCOVERED_N <<<"$FIELDS"
for v in "$N" "$UNPARSEABLE" "$OLDEST" "$OK_COUNT" "$BAD_COUNT" "$OTHER_COUNT" "$UNCOVERED_N"; do
  [[ "$v" =~ ^[0-9]+$ ]] || cannot "the evaluation result carried a non-numeric field"
done
COUNTS=$(jq -r '.counts | to_entries | map("\(.key)=\(.value)") | join(" ")' <<<"$RESULT" 2>/dev/null)

if [[ "$N" -eq 0 ]]; then cannot "0 check-in rows returned (monitor not checking in, or an empty read)"; fi
if [[ "$UNPARSEABLE" -gt 0 ]]; then cannot "${UNPARSEABLE} of ${N} rows have no parseable timestamp"; fi

# A bad row inside the window is a true FAIL even on a truncated page: what was read is what it is.
if [[ "$BAD_COUNT" -gt 0 ]]; then
  echo "FAIL: ${BAD_COUNT} missed/timeout/error check-in(s) in ${WIN_START_ISO}..${WIN_END_ISO} (counts in window: ${COUNTS:-none}) (#10972)"
  jq -r '.bad_list[] | "  - " + .' <<<"$RESULT" 2>/dev/null
  echo "This verdict is permanent for the pinned window; closing #10972 now needs the owner."
  closing
  exit 1
fi

# An unrecognised status word is a vocabulary gap, not a failed slot: never 0, never 1.
if [[ "$OTHER_COUNT" -gt 0 ]]; then
  cannot "${OTHER_COUNT} in-window check-in(s) carry a status this probe does not recognise (printed as other; counts in window: ${COUNTS:-none})"
fi

# Truncation: a full page whose oldest row is newer than the window start may hide older rows.
if [[ "$N" -ge "$PER_PAGE" && "$OLDEST" -gt "$WIN_START" ]]; then
  cannot "the page is full (${N} rows) and its oldest row is newer than the window start: older rows may be unread"
fi

if [[ "$UNCOVERED_N" -gt 0 ]]; then
  UNCOVERED_LIST=$(jq -r '.uncovered | join(" ")' <<<"$RESULT" 2>/dev/null)
  cannot "${UNCOVERED_N} of ${SLOT_FLOOR} slots have no ok check-in (first uncovered slot starts: ${UNCOVERED_LIST}; ok rows in window: ${OK_COUNT})"
fi

echo "PASS: no missed/timeout/error check-in and all ${SLOT_FLOOR} slots have an ok check-in (${OK_COUNT} ok rows) in ${WIN_START_ISO}..${WIN_END_ISO} (counts in window: ${COUNTS:-none}) (#10972)"
closing
exit 0
