#!/usr/bin/env bash
# Read-only status for the inbound email routing table (ADR-269, #9458).
#
#   bash apps/web-platform/scripts/email-route-status.sh
#       -> routes=<n>
#   bash apps/web-platform/scripts/email-route-status.sh --resolve <address>
#       -> route=<id> workspace=<uuid> owner=<uuid>      (a route matches)
#       -> env-fallback                                   (no route matches)
#
# `--resolve` shows the stored route for an address (exact match; the address is
# trimmed and lowercased, display-name forms are not parsed here). It does NOT
# evaluate the resolver's operator-only refusal (ADR-269): a route to any other
# workspace is shown here but claimed under the operator by the pipeline.
#
# email_inbox_routes is service-role only (no RLS policies), so no
# unauthenticated probe can read it. The script reads DATABASE_URL_POOLER from
# the environment; when it is unset it re-execs itself under
# `doppler run -p soleur -c "${EMAIL_ROUTE_STATUS_CONFIG:-prd}"`. The connection
# string is never printed. SELECT-only: the session is opened read-only
# (PGOPTIONS default_transaction_read_only), so the server refuses any write.

set -euo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

# Never trace this script: the environment carries a database credential
# (#7797). Exits 78, like dev-ledger-parity.sh.
case "$-" in
  *x*)
    echo "[FATAL] email-route-status: refusing to run under xtrace (credential in environment; see #7797)" >&2
    exit 78
    ;;
esac

if [[ -z "${DATABASE_URL_POOLER:-}" ]]; then
  command -v doppler >/dev/null 2>&1 || {
    echo "email-route-status: DATABASE_URL_POOLER is unset and doppler is not on PATH" >&2
    exit 2
  }
  # One re-exec only: if the Doppler config lacks the secret, fail instead of
  # re-entering this branch forever.
  if [[ -n "${EMAIL_ROUTE_STATUS_REEXEC:-}" ]]; then
    echo "email-route-status: DATABASE_URL_POOLER is not set in Doppler config '${EMAIL_ROUTE_STATUS_CONFIG:-prd}'" >&2
    exit 2
  fi
  EMAIL_ROUTE_STATUS_REEXEC=1 exec doppler run -p soleur -c "${EMAIL_ROUTE_STATUS_CONFIG:-prd}" -- bash "$0" "$@"
fi

export PGOPTIONS="-c default_transaction_read_only=on"

command -v psql >/dev/null 2>&1 || {
  echo "email-route-status: psql not found on PATH" >&2
  exit 2
}

# Session-mode pooler port: multi-statement and prepared-statement safe.
db_url="${DATABASE_URL_POOLER/:6543\//:5432/}"

if [[ "${1:-}" == "--resolve" ]]; then
  addr="${2:-}"
  if [[ -z "$addr" ]]; then
    echo "usage: email-route-status.sh --resolve <address>" >&2
    exit 2
  fi
  addr="$(printf '%s' "$addr" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # psql variable interpolation (:'addr') quotes the literal: no injection.
  # The query goes in on stdin: `psql -c` does NOT interpolate variables.
  row="$(psql "$db_url" -X -At -v ON_ERROR_STOP=1 -v addr="$addr" <<'SQL'
select 'route=' || id || ' workspace=' || workspace_id || ' owner=' || owner_user_id
  from public.email_inbox_routes
 where address = :'addr'
SQL
)"
  if [[ -n "$row" ]]; then
    printf '%s\n' "$row"
  else
    echo "env-fallback"
  fi
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "usage: email-route-status.sh [--resolve <address>]" >&2
  exit 2
fi

count="$(psql "$db_url" -X -At -v ON_ERROR_STOP=1 \
  -c "select count(*) from public.email_inbox_routes")"
echo "routes=${count}"
