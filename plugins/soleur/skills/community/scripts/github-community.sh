#!/usr/bin/env bash
# github-community.sh -- GitHub community data wrapper
#
# Usage: github-community.sh <command> [args]
# Commands:
#   activity [days]      - Recent issues, PRs, and comments
#   contributors [days]  - Active contributors in period
#   discussions [days]   - Recent discussions (if enabled)
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
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null) || {
    echo "Error: No git remote 'origin' found." >&2
    exit 1
  }

  # Extract owner/repo from SSH or HTTPS URL
  local repo
  repo=$(echo "$remote_url" | sed -E 's#(https://github\.com/|git@github\.com:)##' | sed 's/\.git$//')

  if [[ -z "$repo" || "$repo" == "$remote_url" ]]; then
    echo "Error: Could not parse GitHub repo from remote URL: ${remote_url}" >&2
    exit 1
  fi

  echo "$repo"
}

date_n_days_ago() {
  local days="${1:-7}"
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
    echo "Error: Failed to fetch issues: ${issues}" >&2
    exit 1
  }
  check_rate_limit "$issues"

  prs=$(gh api "repos/${repo}/pulls?state=all&sort=updated&direction=desc&per_page=100" 2>&1) || {
    echo "Error: Failed to fetch PRs: ${prs}" >&2
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
    echo "Error: Failed to fetch commits: ${commits}" >&2
    exit 1
  }
  check_rate_limit "$commits"

  # Get contributors from recent issues/PRs
  local issues
  issues=$(gh api "repos/${repo}/issues?state=all&since=${since}&per_page=100" 2>&1) || {
    echo "Error: Failed to fetch issues: ${issues}" >&2
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
    echo "Error: Failed to fetch discussions: ${result}" >&2
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

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: github-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  activity [days]      - Recent issues, PRs, and comments" >&2
    echo "  contributors [days]  - Active contributors in period" >&2
    echo "  discussions [days]   - Recent discussions (if enabled)" >&2
    exit 1
  fi

  validate_gh

  case "$command" in
    activity)     cmd_activity "$@" ;;
    contributors) cmd_contributors "$@" ;;
    discussions)  cmd_discussions "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'github-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
