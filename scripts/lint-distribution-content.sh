#!/usr/bin/env bash
# lint-distribution-content.sh -- reject distribution content files whose body
# contains unrendered Liquid/Jinja template markers ({{, }}, {%, %}).
#
# Distribution content is piped to third-party APIs verbatim (Discord webhook,
# X/Twitter, LinkedIn, Bluesky). Template markers in the body will be posted
# as literal text. This linter runs both as a lefthook pre-commit guard on
# knowledge-base/marketing/distribution-content/*.md and on-demand for audits.
#
# Usage: lint-distribution-content.sh <file> [<file> ...]
#
# Exit codes:
#   0 - All files clean (or no files provided)
#   1 - At least one file contains Liquid markers in body
#   2 - A provided path does not exist or is not readable

set -euo pipefail

if [[ $# -eq 0 ]]; then
  exit 0
fi

found_markers=0
missing_file=0

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "lint-distribution-content: file not found: $file" >&2
    missing_file=1
    continue
  fi

  # Body only: bytes after the second `---`. Frontmatter may legitimately
  # contain brace-like strings (JSON-encoded values, URL paths); never posted.
  body=$(awk '/^---$/{c++; next} c==2' "$file")
  if [[ -z "$body" ]]; then
    continue
  fi

  # Count body lines consumed by awk so we can report file-relative numbers.
  # We compute the offset = (number of lines up to and including the second `---`).
  offset=$(awk '/^---$/{c++; if (c==2) { print NR; exit } }' "$file")
  if [[ -z "$offset" ]]; then
    offset=0
  fi

  offenders=$(printf '%s\n' "$body" | grep -nF -e '{{' -e '}}' -e '{%' -e '%}' || true)
  if [[ -z "$offenders" ]]; then
    continue
  fi

  while IFS= read -r hit; do
    body_lineno="${hit%%:*}"
    content="${hit#*:}"
    file_lineno=$((body_lineno + offset))
    echo "$file:$file_lineno: unrendered Liquid marker: $content" >&2
  done <<< "$offenders"
  found_markers=1
done

if [[ "$missing_file" -eq 1 && "$found_markers" -eq 0 ]]; then
  exit 2
fi
if [[ "$found_markers" -eq 1 ]]; then
  exit 1
fi
exit 0
