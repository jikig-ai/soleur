#!/usr/bin/env bash
# Category 4: filesystem boundary violations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

YAML="$SCRIPT_DIR/../references/rules/filesystem-boundary.yaml"

tmp="$(stdin_to_tempfile)"
trap 'rm -f "$tmp"' EXIT

findings="$(apply_yaml_rules "$YAML" "$tmp" || true)"

verdict="$(echo "$findings" | findings_to_verdict)"
findings_json="$(echo "$findings" | build_findings_array)"

emit_result "$verdict" "filesystem-boundary" "$findings_json"
