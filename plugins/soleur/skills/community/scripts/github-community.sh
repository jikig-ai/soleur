#!/usr/bin/env bash
# github-community.sh -- GitHub community data wrapper
#
# Usage: github-community.sh <command> [args]
# Commands:
#   activity [days]             - Recent issues, PRs, and comments
#   contributors [days]        - Active contributors in period
#   discussions [days]         - Recent discussions (if enabled)
#   repo-stats [days]          - Stars, forks, watchers, new stargazers
#   fetch-interactions [days]  - External user comments on issues/PRs
#
# Prerequisites: gh CLI authenticated
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

# --- Validation ---

validate_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI is not installed." >&2
    echo "Install: https://cli.github.com/" >&2
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh CLI is not authenticated." >&2
    echo "Run: gh auth login" >&2
    exit 1
  fi
}

detect_repo() {
  # Fast path: GITHUB_REPOSITORY is always set in GitHub Actions
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
    return 0
  fi

  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null) || {
    echo "Error: No git remote 'origin' found." >&2
    exit 1
  }

  # Extract owner/repo from SSH or HTTPS URL
  # Handles: https://github.com/owner/repo.git
  #          git@github.com:owner/repo.git
  #          https://x-access-token:TOKEN@github.com/owner/repo.git
  local repo
  repo=$(echo "$remote_url" | sed -E 's#https?://([^@]+@)?github\.com/##' | sed -E 's#git@github\.com:##' | sed 's/\.git$//')

  if [[ -z "$repo" || "$repo" == "$remote_url" ]]; then
    echo "Error: Could not parse GitHub repo from remote URL: ${remote_url}" >&2
    exit 1
  fi

  echo "$repo"
}

date_n_days_ago() {
  local days="${1:-7}"
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo "Error: days must be a positive integer, got '${days}'" >&2
    exit 1
  fi
  date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

check_rate_limit() {
  local response="$1"
  if echo "$response" | jq -e '.message // empty' 2>/dev/null | grep -qi "rate limit"; then
    echo "Error: GitHub API rate limit exceeded." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Wait and retry (resets hourly)" >&2
    echo "  2. Check limit: gh api rate_limit" >&2
    exit 1
  fi
}

# --- Commands ---

cmd_activity() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  local issues prs
  issues=$(gh api "repos/${repo}/issues?state=all&since=${since}&per_page=100" 2>&1) || {
    echo "Error: Failed to fetch issues ($(echo "$issues" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$issues"

  prs=$(gh api "repos/${repo}/pulls?state=all&sort=updated&direction=desc&per_page=100" 2>&1) || {
    echo "Error: Failed to fetch PRs ($(echo "$prs" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$prs"

  # Filter PRs to those updated within the date range
  prs=$(echo "$prs" | jq --arg since "$since" '[.[] | select(.updated_at >= $since)]')

  # Separate issues from PRs (GitHub returns PRs in issues endpoint too)
  issues=$(echo "$issues" | jq '[.[] | select(.pull_request == null)]')

  jq -n \
    --argjson issues "$issues" \
    --argjson prs "$prs" \
    --arg since "$since" \
    --arg repo "$repo" \
    '{
      repo: $repo,
      since: $since,
      issues: {
        count: ($issues | length),
        items: [$issues[] | {number, title, state, user: .user.login, created_at, updated_at}]
      },
      pull_requests: {
        count: ($prs | length),
        items: [$prs[] | {number, title, state, user: .user.login, created_at, updated_at, merged_at}]
      }
    }'
}

cmd_contributors() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  # Get contributors from recent commits
  local commits
  commits=$(gh api "repos/${repo}/commits?since=${since}&per_page=100" 2>&1) || {
    echo "Error: Failed to fetch commits ($(echo "$commits" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$commits"

  # Get contributors from recent issues/PRs
  local issues
  issues=$(gh api "repos/${repo}/issues?state=all&since=${since}&per_page=100" 2>&1) || {
    echo "Error: Failed to fetch issues ($(echo "$issues" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$issues"

  jq -n \
    --argjson commits "$commits" \
    --argjson issues "$issues" \
    --arg since "$since" \
    --arg repo "$repo" \
    '{
      repo: $repo,
      since: $since,
      commit_authors: [
        $commits[]
        | .author.login // .commit.author.name
        | select(. != null)
      ] | group_by(.) | map({login: .[0], commits: length}) | sort_by(-.commits),
      issue_authors: [
        $issues[]
        | .user.login
        | select(. != null)
      ] | group_by(.) | map({login: .[0], activity: length}) | sort_by(-.activity)
    }'
}

cmd_discussions() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local owner repo_name
  owner=$(echo "$repo" | cut -d/ -f1)
  repo_name=$(echo "$repo" | cut -d/ -f2)
  local since
  since=$(date_n_days_ago "$days")

  # Discussions require GraphQL
  local query='query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      discussions(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
        nodes {
          number
          title
          author { login }
          createdAt
          updatedAt
          answerChosenAt
          comments { totalCount }
          category { name }
        }
      }
    }
  }'

  local result
  result=$(gh api graphql -f query="$query" -f owner="$owner" -f repo="$repo_name" 2>&1) || {
    # Discussions not enabled -- return empty
    if echo "$result" | grep -qi "not found\|not accessible\|discussions are not enabled"; then
      echo '{"discussions": [], "note": "Discussions not enabled for this repository"}'
      return 0
    fi
    echo "Error: Failed to fetch discussions ($(echo "$result" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$result"

  # Filter to recent discussions and format
  echo "$result" | jq --arg since "$since" '{
    discussions: [
      .data.repository.discussions.nodes[]
      | select(.updatedAt >= $since)
      | {
          number,
          title,
          author: .author.login,
          created_at: .createdAt,
          updated_at: .updatedAt,
          answered: (.answerChosenAt != null),
          comment_count: .comments.totalCount,
          category: .category.name
        }
    ]
  }'
}

