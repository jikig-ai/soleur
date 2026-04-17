#!/usr/bin/env bash
# content-publisher.sh -- Scan distribution-content/ for scheduled content and
# publish to declared channels (Discord webhook, X/Twitter API, LinkedIn API).
#
# Usage: content-publisher.sh
#   No arguments. Scans all .md files in distribution-content/, finds files
#   with publish_date == today and status: scheduled, publishes to channels
#   declared in frontmatter, and updates status to published via sed -i.
#
# Environment variables:
#   DISCORD_BLOG_WEBHOOK_URL - Discord webhook for #blog channel (preferred; optional)
#   DISCORD_WEBHOOK_URL      - Discord webhook fallback (optional; skips if neither set)
#   X_API_KEY              - X API key (optional; skips if unset)
#   X_API_SECRET           - X API secret
#   X_ACCESS_TOKEN         - X access token
#   X_ACCESS_TOKEN_SECRET  - X access token secret
#   LINKEDIN_ACCESS_TOKEN   - LinkedIn OAuth 2.0 token (optional; skips if unset)
#   LINKEDIN_PERSON_URN    - LinkedIn person URN for posting
#   LINKEDIN_ORG_ID        - LinkedIn organization ID for company page (optional; skips if unset)
#   BSKY_HANDLE            - Bluesky handle (optional; skips if unset)
#   BSKY_APP_PASSWORD      - Bluesky app password
#   BSKY_ALLOW_POST        - Set to "true" to enable posting
#   GH_TOKEN               - GitHub token for issue creation
#
# Exit codes:
#   0 - All platforms posted (or gracefully skipped)
#   1 - Fatal error (no content directory, invalid setup)
#   2 - Partial failure (some platforms failed but fallback issues were created)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTENT_DIR="$REPO_ROOT/knowledge-base/marketing/distribution-content"
X_SCRIPT="$REPO_ROOT/plugins/soleur/skills/community/scripts/x-community.sh"
LINKEDIN_SCRIPT="$REPO_ROOT/plugins/soleur/skills/community/scripts/linkedin-community.sh"
BSKY_SCRIPT="$REPO_ROOT/plugins/soleur/skills/community/scripts/bsky-community.sh"
AVATAR_URL="https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png"

# Global set per-file in the scan loop, used by fallback issue creators
CASE_NAME=""
# Holds the last Discord error for passing to fallback issue creators
DISCORD_LAST_ERROR=""

# --- Temp File Cleanup ---
# Track all temp files and clean up on any exit (normal, error, or signal).
# Prevents temp file leaks under set -e when a command fails between mktemp and rm.
_TMPFILES=()
trap 'rm -f "${_TMPFILES[@]}"' EXIT

make_tmp() {
  local f
  f=$(mktemp)
  _TMPFILES+=("$f")
  echo "$f"
}

# --- Frontmatter Parsing ---

parse_frontmatter() {
  local file="$1"
  awk '/^---$/{c++; next} c==1' "$file"
}

get_frontmatter_field() {
  local file="$1"
  local field="$2"
  # || true: grep returns exit 1 on no match, which pipefail propagates
  parse_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/' || true
}

# --- Liquid Marker Validation ---
#
# Distribution content files are raw API payloads (Discord webhook content,
# X tweet text, LinkedIn share text) — NOT Eleventy templates. Any Liquid/Jinja
# marker in a body section will be posted verbatim to third parties. This
# validator rejects files containing such markers before the publish loop
# dispatches to any channel.
#
# Scope: body only (bytes after the second `---`). Frontmatter fields are
# exempt because they may legitimately contain braces (JSON-encoded values,
# relative URL paths, etc.) and are never posted to third parties directly.
#
# Returns 0 if clean, 1 if any marker is found. Prints offending lines to
# stderr in `<file>:<file-relative-line>: unrendered Liquid marker: <content>`
# format (matches scripts/lint-distribution-content.sh for operator grepability).

