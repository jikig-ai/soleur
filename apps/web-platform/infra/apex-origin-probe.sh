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
# Reads only public HTTP. No credentials, no private network, no SSH.

set -uo pipefail

URL="${APEX_PROBE_URL:-https://soleur.ai/}"

# -D - writes response headers to stdout; -o /dev/null discards the body so a
# large page cannot flood the caller. --max-time bounds the whole request.
if ! HEADERS=$(curl -sS -D - -o /dev/null --max-time 20 -w 'HTTPCODE=%{http_code}\n' "$URL" 2>/dev/null); then
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
if grep -qiE '^(x-github-request-id|x-fastly-request-id|via: 1\.1 varnish)' <<<"$HEADERS"; then
  echo "SERVING-FROM-GITHUB-PAGES"
else
  echo "SERVING-FROM-CLOUDFLARE-PAGES"
fi
exit 0