cmd_repo_stats() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  # Fetch repo metadata
  local repo_data
  repo_data=$(gh api "repos/${repo}" 2>&1) || {
    echo "Error: Failed to fetch repo metadata ($(echo "$repo_data" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$repo_data"

  # Fetch stargazers with timestamps (custom Accept header).
  # --paginate outputs separate arrays per page; jq -s 'add' merges them.
  local stargazers
  stargazers=$(gh api "repos/${repo}/stargazers?per_page=100" \
    -H "Accept: application/vnd.github.star+json" \
    --paginate 2>&1 | jq -s 'add // []') || {
    echo "Error: Failed to fetch stargazers ($(echo "$stargazers" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$stargazers"

  # Combine and filter
  jq -n \
    --argjson repo_data "$repo_data" \
    --argjson stargazers "$stargazers" \
    --arg since "$since" \
    --arg repo "$repo" \
    --argjson days "$days" \
    '([$stargazers[] | select(.starred_at >= $since) | {login: .user.login, starred_at}]) as $new
    | {
      repo: $repo,
      since: $since,
      stargazers_count: $repo_data.stargazers_count,
      forks_count: $repo_data.forks_count,
      watchers_count: $repo_data.watchers_count,
      subscribers_count: $repo_data.subscribers_count,
      new_stargazers: $new,
      new_stargazers_count: ($new | length),
      period_days: $days
    }'
}

cmd_fetch_interactions() {
  local days="${1:-1}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  # Fetch all issue/PR comments since cutoff (paginated).
  # Use temp file -- paginated results can exceed shell argument limits.
  local tmpfile
  tmpfile=$(mktemp)

  if ! gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" \
    --paginate 2>/dev/null | jq -s 'add // []' > "$tmpfile"; then
    echo "Error: Failed to fetch issue comments" >&2
    rm -f "$tmpfile"
    exit 1
  fi

  # Filter to external users only, exclude bots
  jq --arg since "$since" --arg repo "$repo" \
    '{
      repo: $repo,
      since: $since,
      interactions: [
        .[]
        | select(
            (.author_association == "NONE" or
             .author_association == "CONTRIBUTOR" or
             .author_association == "FIRST_TIMER" or
             .author_association == "FIRST_TIME_CONTRIBUTOR") and
            (.user.type != "Bot") and
            (.user.login | test("\\[bot\\]$") | not)
          )
        | {
            user: .user.login,
            issue_number: (.issue_url | split("/") | last | tonumber),
            body_snippet: (.body | gsub("\n"; " ") | .[:120]),
            url: .html_url,
            created_at: .created_at
          }
      ]
    }' "$tmpfile"

  rm -f "$tmpfile"
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: github-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  activity [days]             - Recent issues, PRs, and comments" >&2
    echo "  contributors [days]        - Active contributors in period" >&2
    echo "  discussions [days]         - Recent discussions (if enabled)" >&2
    echo "  repo-stats [days]          - Stars, forks, watchers, new stargazers" >&2
    echo "  fetch-interactions [days]  - External user comments on issues/PRs" >&2
    exit 1
  fi

  validate_gh

  case "$command" in
    activity)            cmd_activity "$@" ;;
    contributors)        cmd_contributors "$@" ;;
    discussions)         cmd_discussions "$@" ;;
    repo-stats)          cmd_repo_stats "$@" ;;
    fetch-interactions)  cmd_fetch_interactions "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'github-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