# Strip C0/C1 control bytes and Unicode line separators (U+2028/U+2029).
# Content bytes from third-party markdown flow into stderr and issue bodies;
# escape sequences in those bytes can rewrite terminal titles, inject cursor
# control in CI logs, or trigger OSC 52 clipboard hijack. echo (no -e) does
# not interpret them, but many terminals do on raw output.
_liquid_strip_controls() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' | sed 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'
}

validate_no_liquid_markers() {
  local file="$1"
  local body offenders offset

  body=$(awk '/^---$/{c++; next} c==2' "$file")
  if [[ -z "$body" ]]; then
    return 0
  fi

  # Offset = line number of the second `---` in the source file. grep -n
  # against the body gives body-relative numbers; adding offset yields
  # file-relative numbers that a human can open directly in an editor.
  offset=$(awk '/^---$/{c++; if (c==2) { print NR; exit } }' "$file")
  if [[ -z "$offset" ]]; then
    offset=0
  fi

  offenders=$(printf '%s\n' "$body" | grep -nF -e '{{' -e '}}' -e '{%' -e '%}' || true)
  if [[ -z "$offenders" ]]; then
    return 0
  fi

  local hit body_lineno content file_lineno safe_content
  while IFS= read -r hit; do
    body_lineno="${hit%%:*}"
    content="${hit#*:}"
    file_lineno=$((body_lineno + offset))
    safe_content=$(_liquid_strip_controls "$content")
    echo "$file:$file_lineno: unrendered Liquid marker: $safe_content" >&2
  done <<< "$offenders"
  return 1
}

# Redact token-like values before embedding offending lines in a public
# GitHub issue body. Heuristic only — catches the common case of an
# authoring mistake that embeds a secret via template syntax.
_liquid_redact_secrets() {
  sed -E 's/((token|secret|key|password|api[_-]?key)[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1[REDACTED]/gi'
}

create_liquid_marker_fallback_issue() {
  local file="$1"
  local offenders="${2:-}"
  local base safe_offenders
  base=$(basename "$file" .md)

  # Sanitize offender content before embedding in a public issue body:
  # strip control bytes, redact token-like values, escape triple-backticks
  # that would terminate the fenced code block.
  safe_offenders=$(_liquid_strip_controls "$offenders" | _liquid_redact_secrets | sed 's/```/`\xe2\x80\x8b``/g')

  local title="[Content Publisher] Unrendered Liquid markers in $base -- post blocked"
  local offender_section=""
  if [[ -n "$safe_offenders" ]]; then
    offender_section=$(printf '\n\n**Offending lines:**\n```\n%s\n```' "${safe_offenders:0:1500}")
  fi
  local body
  body=$(printf '## Unrendered Liquid Markers Detected\n\nThe content publisher refused to post **%s** because its body contains one or more Liquid/Jinja template markers (`{{`, `}}`, `{%%`, `%%}`).%s\n\nDistribution content is piped to third-party APIs verbatim — template markers are never resolved. Fix the source file, re-set `status: scheduled`, and the next cron run will publish.' \
    "$base" "$offender_section")

  create_dedup_issue "$title" "$body" "action-required,content-publisher"
}

# --- Channel Mapping ---

# Maps channel name from frontmatter to section heading in content file.
# Returns empty string for unknown channels (caller handles warning).
channel_to_section() {
  local channel="$1"
  case "$channel" in
    discord)           echo "Discord" ;;
    x)                 echo "X/Twitter Thread" ;;
    linkedin-personal) echo "LinkedIn Personal" ;;
    linkedin-company)  echo "LinkedIn Company Page" ;;
    bluesky)           echo "Bluesky" ;;
    *)                 echo "" ;;
  esac
}

# --- Content Extraction ---

extract_section() {
  local file="$1"
  local heading="$2"
  local content

  # Extract between "## heading" and next "## " (or EOF), excluding ## lines.
  # Uses awk to avoid sed delimiter conflicts with headings containing '/'.
  # Trims trailing whitespace before comparing to tolerate "## Discord " etc.
  content=$(awk -v h="$heading" '
    /^## / {
      line = $0; gsub(/[[:space:]]+$/, "", line)
      if (line == "## " h) { found=1; next }
      if (found) exit
    }
    found { print }
  ' "$file")

  # Remove horizontal rules between sections
  content=$(echo "$content" | grep -v '^---$' || true)

  # Trim leading blank lines
  content=$(echo "$content" | sed '/./,$!d')

  # Handle "Not scheduled" placeholder sections
  if echo "$content" | grep -q "Not scheduled for"; then
    echo ""
    return 0
  fi

  echo "$content"
}

