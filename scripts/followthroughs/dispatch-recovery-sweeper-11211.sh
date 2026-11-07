#!/usr/bin/env bash
# Follow-through probe for #11211: has the DEFERRED dispatch-recovery sweeper's re-evaluation trigger fired?
#
# #11211 defers a service-role cron that would re-dispatch `action_sends` rows whose spawn event never reached
# Inngest (PR 11208 shipped the send path). It is deferred until both of these hold, and this probe reports the day
# they do, so the deferral cannot rot. This departs from the issue's literal "both criteria" in the FAIL-SAFE direction
# (a notify-only probe may over-report, never stay quiet): a stale-replay refusal counts toward both.
#   criterion 1  a spawn-agent failure was observed in production, Sentry events since 2026-10-26 (PR 11208's merge day):
#                ENQ   = tagged `feature:spawn-agent op:inngest-enqueue`      (the enqueue itself failed), or
#                STALE = tagged `feature:spawn-agent op:inngest-replay-stale` (a re-click was refused; the event
#                        carries `reason: expired` = older than the replay window, the draft is ARCHIVED, or
#                        `reason: future_clicked_at` = the clock_skew arm: a click time in the future beyond the skew
#                        tolerance or unparseable, NOT too old, and the draft is NOT archived);
#                holds when ENQ > 0 or STALE > 0;
#   criterion 2  a stranded send exists: an `action_sends` row with acknowledged_at, failure_reason, undone_at and
#                cancellation_requested_at all NULL, joined to a `messages` row still in status 'draft', whose
#                clicked_at is MORE than 1 h old, with NO upper bound on its age; holds when recoverable + aged_out > 0
#                OR STALE > 0 (an `expired` refusal archives its draft, so the stranded row can already be gone; a
#                `future_clicked_at` refusal leaves the draft in place, so the query may still count it).
# Criterion 2 is counted in two buckets that are printed separately: `recoverable` (clicked under 23 h ago: inside
# REPLAY_MAX_AGE_MS in apps/web-platform/server/action-sends/decide-replay.ts, so a founder re-click can still recover
# it; the 23 h cap is the Inngest event-id dedup horizon (about 24 h) minus a 1 h margin, and that horizon is ASSUMED:
# decide-replay.ts itself calls it a "plan-level assumption: not verified". The suite pins the `23 hours` literal
# below to that constant) and `aged_out` (over 23 h). The count can OVER-count (drafts with an unparseable `source_ref`,
# `no_artifact_in_pr_a`) and UNDER-count (a draft archived between daily runs; STALE covers that case only for an
# `expired` replay: the founder's discard route archives a draft with no STALE event). The table
# has held 0 rows ever (plan-time read 2026-10-29). `per_page=100` caps each Sentry count; only > 0 is ever used.
# ACTION REQUIRED (exit 5) fires on STALE > 0 alone, or on ENQ > 0 together with a stranded draft. The two Sentry
# queries carry no `environment:` filter, so a STALE (or ENQ) event from ANY environment (preview, staging, a
# developer's machine) counts, and since the window start is fixed, one such event keeps STALE > 0 (exit 5) every day.
# WHY THE QUERIES STAY UNFILTERED (#11572 item 5, measured 2026-10-30 against the Sentry org, 30 d window): events carrying
# an `op` tag number about 1.6k with environment production against about 18k with a null environment; every
# web-platform@x.y.z release event is production, the null-environment events are host emitters carrying other `feature`
# tags, and the org holds no non-production environment. `feature:spawn-agent` and `feature:dashboard-send` have 0 events,
# so an `environment:` filter has no positive control today. Leave the queries unfiltered. Re-evaluate when a preview or
# staging environment appears, or when the first real `feature:dashboard-send` event confirms `environment:production`.
# RESIDUAL: the two `op` tags are read from Sentry with no runtime positive control (none exists); the suite pins the
# tags against apps/web-platform/app/api/dashboard/today/[id]/send/route.ts, so a mistyped tag fails CI, but an op
# renamed in the route LATER would silently read 0 here.
#
# NOTIFY-ONLY probe: this tracker is never closed by a script, so nothing here exits 0 or 1
# (followthrough-convention.md, the TRANSIENT sub-vocabulary):
#   2 = NOT YET           the normal daily state (a criterion does not hold)
#   3 = CANNOT ESTABLISH  any read, auth, shape or parse failure, an unusable credential, or an empty answer. The first
#                         failing read exits at once, so a source AFTER it is not reached; when no read fails, all
#                         THREE (ENQ, STALE, Supabase) complete before any verdict, so a quiet source never hides a
#                         failing later one
#   5 = ACTION REQUIRED   both criteria hold: a human decides whether to build the sweeper
#  78 = refused to run under xtrace (#7797), before any credential is read
# THE SWEEPER HAS NO DEDUP: EVERY verdict (2 included) posts one comment per open-tracker sweep, about 30 a month. To
# stop them, remove the directive from the issue body or the `follow-through` label (aged-out rows never clear on
# their own, so a 5 repeats daily until then).
#
# THE SWEEPER POSTS THIS OUTPUT AS A PUBLIC ISSUE COMMENT (the last 4 KB, run with 2>&1). Output is therefore COUNTS
# and fixed reason strings plus an HTTP status code only: never a response body, a curl error, an identifier or a
# timestamp of an individual row. The Supabase token can run writes and DDL; the READ-ONLY control is the suite's
# exact-text pin of the ONE literal query below (no interpolation, no `;`). The runtime `^SELECT`/no-`;` check is a
# tripwire against an accidental edit, NOT that control.
#
# CREDENTIAL POSTURE: SENTRY_ACTIONS_RO_TOKEN (org-level read-only integration, ADR-031) and SUPABASE_ACCESS_TOKEN,
# both already bound in scheduled-followthrough-sweeper.yml, so no workflow edit and no new secret. Each rides curl's
# stdin config (a process substitution), never its argument list, and only to its own host. Every request is bounded
# by `--max-time 30` (the suite pins it) and the TLS-subverting environment is unset before any token is sent.
# Directive (added to the #11211 body at ship time, unfenced at column 0, on ONE line):
#   <!-- soleur:followthrough script=scripts/followthroughs/dispatch-recovery-sweeper-11211.sh earliest=2026-10-30T00:00:00Z secrets=SENTRY_ACTIONS_RO_TOKEN,SUPABASE_ACCESS_TOKEN -->
# `earliest=` is the first sweep day, NOT a deadline: the probe never closes the issue and an elapsed date proves nothing.
#
# RETIREMENT (delete together when #11211 is built or closed): this file, scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh,
# their `run_suite` row in scripts/test-all.sh, their .github/CODEOWNERS rows, the tracker directive (or its `follow-through`
# label), and the back-pointer comment above REPLAY_MAX_AGE_MS in decide-replay.ts.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;  # [mut:xtrace]
esac
trap 'set -- "$?"; if [[ -n "${TMP:-}" ]]; then rm -f "$TMP"; fi; case "$1" in 2|3|5|78) ;; *) echo "CANNOT ESTABLISH: internal error (unexpected exit status, or killed by a signal)"; exit 3 ;; esac' EXIT  # [mut:trap]

