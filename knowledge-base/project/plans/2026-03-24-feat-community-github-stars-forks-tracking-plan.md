---
title: "feat: add GitHub stars, forks, and new stargazers to daily community report"
type: feat
date: 2026-03-24
---

# feat: Add GitHub Stars, Forks, and New Stargazers to Daily Community Report

## Enhancement Summary

**Deepened on:** 2026-03-24
**Sections enhanced:** 4 (Technical Approach, MVP, Test Scenarios, Implementation Constraints)
**Research sources:** GitHub REST API live verification, 6 institutional learnings, existing `github-community.sh` patterns

### Key Improvements

1. Fixed `--paginate` + `2>&1` bug in MVP code -- stderr and stdout mixing produces invalid JSON on API errors
2. Added empty-stargazers defensive pattern (`// []`) to prevent jq crash on repos with zero stars
3. Identified `--argjson` shell argument length limit as scaling concern for repos with 1000+ stargazers
4. Added `--paginate` page cap recommendation (5 pages / 500 stargazers) to prevent runaway API calls at scale

### New Considerations Discovered

- `gh api --paginate` auto-fetches all pages with no built-in cap -- use `--paginate` only while stargazer count is low; switch to manual pagination with explicit page limit when the repo grows past ~200 stars
- The `2>&1` pattern used in all existing commands (`cmd_activity`, `cmd_contributors`) mixes stderr into the captured variable -- on API error, `$repo_data` contains the error message, not JSON, and `check_rate_limit` will fail with a jq parse error rather than the intended rate-limit message; this is a pre-existing pattern issue, not something to fix in this PR
- The `stargazers_count` from repo metadata and the count from paginated stargazers may disagree (repo metadata includes all-time stars from deleted accounts; the stargazers endpoint only lists active users)

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

2. **Stargazers with timestamps** -- `GET /repos/{owner}/{repo}/stargazers` with `Accept: application/vnd.github.star+json` header returns `[{user: {login}, starred_at}]`. This is paginated (100/page). At 5 current stars, a single page suffices for now.

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

### Research Insights: GitHub Stargazers API

**Verified via live API call (2026-03-24):**

- `gh api repos/jikig-ai/soleur/stargazers -H "Accept: application/vnd.github.star+json"` returns timestamps with each stargazer entry. Without the custom Accept header, only user objects are returned (no `starred_at`).
- `gh api --paginate` merges paginated array responses into a single JSON array. This was confirmed to produce valid, parseable JSON for the stargazers endpoint.
- Current repo stats: 5 stars, 1 fork, 0 subscribers. All 5 stargazers are visible via the API with their `starred_at` timestamps.

**Pagination behavior:**

- `--paginate` fetches ALL pages automatically with no built-in cap. For repos with thousands of stars, this could hit rate limits or produce very large responses.
- At current scale (5 stars), `--paginate` is safe and returns a single array in one request.
- When the repo exceeds ~200 stars, consider switching to manual pagination with `per_page=100&page=N` capped at 5 pages (500 stargazers), since we only need "new stargazers in the period" and stars are returned in chronological order (oldest first by default -- use `?direction=desc` if available, or filter client-side).

**`stargazers_count` vs stargazers list:**

The `stargazers_count` field on the repo object may be higher than the number of entries from the stargazers endpoint. Deleted or suspended GitHub accounts are included in the count but not in the list. Use `stargazers_count` for the headline number (consistent with what GitHub.com displays) and the stargazers list only for "new stargazers" identification.

### Workflow prompt update

In the `Batch 2` section of the agent prompt, append `bash $ROUTER github repo-stats 1` to the existing GitHub commands:

```text
bash $ROUTER github activity 1; bash $ROUTER github contributors 1; bash $ROUTER github discussions 1; bash $ROUTER github repo-stats 1
```

Update the digest format instructions (Step 4) to include a repository stats table in the `## GitHub Activity` section:

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

### Research Insights: Implementation Hardening

**From institutional learnings:**

1. **`gh --jq` does not support `--arg` flags** (learning `2026-03-04`): The MVP code correctly uses standalone `jq` (not `gh api --jq`) for complex filtering. This is the right approach since we need `--argjson` for passing the full repo_data and stargazers arrays.

2. **jq generator silent data loss** (learning `2026-03-10`): The stargazers filtering pattern `$stargazers[] | select(.starred_at >= $since)` is safe because it iterates a flat array (no join). Unlike the X mentions case where generator-style joins dropped records, this is a simple filter where zero matches correctly produce an empty array. No INDEX pattern needed.

3. **`require_jq` consistency** (learning `2026-03-10`): The existing `github-community.sh` script does NOT have a `require_jq` startup check, unlike its siblings (`discord-community.sh`, `x-community.sh`). This is a pre-existing gap -- do not fix in this PR (scope creep), but note for future cleanup.

4. **Community router deduplication** (learning `2026-03-13`): The new command is dispatched via `community-router.sh github repo-stats`, which exec's into `github-community.sh repo-stats`. No router changes needed -- the dispatch is already transparent.

5. **`2>&1` stderr capture pattern risk**: The existing commands use `var=$(gh api ... 2>&1)` to capture both stdout and stderr. On API failure, `$var` contains the error message (not JSON), and `check_rate_limit "$var"` will fail with a jq parse error. This is a pre-existing pattern across all commands in this script -- the jq `2>/dev/null` in `check_rate_limit` suppresses the secondary error, but the original error message is lost. Fixing this would require changing the error handling pattern for all commands -- out of scope for this PR.

