#!/usr/bin/env bash
# validate-tweet-draft.sh <file>
#
# Skill-owned structural assertion for feature-tweet drafts (#5021). This is the
# field/heading gate — NOT the Liquid linter. lint-distribution-content.sh
# checks only for unrendered template markers; it validates no frontmatter field
# and no section heading, so a structurally-broken draft (missing channels, no
# `## X/Twitter Thread`) would pass lint and then die silently at publish time.
# This script is the gate that catches that class before the file is finalized.
#
# Asserts the assembled draft has:
#   - a non-empty `title:` frontmatter value
#   - `status: draft` (never write straight-through to scheduled)
#   - a `channels:` value that includes the `x` token
#   - a `## X/Twitter Thread` heading with a non-empty body
#
# Exit 0 when all hold. Exit 1 + "invalid: <reason>" on stderr on any miss.
set -euo pipefail

file="${1:-}"
if [[ -z "$file" || ! -f "$file" ]]; then
  echo "invalid: file not found: ${file:-<none>}" >&2
  exit 1
fi

# Frontmatter = lines between the first and second `---`.
frontmatter=$(awk 'NR==1 && $0!="---"{exit} /^---$/{c++; if(c==2) exit; next} c==1' "$file")

_fm_field() {
  # First `^key:` value from the frontmatter, trimmed of surrounding quotes/space.
  printf '%s\n' "$frontmatter" \
    | sed -n "s/^$1:[[:space:]]*//p" | head -1 \
    | sed 's/^"//; s/"$//; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

title=$(_fm_field title)
status=$(_fm_field status)
channels=$(_fm_field channels)

if [[ -z "$title" ]]; then
  echo "invalid: empty or missing 'title' frontmatter" >&2
  exit 1
fi
if [[ "$status" != "draft" ]]; then
  echo "invalid: 'status' must be 'draft' (got '${status:-<missing>}')" >&2
  exit 1
fi
# channels is a comma/space-separated token list; require the `x` token.
channels_has_x=0
for _tok in ${channels//,/ }; do
  [[ "$_tok" == "x" ]] && channels_has_x=1
done
if [[ "$channels_has_x" -ne 1 ]]; then
  echo "invalid: 'channels' must include the 'x' token (got '${channels:-<missing>}')" >&2
  exit 1
fi

# `## X/Twitter Thread` heading present?
if ! grep -qE '^## X/Twitter Thread[[:space:]]*$' "$file"; then
  echo "invalid: missing '## X/Twitter Thread' heading" >&2
  exit 1
fi

# Body after the heading must be non-empty (up to the next `## ` or EOF).
thread_body=$(awk '
  /^## X\/Twitter Thread[[:space:]]*$/ { grab=1; next }
  grab && /^## / { exit }
  grab { print }
' "$file" | grep -vE '^[[:space:]]*$' || true)

if [[ -z "$thread_body" ]]; then
  echo "invalid: '## X/Twitter Thread' section is empty" >&2
  exit 1
fi

exit 0
