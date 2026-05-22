#!/usr/bin/env bash
set -euo pipefail

# Force a PostgREST schema-cache reload via the Supabase Management API.
#
# Use after a migration apply path that bypasses run-migrations.sh's
# in-band NOTIFY (notably: direct-pg fallback through the IPv4 session-mode
# pooler, which cannot deliver NOTIFY to PostgREST's LISTEN — see learning
# 2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md §1).
#
# Mechanism: POST /v1/projects/<ref>/database/query with body
#   { "query": "NOTIFY pgrst, 'reload schema';" }
# The Management API runs the SQL on a Supabase-side connection that shares
# backend identity with PostgREST's LISTEN, so the NOTIFY actually reaches.
# Without this, PostgREST polls schema every ~10 min by default — every
# supabase-js call against a freshly-added table returns PGRST205 until.
#
# Usage:
#   doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh
#   doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh --best-effort
#
# Required environment:
#   SUPABASE_PAT              Personal access token (sbp_…). Mint at
#                             https://supabase.com/dashboard/account/tokens
#                             then `doppler secrets set SUPABASE_PAT=…`.
#   NEXT_PUBLIC_SUPABASE_URL  Project URL; ref is parsed from it.
#
# Optional environment:
#   SUPABASE_API_HOST         Override Management API host (default
#                             https://api.supabase.com). Test seam.
#
# Flags:
#   --best-effort             Soft-fail: missing PAT or any HTTP error exits
#                             0 with a stderr warning. Used by
#                             run-migrations.sh so a missing PAT or transient
#                             upstream issue cannot break a dev apply.
#   --help, -h                Print this message and exit.
#
# Exit codes (strict mode):
#   0 = success (reload acknowledged)
#   1 = transient (HTTP 5xx, curl network failure) — caller may retry
#   2 = auth/config error (missing PAT, HTTP 401/403, bad ref) — operator action

best_effort=0
for arg in "$@"; do
  case "$arg" in
    --best-effort) best_effort=1 ;;
    --help|-h)
      sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "::error::Unknown argument: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 2 ;;
  esac
done

soft_warn() {
  echo "::warning::postgrest-reload-schema: $1" >&2
}

fail_or_skip() {
  local code="$1" msg="$2"
  if [[ "$best_effort" == "1" ]]; then
    soft_warn "$msg (best-effort: skipping)"
    exit 0
  fi
  echo "::error::postgrest-reload-schema: $msg" >&2
  exit "$code"
}

command -v curl >/dev/null 2>&1 || fail_or_skip 2 "curl not found on PATH"

if [[ -z "${SUPABASE_PAT:-}" ]]; then
  fail_or_skip 2 "SUPABASE_PAT is not set. Mint a PAT at https://supabase.com/dashboard/account/tokens and store via 'doppler secrets set SUPABASE_PAT=…' in each env."
fi

if [[ -z "${NEXT_PUBLIC_SUPABASE_URL:-}" ]]; then
  fail_or_skip 2 "NEXT_PUBLIC_SUPABASE_URL is not set; cannot derive project ref."
fi

# Extract the 20-char project ref from https://<ref>.supabase.co.
# Refs are lowercase alphanumeric (typically 20 chars); guard against
# non-supabase URLs so a misconfigured env doesn't post to a wrong host.
project_ref="$(printf '%s' "$NEXT_PUBLIC_SUPABASE_URL" \
  | sed -nE 's#^https?://([a-z0-9]+)\.supabase\.co/?$#\1#p')"

if [[ -z "$project_ref" ]]; then
  fail_or_skip 2 "Cannot parse project ref from NEXT_PUBLIC_SUPABASE_URL='$NEXT_PUBLIC_SUPABASE_URL'. Expected https://<ref>.supabase.co."
fi

api_host="${SUPABASE_API_HOST:-https://api.supabase.com}"
endpoint="${api_host}/v1/projects/${project_ref}/database/query"

# NOTIFY-via-management-API is the only path that reaches PostgREST's
# LISTEN from outside the Supabase Cloud network (pooler-issued NOTIFY
# does NOT propagate — see learning §1). The Management API executes
# the SQL on a backend that shares process identity with PostgREST's
# listener, so the NOTIFY actually fires.
payload='{"query":"NOTIFY pgrst, '\''reload schema'\'';"}'

# Single curl call; capture body + HTTP status using -w. The trailing
# `\n%{http_code}` lands as the final line; the fake curl in
# postgrest-reload-schema.test.sh mirrors this contract.
set +e
response="$(curl --silent --show-error \
  --request POST \
  --url "$endpoint" \
  --header "Authorization: Bearer ${SUPABASE_PAT}" \
  --header "Content-Type: application/json" \
  --data "$payload" \
  --max-time 15 \
  -w $'\n%{http_code}' \
  2>&1)"
curl_rc=$?
set -e

if [[ "$curl_rc" != "0" ]]; then
  fail_or_skip 1 "curl failed (rc=$curl_rc): ${response}"
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
    fail_or_skip 1 "upstream error (HTTP ${http_code}). Response: ${body}" ;;
  *)
    fail_or_skip 1 "unexpected HTTP code '${http_code}'. Response: ${body}" ;;
esac
