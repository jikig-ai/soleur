#!/usr/bin/env bash
# Follow-through close gate for #8740 (a committed C4 model with elements but no
# views renders an empty diagram with no explanation).
#
# The fix makes GET /api/kb/c4/project detect a zero-view model on read, return a
# model-level diagnostic, and emit a debounced Sentry warning tagged
# feature=c4-project-read op=zero-view-model (apps/web-platform/app/api/kb/c4/
# project/route.ts, the single mirrorWarnWithDebounce call). This probe closes
# #8740 by PROOF BY ABSENCE: the fix is live, the production Sentry sink was
# live, and no production zero-view load was recorded in the trailing 14 days.
# Its FAIL comment is the push signal for option (c) in #8740.
#
# ── EXIT CONTRACT (sweep-followthroughs.sh map) ──────────────────────────────
#   0  PASS             -- all three hold; the sweeper closes #8740.
#   1  FAIL             -- >=1 production zero-view load in 14d. Taken WHATEVER
#                          checks 3 and 4 would say: a load is a load.
#   2  NOT YET          -- production does not yet run the commit that added
#                          this probe (merge-base --is-ancestor rc 1).
#   3  CANNOT ESTABLISH -- a measurement could not be made; the line says which.
#   78 refused to run under xtrace with the credential set (#7797).
# Every exit prints exactly one fixed reason line and nothing else.
#
# ── CHECK ORDER (load-bearing; the single `exit 0` is reachable only through
#    all four, in this order) ───────────────────────────────────────────────────
#   1. token set?             unset -> 3, before any network call.
#   2. signal query           `feature:<SIGNAL_FEATURE> op:<SIGNAL_OP>
#                             environment:production`, 14d. Non-200 or a body
#                             that is not an event array -> 3. Count >=1 -> 1.
#   3. fix deployed           /health build_sha (validated ^[0-9a-f]{40}$ BEFORE
#                             any git call), the commit that ADDED this file
#                             (git log --diff-filter=A, derived, never stored),
#                             git cat-file -e, git merge-base --is-ancestor
#                             <intro> <build_sha>: rc 0 continues, rc 1 -> 2,
#                             anything else -> 3.
#   4. sink live              `event_type:server-startup environment:production`
#                             in 14d. Non-200 / non-array -> 3. Zero -> 3.
#   5. exit 0.
# The /health check proves the fix is live NOW (a positive control the old
# artifact cannot produce, #7220); the liveness check proves the production
# Sentry sink was live at >=1 server restart inside the window. Neither alone
# makes "0 events" mean anything.
#
# ── OUTPUT RULES (the repo and the sweeper comment are public) ───────────────
# Never print a response body, nor any event's dir, modelPath, userIdHash or
# elementCount. A non-200 prints the status only. build_sha is printed only
# after validation, and the FAIL line's timestamp only after it matches an ISO
# shape. curl/jq/git stderr is discarded so no subprocess can relay bytes.
#
# ── CREDENTIAL POSTURE ───────────────────────────────────────────────────────
# SENTRY_ACTIONS_RO_TOKEN only (directive secrets=, the org-level read-only
# integration, ADR-031). It reaches curl as a header on stdin (`-H @-` fed by a
# printf builtin), never on argv. The /health call carries no Authorization.
# The git calls are local reads of the sweeper's fetch-depth: 0 checkout.
#
# ── RESIDUAL RISK ────────────────────────────────────────────────────────────
# Both Sentry signals can be forged by anyone holding the semi-public browser
# DSN: a forged server-startup keeps the sink "live", a forged zero-view event
# forces FAIL. Either affects only #8740's state (a wrong close or a stuck-open
# tracker), no user data.
#
# ── HOW TO STOP THE DAILY FAIL COMMENTS ──────────────────────────────────────
# After choosing option (b) or (c) on #8740, remove the soleur:followthrough
# directive from #8740's body. Re-adding it with a new `earliest=` re-arms it.
#
# RETIREMENT: in this order --
#   1. remove the soleur:followthrough directive from #8740's body;
#   2. delete this script and scripts/followthroughs/c4-zero-view-model-8740.test.sh;
#   3. remove the c4-zero-view-model-8740 run_suite row (and its comment) from
#      scripts/test-all.sh.
#   Then re-census `git grep c4-zero-view-model-8740` (the plan and ADR-050's
#   addendum mention it; point-in-time records may stay).

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so a credential is printed the moment it is used. The test below
# covers EVERY credential this file references and uses `${VAR:+x}`, which is
# non-emptiness WITHOUT expanding the value -- `${VAR:-}` would print it here.
# Tracing stays available with the credentials unset, so this refuses a leak
# without blocking a debugging session.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_ACTIONS_RO_TOKEN). Unset it to trace safely (see #7797).
' >&2
      exit 78
    fi
    ;;
