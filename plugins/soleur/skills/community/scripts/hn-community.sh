#!/usr/bin/env bash
# hn-community.sh -- Hacker News Algolia API wrapper for community operations
#
# Usage: hn-community.sh <command> [args]
# Commands:
#   mentions [--query TERM] [--limit N]  - Search recent HN mentions
#   trending [--limit N]                 - Current front-page stories
#   thread ITEM_ID                       - Fetch item and comment tree
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

HN_API="https://hn.algolia.com/api/v1"

# --- Dependency checks ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# --- API helper ---

hn_request() {
  local url="$1"
  local depth="${2:-0}"

  if (( depth >= 3 )); then
    echo "Error: HN Algolia rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  local response http_code body
  response=$(curl -s -w "\n%{http_code}" --max-time 30 "$url" 2>/dev/null) || {
    echo "Error: Failed to connect to HN Algolia API." >&2
    exit 1
  }
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      if ! echo "$body" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from HN Algolia API." >&2
        exit 1
      fi
      echo "$body"
      ;;
    429)
      local retry_after=5
      local retry_int
      retry_int=$(printf '%.0f' "$retry_after" 2>/dev/null || echo "5")
      if (( retry_int < 1 )); then retry_after=1; fi
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
      sleep "$retry_after"
      hn_request "$url" "$((depth + 1))"
      ;;
    *)
      local msg
      msg=$(echo "$body" | jq -r '.message // empty' 2>/dev/null || true)
      echo "Error: HN Algolia API returned HTTP ${http_code}${msg:+: $msg}" >&2
      exit 1
      ;;
  esac
}

# --- Commands ---

cmd_mentions() {
  local query="soleur"
  local limit=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query) query="${2:-}"; shift 2 ;;
      --limit) limit="${2:-20}"; shift 2 ;;
      *) echo "Error: Unknown option '${1}' for mentions." >&2; exit 1 ;;
    esac
  done

  if [[ -z "$query" ]]; then
    echo "Error: --query requires a non-empty value." >&2
    exit 1
  fi

  # 7-day lookback for monitoring
  local since
  since=$(date -u -d "7 days ago" +%s 2>/dev/null || date -u -v-7d +%s 2>/dev/null)

  local encoded_query
  encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))" 2>/dev/null || echo "$query")

  local url="${HN_API}/search_by_date?query=${encoded_query}&tags=%28story%2Ccomment%29&numericFilters=created_at_i%3E${since}&hitsPerPage=${limit}"

  local result
  result=$(hn_request "$url")

  echo "$result" | jq '{
    hits: [.hits[] | {
      objectID,
      type: .tags[0],
      title: .title,
      url: .url,
      points: .points,
      num_comments: .num_comments,
      author: .author,
      created_at: .created_at,
      comment_text: .comment_text,
      story_title: .story_title,
      hn_url: ("https://news.ycombinator.com/item?id=" + .objectID)
    }],
    count: .nbHits,
    exhaustive: .exhaustiveNbHits
  }'
}

cmd_trending() {
  local limit=30

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="${2:-30}"; shift 2 ;;
      *) echo "Error: Unknown option '${1}' for trending." >&2; exit 1 ;;
    esac
  done

  local url="${HN_API}/search?tags=front_page&hitsPerPage=${limit}"

  local result
  result=$(hn_request "$url")

  echo "$result" | jq '{
    stories: [.hits[] | {
      objectID,
      title: .title,
      url: .url,
      points: .points,
      num_comments: .num_comments,
      author: .author,
      created_at: .created_at,
      hn_url: ("https://news.ycombinator.com/item?id=" + .objectID)
    }],
    count: .nbHits
  }'
}

cmd_thread() {
  local item_id="${1:-}"

  if [[ -z "$item_id" ]]; then
    echo "Error: thread requires an ITEM_ID argument." >&2
    echo "Usage: hn-community.sh thread ITEM_ID" >&2
    exit 1
  fi

  if ! [[ "$item_id" =~ ^[0-9]+$ ]]; then
    echo "Error: ITEM_ID must be numeric, got '${item_id}'." >&2
    exit 1
  fi

  local url="${HN_API}/items/${item_id}"

  local result
  result=$(hn_request "$url")

  # Check for deleted/non-existent items (Algolia returns 200 with null fields)
  local title author
  title=$(echo "$result" | jq -r '.title // empty' 2>/dev/null)
  author=$(echo "$result" | jq -r '.author // empty' 2>/dev/null)

  if [[ -z "$title" && -z "$author" ]]; then
    echo "Error: Item ${item_id} not found or has been deleted." >&2
    exit 1
  fi

  echo "$result" | jq '. + {hn_url: ("https://news.ycombinator.com/item?id=" + (.id | tostring))}'
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: hn-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  mentions [--query TERM] [--limit N]  - Search recent HN mentions" >&2
    echo "  trending [--limit N]                 - Current front-page stories" >&2
    echo "  thread ITEM_ID                       - Fetch item and comment tree" >&2
    exit 1
  fi

  require_jq

  case "$command" in
    mentions)  cmd_mentions "$@" ;;
    trending)  cmd_trending "$@" ;;
    thread)    cmd_thread "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'hn-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
