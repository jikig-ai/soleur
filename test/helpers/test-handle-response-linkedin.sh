#!/usr/bin/env bash
# test-handle-response-linkedin.sh -- Test harness for linkedin-community.sh helpers
#
# Sources linkedin-community.sh (which skips main via the source guard at :409)
# and dispatches to either handle_response or get_request so tests can exercise
# the REAL functions without forking the transform/HTTP-status logic.
#
# Usage:
#   test-handle-response-linkedin.sh handle_response <http_code> <body> <endpoint> <depth> [retry_cmd...]
#   test-handle-response-linkedin.sh get_request <endpoint> <depth>
#   test-handle-response-linkedin.sh cmd_fetch_activity     (get_request stubbed)
#   test-handle-response-linkedin.sh cmd_fetch_metrics      (get_request stubbed)
#
# The get_request entry point lets tests assert the exit-2 rate-limit-exhaustion
# path (depth>=3 short-circuits BEFORE any curl, so no network call), which lives
# in get_request:122-125, NOT in handle_response.
#
# cmd_fetch_activity / cmd_fetch_metrics run the REAL command body (guard +
# transform + emit) with get_request stubbed from env fixtures so no network
# call is made. This exercises the shape guards and numeric guards over fixtures:
#   GET_REQUEST_POSTS_BODY     - body returned for the /rest/posts author-finder
#   GET_REQUEST_SHARE_BODY     - body for organizationalEntityShareStatistics
#   GET_REQUEST_NETWORK_BODY   - body for networkSizes (omit to simulate failure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/../../plugins/soleur/skills/community/scripts/linkedin-community.sh"

# Source the script to load its functions (source guard prevents main from running)
source "$SCRIPT_PATH"

fn="$1"
shift

# Stub get_request for the cmd_* entry points: return the matching env fixture
# instead of making a network call. Selection is by endpoint substring so a
# single stub serves both fetch commands.
if [[ "$fn" == "cmd_fetch_activity" || "$fn" == "cmd_fetch_metrics" ]]; then
  get_request() {
    local endpoint="$1"
    case "$endpoint" in
      *organizationalEntityShareStatistics*) printf '%s' "${GET_REQUEST_SHARE_BODY:-}" ;;
      *networkSizes*)
        if [[ -z "${GET_REQUEST_NETWORK_BODY+x}" ]]; then
          echo "stub: simulated networkSizes failure" >&2
          return 1
        fi
        printf '%s' "${GET_REQUEST_NETWORK_BODY}"
        ;;
      *posts*) printf '%s' "${GET_REQUEST_POSTS_BODY:-}" ;;
      *) printf '%s' "{}" ;;
    esac
  }
fi

"$fn" "$@"
