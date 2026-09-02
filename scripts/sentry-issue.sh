#!/usr/bin/env bash
# Read a Sentry issue / its latest event inline, for no-SSH agent debugging (#5495).
#
# Reads are GET-only and least-privilege. The issue/event endpoints require an
# `event:read`-scoped token: SENTRY_API_TOKEN / SENTRY_AUTH_TOKEN 403 on
# /issues/<id>/ (Discover/ingest scope only — see postmerge/SKILL.md). Use the
# dedicated read-only SENTRY_ISSUE_RO_TOKEN (scopes [event:read, org:read]); the
# write-scoped SENTRY_ISSUE_RW_TOKEN is a GET-only fallback until the RO token is
# minted (see runbook).
#
# Provisioning: SENTRY_ISSUE_RO_TOKEN lives in Doppler soleur/prd. To re-mint, see
# knowledge-base/engineering/operations/runbooks/sentry-issue-read.md.
#
# Host: the EU org-subdomain jikigai-eu.sentry.io (NOT eu.sentry.io — it rewrites
# `-eu` slugs). See ADR-031 glossary. An earlier revision of this line also said
# "NOT de.sentry.io — ingest-only, 404s on /api/"; that is not what the API does
# today. Measured 2026-09-02: de.sentry.io returned HTTP 200 on
# /api/0/organizations/jikigai-eu/events/, and apps/web-platform/infra/scripts/
# fresh-host-boot-trail.sh reads it in production. The org subdomain remains this
# script's default because it is the repo's convention, not because de. 404s.
#
# HOST-SCOPED DISCOVER READS (#7481). Two additional modes, so the git-data rung-2
# capture route gains a SECOND channel without standing up another reader OF THIS
# ENDPOINT FAMILY. Scoped deliberately: the repo holds ~23 direct Sentry Web API call
# sites overall (a runtime TS reader in server/inngest, two inline workflow readers, and
# several agent-executed skill paths), so a flat "no third Sentry reader in this repo"
# would be false by about twenty. What this avoids is a second implementation of the
# issue/event READ that this file already owns, with its own token ladder and its own
# 401/403 wording to drift.
#   scripts/sentry-issue.sh --host-events <host_name> [--start ISO --end ISO | --stats-period 90d]
#   scripts/sentry-issue.sh --liveness <host_name_to_EXCLUDE> [--stats-period 90d]
#
# WHY DISCOVER AND NOT /projects/<org>/<proj>/events/. The plan specified the project
# events endpoint. Measured 2026-09-02, it is wrong twice over:
#   - SENTRY_ISSUE_RO_TOKEN ([event:read, org:read]) gets HTTP 403 there. Only the
#     broader SENTRY_AUTH_TOKEN reads it, and this route prints into a PUBLIC Actions
#     artifact, so reaching for the wider token is the wrong direction.
#   - With SENTRY_AUTH_TOKEN it returns 200 but does not parse TAG syntax: it applies
#     `query` as a free-text match over the event title, so `Error` returns 100 rows and
#     `host_name:<H>` / `environment:production` return 0 even though the tag is on every
#     row. It is a latest-events endpoint, not a search one. (An earlier draft of this note
#     said it "IGNORES the search", which the 100-vs-0 split actually refutes — an endpoint
#     ignoring `query` would return 100 both times.)
# /api/0/organizations/<org>/events/ with explicit `field=` projections answers both:
# HTTP 200 on the RO token, and it honours the query. It is also EVENT-level, which is
# what the plan wanted the project endpoint for — so the issue-group residual (a group
# whose level is fatal need not carry a fatal event from THIS host) never arises, and
# no ADR-147 level-homogeneity argument is needed to paper over it.
#
# ORG AND PROJECT ARE PINNED LITERALS IN THESE MODES, never read from the environment.
# That is #7481 defect 2: callers run under `doppler run -c prd_terraform`, which
# exports every secret in that config, so a SENTRY_ORG present there would silently
# beat a `${SENTRY_ORG:-default}` and redirect the read.
#
# EXIT CONTRACT. 0 on success. A 401 exits 77 and a 403 exits 78 — DISTINCT and
# TERMINAL, because they are repo/credential-side and identical on every attempt: a
# caller that retries them burns its whole poll budget to report the least actionable
# verdict. Every other failure exits 1.
#
# Usage (under doppler so the token is injected from soleur/prd):
#   doppler run -p soleur -c prd -- scripts/sentry-issue.sh <issue-id>
#   doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event <issue-id>
#   ... append --redact to mask obvious email/bearer values for shared contexts.
#
# Output: JSON on stdout. Read the real error at exception.values[].value (message)
# + exception.values[].stacktrace.frames[] (stack). PII caveat below.
set -uo pipefail   # never `set -x` — would trace the Bearer header to stderr.

