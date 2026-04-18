#!/usr/bin/env bash
# PostToolUse advisory hook: warn on unverified CLI invocations in user-facing
# docs. Non-blocking — exits 0 with a stderr warning so the Write/Edit still
# lands. Source rule: AGENTS.md cq-docs-cli-verification.
#
# File-pattern gate: .md, .njk, README (no extension), and Next.js page files
# under apps/**/page.{tsx,jsx}. Source/TS files are excluded — they aren't
# user-facing docs.
#
# Detection: scans every line inside a fenced code block for a known CLI
# first token (ollama, supabase, doppler, gh, curl, npm, bun, pnpm, yarn,
# npx, bunx, node, python, pip, terraform, hcloud, wrangler). Leading env
# vars (FOO=bar), shell prompts ($ ), or sudo prefixes are stripped before
# matching. If a block contains a match AND is not preceded within 5 lines
# by a `<!-- verified: YYYY-MM-DD source: <url> -->` annotation, the hook
# emits one stderr warning per matched block and continues.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# File-pattern gate: only docs.
case "$FILE_PATH" in
  *.md|*.njk) ;;
  */README|*/README.*) ;;
  */apps/*/*.njk|*/apps/*/**/*.njk) ;;
  */apps/*/app/*/page.tsx|*/apps/*/app/*/page.jsx) ;;
  */apps/*/app/**/page.tsx|*/apps/*/app/**/page.jsx) ;;
  *) exit 0 ;;
esac

# Scan for fenced code blocks containing a CLI-shaped token on any line.
awk '
  BEGIN {
    in_block = 0
    verified_window = 0
    block_verified = 0
    # Capture the first CLI-shaped line per fence.
    first_cli = ""
    # Tools that commonly appear in docs. Extend when new first-party
    # tooling surfaces in user-facing guides.
    pattern = "^(ollama|supabase|doppler|gh|curl|npm|bun|pnpm|yarn|npx|bunx|node|python|pip|terraform|hcloud|wrangler)([[:space:]]|$)"
  }
  # Track verified annotations for the next 5 non-fence lines.
  /<!-- verified:/ { verified_window = 5; next }
  /^```/ {
    if (in_block == 0) {
      in_block = 1
      block_verified = (verified_window > 0)
      block_start = NR
      first_cli = ""
    } else {
      in_block = 0
      if (first_cli != "" && !block_verified) {
        printf("[docs-cli-verify] %s:%d unverified CLI invocation: %s — consider running --help and annotating <!-- verified: YYYY-MM-DD source: <url> -->\n", FILENAME, block_start, first_cli) > "/dev/stderr"
      }
    }
    next
  }
  in_block && first_cli == "" {
    # Strip leading env-var assignments, shell prompts, and sudo so the
    # CLI prefix check matches real invocations in readme-style snippets.
    candidate = $0
    sub(/^[[:space:]]*\$[[:space:]]+/, "", candidate)
    sub(/^(sudo[[:space:]]+)/, "", candidate)
    while (match(candidate, /^[A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+/) > 0) {
      candidate = substr(candidate, RLENGTH + 1)
    }
    if (match(candidate, pattern)) {
      first_cli = candidate
    }
  }
  # Decrement the verified window only on non-fence, non-annotation content
  # lines so the 5-line count reflects actual separation from the snippet.
  !in_block && !/<!-- verified:/ && !/^```/ {
    if (verified_window > 0) verified_window--
  }
' "$FILE_PATH"

exit 0
