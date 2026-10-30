#!/usr/bin/env bash
# discord-blog-webhook-fallback.sh — GENERIC verification probe for the
# follow-through sweeper (ADR-298 generic-name precedent:
# post-deploy-incident-soak.sh). No issue number is baked in: one copy serves
# every enrollment, so no tracker's identity appears here.
#
# WHAT IT PROVES. The Discord blog→general webhook fallback feature (merged
# 2026-10-29, squash commit 347d3812) posts to #general and emits a Sentry
# warning (feature "cron-content-publisher", message prefix
# "DISCORD_BLOG_WEBHOOK_URL unset in publisher env") whenever the publisher env
# lacks DISCORD_BLOG_WEBHOOK_URL. The prod secret was written and the live
# container env-file re-downloaded on 2026-10-29, so the FIRST publish dated
# after that must show NO such event. This probe closes its tracker only when
# BOTH hold:
#   (1) LIVENESS — at least one file under
#       knowledge-base/marketing/distribution-content/ carries
#       `status: published` AND `publish_date >= 2026-10-30` AND `discord` in
#       `channels:` — i.e. a post-secret publish actually ran (a zero event
#       count before then proves nothing).
#   (2) ZERO Sentry events matching the fallback-marker query with
#       `timestamp >= 2026-10-29T17:00:00Z` (the post-secret cutoff).
#
# LIVENESS-FIRST ORDERING is load-bearing: the content-dir scan runs BEFORE any
# credentialed read, so a probe run before the first post-secret publish exits
# 2 without ever touching Sentry, and a cred-free manual run cannot emit a
# false PASS.
#
# EXIT CONTRACT (sweep-followthroughs.sh):
#   0   PASS              -> liveness met AND zero in-window events; sweeper
#                          closes the tracker
#   1   FAIL              -> >=1 marker event at/after the cutoff; sweeper
#                          comments, leaves open (the env wiring failed —
#                          inspect the container env-file, not the webhook
#                          value)
#   2   NOT YET           -> no qualifying published file yet (the normal daily
#                          state until the first post-secret publish lands)
#   3   CANNOT ESTABLISH  -> any read failure: missing prereq, unusable token,
#                          unpinned destination, non-200, unparseable payload
#   78  xtrace refusal (#7797)
#
# CREDENTIAL POSTURE. `SENTRY_ACTIONS_RO_TOKEN` — org-level read-only
# `actions-read-prd` integration (ADR-031); the org and API host are PINNED
# literals (Rule D, ADR-202): `jikigai-eu` on `de.sentry.io`, and an env
# override that does not equal the pin is refused (CANNOT ESTABLISH), never
# followed. `GH_TOKEN` — declared in the directive's secrets= so `gh` MAY be
# used; this probe does not call `gh`. The bearer rides curl's stdin config
# channel, never its argument list. NEVER the retired Sentry credential name
# (banned here by varq-ban rule 2 — code AND comments).
#
# Test-only seams (never set under the sweeper's `env -i`):
#   DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR — liveness scan directory.
#
# RETIREMENT: generic — keep as long as ANY live directive names it;
# `gh issue list --label follow-through` and grep the bodies for
# `discord-blog-webhook-fallback` before deleting (a closed-within-lookback
# tracker still runs it). Back-references: this file's
# discord-blog-webhook-fallback.test.sh harness; the
# `run_suite "scripts/followthroughs/discord-blog-webhook-fallback"` row in
# scripts/test-all.sh; the scripts/suite-shard-legs.tsv and
# scripts/suite-durations.tsv rows; the tracker directive's
# `script=` body; scripts/lib/test-affected-paths.sh (only if an
# AFFECTED_*_PATHS edge array is ever declared for it).
#
# Directive example (post-secret publish expected 2026-11-03T14:00Z):
#   <!-- soleur:followthrough
#     script=scripts/followthroughs/discord-blog-webhook-fallback.sh
#     earliest=2026-11-03T15:30:00Z
#     secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN
#   -->