extract_tweets() {
  local file="$1"
  local x_section mode

  x_section=$(extract_section "$file" "X/Twitter Thread")
  if [[ -z "$x_section" ]]; then
    echo "Error: No X/Twitter Thread section found in $file" >&2
    return 1
  fi

  # Two authoring formats are supported:
  #  (a) Labeled format: each tweet preceded by `**Tweet N (...) -- N chars:**` (label dropped).
  #  (b) Numbered format: no label; tweets 2+ begin with `N/ ` on a fresh line. The hook
  #      is the blob before the first `N/` marker. The `N/ ` prefix is preserved so the
  #      posted tweet keeps its thread-position cue.
  # Detect mode so `N/ ` lines inside a labeled tweet body (which are legitimate
  # tweet content in the labeled convention) are not mistakenly treated as tweet
  # boundaries. Label detection tolerates leading whitespace (`  **Tweet 1 ...`).
  mode="labeled"
  if ! echo "$x_section" | grep -qE '^[[:space:]]*\*\*Tweet[[:space:]]+[0-9]'; then
    mode="numbered"
  fi

  # Output RS-separated (\x1e) for safe multi-line handling. mawk silently drops \0.
  if [[ "$mode" == "labeled" ]]; then
    echo "$x_section" | awk '
      /^[[:space:]]*\*\*Tweet[[:space:]]+[0-9]/ { if (buf != "") { printf "%s\x1e", buf }; buf=""; next }
      {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (buf != "") buf = buf "\n" line
        else buf = line
      }
      END { if (buf != "") printf "%s\x1e", buf }
    '
  else
    # Numbered mode: only split when the line starts with `<expected>/ ` where
    # `expected` begins at 2 (hook is tweet 1, un-prefixed) and increments after
    # each match. This prevents prose like `3/5 users` or `1/3 of devs` from
    # being miscounted as a tweet boundary.
    echo "$x_section" | awk '
      BEGIN { expected = 2 }
      {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      }
      # Boundary detected: line starts with the expected sequence number + "/ ".
      # Use substr/match to parse rather than regex interpolation.
      {
        is_boundary = 0
        if (match(line, /^[0-9]+\/ /)) {
          prefix = substr(line, RSTART, RLENGTH)
          n = substr(prefix, 1, length(prefix) - 2) + 0
          if (n == expected) { is_boundary = 1 }
        }
      }
      is_boundary {
        if (buf != "") { printf "%s\x1e", buf }
        buf = line
        expected++
        next
      }
      {
        if (buf != "") buf = buf "\n" line
        else buf = line
      }
      END { if (buf != "") printf "%s\x1e", buf }
    '
  fi
}

# --- Discord Posting ---

