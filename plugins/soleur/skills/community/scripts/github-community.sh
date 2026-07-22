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

# Page size for every list endpoint below. check_cap compares against it, so
# binding both sides to one constant keeps the truncation detector from
# silently retiring if a URL changes.
readonly PER_PAGE=100

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
    _CAUSE="rate-limit"
    echo "Error: GitHub API rate limit exceeded." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Wait and retry (resets hourly)" >&2
    echo "  2. Check limit: gh api rate_limit" >&2
    exit 1
  fi
}

# --- Run state, cleanup, and the collector-status sidecar ---
#
# One trap, registered once in main(), owns BOTH tempfile cleanup and the status
# record. Bash EXIT traps are global and singular -- a second `trap ... EXIT`
# REPLACES the first -- so registering one per tempfile would silently leak all
# but the last on every run. Files are appended to _TMPFILES in the parent
# scope; a helper that appended inside a command substitution would lose every
# entry to the subshell.

_TMPFILES=()
_COMMAND=""
_CAUSE=""
_CAP_WARN=""

# Appends one JSONL record per dispatch -- success AND failure -- to a path the
# caller supplies. This is the only failure channel that does not terminate in
# the spawned agent's context window: the handler reads it directly from the
# run's working directory, with no LLM in the path. No-op when unset, so
# interactive use is unchanged.
_record_status() { # $1=command  $2=exit  $3=cause
  [[ -n "${SOLEUR_COLLECTOR_STATUS_DIR:-}" ]] || return 0
  mkdir -p "$SOLEUR_COLLECTOR_STATUS_DIR" 2>/dev/null || return 0
  jq -nc \
    --arg c "$1" \
    --argjson e "$2" \
    --arg r "${3:-}" \
    --arg w "${_CAP_WARN:-}" \
    '{collector: "github", command: $c, exit: $e, cause: $r}
     + (if $w == "" then {} else {warn: $w} end)' \
    >>"$SOLEUR_COLLECTOR_STATUS_DIR/collector-status.jsonl" 2>/dev/null || true
}