set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797). Shell
# tracing echoes commands AFTER expansion, so a credential is printed the
# moment it is used. `${VAR:+x}` is non-emptiness WITHOUT expanding the value.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

export LC_ALL=C
# TLS-subversion prologue (same as the sibling probes): none of these can
# re-point a Bearer request or leak its keys when the sweeper's `env -i` is
# absent (a local `doppler run`).
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$REPO_ROOT" ]; then
  printf 'CANNOT ESTABLISH: could not resolve the repo root from %s\n' "${BASH_SOURCE[0]}" >&2
  exit 3
fi
CONTENT_DIR="${DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR:-$REPO_ROOT/knowledge-base/marketing/distribution-content}"

# Pinned post-secret cutoff: the first publish AFTER the prod
# DISCORD_BLOG_WEBHOOK_URL write + env-file re-download (2026-10-29T17:21Z).
CUTOFF_ISO="2026-10-29T17:00:00Z"
# A distribution file qualifies as post-secret liveness evidence when its
# publish_date is on/after this floor (ISO dates compare correctly as strings).
LIVENESS_DATE_FLOOR="2026-10-30"

cannot() { printf 'CANNOT ESTABLISH: %s\n' "$1" >&2; }
notyet() { printf 'NOT YET: %s\n' "$1" >&2; }

# ── Prereqs (local only — no credentialed read yet) ──────────────────────────
command -v curl >/dev/null 2>&1 || { cannot "curl not on PATH"; exit 3; }
command -v jq   >/dev/null 2>&1 || { cannot "jq not on PATH";   exit 3; }

# Token-shape guard (empty, or any char outside the allowlist, e.g. a newline
# that would inject a curl config directive on the stdin channel below). Never
# echoes the value. NOT `: "${VAR:?}"` — that aborts with status 1, which the
# sweeper reads as FAIL (the convention's varq ban).
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
if ! _bearer_ok "${SENTRY_ACTIONS_RO_TOKEN:-}"; then
  cannot "SENTRY_ACTIONS_RO_TOKEN unusable (unset or unexpected shape); declare it in the directive's secrets="
  exit 3
fi

# Sole credentialed-curl wrapper: owns the flags and the bearer. The bearer
# rides curl's stdin config channel, never its argument list. Callers pass the
# remaining flags and the URL.
_sentry_get() {
  curl --disable --noproxy '*' -sS "$@" --config - \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_ACTIONS_RO_TOKEN")
}

# Rule D destination pin (ADR-202): the bearer goes only to the pinned Sentry
# org on the pinned host. An env override that does not equal the pin is
# refused, never followed.
readonly ORG_PINNED="jikigai-eu"
readonly API_HOST_PINNED="de.sentry.io"
ORG="${SENTRY_ORG:-$ORG_PINNED}"
API_HOST="${SENTRY_API_HOST:-$API_HOST_PINNED}"
if [[ "$ORG" != "$ORG_PINNED" || "$API_HOST" != "$API_HOST_PINNED" ]]; then
  cannot "refusing an unpinned Sentry destination (org=${ORG} host=${API_HOST}; pinned to ${ORG_PINNED} / ${API_HOST_PINNED})"
  exit 3
fi

# ── LIVENESS (before any credentialed read) ──────────────────────────────────
# Mirrors get_frontmatter_field in scripts/content-publisher.sh: extract the
# frontmatter block (between the first two `---` lines), pull one `key:` field,
# strip surrounding quotes.
parse_frontmatter() { awk '/^---$/{c++; next} c==1' "$1"; }
get_frontmatter_field() {
  local file="$1" field="$2"
  # || true: grep returns exit 1 on no match, which pipefail propagates
  parse_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/' || true
}

