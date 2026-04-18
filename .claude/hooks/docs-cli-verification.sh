#!/usr/bin/env bash
# PostToolUse advisory hook: warn on unverified CLI invocations in user-facing
# docs. Non-blocking — exits 0 with a stderr warning so the Write/Edit still
# lands. Source rule: AGENTS.md cq-docs-cli-verification.
#
# File-pattern gate: .njk, .md, apps/**/page.{tsx,jsx}, and other files under
# apps/**/*.njk. Source/TS files are excluded — they aren't user-facing docs.
#
# Detection: fenced code blocks starting with a known CLI prefix (ollama,
# supabase, doppler, gh, curl, npm run, bun run). If the enclosing block does
# NOT contain a `<!-- verified: ... -->` annotation in a preceding line, the
# hook emits one stderr warning per matched block.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# File-pattern gate: only docs.
case "$FILE_PATH" in
  *.md|*.njk) ;;
  */apps/*/app/*/page.tsx|*/apps/*/app/*/page.jsx) ;;
  *) exit 0 ;;
esac

# Scan for fenced code blocks containing CLI-shaped first tokens.
awk '
  BEGIN {
    in_block = 0
    verified_recent = 0
    block_verified = 0
    pattern = "^(ollama|supabase|doppler|gh|curl|npm run|bun run)[[:space:]]"
  }
  # Track a verified annotation in the 3 lines preceding a fence opener.
  /<!-- verified:/ { verified_recent = 3 }
  /^```/ {
    if (in_block == 0) {
      in_block = 1
      block_verified = (verified_recent > 0)
      block_start = NR
      first_cli = ""
    } else {
      in_block = 0
      if (first_cli != "" && !block_verified) {
        printf("[docs-cli-verify] %s:%d unverified CLI invocation: %s — consider running --help and annotating <!-- verified: YYYY-MM-DD source: <url> -->\n", FILENAME, block_start, first_cli) > "/dev/stderr"
      }
    }
    if (verified_recent > 0) verified_recent--
    next
  }
  in_block && first_cli == "" {
    if (match($0, pattern)) {
      first_cli = $0
    }
  }
  { if (verified_recent > 0 && !/<!-- verified:/) verified_recent-- }
' "$FILE_PATH"

exit 0