post_discord() {
  local content="$1"

  # Prefer blog channel, fall back to general
  local webhook_url="${DISCORD_BLOG_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"

  if [[ -z "$webhook_url" ]]; then
    echo "Warning: No Discord webhook URL set (checked DISCORD_BLOG_WEBHOOK_URL, DISCORD_WEBHOOK_URL). Skipping Discord posting." >&2
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg content "$content" \
    --arg username "Sol" \
    --arg avatar_url "$AVATAR_URL" \
    '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

  local stderr_file http_code response_body
  stderr_file=$(make_tmp)
  http_code=$(curl -s -w "%{http_code}" -o "$stderr_file" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url")

  if [[ "$http_code" =~ ^2 ]]; then
    rm -f "$stderr_file"
    echo "[ok] Discord message posted (HTTP $http_code)."
  else
    response_body=$(head -c 1000 "$stderr_file")
    rm -f "$stderr_file"
    echo "Error: Discord webhook returned HTTP $http_code." >&2
    # Store error context for caller to pass to fallback issue
    DISCORD_LAST_ERROR="HTTP $http_code: $response_body"
    return 1
  fi
}

post_discord_warning() {
  local message="$1"

  # Use general webhook for warnings, not blog channel
  local webhook_url="${DISCORD_WEBHOOK_URL:-}"

  if [[ -z "$webhook_url" ]]; then
    echo "Warning: No Discord webhook URL set. Cannot send stale content warning." >&2
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg content "$message" \
    --arg username "Sol" \
    --arg avatar_url "$AVATAR_URL" \
    '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

  curl -s -o /dev/null -w "" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url" || true
}

# --- X/Twitter Posting ---

create_x_fallback_issue() {
  local file="$1"
  local error_reason="${2:-}"
  local x_content
  x_content=$(extract_section "$file" "X/Twitter Thread")

  local title="[Content Publisher] X API failed -- manual posting required for $CASE_NAME"
  local error_section=""
  if [[ -n "$error_reason" ]]; then
    error_section=$(printf '\n\n**Error:**\n```\n%s\n```' "${error_reason:0:1000}")
  fi
  local body
  body=$(printf '## Manual X/Twitter Posting Required\n\nThe scheduled content publisher could not post to X/Twitter for **%s**.%s\n\nPost this thread manually at https://x.com/compose/post:\n\n---\n\n%s' "$CASE_NAME" "$error_section" "$x_content")

  create_dedup_issue "$title" "$body" "action-required,content-publisher" || {
    echo "FATAL: X posting failed AND fallback issue creation failed." >&2
    return 1
  }
}

create_partial_thread_issue() {
  local file="$1"
  local last_tweet_id="$2"
  local resume_from="$3"
  local error_reason="${4:-}"
  local x_content
  x_content=$(extract_section "$file" "X/Twitter Thread")

  local title="[Content Publisher] Partial X thread -- resume for $CASE_NAME"
  local error_section=""
  if [[ -n "$error_reason" ]]; then
    error_section=$(printf '\n\n**Error:**\n```\n%s\n```' "${error_reason:0:1000}")
  fi
  local body
  body=$(printf '## Partial X Thread -- Resume Required\n\nThe thread for **%s** was partially posted. Resume from tweet %s.%s\n\n**Last successful tweet:** https://x.com/soleur_ai/status/%s\n**Resume with:** `--reply-to %s`\n\n---\n\n%s' \
    "$CASE_NAME" "$resume_from" "$error_section" "$last_tweet_id" "$last_tweet_id" "$x_content")

  create_dedup_issue "$title" "$body" "action-required,content-publisher" || {
    echo "FATAL: Partial thread issue creation failed. Data loss: thread stalled at tweet $resume_from." >&2
    return 1
  }
}

create_discord_fallback_issue() {
  local content="$1"
  local error_reason="${2:-}"
  local title="[Content Publisher] Discord posting failed -- manual posting required for $CASE_NAME"
  local error_section=""
  if [[ -n "$error_reason" ]]; then
    error_section=$(printf '\n\n**Error:**\n```\n%s\n```' "${error_reason:0:1000}")
  fi
  local body
  body=$(printf '## Manual Discord Posting Required\n\nThe scheduled content publisher could not post to Discord for **%s**.%s\n\nPost this content manually in the Discord channel:\n\n---\n\n%s' "$CASE_NAME" "$error_section" "$content")
  create_dedup_issue "$title" "$body" "action-required,content-publisher"
}

post_x_thread() {
  local file="$1"

  if [[ -z "${X_API_KEY:-}" || -z "${X_API_SECRET:-}" || -z "${X_ACCESS_TOKEN:-}" || -z "${X_ACCESS_TOKEN_SECRET:-}" ]]; then
    echo "Warning: X API credentials not configured. Skipping X posting." >&2
    return 0
  fi

  local -a tweets=()
  local tweet

  # Read RS-separated (\x1e) tweets into array
  while IFS= read -r -d $'\x1e' tweet; do
    [[ -n "$tweet" ]] && tweets+=("$tweet")
  done < <(extract_tweets "$file")

  if [[ ${#tweets[@]} -eq 0 ]]; then
    echo "Warning: No tweets found in X/Twitter Thread section. Skipping X posting." >&2
    return 0
  fi

  # Post hook tweet -- capture stdout (JSON) and stderr separately
  local hook_result hook_id hook_stderr
  local prev_id reply_result reply_id reply_stderr i
  hook_stderr=$(make_tmp)
  hook_result=$(bash "$X_SCRIPT" post-tweet "${tweets[0]}" 2>"$hook_stderr") || {
    local exit_code=$?
    local err_text
    err_text=$(cat "$hook_stderr")
    rm -f "$hook_stderr"
    if echo "$err_text" | grep -q "402"; then
      echo "X API returned 402 (Payment Required). Creating fallback issue." >&2
      create_x_fallback_issue "$file" "$err_text"
      return 1
    fi
    echo "Error posting hook tweet (exit $exit_code): $err_text" >&2
    create_x_fallback_issue "$file" "$err_text"
    return 1
  }
  rm -f "$hook_stderr"

  hook_id=$(echo "$hook_result" | jq -r '.id // empty')
  if [[ -z "$hook_id" ]]; then
    echo "Error: Failed to extract tweet ID from hook response." >&2
    create_x_fallback_issue "$file" "Failed to extract tweet ID from response: ${hook_result:0:500}"
    return 1
  fi
  echo "[ok] Hook tweet posted: https://x.com/soleur_ai/status/$hook_id"

  # Chain body tweets -- each reply references the immediately preceding tweet
  prev_id="$hook_id"
  reply_stderr=$(make_tmp)
  for (( i = 1; i < ${#tweets[@]}; i++ )); do
    sleep 2  # Rate-limit guard: pause between thread tweets to avoid X API 429s
    reply_result=$(bash "$X_SCRIPT" post-tweet "${tweets[$i]}" --reply-to "$prev_id" 2>"$reply_stderr") || {
      local reply_exit=$?
      local reply_err
      reply_err=$(cat "$reply_stderr")
      if echo "$reply_err" | grep -q "402"; then
        echo "X API returned 402 (Payment Required) on tweet $((i+1)). Thread is partial." >&2
      else
        echo "Error posting tweet $((i+1))/${#tweets[@]} (exit $reply_exit): $reply_err" >&2
      fi
      rm -f "$reply_stderr"
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))" "$reply_err"
      return 1
    }
    reply_id=$(echo "$reply_result" | jq -r '.id // empty')
    if [[ -z "$reply_id" ]]; then
      echo "Error: Failed to extract reply ID for tweet $((i+1)). Thread is partial." >&2
      rm -f "$reply_stderr"
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))" "Failed to extract reply ID from response: ${reply_result:0:500}"
      return 1
    fi
    prev_id="$reply_id"
    echo "[ok] Tweet $((i+1))/${#tweets[@]} posted: https://x.com/soleur_ai/status/$reply_id"
  done
  rm -f "$reply_stderr"

  echo "[ok] X thread posted successfully (${#tweets[@]} tweets)."
}

# --- LinkedIn Posting ---

create_linkedin_fallback_issue() {
  local file="$1"
  local section="${2:-LinkedIn Personal}"
  local error_reason="${3:-}"
  local linkedin_content
  linkedin_content=$(extract_section "$file" "$section")

  local title="[Content Publisher] LinkedIn API failed -- manual posting required for $CASE_NAME ($section)"
  local error_section=""
  if [[ -n "$error_reason" ]]; then
    error_section=$(printf '\n\n**Error:**\n```\n%s\n```' "${error_reason:0:1000}")
  fi
  local body
  body=$(printf '## Manual LinkedIn Posting Required\n\nThe scheduled content publisher could not post to LinkedIn for **%s** (%s).%s\n\nPost this content manually at https://www.linkedin.com/feed/:\n\n---\n\n%s' "$CASE_NAME" "$section" "$error_section" "$linkedin_content")

  create_dedup_issue "$title" "$body" "action-required,content-publisher" || {
    echo "FATAL: LinkedIn posting failed AND fallback issue creation failed." >&2
    return 1
  }
}

post_linkedin() {
  local file="$1"
  local section="${2:-LinkedIn Personal}"

  if [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]]; then
    echo "Warning: LINKEDIN_ACCESS_TOKEN not set. Skipping LinkedIn posting." >&2
    return 0
  fi

  local content
  content=$(extract_section "$file" "$section")
  if [[ -z "$content" ]]; then
    echo "Warning: No $section content found in $(basename "$file"). Skipping." >&2
    return 0
  fi

  local stderr_file
  stderr_file=$(make_tmp)
  if ! bash "$LINKEDIN_SCRIPT" post-content --text "$content" 2>"$stderr_file"; then
    local error_reason
    error_reason=$(head -c 1000 "$stderr_file")
    rm -f "$stderr_file"
    echo "Error: LinkedIn posting failed ($section). Creating fallback issue." >&2
    create_linkedin_fallback_issue "$file" "$section" "$error_reason"
    return 1
  fi
  rm -f "$stderr_file"
  echo "[ok] LinkedIn post published ($section)."
}

post_linkedin_company() {
  local file="$1"

  if [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]]; then
    echo "Warning: LINKEDIN_ACCESS_TOKEN not set. Skipping LinkedIn Company Page posting." >&2
    return 0
  fi

  if [[ -z "${LINKEDIN_ORG_ID:-}" ]]; then
    echo "Warning: LINKEDIN_ORG_ID not set. Skipping LinkedIn Company Page posting." >&2
    return 0
  fi

  if [[ "${LINKEDIN_ALLOW_POST:-}" != "true" ]]; then
    echo "Warning: LINKEDIN_ALLOW_POST is not set to 'true'. Skipping LinkedIn Company Page posting." >&2
    return 0
  fi

  local content
  content=$(extract_section "$file" "LinkedIn Company Page")
  if [[ -z "$content" ]]; then
    echo "Warning: No LinkedIn Company Page content found in $(basename "$file"). Skipping." >&2
    return 0
  fi

  local stderr_file
  stderr_file=$(make_tmp)
  if ! bash "$LINKEDIN_SCRIPT" post-content --text "$content" --author "urn:li:organization:${LINKEDIN_ORG_ID}" 2>"$stderr_file"; then
    local error_reason
    error_reason=$(head -c 1000 "$stderr_file")
    rm -f "$stderr_file"
    echo "Error: LinkedIn Company Page posting failed. Creating fallback issue." >&2
    create_linkedin_fallback_issue "$file" "LinkedIn Company Page" "$error_reason"
    return 1
  fi
  rm -f "$stderr_file"
  echo "[ok] LinkedIn Company Page post published."
}

# --- Bluesky Posting ---

create_bluesky_fallback_issue() {
  local file="$1"
  local error_reason="${2:-}"
  local bsky_content
  bsky_content=$(extract_section "$file" "Bluesky")

  local title="[Content Publisher] Bluesky API failed -- manual posting required for $CASE_NAME"
  local error_section=""
  if [[ -n "$error_reason" ]]; then
    error_section=$(printf '\n\n**Error:**\n```\n%s\n```' "${error_reason:0:1000}")
  fi
  local body
  body=$(printf '## Manual Bluesky Posting Required\n\nThe scheduled content publisher could not post to Bluesky for **%s**.%s\n\nPost this content manually at https://bsky.app:\n\n---\n\n%s' "$CASE_NAME" "$error_section" "$bsky_content")

  create_dedup_issue "$title" "$body" "action-required,content-publisher" || {
    echo "FATAL: Bluesky posting failed AND fallback issue creation failed." >&2
    return 1
  }
}

post_bluesky() {
  local file="$1"

  if [[ -z "${BSKY_HANDLE:-}" || -z "${BSKY_APP_PASSWORD:-}" ]]; then
    echo "Warning: Bluesky credentials not configured (checked BSKY_HANDLE, BSKY_APP_PASSWORD). Skipping Bluesky posting." >&2
    return 0
  fi

  if [[ "${BSKY_ALLOW_POST:-}" != "true" ]]; then
    echo "Warning: BSKY_ALLOW_POST is not set to 'true'. Skipping Bluesky posting." >&2
    return 0
  fi

  local content
  content=$(extract_section "$file" "Bluesky")
  if [[ -z "$content" ]]; then
    echo "Warning: No Bluesky content found in $(basename "$file"). Skipping Bluesky." >&2
    return 0
  fi

  local stderr_file
  stderr_file=$(make_tmp)
  if ! bash "$BSKY_SCRIPT" post "$content" 2>"$stderr_file"; then
    local error_reason
    error_reason=$(head -c 1000 "$stderr_file")
    rm -f "$stderr_file"
    echo "Error: Bluesky posting failed. Creating fallback issue." >&2
    create_bluesky_fallback_issue "$file" "$error_reason"
    return 1
  fi
  rm -f "$stderr_file"
  echo "[ok] Bluesky post published."
}

# --- Issue Management ---

create_dedup_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"
  local milestone="${4:-Post-MVP / Later}"

  # Check for existing open issue with exact title match
  local existing
  existing=$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
    --jq "[.[] | select(.title == \"$title\")] | .[0].number // empty")

  if [[ -n "$existing" ]]; then
    echo "Issue already exists: #$existing -- skipping." >&2
    return 0
  fi

  if gh issue create --title "$title" --label "$labels" --milestone "$milestone" --body "$body"; then
    echo "[ok] Issue created: $title"
  else
    echo "Error: Failed to create issue: $title" >&2
    return 1
  fi
}

