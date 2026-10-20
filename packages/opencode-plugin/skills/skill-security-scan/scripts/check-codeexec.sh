#!/usr/bin/env bash
# Category 1: code-execution anti-patterns.
# Stdin = SKILL.md content. Stdout = JSON {verdict, category, findings}. Exit 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

YAML="$SCRIPT_DIR/../references/rules/code-exec.yaml"

tmp="$(stdin_to_tempfile)"
trap 'rm -f "$tmp" "$tmp.code"' EXIT

# Extract fenced code block content only (skip prose). Format-only fences
# (json/yaml/toml/csv/text) are skipped per regex-patterns.md carve-out.
awk '
  /^```/ {
    if (in_block) { in_block=0; next }
    lang = substr($0, 4)
    gsub(/[[:space:]]+$/, "", lang)
    if (lang == "json" || lang == "yaml" || lang == "yml" || \
        lang == "toml" || lang == "csv" || lang == "text" || lang == "md") {
      skip=1
    } else {
      skip=0
    }
    in_block=1
    print ""  # preserve line numbers
    next
  }
  in_block && !skip { print; next }
  { print "" }  # non-code lines as empty so line numbers map to original
' "$tmp" > "$tmp.code"

findings="$(apply_yaml_rules "$YAML" "$tmp.code" || true)"

verdict="$(echo "$findings" | findings_to_verdict)"
findings_json="$(echo "$findings" | build_findings_array)"

emit_result "$verdict" "code-execution" "$findings_json"
