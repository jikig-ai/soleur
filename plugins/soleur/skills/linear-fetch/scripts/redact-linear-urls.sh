#!/usr/bin/env bash
# Redact uploads.linear.app URLs from stdin. Writes redacted text to
# stdout; writes redaction count to stderr.
#
# Brand-survival: a regression here means a uploads.linear.app signed URL
# can leak into a committed artifact on a public-GitHub repo. See
# knowledge-base/project/specs/feat-linear-issue-image-context/spec.md FR7
# and the plan's User-Brand Impact section.
#
# Hostname matching is case-insensitive (DNS is case-insensitive — a URL like
# https://Uploads.Linear.App/x.png resolves to the same CDN host as the
# lowercase form and still serves the signed bearer credential). The hostname
# is encoded as bracketed character classes ([Hh][Tt]...) because BSD sed
# (macOS) does not portably support the `s///gI` case-insensitive flag, so
# we cannot rely on a flag in the substitution path.
#
# URL-path character class is a POSITIVE match against the RFC 3986 unreserved
# + reserved set (ASCII only). This is more conservative than the prior
# negated class:
#   - Multi-byte UTF-8 sequences (U+2028, U+2029, NBSP, etc.) automatically
#     terminate the match at the first non-ASCII byte. POSIX [:space:] is
#     ASCII-only and would let the redactor consume past Unicode separators
#     (security-sentinel P2-3 + cq-regex-unicode-separators-escape-only).
#   - Markdown/HTML terminators (< > " ' ) ]) are not in the set, so URLs
#     end correctly inside autolinks, HTML attributes, and markdown links.
#
# Adding a new CDN hostname (e.g., cdn.linear.app) requires:
#   1. A new entry in LINEAR_CDN_PATTERNS below.
#   2. An updated regex in .github/workflows/pr-quality-guards.yml pii-grep.
#   3. A matching fixture in redact-linear-urls.test.sh.
# The parity test (parity.test.sh, when added) enforces 1 and 2 stay in sync.
#
# set -e is on; pipefail is intentionally off because `grep -oE` returns
# exit 1 on zero matches — a benign condition we count and continue past.

set -eu

LINEAR_CDN_PATTERNS=(
  $'[Hh][Tt][Tt][Pp][Ss]?://[Uu][Pp][Ll][Oo][Aa][Dd][Ss]\\.[Ll][Ii][Nn][Ee][Aa][Rr]\\.[Aa][Pp][Pp]/[A-Za-z0-9._~:/?#@!$&*+,;=%-]+'
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