cannot() { echo "CANNOT ESTABLISH: $1"; exit 3; }

# The same line scripts/betterstack-query.sh (#7873) carries: an environment that subverts TLS itself (session-key log,
# substitute trust store, host aliases) must not be able to read a bearer token off the wire.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS  # [mut:tls-unset]

# Token-shape check only (empty, or any char outside the allowlist, e.g. a newline that would inject a curl config
# directive on the stdin channel below). Never echoes a value. Explicit guards, never `${VAR:?}` (that aborts with 1).
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_bearer_ok "${SENTRY_ACTIONS_RO_TOKEN:-}" || cannot "SENTRY_ACTIONS_RO_TOKEN unusable"  # [mut:token-check-sentry]
_bearer_ok "${SUPABASE_ACCESS_TOKEN:-}" || cannot "SUPABASE_ACCESS_TOKEN unusable"  # [mut:token-check-supabase]
command -v jq >/dev/null 2>&1 || cannot "jq is not available"

NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW_EPOCH" =~ ^[1-9][0-9]{0,15}$ ]] || cannot "unusable NOW_EPOCH"  # no leading zero: it would be octal inside (( ))
END_ISO="$(date -u -d "@${NOW_EPOCH}" '+%Y-%m-%dT%H%%3A%M%%3A%S' 2>/dev/null)"
[[ -n "$END_ISO" ]] || cannot "could not format the window end"

TMP="$(mktemp "${TMPDIR:-/tmp}/ft11211.XXXXXX")" || cannot "mktemp failed"

# Criterion 1, two plain Sentry reads (never one `op:[a,b]`), URL-encoded: ENQ = `feature:spawn-agent op:inngest-enqueue`,
# STALE = `feature:spawn-agent op:inngest-replay-stale`, both since PR 11208 merged.
# Bound literals ride the /events/ logical line itself (lint rule 6): the bound on a
# separate statement is the lint's declared blind spot, so BASE/TAIL assembly is inlined.
ENQ_URL="https://de.sentry.io/api/0/organizations/jikigai-eu/events/?query=feature%3Aspawn-agent%20op%3Ainngest-enqueue&start=2026-10-26T00%3A00%3A00&end=${END_ISO}&dataset=errors&per_page=100&field=id&field=timestamp"  # [mut:enq-url]
STALE_URL="https://de.sentry.io/api/0/organizations/jikigai-eu/events/?query=feature%3Aspawn-agent%20op%3Ainngest-replay-stale&start=2026-10-26T00%3A00%3A00&end=${END_ISO}&dataset=errors&per_page=100&field=id&field=timestamp"  # [mut:stale-url]