esac

# The route's Sentry tags. The .test.sh drift row reads THESE two lines and
# checks them against the mirrorWarnWithDebounce call in route.ts.
readonly SIGNAL_FEATURE="c4-project-read"
readonly SIGNAL_OP="zero-view-model"

readonly PROBE_PATH="scripts/followthroughs/c4-zero-view-model-8740.sh"
readonly SENTRY_EVENTS_URL="https://sentry.io/api/0/organizations/jikigai-eu/events/"
# The web-platform project id (scripts/sentry-issue.sh PINNED_PROJECT_ID).
readonly SENTRY_PROJECT_ID="4511404943671376"
readonly HEALTH_URL="https://app.soleur.ai/health"
readonly WINDOW="14d"

# 1. TOKEN
if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then
  echo "CANNOT ESTABLISH: token unset"
  exit 3
fi

# split_status <curl output>: sets RESP_STATUS (3 digits, or "malformed") and
# RESP_BODY. The trailer is the LAST line only, so a body line that happens to
# start with HTTP_STATUS: cannot steer it.
split_status() {
  local resp="$1" last
  last="${resp##*$'\n'}"
  RESP_STATUS="${last#HTTP_STATUS:}"
  if [[ "$last" != HTTP_STATUS:* || ! "$RESP_STATUS" =~ ^[0-9]{3}$ ]]; then
    RESP_STATUS="malformed"
    RESP_BODY=""
    return
  fi
  if [[ "$resp" == *$'\n'* ]]; then RESP_BODY="${resp%$'\n'*}"; else RESP_BODY=""; fi
}

# sentry_query <query>: sets SQ_STATUS, SQ_COUNT, SQ_NEWEST.
# Returns 0 on a 200 whose body is an object with a .data array, 1 on a
# non-200 (SQ_STATUS says which), 2 on a 200 that is not an event array.
sentry_query() {
  local enc url resp
  SQ_STATUS="000"; SQ_COUNT=""; SQ_NEWEST=""
  enc="$(printf '%s' "$1" | jq -sRr @uri 2>/dev/null)" || enc=""
  if [[ -z "$enc" ]]; then SQ_STATUS="unencodable"; return 1; fi
  url="${SENTRY_EVENTS_URL}?project=${SENTRY_PROJECT_ID}&query=${enc}&statsPeriod=${WINDOW}&per_page=100&sort=-timestamp&field=timestamp"
  resp="$(printf 'Authorization: Bearer %s\n' "$SENTRY_ACTIONS_RO_TOKEN" \
    | curl --disable --noproxy '*' -m 20 -sS -w '\nHTTP_STATUS:%{http_code}' \
        -H @- -H 'Accept: application/json' "$url" 2>/dev/null)" || true
  split_status "$resp"
  SQ_STATUS="$RESP_STATUS"
  [[ "$SQ_STATUS" == "200" ]] || return 1
  # SHAPE BEFORE COUNT: `{}` or an error object has no .data, and a defaulted 0
  # would be a counted zero -- the vacuous PASS this gate exists to refuse.
  SQ_COUNT="$(printf '%s' "$RESP_BODY" \
    | jq -r 'if type == "object" and (.data | type) == "array" then (.data | length) else error("shape") end' 2>/dev/null)" \
    || SQ_COUNT=""
  [[ "$SQ_COUNT" =~ ^[0-9]+$ ]] || return 2
  SQ_NEWEST="$(printf '%s' "$RESP_BODY" \
    | jq -r '.data[0].timestamp | if type == "string" then . else empty end' 2>/dev/null)" \
    || SQ_NEWEST=""
  [[ "$SQ_NEWEST" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?$ ]] \
    || SQ_NEWEST="unknown"
  return 0
}

