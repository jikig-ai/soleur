#!/usr/bin/env bash
# Redact uploads.linear.app URLs from stdin. Writes redacted text to
# stdout; writes redaction count to stderr.
#
# Brand-survival: a regression here means a uploads.linear.app signed URL
# can leak into a committed artifact on a public-GitHub repo. See
# knowledge-base/project/specs/feat-linear-issue-image-context/spec.md FR7
# and the plan's User-Brand Impact section.
#
# Character class for URL termination excludes whitespace and < > " ' ) ].
# Each excluded character has a markdown/HTML shape behind it:
#   whitespace : standard URL terminator
#   < and >    : markdown autolink <URL>
#   " and '    : HTML attribute quoting <img src="URL"> / src='URL'
#   )          : markdown link shape [text](URL)
#   ]          : markdown link-reference [text][REF] and reference defs [REF]: URL
# Adding a new excluded character is a one-line change here AND requires
# updating the CI pii-grep workflow regex to stay in sync.
#
# Adding a new CDN hostname (e.g., cdn.linear.app) is a one-line append
# to LINEAR_CDN_PATTERNS plus a matching fixture in redact-linear-urls.test.sh.
#
# set -e is on; pipefail is intentionally off because `grep -oE` returns
# exit 1 on zero matches — a benign condition we count and continue past.

set -eu

LINEAR_CDN_PATTERNS=(
  $'https?://uploads\\.linear\\.app/[^]<>"\x27)[:space:]]+'
)

input=$(cat -)
count=0
output="$input"
for pattern in "${LINEAR_CDN_PATTERNS[@]}"; do
  matches=$(printf '%s' "$output" | grep -oE "$pattern" | wc -l | tr -d '[:space:]')
  count=$((count + matches))
  output=$(printf '%s' "$output" | sed -E "s#$pattern#[linear-image: REDACTED]#g")
done
printf '%s' "$output"
printf '%s' "$count" >&2
