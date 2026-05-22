#!/usr/bin/env bash
set -euo pipefail

# Force a PostgREST schema-cache reload via the Supabase Management API.
# See postgrest-reload-schema.sh --help for usage.
# Context: knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md §1

print_help() {
  cat <<'USAGE'
Usage: postgrest-reload-schema.sh [--best-effort] [--help]

Force a PostgREST schema-cache reload via the Supabase Management API.
Use after a migration apply path that bypasses run-migrations.sh's in-band
NOTIFY (notably: direct-pg fallback through the IPv4 session-mode pooler,
which cannot deliver NOTIFY to PostgREST's LISTEN). Without this, every
supabase-js call against a freshly-added table returns PGRST205 until
PostgREST's natural ~10-min schema poll.

Mechanism: POST /v1/projects/<ref>/database/query with body
  { "query": "NOTIFY pgrst, 'reload schema';" }
The Management API runs the SQL on a Supabase-side connection that shares
backend identity with PostgREST's LISTEN, so the NOTIFY actually reaches.

Examples:
  doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh
  doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh --best-effort

Required environment:
  SUPABASE_PAT              Personal access token (sbp_…). Mint at
                            https://supabase.com/dashboard/account/tokens
                            then `doppler secrets set SUPABASE_PAT=…`.
  NEXT_PUBLIC_SUPABASE_URL  Project URL; ref is parsed from it.

Flags:
  --best-effort             Soft-fail: missing PAT or any HTTP error exits
                            0 with a stderr warning. Used by
                            run-migrations.sh so a missing PAT or transient
                            upstream issue cannot break a dev apply.
  --help, -h                Print this message and exit.

Exit codes (strict mode):
  0 = success (reload acknowledged)
  1 = transient (HTTP 5xx, curl network failure) — caller may retry
  2 = auth/config error (missing PAT, HTTP 401/403, bad ref) — operator action
USAGE
}

best_effort=0
for arg in "$@"; do
  case "$arg" in
    --best-effort) best_effort=1 ;;
    --help|-h) print_help; exit 0 ;;
    *)
      echo "::error::Unknown argument: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 2 ;;
  esac
done

# Scrub bearer tokens from any string before it's echoed to stderr/logs.
# Belt-and-braces: SUPABASE_PAT should never appear in $body/$response from
# a well-behaved Supabase API, but a misconfigured curl flag (e.g., --verbose
# added later) could surface the Authorization header; this gate makes the
# leak class structurally impossible at the print site.
scrub_pat() {
  printf '%s' "$1" | sed -E 's/sbp_[A-Za-z0-9]{20,}/sbp_REDACTED/g'
}

soft_warn() {
  echo "::warning::postgrest-reload-schema: $(scrub_pat "$1")" >&2
}

fail_or_skip() {
  local code="$1" msg="$2"
  msg="$(scrub_pat "$msg")"
  if [[ "$best_effort" == "1" ]]; then
    soft_warn "$msg (best-effort: skipping)"
    exit 0
  fi
  echo "::error::postgrest-reload-schema: $msg" >&2
  exit "$code"
}

command -v curl >/dev/null 2>&1 || fail_or_skip 2 "curl not found on PATH. Install via 'apt install curl' / 'brew install curl'."

if [[ -z "${SUPABASE_PAT:-}" ]]; then
  fail_or_skip 2 "SUPABASE_PAT is not set. Mint a PAT at https://supabase.com/dashboard/account/tokens and store via 'doppler secrets set SUPABASE_PAT=…' in each env."
fi

if [[ -z "${NEXT_PUBLIC_SUPABASE_URL:-}" ]]; then
  fail_or_skip 2 "NEXT_PUBLIC_SUPABASE_URL is not set; cannot derive project ref."
fi

# Resolve the 20-char project ref via the canonical helper (handles both
# https://<ref>.supabase.co and custom domains via CNAME, with the
# subdomain-bypass guard). The helper lives at scripts/lib/ so future
# callers can source the same shape and the security-critical anchored
# regex stays single-sourced.
RESOLVER="$(dirname "${BASH_SOURCE[0]}")/lib/supabase-ref-resolver.sh"
# shellcheck source=lib/supabase-ref-resolver.sh
source "$RESOLVER"

if ! project_ref=$(resolve_supabase_ref "$NEXT_PUBLIC_SUPABASE_URL" 2>&1); then
  fail_or_skip 2 "$project_ref"
fi

# Surface the resolved ref to stderr so operators see ref drift in the
# script's own output BEFORE the POST lands. Cheap audit trail per the
# data-integrity P3 + security F3 advisory (PR #4320 review).
echo "postgrest-reload-schema: resolved NEXT_PUBLIC_SUPABASE_URL → ref=${project_ref}" >&2

# Endpoint is pinned to api.supabase.com — no env override.
# A `SUPABASE_API_HOST` test seam would let an attacker who controls env
# (poisoned Doppler config, malicious workflow PR, .envrc injection)
# redirect this POST and exfiltrate the SUPABASE_PAT (account-level token).
# Tests inject via PATH-shimmed fake curl instead — same isolation, no
# production risk surface.
endpoint="https://api.supabase.com/v1/projects/${project_ref}/database/query"

# NOTIFY-via-management-API is the only path that reaches PostgREST's
# LISTEN from outside the Supabase Cloud network (pooler-issued NOTIFY
# does NOT propagate — see learning §1). The Management API executes
# the SQL on a backend that shares process identity with PostgREST's
# listener, so the NOTIFY actually fires.
payload='{"query":"NOTIFY pgrst, '\''reload schema'\'';"}'

# Single curl call; capture body + HTTP status using -w. The trailing
# `\n%{http_code}` lands as the final line; the fake curl in
# postgrest-reload-schema.test.sh mirrors this contract.
# Capture stderr separately to /dev/null so a future flag change (e.g.,
# adding --verbose) cannot leak the Authorization header into $response
# and from there into our `::error::` echoes. scrub_pat is the second line
# of defense.
set +e
response="$(curl --silent --show-error \
  --request POST \
  --url "$endpoint" \
  --header "Authorization: Bearer ${SUPABASE_PAT}" \
  --header "Content-Type: application/json" \
  --data "$payload" \
  --max-time 15 \
  -w $'\n%{http_code}' \
  2>/dev/null)"
curl_rc=$?
set -e

if [[ "$curl_rc" != "0" ]]; then
  fail_or_skip 1 "curl failed (rc=$curl_rc). Check network/DNS and retry."
fi

http_code="${response##*$'\n'}"
body="${response%$'\n'*}"

case "$http_code" in
  2??)
    echo "postgrest-reload-schema: reload acknowledged (ref=${project_ref}, HTTP ${http_code})."
    exit 0 ;;
  401|403)
    fail_or_skip 2 "auth rejected (HTTP ${http_code}). Verify SUPABASE_PAT scope and that the PAT owner has project access. Response: ${body}" ;;
  4??)
    # 404 = wrong ref (config); 422 = bad SQL (would only happen if NOTIFY
    # syntax broke — treat as durable). Other 4xx is operator-actionable.
    fail_or_skip 2 "client error (HTTP ${http_code}). Response: ${body}" ;;
  5??)
    fail_or_skip 1 "upstream error (HTTP ${http_code}). Retry; if persistent see https://status.supabase.com. Response: ${body}" ;;
  *)
    # Defensive: catches curl's '000' on proxy disconnect, rare 1xx
    # passthrough, or non-numeric tokens from a MITM. Transient → exit 1.
    fail_or_skip 1 "unexpected HTTP code '${http_code}'. Response: ${body}" ;;
esac