HOST="${SENTRY_API_HOST:-jikigai-eu.sentry.io}"
ORG="${SENTRY_ORG:-jikigai-eu}"

# PINNED, NOT ENV-SOURCED (#7481 defect 2) — see the pinning note in the header. The
# numeric project id is what /api/0/organizations/jikigai-eu/projects/ reports for the
# `web-platform` project, read 2026-09-02; recorded here so the next reader does not
# inherit a bare magic number.
PINNED_ORG='jikigai-eu'
PINNED_PROJECT_ID='4511404943671376'
# AND THE HOST. Pinning the org and project and leaving `HOST` env-sourced was defect 2
# followed through on two operands of three — and the third is the worst one: redirecting
# ORG misdirects a READ, redirecting HOST sends the `Authorization: Bearer` header to an
# attacker-chosen origin. Measured 2026-09-03: SENTRY_API_HOST IS present in
# `prd_terraform` (value `jikigai-eu.sentry.io`, benign today), so `${SENTRY_API_HOST:-…}`
# is not a theoretical injection surface for a caller running under `doppler run -c
# prd_terraform` — it is a live one that happens to hold the right value.
PINNED_HOST='jikigai-eu.sentry.io'


REDACT=0
MODE="issue"
ISSUE_ID=""
EVENT_HOST=""
WIN_START=""
WIN_END=""
STATS_PERIOD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest-event) MODE="latest-event"; shift ;;
    # `shift 2 || shift` IS LOAD-BEARING, not defensive noise. A bare `shift 2` with only
    # the flag left FAILS and leaves $# unchanged, so the while loop never terminates —
    # measured: `--host-events` with no value hung until the caller's timeout killed it,
    # which is the worst shape for a flag whose whole job is to be validated and refused.
    --host-events) MODE="host-events"; EVENT_HOST="${2:-}"; shift 2 || shift ;;
    --liveness) MODE="liveness"; EVENT_HOST="${2:-}"; shift 2 || shift ;;
    --start) WIN_START="${2:-}"; shift 2 || shift ;;
    --end) WIN_END="${2:-}"; shift 2 || shift ;;
    --stats-period) STATS_PERIOD="${2:-}"; shift 2 || shift ;;
    --redact) REDACT=1; shift ;;   # honoured in every mode; see the discover 200-branch
    --) shift ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) ISSUE_ID="$1"; shift ;;
  esac
done

