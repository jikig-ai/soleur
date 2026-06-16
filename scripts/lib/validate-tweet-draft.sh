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
#   - a `channels:` value that includes the `bluesky` token (#5022)
#   - a `## X/Twitter Thread` heading with a non-empty body
#   - a `## Bluesky` heading with a non-empty body (#5022)
#
# Exit 0 when all hold. Exit 1 + "invalid: <reason>" on stderr on any miss.
set -euo pipefail

file="${1:-}"
if [[ -z "$file" || ! -f "$file" ]]; then
  echo "invalid: file not found: ${file:-<none>}" >&2
  exit 1
fi

# Require a properly terminated frontmatter block: the first line must be `---`
# and a closing `---` must exist. Without the closing-fence check, a draft with
# an opening `---` and no closing fence makes the extractor below emit the whole
# file as "frontmatter" — body `key: value` lines then satisfy the field checks
# and a structurally-broken draft passes the very gate meant to reject it.
if [[ "$(head -1 "$file")" != "---" ]]; then
  echo "invalid: missing frontmatter (file does not start with '---')" >&2
  exit 1
fi
if [[ "$(awk '/^---$/{c++} END{print c+0}' "$file")" -lt 2 ]]; then
  echo "invalid: unterminated frontmatter (no closing '---')" >&2
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
# channels is a comma/space-separated token list (optionally a YAML inline list
# `[x, bluesky]` or quoted `"x"`); strip list/quote punctuation, then require the
# `x` token.
channels_has_x=0
_channels_clean="${channels//[\[\]\",\']/ }"
for _tok in ${_channels_clean//,/ }; do
  [[ "$_tok" == "x" ]] && channels_has_x=1
done
if [[ "$channels_has_x" -ne 1 ]]; then
  echo "invalid: 'channels' must include the 'x' token (got '${channels:-<missing>}')" >&2
  exit 1
fi
# #5022 — feature-tweet cross-posts to Bluesky too. Reuse `_channels_clean`
# (already punctuation-stripped above) to require the `bluesky` token.
channels_has_bluesky=0
for _tok in ${_channels_clean//,/ }; do
  [[ "$_tok" == "bluesky" ]] && channels_has_bluesky=1
done
if [[ "$channels_has_bluesky" -ne 1 ]]; then
  echo "invalid: 'channels' must include the 'bluesky' token (got '${channels:-<missing>}')" >&2
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

# `## Bluesky` heading present? (#5022 — parallel to the X thread gate)
if ! grep -qE '^## Bluesky[[:space:]]*$' "$file"; then
  echo "invalid: missing '## Bluesky' heading" >&2
  exit 1
fi

# Bluesky body after the heading must be non-empty (up to the next `## ` or EOF).
bluesky_body=$(awk '
  /^## Bluesky[[:space:]]*$/ { grab=1; next }
  grab && /^## / { exit }
  grab { print }
' "$file" | grep -vE '^[[:space:]]*$' || true)

if [[ -z "$bluesky_body" ]]; then
  echo "invalid: '## Bluesky' section is empty" >&2
  exit 1
fi

exit 0