# --- Main ---

main() {
  if [[ ! -d "$CONTENT_DIR" ]]; then
    echo "Error: Content directory not found: $CONTENT_DIR" >&2
    exit 1
  fi

  # Validate x-community.sh exists if X credentials are configured
  if [[ -n "${X_API_KEY:-}" && ! -f "$X_SCRIPT" ]]; then
    echo "Error: x-community.sh not found at $X_SCRIPT" >&2
    exit 1
  fi

  # Validate linkedin-community.sh exists if LinkedIn credentials are configured
  if [[ -n "${LINKEDIN_ACCESS_TOKEN:-}" && ! -f "$LINKEDIN_SCRIPT" ]]; then
    echo "Error: linkedin-community.sh not found at $LINKEDIN_SCRIPT" >&2
    exit 1
  fi

  # Validate bsky-community.sh exists if Bluesky credentials are configured
  if [[ -n "${BSKY_HANDLE:-}" && ! -f "$BSKY_SCRIPT" ]]; then
    echo "Error: bsky-community.sh not found at $BSKY_SCRIPT" >&2
    exit 1
  fi

  local today
  today=$(date +%Y-%m-%d)
  local failures=0
  local published=0

  echo "Scanning $CONTENT_DIR for content scheduled on $today..."

  for file in "$CONTENT_DIR"/*.md; do
    [[ -f "$file" ]] || continue

    local status publish_date channels title
    status=$(get_frontmatter_field "$file" "status")
    publish_date=$(get_frontmatter_field "$file" "publish_date")
    channels=$(get_frontmatter_field "$file" "channels")
    title=$(get_frontmatter_field "$file" "title")

    # Skip files without valid frontmatter
    if [[ -z "$status" || -z "$publish_date" ]]; then
      echo "Warning: Missing frontmatter (status/publish_date) in $(basename "$file"). Skipping." >&2
      continue
    fi

    # Skip non-scheduled content
    [[ "$status" == "scheduled" ]] || continue

    # Stale content: scheduled but publish_date in the past.
    # Mark as stale to prevent duplicate warnings on subsequent runs.
    if [[ "$publish_date" < "$today" ]]; then
      echo "WARNING: Stale scheduled content: $(basename "$file") (publish_date: $publish_date)" >&2
      post_discord_warning "**Stale scheduled content detected**\n\nFile: $(basename "$file")\nPublish date: $publish_date\nStatus: scheduled\n\nThis content was scheduled for a past date and was not published. Update the publish_date or set status to draft."
      sed -i 's/^status: scheduled/status: stale/' "$file"
      continue
    fi

    # Skip future content
    [[ "$publish_date" == "$today" ]] || continue

    # Skip files with no channels declared
    if [[ -z "$channels" ]]; then
      echo "Warning: No channels declared in $(basename "$file"). Skipping." >&2
      continue
    fi

    # Set CASE_NAME for fallback issue creators
    CASE_NAME="${title:-$(basename "$file" .md)}"

    echo "---"
    echo "Publishing: $CASE_NAME ($(basename "$file"))"

    # Hard gate: reject any file whose body contains unrendered Liquid/Jinja
    # markers. Distribution content is posted verbatim to third parties — a
    # stray `{{ site.url }}` becomes a literal `{{ site.url }}` in the
    # Discord message. Skip all channels for this file and file a fallback
    # issue so the broken content is tracked, not lost.
    local liquid_offenders
    if ! liquid_offenders=$(validate_no_liquid_markers "$file" 2>&1 1>/dev/null); then
      echo "Error: Unrendered Liquid markers detected. Skipping all channels for this file." >&2
      create_liquid_marker_fallback_issue "$file" "$liquid_offenders" || true
      failures=$((failures + 1))
      continue
    fi

    local file_failures=0
    local file_successes=0

    # Publish to each declared channel
    local channel section
    while IFS= read -r channel; do
      channel=$(echo "$channel" | xargs)
      [[ -z "$channel" ]] && continue

      section=$(channel_to_section "$channel")
      if [[ -z "$section" ]]; then
        echo "Warning: Unknown channel '$channel' in $(basename "$file"). Skipping." >&2
        continue
      fi

      case "$channel" in
        discord)
          local discord_content
          discord_content=$(extract_section "$file" "$section")
          if [[ -n "$discord_content" ]]; then
            DISCORD_LAST_ERROR=""
            if post_discord "$discord_content"; then
              file_successes=$((file_successes + 1))
            else
              echo "Warning: Discord posting failed. Creating fallback issue." >&2
              create_discord_fallback_issue "$discord_content" "$DISCORD_LAST_ERROR" || true
              file_failures=$((file_failures + 1))
            fi
          else
            echo "Warning: No $section content found in $(basename "$file"). Skipping Discord." >&2
          fi
          ;;
        x)
          if post_x_thread "$file"; then
            file_successes=$((file_successes + 1))
          else
            file_failures=$((file_failures + 1))
          fi
          ;;
        linkedin-personal)
          if post_linkedin "$file" "LinkedIn Personal"; then
            file_successes=$((file_successes + 1))
          else
            file_failures=$((file_failures + 1))
          fi
          ;;
        linkedin-company)
          if post_linkedin_company "$file"; then
            file_successes=$((file_successes + 1))
          else
            file_failures=$((file_failures + 1))
          fi
          ;;
        bluesky)
          if post_bluesky "$file"; then
            file_successes=$((file_successes + 1))
          else
            file_failures=$((file_failures + 1))
          fi
          ;;
      esac
    done < <(echo "$channels" | tr ',' '\n')

    if [[ "$file_successes" -gt 0 ]]; then
      # At least one channel succeeded — mark as published.
      # Failed channels already have fallback issues created above.
      sed -i 's/^status: scheduled/status: published/' "$file"
      if [[ "$file_failures" -gt 0 ]]; then
        echo "[partial] Published to $file_successes channel(s), $file_failures failed. Status updated: $(basename "$file")"
      else
        echo "[ok] Published and status updated: $(basename "$file")"
      fi
      published=$((published + 1))
    elif [[ "$file_failures" -gt 0 ]]; then
      failures=$((failures + 1))
    fi

    sleep 5  # Rate limit buffer between files
  done

  echo "---"
  echo "Scan complete. Published: $published. Failures: $failures."

  if [[ "$failures" -gt 0 ]]; then
    exit 2
  fi
}

# Guard: only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