QUALIFYING=0
SCANNED=0
if [[ -d "$CONTENT_DIR" ]]; then
  for f in "$CONTENT_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    SCANNED=$((SCANNED + 1))
    status="$(get_frontmatter_field "$f" status)"
    [[ "$status" == "published" ]] || continue
    pdate="$(get_frontmatter_field "$f" publish_date)"
    [[ -n "$pdate" && ! "$pdate" < "$LIVENESS_DATE_FLOOR" ]] || continue
    channels="$(get_frontmatter_field "$f" channels)"
    # Word match inside the CSV value — `discord` must not match
    # `discord-blog` or any other token that merely contains the substring.
    case ", $(printf '%s' "$channels" | tr -d ' ')," in
      *,discord,*) QUALIFYING=$((QUALIFYING + 1)) ;;
    esac
  done
fi
if [[ "$QUALIFYING" -eq 0 ]]; then
  notyet "no file under ${CONTENT_DIR} with status: published, publish_date >= ${LIVENESS_DATE_FLOOR} and discord in channels (${SCANNED} file(s) scanned) — no post-secret publish has landed yet"
  exit 2
fi

# ── Sentry: zero in-window fallback-marker events ────────────────────────────
# `sort=-timestamp` is pinned (CTO ruling): newest-first is the observed
# default but NOT a documented contract — with the sort explicit, per_page=10
# provably covers the FAIL arm because any `timestamp >= cutoff` event ranks
# within the newest 10.
QUERY='feature:"cron-content-publisher" "DISCORD_BLOG_WEBHOOK_URL unset in publisher env"'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="https://${API_HOST}/api/0/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=30d&per_page=10&field=title&field=timestamp&sort=-timestamp"
# Re-assert the pin on the assembled URL: the bearer must never leave it.
case "$URL" in
  "https://de.sentry.io/api/0/organizations/jikigai-eu/"*) ;;
  *) cannot "refusing a credentialed call to an unpinned URL"; exit 3 ;;
esac
RESP=$(_sentry_get -w '\nHTTP_STATUS:%{http_code}' \
  -H "Accept: application/json" \
  "$URL")
HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')
if [[ "$HTTP_STATUS" != "200" ]]; then
  cannot "Sentry events API returned ${HTTP_STATUS:-<none>}"
  exit 3
fi
if ! printf '%s' "$BODY" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
  cannot "Sentry events response has no .data array (schema drift or non-JSON body)"
  exit 3
fi

# Every returned row already matched the marker query; a row whose timestamp
# cannot be parsed makes the window bound unjudgeable, so it is a measure
# failure (CANNOT ESTABLISH), never silently ignored. The events endpoint
# serializes timestamps as `+00:00` (the in-repo fixture shape), so they are
# normalized to the canonical `Z` form fromdateiso8601 requires — the same
# normalization the sibling probes use — before the window compare.
if ! OFFENDERS=$(printf '%s' "$BODY" | jq -c --arg cutoff "$CUTOFF_ISO" '
    [ .data[]
      | . as $e
      | ($e.timestamp | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")
          | try fromdateiso8601 catch null) as $t
      | if $t == null
        then error("unparseable event timestamp")
        else select($t >= ($cutoff | fromdateiso8601))
             | {title: $e.title, timestamp: $e.timestamp}
        end ]' 2>/dev/null); then
  cannot "could not parse Sentry event timestamps"
  exit 3
fi
N=$(printf '%s' "$OFFENDERS" | jq 'length' 2>/dev/null)
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  cannot "could not count parsed Sentry offenders"
  exit 3
fi
if [[ "$N" -gt 0 ]]; then
  printf 'FAIL: %s discord-blog-webhook-fallback marker event(s) at/after %s — the post-secret publish still lacks DISCORD_BLOG_WEBHOOK_URL in the publisher env:\n' "$N" "$CUTOFF_ISO"
  printf '%s' "$OFFENDERS" | jq -r '.[] | "  - \(.title) @ \(.timestamp)"'
  exit 1
fi
printf 'PASS: %s qualifying post-secret publish file(s) and 0 discord-blog-webhook-fallback marker events since %s\n' "$QUALIFYING" "$CUTOFF_ISO"
exit 0