if [[ "$MODE" == "host-events" || "$MODE" == "liveness" ]]; then
  if [[ -z "$EVENT_HOST" ]]; then
    echo "usage: sentry-issue.sh --host-events <host_name> | --liveness <host_name_to_exclude> [--start ISO --end ISO | --stats-period 90d]" >&2
    exit 64
  fi
  # SAME DISCIPLINE AS THE ISSUE-ID CHECK BELOW, for the same reason one level over: this
  # value is interpolated into a Sentry SEARCH QUERY, and which rows the query returns IS
  # the verdict the caller computes. A space or a quote would let the caller rewrite the
  # query and silently change what was measured while still producing a verdict. The hosts
  # this reads are `soleur-git-data-rehearsal-<run-id>`, so the charset is narrow on purpose.
  #
  # THE CHARSET IS NOT WHAT KEEPS THIS OFF THE PRODUCTION HOST. `soleur-git-data` satisfies
  # it perfectly. What binds this to rehearsal hosts is the CALLER's prefix assertion in
  # scripts/followthroughs/git-data-rung2-evidence-capture.sh, which refuses any --host-name
  # outside `^soleur-git-data-rehearsal-`. This file is a general repo tool and will read
  # whatever host it is given; a future caller that projects `detail` into a public artifact
  # must carry its own prefix guard.
  if [[ ! "$EVENT_HOST" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "invalid host name '$EVENT_HOST' (allowed: [A-Za-z0-9._-]); refusing to build a query" >&2
    exit 64
  fi
  # A WINDOW IS MANDATORY, and the two shapes are mutually exclusive. An unwindowed read is
  # #7481 defect 5: `host_name` embeds the run id, but a run id is STABLE across GitHub
  # re-run ATTEMPTS, so attempt 2 of a fixed host would read attempt 1's fatal and report a
  # failure that has already been fixed.
  if [[ -n "$WIN_START" || -n "$WIN_END" ]]; then
    if [[ -z "$WIN_START" || -z "$WIN_END" ]]; then
      echo "--start and --end must be given together (Sentry rejects one without the other)" >&2
      exit 64
    fi
    if [[ -n "$STATS_PERIOD" ]]; then
      echo "--stats-period cannot be combined with --start/--end" >&2
      exit 64
    fi
    for _w in "$WIN_START" "$WIN_END"; do
      if [[ ! "$_w" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo "invalid window bound '$_w' (want YYYY-MM-DDTHH:MM:SS)" >&2
        exit 64
      fi
    done
  else
    STATS_PERIOD="${STATS_PERIOD:-90d}"
    if [[ ! "$STATS_PERIOD" =~ ^[0-9]+[mhdw]$ ]]; then
      echo "invalid --stats-period '$STATS_PERIOD' (want <n>m|h|d|w)" >&2
      exit 64
    fi
  fi
elif [[ -z "$ISSUE_ID" ]]; then
  echo "usage: sentry-issue.sh [--latest-event] [--redact] <issue-id>" >&2
  exit 64
fi

# Issue-id charset validation BEFORE any URL interpolation. Closes path/endpoint
# injection (load-bearing given the EU slug-rewrite trap): a `/`, `?`, or `..`
# would rewrite the request path and could escape the read endpoint allowlist.
if [[ -n "$ISSUE_ID" && ! "$ISSUE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "invalid issue-id '$ISSUE_ID' (allowed: [A-Za-z0-9_-]); refusing to build a URL" >&2
  exit 64
fi

# Token resolution: prefer the least-privilege read-only token; fall back to the
# write-scoped token GET-only with a loud warning (never the steady state).
if [[ -n "${SENTRY_ISSUE_RO_TOKEN:-}" ]]; then
  TOKEN="$SENTRY_ISSUE_RO_TOKEN"
elif [[ -n "${SENTRY_ISSUE_RW_TOKEN:-}" ]]; then
  TOKEN="$SENTRY_ISSUE_RW_TOKEN"
  echo "WARNING: using RW token GET-only; mint SENTRY_ISSUE_RO_TOKEN (see runbook)" >&2
else
  echo "ERROR: no Sentry read token. Set SENTRY_ISSUE_RO_TOKEN in Doppler soleur/prd (see runbook)." >&2
  exit 1
fi

# URL allowlist — read endpoints only, both event:read, built from the fixed method
# GET with no request body. The discover modes use the PINNED org, never $ORG.
case "$MODE" in
  issue)              PATH_PART="/api/0/organizations/${ORG}/issues/${ISSUE_ID}/" ;;
  latest-event)       PATH_PART="/api/0/organizations/${ORG}/issues/${ISSUE_ID}/events/latest/" ;;
  host-events|liveness) PATH_PART="/api/0/organizations/${PINNED_ORG}/events/" ;;
esac
if [[ "$MODE" == "host-events" || "$MODE" == "liveness" ]]; then
  URL="https://${PINNED_HOST}${PATH_PART}"
else
  URL="https://${HOST}${PATH_PART}"
fi

# ── the discover modes (#7481) ──────────────────────────────────────────────────
if [[ "$MODE" == "host-events" || "$MODE" == "liveness" ]]; then
  QARGS=(--data-urlencode "project=${PINNED_PROJECT_ID}")
  if [[ -n "$WIN_START" ]]; then
    QARGS+=(--data-urlencode "start=${WIN_START}" --data-urlencode "end=${WIN_END}")
  else
    QARGS+=(--data-urlencode "statsPeriod=${STATS_PERIOD}")
  fi
  if [[ "$MODE" == "host-events" ]]; then
    # `level:fatal` at the EVENT level closes #7481 defect 1. cloud-init emits an
    # UNCONDITIONAL level:info bootcmd beacon tagged with host_name on every boot, so a
    # query of host_name alone matches a PERFECTLY HEALTHY host and every rehearsal would
    # false-FAIL. Measured against the 2026-07-31 rehearsal host: 5 rows unfiltered
    # (2 fatal, 1 warning, 2 info), 2 rows with this filter.
    #
    # `detail` and `rc` ARE PROJECTED, and that is #7481's §4.5a. Fixing WHO reads Sentry
    # while leaving WHAT it prints unspecified reproduces this route's originating
    # incident: the 2026-07-31 capture reported the verdict and not the cause, because
    # HOST_SQL did not SELECT detail. `stage` says which stage died; `detail` and `rc` say
    # why. All three are `_clean`-scrubbed at the producer (the emitter truncates to 180
    # bytes after its redaction passes), so this is a projection choice, not a new leak.
    QARGS+=(--data-urlencode "field=timestamp" --data-urlencode "field=level"
            --data-urlencode "field=host_name" --data-urlencode "field=stage"
            --data-urlencode "field=rc" --data-urlencode "field=detail"
            --data-urlencode "sort=-timestamp"
            --data-urlencode "query=host_name:${EVENT_HOST} level:fatal")
  else
    # LIVENESS: "is this source answering at all", and it must be independent of the host
    # it anchors for. Excluding that host is not a detail — its own unconditional info
    # beacon would otherwise satisfy the anchor, making it vacuous exactly when it matters.
    #
    # COUNT ONLY, never title/culprit/detail. The caller prints into a PUBLIC Actions
    # artifact, and an anchor needs one bit — is anything arriving — so projecting event
    # content here would export production boot telemetry to answer a yes/no question.
    QARGS+=(--data-urlencode "field=count()"
            --data-urlencode "query=!host_name:${EVENT_HOST}")
  fi

  # STATUS INTO A SEPARATE STREAM, never appended to the body. Measured while composing
  # this: `--write-out` text appended to the response makes the whole payload unparseable
  # (`json.decoder.JSONDecodeError: Extra data`), and a parser that then reports "not an
  # array" would blame the endpoint for the reader's own framing bug.
  #
  # NO -v AND NO --trace*: those dump the Authorization header verbatim, and this output is
  # piped into a public artifact by the rung-2 capture route. curl's ordinary stderr echoes
  # scheme and host only, so it is kept for diagnosis.
  _body_f="$(mktemp -t sentry-disc.XXXXXXXX.json)"
  _err_f="$(mktemp -t sentry-disc.XXXXXXXX.err)"
  CODE="$(curl -sS --max-time 30 -G -o "$_body_f" -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Accept: application/json' \
    "${QARGS[@]}" "$URL" 2>"$_err_f")" || CODE="000"
  BODY="$(cat "$_body_f" 2>/dev/null || echo '')"
  ERRTXT="$(cat "$_err_f" 2>/dev/null || echo '')"
  rm -f "$_body_f" "$_err_f"

  case "$CODE" in
    200)
      # SHAPE BEFORE COUNT. `jq -e` on `null | length` returns 0 AND exits 0, so a count is
      # never the first thing trusted: a 200 whose body is HTML (a CDN or captive-portal
      # interstitial) or an error object must read as unusable, not as "zero events".
      if ! printf '%s' "$BODY" | jq -e 'type == "object" and ((.data | type) == "array")' >/dev/null 2>&1; then
        echo "ERROR: Sentry returned HTTP 200 for ${PATH_PART} but the body is not a discover result object with a .data array. The read did NOT run; this is NOT an 'emitted nothing' result." >&2
        printf '%s\n' "$BODY" | head -c 400 >&2; echo >&2
        exit 1
      fi
      # --redact IS HONOURED HERE. It was parsed and then consumed only in the issue/
      # latest-event branch, so `--host-events --redact` produced UNREDACTED output with no
      # warning — on the only modes whose stdout is written into a public Actions artifact.
      # A flag that silently does nothing is worse than one that refuses.
      if (( REDACT )); then
        printf '%s\n' "$BODY" | sed -E \
          -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[redacted-email]/g' \
          -e 's/(Bearer|Authorization|token)[" :=]+[A-Za-z0-9._-]{8,}/\1 [redacted]/gI'
      else
        printf '%s\n' "$BODY"
      fi
      exit 0 ;;
    401)
      echo "ERROR: 401 from Sentry (discover). A 401 is a token-SCOPE / membership signal, not proof the org is unowned (ADR-031 glossary). DETERMINISTIC: identical on every attempt — do NOT retry. Verify SENTRY_ISSUE_RO_TOKEN's org-membership scope for '${PINNED_ORG}'." >&2
      exit 77 ;;
    403)
      echo "ERROR: 403 from Sentry (discover) — the token lacks the scope for /organizations/${PINNED_ORG}/events/. Use SENTRY_ISSUE_RO_TOKEN ([event:read, org:read]). NOTE: SENTRY_AUTH_TOKEN also reads this endpoint (measured 200, 2026-09-03) — RO is required here for artifact-hygiene reasons, not capability ones, so a 403 means the token lacks org membership or the scope, not that you picked the wrong one of two working tokens. DETERMINISTIC: identical on every attempt — do NOT retry." >&2
      exit 78 ;;
    *)
      echo "ERROR: Sentry GET ${PATH_PART} returned HTTP ${CODE}." >&2
      [[ -n "$ERRTXT" ]] && printf '%s\n' "$ERRTXT" >&2
      printf '%s\n' "$BODY" | head -c 400 >&2; echo >&2
      exit 1 ;;
  esac
