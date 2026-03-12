#!/usr/bin/env bash
# content-publisher.sh -- Post pre-written case study content to Discord,
# X/Twitter, and create GitHub issues for manual platforms.
#
# Usage: content-publisher.sh <case-study-number>
#
# Environment variables:
#   DISCORD_BLOG_WEBHOOK_URL - Discord webhook for #blog channel (preferred; optional)
#   DISCORD_WEBHOOK_URL      - Discord webhook fallback (optional; skips if neither set)
#   X_API_KEY              - X API key (optional; skips if unset)
#   X_API_SECRET           - X API secret
#   X_ACCESS_TOKEN         - X access token
#   X_ACCESS_TOKEN_SECRET  - X access token secret
#   GH_TOKEN               - GitHub token for issue creation
#
# Exit codes:
#   0 - All platforms posted (or gracefully skipped)
#   1 - Fatal error (missing content file, invalid input)
#   2 - Partial failure (some platforms failed but fallback issues were created)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTENT_DIR="$REPO_ROOT/knowledge-base/specs/feat-product-strategy/distribution-content"
X_SCRIPT="$REPO_ROOT/plugins/soleur/skills/community/scripts/x-community.sh"
AVATAR_URL="https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png"

# Globals set by resolve_content()
CONTENT_FILE=""
CASE_NAME=""
MANUAL_PLATFORMS=""

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

  # Handle "Not scheduled" placeholder sections (studies 2, 4)
  if echo "$content" | grep -q "Not scheduled for"; then
    echo ""
    return 0
  fi

  echo "$content"
}

extract_tweets() {
  local file="$1"
  local x_section

  x_section=$(extract_section "$file" "X/Twitter Thread")
  if [[ -z "$x_section" ]]; then
    echo "Error: No X/Twitter Thread section found in $file" >&2
    return 1
  fi

  # Split on **Tweet N pattern, output RS-separated (\x1e) for safe multi-line handling.
  # Uses \x1e (ASCII Record Separator) because mawk silently drops \0.
  # Strips the label line (e.g., "**Tweet 1 (Hook) -- 272 chars:**").
  echo "$x_section" | awk '
    /^\*\*Tweet [0-9]/ { if (buf != "") { printf "%s\x1e", buf }; buf=""; next }
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (buf != "") buf = buf "\n" line
      else buf = line
    }
    END { if (buf != "") printf "%s\x1e", buf }
  '
}

# --- Content Mapping ---

resolve_content() {
  local num="$1"

  case "$num" in
    1) CONTENT_FILE="$CONTENT_DIR/01-legal-document-generation.md"
       CASE_NAME="Legal Document Generation"
       MANUAL_PLATFORMS="indiehackers,reddit,hackernews" ;;
    2) CONTENT_FILE="$CONTENT_DIR/02-operations-management.md"
       CASE_NAME="Operations Management"
       MANUAL_PLATFORMS="" ;;
    3) CONTENT_FILE="$CONTENT_DIR/03-competitive-intelligence.md"
       CASE_NAME="Competitive Intelligence"
       MANUAL_PLATFORMS="indiehackers,reddit" ;;
    4) CONTENT_FILE="$CONTENT_DIR/04-brand-guide-creation.md"
       CASE_NAME="Brand Guide Creation"
       MANUAL_PLATFORMS="" ;;
    5) CONTENT_FILE="$CONTENT_DIR/05-business-validation.md"
       CASE_NAME="Business Validation"
       MANUAL_PLATFORMS="indiehackers,reddit,hackernews" ;;
    *) echo "Error: Invalid case study number: $num (expected 1-5)" >&2
       exit 1 ;;
  esac

  if [[ ! -f "$CONTENT_FILE" ]]; then
    echo "Error: Content file not found: $CONTENT_FILE" >&2
    echo "Ensure distribution-content/ has been merged from feat-product-strategy." >&2
    exit 1
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

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url")

  if [[ "$http_code" =~ ^2 ]]; then
    echo "[ok] Discord message posted (HTTP $http_code)."
  else
    echo "Error: Discord webhook returned HTTP $http_code." >&2
    return 1
  fi
}

# --- X/Twitter Posting ---

create_x_fallback_issue() {
  local file="$1"
  local x_content
  x_content=$(extract_section "$file" "X/Twitter Thread")

  local title="[Content Publisher] X API failed -- manual posting required for $CASE_NAME"
  local body
  body=$(printf '## Manual X/Twitter Posting Required\n\nThe scheduled content publisher could not post to X/Twitter for **%s**.\n\nPost this thread manually at https://x.com/compose/post:\n\n---\n\n%s' "$CASE_NAME" "$x_content")

  create_dedup_issue "$title" "$body" "action-required,content-publisher" || {
    echo "FATAL: X posting failed AND fallback issue creation failed." >&2
    return 1
  }
}

create_partial_thread_issue() {
  local file="$1"
  local last_tweet_id="$2"
  local resume_from="$3"
  local x_content
  x_content=$(extract_section "$file" "X/Twitter Thread")

  local title="[Content Publisher] Partial X thread -- resume for $CASE_NAME"
  local body
  body=$(printf '## Partial X Thread -- Resume Required\n\nThe thread for **%s** was partially posted. Resume from tweet %s.\n\n**Last successful tweet:** https://x.com/soleur_ai/status/%s\n**Resume with:** `--reply-to %s`\n\n---\n\n%s' \
    "$CASE_NAME" "$resume_from" "$last_tweet_id" "$last_tweet_id" "$x_content")

  create_dedup_issue "$title" "$body" "action-required,content-publisher" || {
    echo "FATAL: Partial thread issue creation failed. Data loss: thread stalled at tweet $resume_from." >&2
    return 1
  }
}

