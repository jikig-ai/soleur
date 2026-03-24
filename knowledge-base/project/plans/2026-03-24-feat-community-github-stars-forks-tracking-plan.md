---
title: "feat: add GitHub stars, forks, and new stargazers to daily community report"
type: feat
date: 2026-03-24
---

# feat: Add GitHub Stars, Forks, and New Stargazers to Daily Community Report

## Overview

The daily community digest (`scheduled-community-monitor.yml`) tracks Discord, X, Bluesky, LinkedIn, HN, and GitHub activity (issues, PRs, contributors, discussions) -- but omits repository-level metrics: star count, fork count, and new stargazers since the last digest. These are the most visible signals of open-source community growth and should appear alongside the existing GitHub Activity section.

## Problem Statement

The `github-community.sh` script exposes three commands (`activity`, `contributors`, `discussions`) but no command for repo-level stats. The digest's `## GitHub Activity` section reports issues, PRs, releases, and discussions -- but never star count, fork count, or who starred the repo recently. Other platform sections already track follower growth (X: `+1 from last digest`, Bluesky: follower delta), making the GitHub section's omission inconsistent.

## Proposed Solution

1. **Add a `repo-stats` command** to `plugins/soleur/skills/community/scripts/github-community.sh` that returns star count, fork count, watcher count, and recent stargazers with timestamps via the GitHub REST API.
2. **Update the workflow prompt** in `.github/workflows/scheduled-community-monitor.yml` to call `github repo-stats` alongside existing GitHub commands.
3. **Update the SKILL.md** description of `github-community.sh` to reflect the new command.

No new scripts, no new secrets, no new dependencies. The `gh` CLI (already required and authenticated) provides everything.

## Technical Approach

### New `cmd_repo_stats` function in `github-community.sh`

Two API calls:

1. **Repo metadata** -- `GET /repos/{owner}/{repo}` returns `stargazers_count`, `forks_count`, `watchers_count`, `subscribers_count` (all available without additional auth scopes).

2. **Stargazers with timestamps** -- `GET /repos/{owner}/{repo}/stargazers` with `Accept: application/vnd.github.star+json` header returns `[{user: {login}, starred_at}]`. This is paginated (100/page). At 5 current stars, a single page suffices for now. Paginate with `per_page=100&page=N` when needed, capped at 5 pages (500 stargazers) to avoid runaway API calls.

The function accepts an optional `[days]` argument (default 7) to filter "new stargazers" to those with `starred_at` within the period, consistent with the other commands.

**Output JSON:**

```json
{
  "repo": "jikig-ai/soleur",
  "stargazers_count": 5,
  "forks_count": 1,
  "watchers_count": 5,
  "subscribers_count": 0,
  "new_stargazers": [
    {"login": "mvandermeulen", "starred_at": "2026-03-06T18:45:53Z"}
  ],
  "new_stargazers_count": 1,
  "period_days": 7
}
```

### Workflow prompt update

In the `Batch 2` section of the agent prompt, append `bash $ROUTER github repo-stats 1` to the existing GitHub commands:

```text
bash $ROUTER github activity 1; bash $ROUTER github contributors 1; bash $ROUTER github discussions 1; bash $ROUTER github repo-stats 1
```

Update the digest format instructions (Step 4) to include `## GitHub Repository Stats` or fold into existing `## GitHub Activity` section:

```text
## GitHub Activity
...existing content...

**Repository stats:**
| Metric | Value | Change |
|---|---|---|
| Stars | 5 | +1 new |
| Forks | 1 | -- |
| Watchers | 5 | -- |

**New stargazers this period:** @mvandermeulen (Mar 6)
```

### Implementation constraints

- Follow existing patterns in `github-community.sh`: `validate_gh`, `detect_repo`, `date_n_days_ago`, `check_rate_limit` helpers are already available.
- Apply shell API wrapper hardening patterns per `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`: jq fallback chains, curl stderr suppression, JSON validation on 2xx.
- Apply depth-limited retry per `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md` -- though `gh api` handles its own retry, the pattern applies if raw `curl` is used.
- The stargazers endpoint with the custom Accept header is not natively supported by `gh api` flag syntax -- use `gh api -H "Accept: application/vnd.github.star+json"` which works.
- No new secrets required. The existing `GH_TOKEN` (default `github.token` in Actions) has read access to public repo stats and stargazers.