# 2. SIGNAL -- before everything else: a production load is FAIL whatever the
# deploy or the sink says.
sentry_query "feature:${SIGNAL_FEATURE} op:${SIGNAL_OP} environment:production"
sq_rc=$?
case "$sq_rc" in
  0) ;;
  1) echo "CANNOT ESTABLISH: signal query ${SQ_STATUS}"; exit 3 ;;
  *) echo "CANNOT ESTABLISH: signal query 200 (body is not an event array)"; exit 3 ;;
esac
if (( SQ_COUNT >= 1 )); then
  shown="$SQ_COUNT"
  (( SQ_COUNT >= 100 )) && shown=">=100"
  echo "FAIL: ${shown} production zero-view loads in ${WINDOW}, newest ${SQ_NEWEST}"
  exit 1
fi

# 3. FIX DEPLOYED. No Authorization header on this call, ever.
resp="$(curl --disable --noproxy '*' --proto '=https' --max-redirs 0 -m 10 --max-filesize 65536 \
  -sS -w '\nHTTP_STATUS:%{http_code}' "$HEALTH_URL" 2>/dev/null)" || true
split_status "$resp"
if [[ "$RESP_STATUS" != "200" ]]; then
  echo "CANNOT ESTABLISH: /health ${RESP_STATUS}"
  exit 3
fi
BUILD_SHA="$(printf '%s' "$RESP_BODY" \
  | jq -r 'if type == "object" and (.build_sha | type) == "string" then .build_sha else empty end' 2>/dev/null)" \
  || BUILD_SHA=""
# Validated BEFORE any git call: `dev`, `HEAD`, `-h` or a short sha must never
# reach git as a revision or an option.
if [[ ! "$BUILD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "CANNOT ESTABLISH: /health build_sha is not a 40-hex commit id"
  exit 3
fi
INTRO="$(git log --diff-filter=A --format=%H -1 -- "$PROBE_PATH" 2>/dev/null)" || INTRO=""
if [[ ! "$INTRO" =~ ^[0-9a-f]{40}$ ]]; then
  echo "CANNOT ESTABLISH: introducing commit of this probe not derivable (needs full history)"
  exit 3
fi
if ! git cat-file -e "${BUILD_SHA}^{commit}" 2>/dev/null; then
  echo "CANNOT ESTABLISH: deployed build_sha ${BUILD_SHA:0:12} is not a commit in this checkout"
  exit 3
fi
git merge-base --is-ancestor "$INTRO" "$BUILD_SHA" 2>/dev/null
mb_rc=$?
case "$mb_rc" in
  0) ;;
  1) echo "NOT YET: fix not live (production runs ${BUILD_SHA:0:12})"; exit 2 ;;
  *) echo "CANNOT ESTABLISH: merge-base --is-ancestor rc ${mb_rc}"; exit 3 ;;
esac

# 4. SINK LIVE -- without it, 0 zero-view events is silence, not absence.
sentry_query "event_type:server-startup environment:production"
sq_rc=$?
case "$sq_rc" in
  0) ;;
  1) echo "CANNOT ESTABLISH: liveness query ${SQ_STATUS}"; exit 3 ;;
  *) echo "CANNOT ESTABLISH: liveness query 200 (body is not an event array)"; exit 3 ;;
esac
if (( SQ_COUNT == 0 )); then
  echo "CANNOT ESTABLISH: no production server-startup in window"
  exit 3
fi

# 5. PASS
echo "PASS: 0 production zero-view loads in ${WINDOW} (proof by absence; fix live at ${BUILD_SHA:0:12})"
exit 0