create_discord_fallback_issue() {
  local content="$1"
  local title="[Content Publisher] Discord posting failed -- manual posting required for $CASE_NAME"
  local body
  body=$(printf '## Manual Discord Posting Required\n\nThe scheduled content publisher could not post to Discord for **%s**.\n\nPost this content manually in the Discord channel:\n\n---\n\n%s' "$CASE_NAME" "$content")
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
  hook_stderr=$(mktemp)
  hook_result=$(bash "$X_SCRIPT" post-tweet "${tweets[0]}" 2>"$hook_stderr") || {
    local exit_code=$?
    local err_text
    err_text=$(cat "$hook_stderr")
    rm -f "$hook_stderr"
    if echo "$err_text" | grep -q "402"; then
      echo "X API returned 402 (Payment Required). Creating fallback issue." >&2
      create_x_fallback_issue "$file"
      return 1
    fi
    echo "Error posting hook tweet (exit $exit_code): $err_text" >&2
    create_x_fallback_issue "$file"
    return 1
  }
  rm -f "$hook_stderr"

  hook_id=$(echo "$hook_result" | jq -r '.id // empty')
  if [[ -z "$hook_id" ]]; then
    echo "Error: Failed to extract tweet ID from hook response." >&2
    create_x_fallback_issue "$file"
    return 1
  fi
  echo "[ok] Hook tweet posted: https://x.com/soleur_ai/status/$hook_id"

  # Chain body tweets -- each reply references the immediately preceding tweet
  prev_id="$hook_id"
  reply_stderr=$(mktemp)
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
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))"
      return 1
    }
    reply_id=$(echo "$reply_result" | jq -r '.id // empty')
    if [[ -z "$reply_id" ]]; then
      echo "Error: Failed to extract reply ID for tweet $((i+1)). Thread is partial." >&2
      rm -f "$reply_stderr"
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))"
      return 1
    fi
    prev_id="$reply_id"
    echo "[ok] Tweet $((i+1))/${#tweets[@]} posted: https://x.com/soleur_ai/status/$reply_id"
  done
  rm -f "$reply_stderr"

  echo "[ok] X thread posted successfully (${#tweets[@]} tweets)."
}

# --- Issue Management ---

create_dedup_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"

  # Check for existing open issue with exact title match
  local existing
  existing=$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
    --jq "[.[] | select(.title == \"$title\")] | .[0].number // empty")

  if [[ -n "$existing" ]]; then
    echo "Issue already exists: #$existing -- skipping." >&2
    return 0
  fi

  if gh issue create --title "$title" --label "$labels" --body "$body"; then
    echo "[ok] Issue created: $title"
  else
    echo "Error: Failed to create issue: $title" >&2
    return 1
  fi
}

create_manual_issues() {
  local file="$1"
  local platforms="$2"
  local section_name body_content title body

  [[ -z "$platforms" ]] && return 0

  local IFS=','
  for platform in $platforms; do
    case "$platform" in
      indiehackers) section_name="IndieHackers" ;;
      reddit)       section_name="Reddit" ;;
      hackernews)   section_name="Hacker News" ;;
      *) echo "Warning: Unknown platform: $platform" >&2; continue ;;
    esac

    body_content=$(extract_section "$file" "$section_name")
    if [[ -z "$body_content" ]]; then
      echo "Warning: No $section_name content found. Skipping." >&2
      continue
    fi

    title="[Content Publisher] Post to $section_name: $CASE_NAME"
    body=$(printf '## Manual Posting Required: %s\n\n**Case study:** %s\n**Platform:** %s\n\nCopy-paste the content below:\n\n---\n\n%s' \
      "$section_name" "$CASE_NAME" "$section_name" "$body_content")

    create_dedup_issue "$title" "$body" "action-required,content-publisher"
  done
}

# --- Main ---

main() {
  local case_study_num="${1:?Usage: content-publisher.sh <case-study-number>}"

  resolve_content "$case_study_num"

  echo "Publishing case study $case_study_num: $CASE_NAME"
  echo "Content file: $CONTENT_FILE"
  echo "Manual platforms: ${MANUAL_PLATFORMS:-none}"

  # Validate x-community.sh exists if X credentials are configured
  if [[ -n "${X_API_KEY:-}" && ! -f "$X_SCRIPT" ]]; then
    echo "Error: x-community.sh not found at $X_SCRIPT" >&2
    echo "Ensure the community skill is available at the expected path." >&2
    exit 1
  fi

  echo "---"

  local had_failures=0

  # Discord -- failure does not abort subsequent platforms
  local discord_content
  discord_content=$(extract_section "$CONTENT_FILE" "Discord")
  if [[ -n "$discord_content" ]]; then
    post_discord "$discord_content" || {
      echo "Warning: Discord posting failed. Creating fallback issue." >&2
      create_discord_fallback_issue "$discord_content" || had_failures=1
      had_failures=1
    }
  else
    echo "Warning: No Discord content found. Skipping." >&2
  fi

  # X/Twitter -- failure does not abort subsequent platforms
  post_x_thread "$CONTENT_FILE" || had_failures=1

  # Manual platform issues (IH, Reddit, HN) -- only for studies with manual platforms
  create_manual_issues "$CONTENT_FILE" "$MANUAL_PLATFORMS"

  echo "---"
  if [[ "$had_failures" -eq 1 ]]; then
    echo "[partial] Content publisher completed with failures for: $CASE_NAME" >&2
    exit 2
  fi
  echo "[ok] Content publisher completed for: $CASE_NAME"
}

# Guard: only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