_on_exit() {
  local rc=$?
  if ((${#_TMPFILES[@]} > 0)); then
    rm -f "${_TMPFILES[@]}"
  fi
  _record_status "${_COMMAND:-unknown}" "$rc" "$_CAUSE"
}

# Rejects any payload that is not a JSON array. A 404/403/410 body arrives at
# exit 0 and reaches jq as an object; without this the failure surfaces as an
# opaque "Cannot index string" from deep inside a jq program. This turns it into
# a named, greppable cause.
check_array_response() { # $1=file  $2=what
  # An empty body is NOT an empty result. The API renders "no results" as `[]`,
  # so zero bytes means the response was lost, not that the period was quiet --
  # and slurping an empty file yields [], which would render a plausible 0. This
  # is the last path by which a missing fetch could still look like a quiet day.
  if [[ ! -s "$1" ]] || [[ "$(jq -s 'length' <"$1" 2>/dev/null || echo 0)" -eq 0 ]]; then
    _CAUSE="${2}-empty-response"
    echo "GITHUB_COLLECTOR_CAUSE=${2} returned an empty body (expected a JSON array)" >&2
    echo "Error: Failed to fetch ${2} (empty response)" >&2
    exit 1
  fi
  if ! jq -se 'all(type == "array")' <"$1" >/dev/null 2>&1; then
    local detail
    detail=$(jq -rs '.[0].message? // empty' <"$1" 2>/dev/null | head -c 200)
    _CAUSE="${2}-non-array"
    echo "GITHUB_COLLECTOR_CAUSE=${2} returned a non-array payload: ${detail:-unparseable}" >&2
    echo "Error: Failed to fetch ${2} (non-array response)" >&2
    exit 1
  fi
}

_json_len() { # $1=file
  jq -s 'add // [] | length' <"$1" 2>/dev/null || echo 0
}

# A response holding exactly per_page items is indistinguishable from a
# truncated one. Record it so a future growth-driven undercount is loud instead
# of silent. This is detection, not pagination.
#
# NOT applied to stargazers: that fetch paginates to exhaustion, so a total of
# exactly PER_PAGE means the set is COMPLETE, not truncated -- warning there
# would cry wolf on any repo sitting at exactly 100 stars.
#
# Takes a COUNT, not a file, because "a full page" only means truncation for
# endpoints that filter server-side. The pulls endpoint deliberately over-fetches
# a fixed page and filters by date afterwards, so a full raw page is its normal
# state -- warning on it would fire every run and train the reader to ignore the
# signal. For that endpoint the caller passes the post-filter count instead,
# where a full page really does mean the window is saturated.
check_cap() { # $1=count  $2=what
  if [[ "${1:-0}" -eq "$PER_PAGE" ]]; then
    _CAP_WARN="truncated_at_per_page"
    echo "WARN: ${2} returned exactly ${PER_PAGE} items (per_page cap) -- results may be truncated" >&2
  fi
}

# --- Commands ---

cmd_activity() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  # Payloads are spooled to files and read by jq through a file descriptor.
  # Passing them as command-line bindings placed the whole body in a single
  # execve argument, which breaches MAX_ARG_STRLEN (131,072 B PER ARGUMENT --
  # not the 2 MB ARG_MAX total). That is why this failed on as few as 10 items:
  # the ceiling is per-argument byte size, not item count. `printf` is a shell
  # builtin, so spooling itself invokes no execve and has no size limit.
  local issues_f prs_f
  issues_f=$(mktemp)
  _TMPFILES+=("$issues_f")
  prs_f=$(mktemp)
  _TMPFILES+=("$prs_f")

  local issues prs
  issues=$(gh api "repos/${repo}/issues?state=all&since=${since}&per_page=${PER_PAGE}" 2>&1) || {
    _CAUSE="issues-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=issues: $(echo "$issues" | head -c 200 | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch issues ($(echo "$issues" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$issues"
  printf '%s' "$issues" >"$issues_f"
  check_array_response "$issues_f" issues
  check_cap "$(_json_len "$issues_f")" issues

  prs=$(gh api "repos/${repo}/pulls?state=all&sort=updated&direction=desc&per_page=${PER_PAGE}" 2>&1) || {
    _CAUSE="pulls-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=pulls: $(echo "$prs" | head -c 200 | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch PRs ($(echo "$prs" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$prs"
  printf '%s' "$prs" >"$prs_f"
  check_array_response "$prs_f" pulls
  # Post-filter count: see check_cap on why pulls is measured after the date filter.
  check_cap "$(jq -s --arg since "$since" 'add // [] | map(select(.updated_at >= $since)) | length' <"$prs_f" 2>/dev/null || echo 0)" pulls

  # The slurped binding wraps the file's contents in an array, so a single-array
  # body reads as [[...]] and a paginated body as [[...],[...]]. `add // []`
  # flattens both to one array, giving every binding in this file the same
  # dereference shape. Leaving `length` applied to the wrapper while fixing only
  # the projection is the silent failure: it emits count 1 alongside a full
  # items array, at exit 0.
  jq -n \
    --slurpfile issues "$issues_f" \
    --slurpfile prs "$prs_f" \
    --arg since "$since" \
    --arg repo "$repo" \
    '($issues | add // [] | map(select(.pull_request == null))) as $iss
    | ($prs | add // [] | map(select(.updated_at >= $since))) as $pr
    | {
      repo: $repo,
      since: $since,
      issues: {
        count: ($iss | length),
        items: [$iss[] | {number, title, state, user: .user.login, created_at, updated_at}]
      },
      pull_requests: {
        count: ($pr | length),
        items: [$pr[] | {number, title, state, user: .user.login, created_at, updated_at, merged_at}]
      }
    }'
}

cmd_contributors() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  # Same per-argument ceiling as cmd_activity -- spool, then read via jq's file
  # descriptor. Both files are registered with the single EXIT trap.
  local commits_f issues_f
  commits_f=$(mktemp)
  _TMPFILES+=("$commits_f")
  issues_f=$(mktemp)
  _TMPFILES+=("$issues_f")

  # Get contributors from recent commits
  local commits
  commits=$(gh api "repos/${repo}/commits?since=${since}&per_page=${PER_PAGE}" 2>&1) || {
    _CAUSE="commits-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=commits: $(echo "$commits" | head -c 200 | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch commits ($(echo "$commits" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$commits"
  printf '%s' "$commits" >"$commits_f"
  check_array_response "$commits_f" commits
  check_cap "$(_json_len "$commits_f")" commits

  # Get contributors from recent issues/PRs
  local issues
  issues=$(gh api "repos/${repo}/issues?state=all&since=${since}&per_page=${PER_PAGE}" 2>&1) || {
    _CAUSE="issues-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=issues: $(echo "$issues" | head -c 200 | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch issues ($(echo "$issues" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$issues"
  printf '%s' "$issues" >"$issues_f"
  check_array_response "$issues_f" issues
  check_cap "$(_json_len "$issues_f")" issues

  jq -n \
    --slurpfile commits "$commits_f" \
    --slurpfile issues "$issues_f" \
    --arg since "$since" \
    --arg repo "$repo" \
    '($commits | add // []) as $cm
    | ($issues | add // []) as $iss
    | {
      repo: $repo,
      since: $since,
      commit_authors: [
        $cm[]
        | .author.login // .commit.author.name
        | select(. != null)
      ] | group_by(.) | map({login: .[0], commits: length}) | sort_by(-.commits),
      issue_authors: [
        $iss[]
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

  # Fetch repo metadata. This body is a single repo object (~7 KB), well under
  # the per-argument ceiling, so it stays an inline binding.
  local repo_data
  repo_data=$(gh api "repos/${repo}" 2>&1) || {
    _CAUSE="repo-metadata-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=repo metadata: $(echo "$repo_data" | head -c 200 | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch repo metadata ($(echo "$repo_data" | head -c 200))" >&2
    exit 1
  }
  check_rate_limit "$repo_data"

  # Object-shaped counterpart to check_array_response: an error body would
  # otherwise reach the jq program and surface as an opaque indexing error.
  if ! echo "$repo_data" | jq -e '(.stargazers_count | type) == "number"' >/dev/null 2>&1; then
    _CAUSE="repo-metadata-non-numeric"
    echo "GITHUB_COLLECTOR_CAUSE=repo metadata lacked a numeric stargazers_count: $(echo "$repo_data" | jq -r '.message // "unknown"' 2>/dev/null | head -c 200)" >&2
    echo "Error: Failed to fetch repo metadata (unexpected shape)" >&2
    exit 1
  fi

  # Fetch stargazers with timestamps (custom Accept header).
  # stdout and stderr go to SEPARATE files. Folding the error stream into the
  # JSON stream is what broke this parse: a single warning byte from the API
  # client made the whole payload unparseable. Keeping them apart preserves the
  # diagnostic without corrupting the data.
  # --paginate emits one array per page; the slurped binding is flattened below.
  local star_f star_err
  star_f=$(mktemp)
  _TMPFILES+=("$star_f")
  star_err=$(mktemp)
  _TMPFILES+=("$star_err")

  if ! gh api "repos/${repo}/stargazers?per_page=${PER_PAGE}" \
    -H "Accept: application/vnd.github.star+json" \
    --paginate >"$star_f" 2>"$star_err"; then
    _CAUSE="stargazers-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=stargazers: $(head -c 200 "$star_err" | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch stargazers" >&2
    exit 1
  fi
  check_array_response "$star_f" stargazers

  # Combine and filter
  jq -n \
    --argjson repo_data "$repo_data" \
    --slurpfile stargazers "$star_f" \
    --arg since "$since" \
    --arg repo "$repo" \
    --argjson days "$days" \
    '($stargazers | add // []) as $sg
    | ([$sg[] | select(.starred_at >= $since) | {login: .user.login, starred_at}]) as $new
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
  # Registered with the single EXIT trap rather than removed by hand: the old
  # form cleaned up only on the paths it remembered, leaking the spool on every
  # other early exit.
  #
  # stdout and stderr go to separate files for the same reason as the stargazer
  # fetch. The old form discarded stderr and collapsed the body through
  # `add // []` BEFORE any validation, so a lost or error response became an
  # empty interaction list at exit 0 -- a quiet day, indistinguishable from a
  # real one.
  local tmpfile err_f
  tmpfile=$(mktemp)
  _TMPFILES+=("$tmpfile")
  err_f=$(mktemp)
  _TMPFILES+=("$err_f")

  if ! gh api "repos/${repo}/issues/comments?since=${since}&per_page=${PER_PAGE}" \
    --paginate >"$tmpfile" 2>"$err_f"; then
    _CAUSE="issue-comments-fetch-failed"
    echo "GITHUB_COLLECTOR_CAUSE=issue comments: $(head -c 200 "$err_f" | tr '\n' ' ')" >&2
    echo "Error: Failed to fetch issue comments" >&2
    exit 1
  fi
  check_array_response "$tmpfile" issue-comments

  # Filter to external users only, exclude bots
  jq -n --slurpfile comments "$tmpfile" --arg since "$since" --arg repo "$repo" \
    '($comments | add // []) as $c
    | {
      repo: $repo,
      since: $since,
      interactions: [
        $c[]
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
    echo "  activity [days]             - Recent issues, PRs, and comments" >&2
    echo "  contributors [days]        - Active contributors in period" >&2
    echo "  discussions [days]         - Recent discussions (if enabled)" >&2
    echo "  repo-stats [days]          - Stars, forks, watchers, new stargazers" >&2
    echo "  fetch-interactions [days]  - External user comments on issues/PRs" >&2
    exit 1
  fi

  # One trap for the whole run, registered before the first thing that can
  # fail, so cleanup and the status record cover validation failures too.
  # EXIT, never RETURN: a RETURN trap does not fire on `exit`, which is exactly
  # how every failure branch below terminates.
  _COMMAND="$command"
  trap _on_exit EXIT

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
