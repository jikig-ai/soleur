#!/usr/bin/env bash
# blog-jargon-scan.sh - flag reader-visible jargon that a brand guide's Blog note bans.
#
# Usage: blog-jargon-scan.sh <post.md>
#
# Scans the frontmatter title/seoTitle/description values and the body up to the
# first JSON-LD <script> block. Markdown link targets "](...)" are stripped first:
# a URL is not reader-visible text. Flags a backtick, a --flag token, or a #NN number.
#
# Exit codes:
#   0  no hits
#   1  hits found; each printed as "<line>: <text>"
#   2  usage error, or the file could not be read or scanned
set -euo pipefail

[[ $# -eq 1 && -f "$1" && -r "$1" ]] || { echo "usage: blog-jargon-scan.sh <post.md>" >&2; exit 2; }

visible=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next}
               fm && /^---[[:space:]]*$/ {fm=0; next}
               fm { if ($0 ~ /^(title|seoTitle|description):/) print NR": "$0; next }
               /<script type="application\/ld\+json">/ {exit}
               {print NR": "$0}' "$1" | sed -E 's/\]\([^)]*\)/]()/g') \
  || { echo "blog-jargon-scan: cannot scan $1" >&2; exit 2; }

rc=0
hits=$(printf '%s\n' "$visible" | grep -E '`|(^|[[:space:](])--[a-z][a-z-]+|(^|[^[:alnum:]&/#])#[0-9]{2,}') || rc=$?
if (( rc > 1 )); then
  echo "blog-jargon-scan: grep failed (rc=$rc)" >&2
  exit 2
fi
[[ -z "$hits" ]] && exit 0
printf '%s\n' "$hits"
exit 1
