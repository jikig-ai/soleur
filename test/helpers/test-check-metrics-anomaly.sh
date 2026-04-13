#!/usr/bin/env bash
# test-check-metrics-anomaly.sh -- Test harness for _has_metrics_anomaly()
#
# Sources x-community.sh (which skips main via the source guard)
# and calls _has_metrics_anomaly with the provided JSON argument.
#
# Usage: test-check-metrics-anomaly.sh <metrics_json>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/../../plugins/soleur/skills/community/scripts/x-community.sh"

# Source the script to load _has_metrics_anomaly (source guard prevents main from running)
source "$SCRIPT_PATH"

_has_metrics_anomaly "$@"
