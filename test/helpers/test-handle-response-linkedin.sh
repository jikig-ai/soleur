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
#
# The get_request entry point lets tests assert the exit-2 rate-limit-exhaustion
# path (depth>=3 short-circuits BEFORE any curl, so no network call), which lives
# in get_request:122-125, NOT in handle_response.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/../../plugins/soleur/skills/community/scripts/linkedin-community.sh"

# Source the script to load its functions (source guard prevents main from running)
source "$SCRIPT_PATH"

fn="$1"
shift

"$fn" "$@"
