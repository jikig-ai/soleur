#!/usr/bin/env bash
# blog-jargon-scan.sh - flag reader-visible jargon that a brand guide's Blog note bans.
#
# Usage: blog-jargon-scan.sh <post.md>
#
# Scans the frontmatter title/seoTitle/description values (including folded,
# multi-line values) and the body, skipping every JSON-LD <script> block.
# Markdown link targets "](...)" are stripped first: a URL is not reader-visible
# text. Flags a backtick, a <code>/<pre> tag, a --flag token, or a #NN number
# (two or more digits). Indented code blocks are not detected: they cannot be told
# apart from list continuation lines.
# This is a fixed subset of what a Blog note can ban; see content-writer Phase 2.4.
#
# Exit codes:
#   0  no hits
#   1  hits found; each printed as "<line>: <text>"
#   2  usage error, or the file could not be read or scanned
set -euo pipefail

[[ $# -eq 1 && -f "$1" && -r "$1" ]] || { echo "usage: blog-jargon-scan.sh <post.md>" >&2; exit 2; }

# Every output line starts with "NR: ", so no pattern below needs a ^ anchor.
visible=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next}
               fm && /^---[[:space:]]*$/ {fm=0; next}
               fm && /^(title|seoTitle|description):/ {cont=1; print NR": "$0; next}
               fm && cont && /^[[:space:]]+[^[:space:]]/ {print NR": "$0; next}
               fm {cont=0; next}
               /<script type="application\/ld\+json">/ {if ($0 !~ /<\/script>/) ld=1; next}
               ld && /<\/script>/ {ld=0; next}
               ld {next}
               {print NR": "$0}' "$1" | sed -E 's/\]\(([^()]|\([^()]*\))*\)/]()/g') \
  || { echo "blog-jargon-scan: cannot scan $1" >&2; exit 2; }

rc=0
hits=$(printf '%s\n' "$visible" | grep -E '`|<(code|pre)[ >]|[[:space:](]--[a-z][a-z-]+|[^[:alnum:]&/#]#[0-9]{2,}') || rc=$?
if (( rc > 1 )); then
  echo "blog-jargon-scan: grep failed (rc=$rc)" >&2
  exit 2
fi
[[ -z "$hits" ]] && exit 0
printf '%s\n' "$hits"
exit 1
