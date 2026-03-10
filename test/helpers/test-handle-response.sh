#!/usr/bin/env bash
# test-handle-response.sh -- Test harness for handle_response()
#
# Sources x-community.sh (which skips main via the source guard)
# and calls handle_response with the provided arguments.
#
# Usage: test-handle-response.sh <http_code> <body> <endpoint> <depth> [retry_cmd...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/../../plugins/soleur/skills/community/scripts/x-community.sh"

# Source the script to load handle_response (source guard prevents main from running)
source "$SCRIPT_PATH"

handle_response "$@"
