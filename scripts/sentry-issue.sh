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
# `-eu` slugs; NOT de.sentry.io — ingest-only, 404s on /api/). See ADR-031 glossary.
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

REDACT=0
MODE="issue"
ISSUE_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest-event) MODE="latest-event"; shift ;;
    --redact) REDACT=1; shift ;;
    --) shift ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) ISSUE_ID="$1"; shift ;;
  esac
done

if [[ -z "$ISSUE_ID" ]]; then
  echo "usage: sentry-issue.sh [--latest-event] [--redact] <issue-id>" >&2
  exit 64
fi

# Issue-id charset validation BEFORE any URL interpolation. Closes path/endpoint
# injection (load-bearing given the EU slug-rewrite trap): a `/`, `?`, or `..`
# would rewrite the request path and could escape the read endpoint allowlist.
if [[ ! "$ISSUE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
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

# URL allowlist — exactly two read endpoints, both event:read, built from the
# fixed method GET with no request body.
case "$MODE" in
  issue)        PATH_PART="/api/0/organizations/${ORG}/issues/${ISSUE_ID}/" ;;
  latest-event) PATH_PART="/api/0/organizations/${ORG}/issues/${ISSUE_ID}/events/latest/" ;;
esac
URL="https://${HOST}${PATH_PART}"

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
    echo "ERROR: 401 from Sentry. A 401 is a token-SCOPE / membership signal, not proof the org is unowned (ADR-031 glossary). Verify the token's org-membership scope for '${ORG}'." >&2
    exit 1 ;;
  403)
    echo "ERROR: 403 from Sentry — the token lacks event:read on /issues/<id>/ (SENTRY_API_TOKEN/SENTRY_AUTH_TOKEN carry Discover/ingest scope only). Use SENTRY_ISSUE_RO_TOKEN ([event:read, org:read])." >&2
    exit 1 ;;
  *)
    echo "ERROR: Sentry GET ${PATH_PART} returned HTTP ${CODE}." >&2
    printf '%s\n' "$BODY" >&2
    exit 1 ;;
esac
