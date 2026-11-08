#!/usr/bin/env bash
# legal-acceptance-counts.sh <key> -- the credential-free pre-flag aggregate check (#12429, ADR-319 amendment 2026-11-08).
#
# Asks the production web app how many decision rows exist for <key>, and whether every one of them is under the registry
# hash, using ONLY the verify bearer (LEGAL_ACCEPTANCE_VERIFY_TOKEN, read from the secret store by bc_read_token). It never
# touches the database and needs no owner credential (DATABASE_URL stays reserved by the runbook).
#
# Output, on success and nothing else (exit 0):
#   ok_to_flag=<true|false> total=<n> measured=production-table-only
# `measured=production-table-only` is a label, not decoration: the count measures ONLY the production table for that key.
# It does not measure database backups, the Sentry `accepted` count, or dev/preview. `ok_to_flag` is vacuously true at total 0
# and it is ADVISORY: it does not authorize flipping the approval-queue flag (hr-menu-option-ack-not-prod-write-auth).
#
# Any failure (bad argument, unreadable token, HTTP 401/404/502/503, transport error, a body that is not the documented
# shape) exits non-zero, prints NO `ok_to_flag=` line, and prints one status line to stderr such as `counts: HTTP 503
# store_failed`. The response body is never echoed. The host is hardcoded (no environment override). Refuses under xtrace.
#
# Operator tooling with a production URL: deliberately outside plugins/soleur (that tree ships to customer machines).
# Suite: scripts/legal-acceptance-counts.test.sh.

# xtrace would print the credential (see #7797). Checked before anything else, and again by the sourced helper.
case "$-" in
  *x*)
    printf 'counts: refusing to run under xtrace: this script handles a live credential and -x would print it. No secret has been read.\n' >&2
    exit 78 # mut:xtrace
    ;;
esac

set -uo pipefail
export LC_ALL=C

fail() { printf 'counts: %s\n' "$1" >&2; exit "${2:-1}"; }

[ "$#" -eq 1 ] || fail "usage: scripts/legal-acceptance-counts.sh <key>" 64

KEY="$1"
KEY_RE='^[a-z0-9][a-z0-9-]{0,62}$' # the same shape as KEY_RE in server/legal-acceptance/canonical.ts (cross-layer-limits.test.ts)
[[ "$KEY" =~ $KEY_RE ]] || fail "key must match ^[a-z0-9][a-z0-9-]{0,62}\$" 64

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || fail "cannot resolve the script directory"
case "$SCRIPT_DIR" in /|"") fail "cannot resolve the script directory" ;; esac
LIB="$SCRIPT_DIR/../plugins/soleur/scripts/lib/bearer-fetch.sh"
[ -f "$LIB" ] || fail "bearer-fetch.sh not found"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"

# shellcheck source=../plugins/soleur/scripts/lib/bearer-fetch.sh
# shellcheck source-path=SCRIPTDIR
. "$LIB" || fail "cannot load bearer-fetch.sh"

HOST="https://app.soleur.ai"
SCRATCH="$(mktemp -d)" || fail "cannot create a scratch directory"
case "$SCRATCH" in /?*) ;; *) fail "unexpected scratch directory" ;; esac
cleanup() { bc_clear; rm -rf -- "$SCRATCH"; }
trap cleanup EXIT

bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN || fail "token unreadable (${BC_ERR:-missing})"

bc_get "$SCRATCH" "$HOST/api/internal/legal-acceptance/$KEY/counts" || fail "request failed (no HTTP answer)"
bc_clear

case "$BC_STATUS" in
  200) ;;
  401) fail "HTTP 401 unauthorized" ;;
  404) fail "HTTP 404 not_found" ;;
  502) fail "HTTP 502 bad_gateway" ;;
  503) fail "HTTP 503 store_failed" ;;
  *)   fail "HTTP $BC_STATUS unexpected" ;;
esac

[ -n "$BC_BODY" ] && [ -f "$BC_BODY" ] || fail "empty response"

# The documented shape, checked field by field: a missing or mistyped field never defaults to true.
jq -e --arg k "$KEY" '
  type == "object"
  and .key == $k
  and (.ok_to_flag | type == "boolean")
  and (.total | type == "number" and . == floor and . >= 0)
  and (.registry_hash | type == "string" and test("^[0-9a-f]{64}$"))
  and (.by_hash | type == "array")
  and ([.by_hash[] | .count] | add // 0) == .total
' "$BC_BODY" >/dev/null 2>&1 || fail "response is not the documented shape"

OK="$(jq -r '.ok_to_flag' "$BC_BODY")" || fail "response is not the documented shape"
TOTAL="$(jq -r '.total' "$BC_BODY")" || fail "response is not the documented shape"
[[ "$OK" == true || "$OK" == false ]] || fail "response is not the documented shape"
[[ "$TOTAL" =~ ^[0-9]{1,15}$ ]] || fail "response is not the documented shape"

printf 'ok_to_flag=%s total=%s measured=production-table-only\n' "$OK" "$TOTAL"