# Criterion 2: ONE literal string. No interpolation, no `;`, `now() - interval` in SQL, never a shell-built timestamp.
readonly QUERY="SELECT count(*) FILTER (WHERE s.clicked_at >= now() - interval '23 hours') AS recoverable, count(*) FILTER (WHERE s.clicked_at < now() - interval '23 hours') AS aged_out FROM public.action_sends s JOIN public.messages m ON m.id = s.message_id WHERE s.acknowledged_at IS NULL AND s.failure_reason IS NULL AND s.undone_at IS NULL AND s.cancellation_requested_at IS NULL AND m.status = 'draft' AND s.clicked_at < now() - interval '1 hour'"  # [mut:query]
[[ "$QUERY" == SELECT* && "$QUERY" != *';'* ]] || cannot "the query is not a single SELECT"  # tripwire only: the suite's exact-text pin is the control
SB_URL="https://api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query"
PAYLOAD="$(jq -n --arg q "$QUERY" '{query: $q}')" || cannot "could not build the request payload"

# A count is a canonical non-negative integer: a leading zero is OCTAL inside bash `(( ))` ("08" is an invalid base-8 value).
readonly COUNT_RE='^(0|[1-9][0-9]{0,8})$'  # [mut:count-re]

# fetch <token> <url> [curl args...]: sets HTTP; the body lands in $TMP and is parsed, never printed.
fetch() {
  truncate -s 0 "$TMP"
  HTTP="$(curl --disable --noproxy '*' -sS --max-time 30 -o "$TMP" -w '%{http_code}' "${@:3}" --config - "$2" 2>/dev/null < <(printf 'header = "Authorization: Bearer %s"\n' "$1"))" || true  # [mut:fetch]
  [[ "$HTTP" =~ ^[0-9]{3}$ ]] || HTTP=000
}

# read_sentry <url>: sets COUNT to the number of events (a bounded page; only > 0 is used).
COUNT=""
read_sentry() {
  fetch "$SENTRY_ACTIONS_RO_TOKEN" "$1" -H 'Accept: application/json'
  [[ "$HTTP" == "200" ]] || cannot "Sentry read failed (http=${HTTP})"  # [mut:sentry-fail]
  COUNT="$(jq -r 'if (.data | type) == "array" then (.data | length) else "x" end' "$TMP" 2>/dev/null)"
  [[ "$COUNT" =~ $COUNT_RE ]] || cannot "Sentry response unparseable"  # [mut:sentry-parse]
}

RECOVERABLE=""; AGED_OUT=""
read_supabase() {
  fetch "$SUPABASE_ACCESS_TOKEN" "$SB_URL" -X POST -H 'Content-Type: application/json' -d "$PAYLOAD"
  # The query endpoint answers 200 OR 201 on success.
  [[ "$HTTP" == "200" || "$HTTP" == "201" ]] || cannot "Supabase read failed (http=${HTTP})"  # [mut:sb-fail]
  local pair
  pair="$(jq -r 'if (type == "array" and length == 1 and (.[0] | type) == "object") then "\(.[0].recoverable | tostring) \(.[0].aged_out | tostring)" else "x x" end' "$TMP" 2>/dev/null)"
  RECOVERABLE="${pair%% *}"; AGED_OUT="${pair#* }"
  [[ "$RECOVERABLE" =~ $COUNT_RE && "$AGED_OUT" =~ $COUNT_RE ]] || cannot "Supabase response unparseable"  # [mut:sb-parse]
}

# All three reads complete before any verdict, so a quiet first source never hides a failing later one.
read_sentry "$ENQ_URL"; ENQ="$COUNT"
# [mut:after-enq]
read_sentry "$STALE_URL"; STALE="$COUNT"
# [mut:after-sentry]
read_supabase

echo "dispatch-recovery sweeper (#11211): criterion1 enqueue_events=${ENQ} replay_stale_events=${STALE} criterion2 recoverable=${RECOVERABLE} aged_out=${AGED_OUT}"
if (( (ENQ > 0 || STALE > 0) && ((RECOVERABLE + AGED_OUT) > 0 || STALE > 0) )); then  # [mut:decision]
  echo "ACTION REQUIRED: both re-evaluation criteria hold (a spawn-agent failure was observed and a stranded or refused-stale send exists). The sweeper is NOT built by this probe and the tracker is NOT closed by the probe: decide on #11211 whether to build it, then close the issue and remove its follow-through label by hand."
  exit 5  # [mut:action]
fi
echo "NOT YET: the re-evaluation criteria do not both hold; the sweeper stays deferred."
exit 2