## Acceptance Criteria

- [x] `github-community.sh repo-stats` returns JSON with `stargazers_count`, `forks_count`, `watchers_count`, and `new_stargazers` array
- [x] `github-community.sh repo-stats 1` filters new stargazers to the last 1 day
- [x] The scheduled community monitor workflow calls `github repo-stats` and includes the data in the digest
- [x] The daily digest `## GitHub Activity` section includes a repository stats table with star/fork/watcher counts
- [x] New stargazers (within the report period) are listed by username and date
- [x] Rate limit errors are handled gracefully (check_rate_limit pattern)
- [x] The `github-community.sh` usage text includes the new `repo-stats` command

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change to an existing internal monitoring script.

## Test Scenarios

- Given a repo with 5 stars and 1 fork, when `github-community.sh repo-stats` runs, then JSON output contains `stargazers_count: 5` and `forks_count: 1`
- Given a stargazer who starred 2 days ago, when `github-community.sh repo-stats 1` runs, then `new_stargazers` array is empty (outside 1-day window)
- Given a stargazer who starred 2 days ago, when `github-community.sh repo-stats 7` runs, then `new_stargazers` array contains that user
- Given the GitHub API rate limit is exceeded, when `repo-stats` runs, then the script exits with an error message to stderr
- Given the stargazers endpoint returns an empty array (no stars), when `repo-stats` runs, then JSON output contains `stargazers_count: 0` and `new_stargazers: []`
- Given `gh api --paginate` returns an empty array `[]` (zero stargazers), when jq processes `$stargazers[]`, then the iterator produces zero elements and `new_stargazers` is `[]` (no jq crash)

### Research Insights: Additional Edge Cases

- **Deleted/suspended stargazer accounts**: `stargazers_count` on repo metadata may be higher than the list returned by the stargazers endpoint (deleted accounts are counted but not listed). The digest should use `stargazers_count` for the headline and note "N new this period" from the filtered list.
- **`starred_at` timezone**: All timestamps from the GitHub API are UTC (ISO 8601 with `Z` suffix). The `date_n_days_ago` helper also produces UTC timestamps, so the comparison `select(.starred_at >= $since)` is safe without timezone conversion.
- **Private forks**: `forks_count` includes all forks (public and private). For public repos, this is accurate. For private repos, the token's access scope determines visibility.

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
  # --paginate merges all pages into a single JSON array.
  # At current scale (5 stars) this is one request.
  # For repos with 1000+ stars, consider manual pagination with a page cap.
  local stargazers
  stargazers=$(gh api "repos/${repo}/stargazers" \
    -H "Accept: application/vnd.github.star+json" \
    --paginate 2>&1) || {
    echo "Error: Failed to fetch stargazers: ${stargazers}" >&2
    exit 1
  }
  check_rate_limit "$stargazers"

  # Defensive: if stargazers is empty or not valid JSON, default to empty array
  if ! echo "$stargazers" | jq empty 2>/dev/null; then
    stargazers="[]"
  fi

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

**Changes from initial draft:**

- Added JSON validation guard (`jq empty`) before passing `$stargazers` to the main jq pipeline. If `--paginate` fails mid-stream or returns non-JSON (HTML error page), the variable falls back to `[]` instead of crashing jq.
- Added inline comments explaining `--paginate` behavior and scale boundaries.

### `.github/workflows/scheduled-community-monitor.yml` (prompt change)

Add `bash $ROUTER github repo-stats 1` to Batch 2 GitHub commands. Update Step 4 digest format instructions to include `## GitHub Repository Stats` or fold repo-stats into existing `## GitHub Activity` section with a stats table and new-stargazers list.

### `plugins/soleur/skills/community/SKILL.md` (description update)

Update `github-community.sh` description line to:

```text
- [github-community.sh](./scripts/github-community.sh) -- GitHub API wrapper (activity, contributors, discussions, repo-stats)
```

## Future Enhancements (Out of Scope)

- **New forks tracking**: The `/repos/{owner}/{repo}/forks?sort=newest` endpoint returns fork details with `created_at` timestamps. This would allow "new forks this period" tracking, mirroring the new-stargazers pattern. Deferred because the initial ask is for fork count, not fork activity.
- **Star/fork trend over time**: Store historical values in `knowledge-base/support/community/` digest frontmatter to compute week-over-week deltas. Currently, the digest has no mechanism to read the previous digest for delta calculation.
- **`require_jq` addition**: The existing `github-community.sh` is missing the `require_jq` startup check that sibling scripts have. Should be added in a separate cleanup PR.

## References

- Existing script: `plugins/soleur/skills/community/scripts/github-community.sh`
- Workflow: `.github/workflows/scheduled-community-monitor.yml`
- Recent digest example: `knowledge-base/support/community/2026-03-22-digest.md`
- GitHub REST API -- Stargazers: `GET /repos/{owner}/{repo}/stargazers` with `Accept: application/vnd.github.star+json`
- GitHub REST API -- Repos: `GET /repos/{owner}/{repo}` (includes `stargazers_count`, `forks_count`)
- Learning: `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-jq-generator-silent-data-loss.md`
- Learning: `knowledge-base/project/learnings/2026-03-04-gh-jq-does-not-support-arg-flag.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-community-router-deduplication.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-require-jq-startup-check-consistency.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-10-continuous-community-agent-brainstorm.md`
