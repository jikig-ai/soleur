#!/usr/bin/env bash
set -euo pipefail

# Refuse to run under xtrace, unconditionally: `bash -x` would print the
# bearer into the job log (see #7797), and the --help text below names a
# runtime acquisition (`doppler secrets get …`), so a refusal conditioned on
# the variable being set would open exactly when the value is about to be
# traced. Exit 78 = EX_CONFIG.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

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
  # prd (token lives in the prd root, inherited by every prd_* branch):
  doppler run -p soleur -c prd -- bash apps/web-platform/scripts/postgrest-reload-schema.sh
  # dev target (no dev config carries the token by design; read it from prd_terraform,
  # value never expanded in the caller's shell):
  doppler run -p soleur -c prd_terraform --only-secrets SUPABASE_ACCESS_TOKEN -- \
    doppler run -p soleur -c dev --preserve-env=SUPABASE_ACCESS_TOKEN -- \
    bash apps/web-platform/scripts/postgrest-reload-schema.sh

Required environment:
  SUPABASE_ACCESS_TOKEN     Supabase Management-API token (sbp_…), the same
                            account-scoped token the supabase CLI reads.
                            Doppler: prd root only (inherited by prd_*);
                            absent from every dev config by design (#8028).
                            Rotation: knowledge-base/engineering/operations/secret-scanning.md
  NEXT_PUBLIC_SUPABASE_URL  Project URL; ref is parsed from it.

Flags:
  --best-effort             Soft-fail ONLY for absence (no token in this
                            environment → ::notice::, exit 0) and transience
                            (5xx, network, non-JSON 401/403 → ::warning::,
                            exit 0). With a token present, a rejected
                            credential or any config defect still exits 2 —
                            a dead-but-present token must be loud (#8028).
  --help, -h                Print this message and exit.

Exit codes:
  0 = success (reload acknowledged), or a soaked absence/transience under --best-effort
  1 = transient (HTTP 5xx, curl network failure, 401/403 without an API JSON body) — caller may retry
  2 = auth/config error (missing token in strict mode, JSON-bodied 401/403, bad ref) — operator action;
      under --best-effort this class still exits 2 whenever a token is present
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
# Belt-and-braces: the token should never appear in $body/$response from
# a well-behaved Supabase API, but a misconfigured curl flag (e.g., --verbose
# added later) could surface the Authorization header; this gate makes the
# leak class structurally impossible at the print site. Control bytes are
# stripped (a line beginning with `::` would otherwise be parsed as a runner
# command) and the message is capped at 512 bytes AFTER redaction — capping
# first would let a token straddling the cut survive the regex's 20-char
# floor (review of #8028 measured a 19-char prefix leak).
scrub_token() {
  printf '%s' "$1" | sed -E 's/sbp_[A-Za-z0-9]{20,}/sbp_REDACTED/g' | tr -d '[:cntrl:]' | head -c 512
}

# The single soak rule (#8028). Under --best-effort a failure is soft ONLY
# when the environment never opted in (no token → ::notice::) or the
# failure is transient (exit-1 class → ::warning::). Everything else with a
# token present — a JSON-bodied 401/403, a 404, an unset/unparseable URL, a
# missing curl — exits with its code so a dead-but-present credential is as
# loud under the migration runner as it is in strict mode.
fail_or_skip() {
  local code="$1" msg="$2"
  msg="$(scrub_token "$msg")"
  if [[ "$best_effort" == "1" && ( "$code" == "1" || -z "${SUPABASE_ACCESS_TOKEN:-}" ) ]]; then
    # Absence is informational (dev CI hits it on every PR); transience is a
    # titled warning so it stands out in the run's annotations list.
    local level="warning title=PostgREST schema reload skipped (transient)"
    [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]] || level="notice"
    echo "::${level}::postgrest-reload-schema: $msg (best-effort: skipping)" >&2
    exit 0
  fi
  echo "::error::postgrest-reload-schema: $msg" >&2
  exit "$code"
}

command -v curl >/dev/null 2>&1 || fail_or_skip 2 "curl not found on PATH. Install via 'apt install curl' / 'brew install curl'."

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  fail_or_skip 2 "SUPABASE_ACCESS_TOKEN is not set (Doppler config: ${DOPPLER_CONFIG:-none}). It lives in the prd root only; for a dev target read it from prd_terraform — run with --help for the one-liner."
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
# redirect this POST and exfiltrate SUPABASE_ACCESS_TOKEN (account-level token).
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
# The bearer header is piped in on STDIN (curl reads the header file from
# `-`) so the token is never in curl's argv (process listings, xtrace);
# `--disable` FIRST aborts
# ~/.curlrc parsing and `--noproxy '*'` keeps ALL_PROXY/HTTPS_PROXY from
# redirecting the request (lint-shell-trace-credential-refusal Rule D).
# Capture stderr separately to /dev/null so a future flag change (e.g.,
# adding --verbose) cannot leak the Authorization header into $response
# and from there into our `::error::` echoes. scrub_token is the second line
# of defense.
set +e
response="$(printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" \
  | curl --disable --noproxy '*' --silent --show-error \
  --request POST \
  --url "$endpoint" \
  --header @- \
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
    # The Management API answers a rejected credential with a JSON object
    # (measured 2026-09-13: `{"message":"Unauthorized"}`); an edge/WAF
    # 401/403 carries HTML or nothing. Only the former proves the token is
    # dead — the latter is retry-able and must not block a release.
    if [[ "$body" =~ ^[[:space:]]*\{ ]]; then
      fail_or_skip 2 "Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP ${http_code}) from Doppler config '${DOPPLER_CONFIG:-none}' (ref=${project_ref}). Rotate it per knowledge-base/engineering/operations/secret-scanning.md §SUPABASE_ACCESS_TOKEN, then re-run this job. Response: ${body}"
    else
      fail_or_skip 1 "auth endpoint answered HTTP ${http_code} without an API JSON body (edge/WAF?). Retry; if persistent see https://status.supabase.com. Response: ${body}"
    fi ;;
  408|429)
    # Request timeout / rate limit are transient by definition (RFC 6585);
    # the account token is shared with three other workflows that can run
    # alongside a release, so a 429 must not block deploy.
    fail_or_skip 1 "rate-limited or timed out (HTTP ${http_code}). Retry. Response: ${body}" ;;
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
