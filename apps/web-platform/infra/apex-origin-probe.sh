#!/usr/bin/env bash
# Which origin is serving https://soleur.ai/ right now?
#
# WHY THIS IS A COMMITTED SCRIPT AND NOT AN INLINE `command:`
#
# It is the ADR-194 plan's `discoverability_test`. The inline form it replaces was
# doubly unrunnable by preflight Check 10:
#
#   1. STRUCTURALLY — it carried `$(`, `|` and `;`, which Check 10's shell-active
#      token reject refuses before execution. The sanctioned remedy for a probe
#      that genuinely needs shell control flow is exactly this: wrap it in a
#      repo-relative script (`bash <path>`), which is an allowlisted verb.
#   2. SEMANTICALLY — its `expected_output` asserted the POST-cutover origin while
#      the migration is four PRs long. Every run before the cutover reported a
#      mismatch, i.e. the check could only ever fail until the last PR landed.
#
# AP-021: A VERDICT MUST NEVER COLLAPSE "COULD NOT CHECK" INTO A DEFINITE ANSWER.
#
# The plan records that an earlier ad-hoc version of this probe FAILED OPEN —
# printing a success verdict for an unreachable site. That is the defect this
# script exists to not have, so the unreachable arms are first-class outcomes with
# their own exit code, not a fallback into one of the origin verdicts.
#
# Four arms, three verdicts:
#   SERVING-FROM-GITHUB-PAGES     rc 0  — a GitHub/Fastly origin marker is present
#   SERVING-FROM-CLOUDFLARE-PAGES rc 0  — 200, and no GitHub/Fastly marker
#   UNREACHABLE (transport)       rc 2  — curl could not complete the request
#   UNREACHABLE (status not 200)  rc 2  — reached, but not a 200
#
# The cache-buster added in PR4b changes the URL requested, NOT the arms: still
# three verdicts and both AP-021 UNREACHABLE arms (AC61).
#
# Reads only public HTTP. No credentials, no private network, no SSH.

set -uo pipefail

# The marker set is single-sourced (see apex-origin-markers.sh): this probe knew
# three of the six, and its Cloudflare arm is residual, so the three it did not
# know read as Cloudflare — the verdict that routes a rollback into a second
# destroy.
# shellcheck source=apps/web-platform/infra/apex-origin-markers.sh
. "$(dirname "${BASH_SOURCE[0]}")/apex-origin-markers.sh"

URL="${APEX_PROBE_URL:-https://soleur.ai/}"

# CACHE-BUSTER (#7640 PR4b, AC61). Measured 2026-09-02: the apex answers with
# `cache-control: max-age=600`, `age: 279`, `x-cache: HIT`, so an unbusted
# request can be served from cache for up to ten minutes.
#
# That is not a cosmetic staleness problem here, because of which arm is
# RESIDUAL. `SERVING-FROM-CLOUDFLARE-PAGES` is not positively detected — it is
# "200, and no GitHub marker". A cached pre-cutover response, or any
# Cloudflare-served 200 error page, therefore reads as CLOUDFLARE. This probe is
# the ROLLBACK'S BRANCH SELECTOR at the T+20 decision point: a false
# "already on Cloudflare" is what routes an operator into reverting PR3 — a
# SECOND destroy — during an active incident.
#
# Query-aware join so an APEX_PROBE_URL that already carries a query string is
# not corrupted into a second `?`. The sibling build-identity probe uses the same
# `cb=` idiom (deploy-docs.yml passes `?cb=${{ github.sha }}`); here the nonce is
# per-invocation, because this probe runs repeatedly within one cutover window
# and a fixed nonce would be cached after the first sample.
PROBE_CB="${APEX_PROBE_CB:-$(date -u +%s)-$$-${RANDOM}}"
case "$URL" in
  *\?*) PROBE_URL="${URL}&cb=${PROBE_CB}" ;;
  *)    PROBE_URL="${URL}?cb=${PROBE_CB}" ;;
esac

# INTROSPECTION SEAM: print the URL that WOULD be requested and exit, making no
# request at all. It cannot fabricate a verdict — there is no network path
# through it — so it is safe to leave unguarded, unlike a seam that could
# redirect the probe at a fixture and report green about a site nobody serves.
if [[ -n "${APEX_PROBE_PRINT_URL:-}" ]]; then
  printf '%s\n' "$PROBE_URL"
  exit 0
fi

# -D - writes response headers to stdout; -o /dev/null discards the body so a
# large page cannot flood the caller. --max-time bounds the whole request.
# `Cache-Control`/`Pragma` are belt-and-braces beside the query-string buster:
# intermediaries may honour them, but the distinct URL is what actually
# guarantees a fresh edge lookup.
if ! HEADERS=$(curl -sS -D - -o /dev/null --max-time 20 \
    -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
    -w 'HTTPCODE=%{http_code}\n' "$PROBE_URL" 2>/dev/null); then
  echo "UNREACHABLE (transport)"
  exit 2
fi

case "$HEADERS" in
  *"HTTPCODE=200"*) ;;
  *)
    echo "UNREACHABLE (status not 200)"
    exit 2
    ;;
esac

# Anchored on ^ because these are header NAMES at line start. An unanchored match
# would also hit the same token appearing inside another header's VALUE — the
# bare-token class this repo has been bitten by repeatedly.
#
# grep is fed by a herestring rather than a pipe: under `set -o pipefail`,
# `printf ... | grep -q` returns 141 when grep exits early on a match and the
# producer takes SIGPIPE, which would misreport a found marker as not-found.
if grep -qiE "$APEX_GH_ORIGIN_MARKERS" <<<"$HEADERS"; then
  echo "SERVING-FROM-GITHUB-PAGES"
else
  echo "SERVING-FROM-CLOUDFLARE-PAGES"
fi
exit 0
