#!/usr/bin/env bash
# Follow-through probe for #11211: has the DEFERRED dispatch-recovery sweeper's re-evaluation trigger fired?
#
# #11211 defers a service-role cron that would re-dispatch `action_sends` rows whose spawn event never reached
# Inngest (PR 11208 shipped the send path). It is deferred until BOTH of these hold, and this probe reports the day
# they do, so the deferral cannot rot:
#   criterion 1  a spawn-agent enqueue failure was observed in production: Sentry events tagged
#                `feature:spawn-agent op:inngest-enqueue` since 2026-10-26 (PR 11208's merge day), count > 0;
#   criterion 2  a stranded send exists: an `action_sends` row with acknowledged_at, failure_reason, undone_at and
#                cancellation_requested_at all NULL, joined to a `messages` row still in status 'draft', whose
#                clicked_at is MORE than 1 h old, with NO upper bound on its age.
# Criterion 2 is counted in two buckets that are printed separately: `recoverable` (clicked under 23 h ago, still
# inside REPLAY_MAX_AGE_MS in apps/web-platform/server/action-sends/decide-replay.ts, so a replay could still act)
# and `aged_out` (over 23 h: a once-daily snapshot misses rows that age past 23 h between runs, and a draft nobody
# re-clicked is exactly the evidence the criterion names). ACTION REQUIRED needs criterion 1 AND either bucket above
# zero, so the aged-out bucket can never fire alone. The count over-includes drafts whose `source_ref` is not a
# parseable artifact (`no_artifact_in_pr_a`); an over-count only moves the probe toward ACTION REQUIRED, the
# fail-safe direction for a notify-only probe, and the table has held 0 rows ever (plan-time read 2026-10-29).
#
# NOTIFY-ONLY probe: this tracker is never closed by a script, so nothing here exits 0 or 1
# (followthrough-convention.md, the TRANSIENT sub-vocabulary):
#   2 = NOT YET           the normal daily state (a criterion does not hold)
#   3 = CANNOT ESTABLISH  any read, auth, shape or parse failure, an unusable credential, or an empty answer. Both
#                         sources are ALWAYS read, so a failing second source is never hidden behind a quiet first
#   5 = ACTION REQUIRED   both criteria hold: a human decides whether to build the sweeper
#  78 = refused to run under xtrace (#7797), before any credential is read
# THE SWEEPER HAS NO DEDUP: exits 3 and 5 repeat in the daily comment until the directive is removed from the issue
# body or the `follow-through` label is removed (aged-out rows never clear on their own, so a 5 repeats daily).
#
# THE SWEEPER POSTS THIS OUTPUT AS A PUBLIC ISSUE COMMENT (the last 4 KB, run with 2>&1). Output is therefore COUNTS
# and fixed reason strings plus an HTTP status code only: never a response body, a curl error, an identifier or a
# timestamp of an individual row. The Supabase token can run writes and DDL, so the ONE literal `^SELECT` below
# (no interpolation, no `;`) is the only read-only control; the suite pins its exact text.
#
# CREDENTIAL POSTURE: SENTRY_ACTIONS_RO_TOKEN (org-level read-only integration, ADR-031) and SUPABASE_ACCESS_TOKEN,
# both already bound in scheduled-followthrough-sweeper.yml, so no workflow edit and no new secret. Each rides curl's
# stdin config (a process substitution), never its argument list, and only to its own host.
# Directive (added to the #11211 body at ship time, unfenced at column 0):
#   soleur:followthrough script=scripts/followthroughs/dispatch-recovery-sweeper-11211.sh earliest=2026-10-30T00:00:00Z
#   secrets=SENTRY_ACTIONS_RO_TOKEN,SUPABASE_ACCESS_TOKEN
# `earliest=` is the first sweep day, NOT a deadline: the probe never closes the issue and an elapsed date proves nothing.
#
# RETIREMENT (delete together when #11211 is built or closed): this file, scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh,
# their two `run_suite` rows in scripts/test-all.sh, their .github/CODEOWNERS rows, and the tracker directive.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;  # [mut:xtrace]
esac

TMP=""
_finish() {
  local rc=$?
  if [[ -n "$TMP" ]]; then rm -f "$TMP"; fi
  case "$rc" in 2|3|5|78) ;; *) echo "CANNOT ESTABLISH: internal error (unexpected exit status ${rc})"; exit 3 ;; esac
}
trap _finish EXIT  # [mut:trap]

cannot() { echo "CANNOT ESTABLISH: $1"; exit 3; }

# Token-shape check only (empty, or any char outside the allowlist, e.g. a newline that would inject a curl config
# directive on the stdin channel below). Never echoes a value. Explicit guards, never `${VAR:?}` (that aborts with 1).
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_bearer_ok "${SENTRY_ACTIONS_RO_TOKEN:-}" || cannot "SENTRY_ACTIONS_RO_TOKEN unusable"  # [mut:token-check]
_bearer_ok "${SUPABASE_ACCESS_TOKEN:-}" || cannot "SUPABASE_ACCESS_TOKEN unusable"  # [mut:token-check]
command -v jq >/dev/null 2>&1 || cannot "jq is not available"

NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || cannot "unusable NOW_EPOCH"
END_ISO="$(date -u -d "@${NOW_EPOCH}" '+%Y-%m-%dT%H%%3A%M%%3A%S' 2>/dev/null)"
[[ -n "$END_ISO" ]] || cannot "could not format the window end"

TMP="$(mktemp "${TMPDIR:-/tmp}/ft11211.XXXXXX")" || cannot "mktemp failed"

# Criterion 1: spawn-agent enqueue failures since PR 11208 merged (query is `feature:spawn-agent op:inngest-enqueue`, URL-encoded).
SENTRY_URL="https://de.sentry.io/api/0/organizations/jikigai-eu/events/?query=feature%3Aspawn-agent%20op%3Ainngest-enqueue&start=2026-10-26T00%3A00%3A00&end=${END_ISO}&dataset=errors&per_page=100&field=id&field=timestamp"

# Criterion 2: ONE literal string. No interpolation, no `;`, `now() - interval` in SQL, never a shell-built timestamp.
readonly QUERY="SELECT count(*) FILTER (WHERE s.clicked_at >= now() - interval '23 hours') AS recoverable, count(*) FILTER (WHERE s.clicked_at < now() - interval '23 hours') AS aged_out FROM public.action_sends s JOIN public.messages m ON m.id = s.message_id WHERE s.acknowledged_at IS NULL AND s.failure_reason IS NULL AND s.undone_at IS NULL AND s.cancellation_requested_at IS NULL AND m.status = 'draft' AND s.clicked_at < now() - interval '1 hour'"  # [mut:query]
[[ "$QUERY" == SELECT* && "$QUERY" != *';'* ]] || cannot "the query is not a single SELECT"
SB_URL="https://api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query"
PAYLOAD="$(jq -n --arg q "$QUERY" '{query: $q}')" || cannot "could not build the request payload"

# fetch <token> <url> [curl args...]: sets HTTP; the body lands in $TMP and is parsed, never printed.
fetch() {
  : > "$TMP"
  HTTP="$(curl --disable --noproxy '*' -sS --max-time 30 -o "$TMP" -w '%{http_code}' "${@:3}" --config - "$2" 2>/dev/null < <(printf 'header = "Authorization: Bearer %s"\n' "$1"))" || true  # [mut:fetch]
  [[ "$HTTP" =~ ^[0-9]{3}$ ]] || HTTP=000
}

SENTRY_EVENTS=""
read_sentry() {
  fetch "$SENTRY_ACTIONS_RO_TOKEN" "$SENTRY_URL" -H 'Accept: application/json'
  [[ "$HTTP" == "200" ]] || cannot "Sentry read failed (http=${HTTP})"  # [mut:sentry-fail]
  SENTRY_EVENTS="$(jq -r 'if (.data | type) == "array" then (.data | length) else "x" end' "$TMP" 2>/dev/null)"
  [[ "$SENTRY_EVENTS" =~ ^[0-9]{1,9}$ ]] || cannot "Sentry response unparseable"  # [mut:sentry-parse]
}

RECOVERABLE=""; AGED_OUT=""
read_supabase() {
  fetch "$SUPABASE_ACCESS_TOKEN" "$SB_URL" -X POST -H 'Content-Type: application/json' -d "$PAYLOAD"
  # The query endpoint answers 200 OR 201 on success.
  [[ "$HTTP" == "200" || "$HTTP" == "201" ]] || cannot "Supabase read failed (http=${HTTP})"  # [mut:sb-fail]
  local pair
  pair="$(jq -r 'if (type == "array" and length == 1 and (.[0] | type) == "object") then "\(.[0].recoverable | tostring) \(.[0].aged_out | tostring)" else "x x" end' "$TMP" 2>/dev/null)"
  RECOVERABLE="${pair%% *}"; AGED_OUT="${pair#* }"
  [[ "$RECOVERABLE" =~ ^[0-9]{1,9}$ && "$AGED_OUT" =~ ^[0-9]{1,9}$ ]] || cannot "Supabase response unparseable"  # [mut:sb-parse]
}

# BOTH sources are always read before any verdict: a failing second source must not hide behind a quiet first one.
read_sentry
# [mut:after-sentry]
read_supabase

echo "dispatch-recovery sweeper (#11211): criterion1 sentry_events=${SENTRY_EVENTS} criterion2 recoverable=${RECOVERABLE} aged_out=${AGED_OUT}"
if (( SENTRY_EVENTS > 0 && (RECOVERABLE + AGED_OUT) > 0 )); then  # [mut:decision]
  echo "ACTION REQUIRED: both re-evaluation criteria hold (an enqueue failure was observed and a stranded draft exists). The sweeper is NOT built by this probe and the tracker is NOT closed by the probe: decide on #11211 whether to build it, then close the issue and remove its follow-through label by hand."
  exit 5  # [mut:action]
fi
echo "NOT YET: the re-evaluation criteria do not both hold; the sweeper stays deferred."
exit 2