## Acceptance Criteria

- [ ] `github-community.sh repo-stats` returns JSON with `stargazers_count`, `forks_count`, `watchers_count`, and `new_stargazers` array
- [ ] `github-community.sh repo-stats 1` filters new stargazers to the last 1 day
- [ ] The scheduled community monitor workflow calls `github repo-stats` and includes the data in the digest
- [ ] The daily digest `## GitHub Activity` section includes a repository stats table with star/fork/watcher counts
- [ ] New stargazers (within the report period) are listed by username and date
- [ ] Rate limit errors are handled gracefully (check_rate_limit pattern)
- [ ] The `github-community.sh` usage text includes the new `repo-stats` command

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change to an existing internal monitoring script.

## Test Scenarios

- Given a repo with 5 stars and 1 fork, when `github-community.sh repo-stats` runs, then JSON output contains `stargazers_count: 5` and `forks_count: 1`
- Given a stargazer who starred 2 days ago, when `github-community.sh repo-stats 1` runs, then `new_stargazers` array is empty (outside 1-day window)
- Given a stargazer who starred 2 days ago, when `github-community.sh repo-stats 7` runs, then `new_stargazers` array contains that user
- Given the GitHub API rate limit is exceeded, when `repo-stats` runs, then the script exits with an error message to stderr
- Given the stargazers endpoint returns an empty array (no stars), when `repo-stats` runs, then JSON output contains `stargazers_count: 0` and `new_stargazers: []`

## MVP

### `plugins/soleur/skills/community/scripts/github-community.sh` (additions)

```bash
cmd_repo_stats() {
  local days="${1:-7}"
  local repo
  repo=$(detect_repo)
  local since
  since=$(date_n_days_ago "$days")

  # Fetch repo metadata
  local repo_data
  repo_data=$(gh api "repos/${repo}" 2>&1) || {
    echo "Error: Failed to fetch repo metadata: ${repo_data}" >&2
    exit 1
  }
  check_rate_limit "$repo_data"

  # Fetch stargazers with timestamps (custom Accept header)
  local stargazers
  stargazers=$(gh api "repos/${repo}/stargazers" \
    -H "Accept: application/vnd.github.star+json" \
    --paginate 2>&1) || {
    echo "Error: Failed to fetch stargazers: ${stargazers}" >&2
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
    '{
      repo: $repo,
      stargazers_count: $repo_data.stargazers_count,
      forks_count: $repo_data.forks_count,
      watchers_count: $repo_data.watchers_count,
      subscribers_count: $repo_data.subscribers_count,
      new_stargazers: [
        $stargazers[]
        | select(.starred_at >= $since)
        | {login: .user.login, starred_at}
      ],
      new_stargazers_count: ([$stargazers[] | select(.starred_at >= $since)] | length),
      period_days: $days
    }'
}
```

### `.github/workflows/scheduled-community-monitor.yml` (prompt change)

Add `bash $ROUTER github repo-stats 1` to Batch 2 GitHub commands.

### `plugins/soleur/skills/community/SKILL.md` (description update)

Update `github-community.sh` description line to:

```text
- [github-community.sh](./scripts/github-community.sh) -- GitHub API wrapper (activity, contributors, discussions, repo-stats)
```

## References

- Existing script: `plugins/soleur/skills/community/scripts/github-community.sh`
- Workflow: `.github/workflows/scheduled-community-monitor.yml`
- Recent digest example: `knowledge-base/support/community/2026-03-22-digest.md`
- GitHub REST API -- Stargazers: `GET /repos/{owner}/{repo}/stargazers` with `Accept: application/vnd.github.star+json`
- GitHub REST API -- Repos: `GET /repos/{owner}/{repo}` (includes `stargazers_count`, `forks_count`)
- Learning: `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-10-continuous-community-agent-brainstorm.md`