fi

# Operator-hygiene caveat (NOT a transfer control — PII is in the stdout body the
# agent consumes). Sentry's ingest scrub is key-name only; message/breadcrumb/tag
# and user.* values may carry residual PII.
echo "NOTE: Sentry event bodies may contain residual user PII (message/breadcrumb/tag/user.* values) not removed by the ingest key-scrub — do not paste into shared/persistent contexts." >&2

# GET-only. -w appends the HTTP status on its own trailing line so we can map
# 401/403 without --fail-with-body (which would swallow the parse).
RESP="$(curl -sS --max-time 30 -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Accept: application/json' \
  -w $'\n%{http_code}' "$URL")"
CODE="$(printf '%s' "$RESP" | tail -n1)"
BODY="$(printf '%s' "$RESP" | sed '$d')"

case "$CODE" in
  200)
    if (( REDACT )); then
      printf '%s\n' "$BODY" | sed -E \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[redacted-email]/g' \
        -e 's/(Bearer|Authorization|token)[" :=]+[A-Za-z0-9._-]{8,}/\1 [redacted]/gI'
    else
      printf '%s\n' "$BODY"
    fi
    ;;
  401)
    echo "ERROR: 401 from Sentry. A 401 is a token-SCOPE / membership signal, not proof the org is unowned (ADR-031 glossary). DETERMINISTIC — do NOT retry. Verify the token's org-membership scope for '${ORG}'." >&2
    exit 77 ;;
  403)
    echo "ERROR: 403 from Sentry — the token lacks event:read on /issues/<id>/ (SENTRY_API_TOKEN/SENTRY_AUTH_TOKEN carry Discover/ingest scope only). DETERMINISTIC — do NOT retry. Use SENTRY_ISSUE_RO_TOKEN ([event:read, org:read])." >&2
    exit 78 ;;
  *)
    echo "ERROR: Sentry GET ${PATH_PART} returned HTTP ${CODE}." >&2
    printf '%s\n' "$BODY" >&2
    exit 1 ;;
esac
