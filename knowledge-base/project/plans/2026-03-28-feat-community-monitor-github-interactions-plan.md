---
title: "feat: Add GitHub issue comment interactions to daily community digest"
type: feat
date: 2026-03-28
---

# feat: Add GitHub issue comment interactions to daily community digest

Add a `fetch-interactions` command to `github-community.sh` that fetches external user comments on issues/PRs from the last 24 hours. The scheduled community monitor includes this data in the daily digest as a summary table under `## GitHub Activity`.

## Proposed Solution

Three files change. No new files, no new dependencies.

### 1. `plugins/soleur/skills/community/scripts/github-community.sh`

Add `cmd_fetch_interactions()` following the existing command pattern:

- Accept `days` argument (default: 1)
- Call `gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" --paginate` piped through `jq -s 'add // []'`
- Filter by `author_association`: keep `NONE`, `CONTRIBUTOR`, `FIRST_TIMER`, `FIRST_TIME_CONTRIBUTOR`
- Filter out bots: primary filter `.user.type != "Bot"`, fallback `.user.login | test("\\[bot\\]$") | not`
- Truncate `body_snippet`: strip newlines (replace `\n` with space), take first 120 chars via jq `.body | gsub("\n"; " ") | .[:120]`
- Extract issue number from `issue_url` (split on `/`, take last segment)
- Output JSON: `{repo, since, interactions: [{user, issue_number, body_snippet, url, created_at}]}`
- Add `fetch-interactions)` case to `main()` dispatch and update the usage block
- Follow existing error handling: capture output, check exit code, `check_rate_limit`

### 2. `.github/workflows/scheduled-community-monitor.yml`

Add `bash $ROUTER github fetch-interactions 1` to the Batch 2 semicolon chain (line ~98). Add rendering instructions in Step 4 telling the agent to include a `**Community Interactions:**` sub-section within `## GitHub Activity` when external comments exist, formatted as a markdown table: `| User | Issue/PR | Comment |`. Omit the sub-section when there are no external comments.

### 3. `plugins/soleur/agents/support/community-manager.md`

Add `$ROUTER github fetch-interactions 7` to Capability 1 (Digest Generation) Step 1 data collection. Update the digest heading contract to document the optional `**Community Interactions:**` sub-heading under `## GitHub Activity`.

## Acceptance Criteria

- [x] `github-community.sh fetch-interactions 1` outputs valid JSON with external comments from the last 24 hours
- [x] Bot and org-member comments are excluded (filtered by `author_association`)
- [x] Daily digest includes `**Community Interactions:**` table when external comments exist
- [x] No interactions sub-section when there are no external comments (clean omission)
- [x] Pagination handled correctly (`--paginate` + `jq -s 'add // []'`)
- [x] Existing commands (`activity`, `contributors`, `discussions`, `repo-stats`) remain unchanged

## Test Scenarios

- Given a repo with external comments in the last 24 hours, when `fetch-interactions 1` runs, then JSON output contains those comments with correct fields
- Given a repo with only org-member comments, when `fetch-interactions 1` runs, then `interactions` array is empty
- Given a repo with bot comments (e.g., `dependabot[bot]`), when `fetch-interactions 1` runs, then bot comments are excluded
- Given no comments in the last 24 hours, when `fetch-interactions 1` runs, then `interactions` is an empty array
- Given the scheduled workflow runs, when `fetch-interactions 1` produces results, then the digest contains a `**Community Interactions:**` table
- Given the scheduled workflow runs, when `fetch-interactions 1` produces no results, then no interactions sub-section appears

## Domain Review

**Domains relevant:** Support

### Support (CCO)

**Status:** reviewed
**Assessment:** The community monitor currently has zero visibility into external user comments on GitHub issues/PRs. This feature closes that gap. The CCO identified two actionable items already covered by the plan: (1) bot filtering via `[bot]$` login pattern matching, and (2) digest heading contract update in `community-manager.md`. The CCO also surfaced future opportunities — contributor funnel tracking (`FIRST_TIMER` → `CONTRIBUTOR` progression), content signal detection for CMO, and a response playbook — all correctly out of scope for this feature. No blockers or concerns raised.

## Context

**Learnings to apply:**

- `gh api --paginate` output is concatenated arrays — always pipe through `jq -s 'add // []'` (learning: 2026-03-24)
- Follow five-layer API wrapper hardening pattern (learning: 2026-03-09)
- Stay within the 50 max-turns budget — batch commands with `;` (learning: 2026-03-20)
- Workflow platform addition has 4 touchpoints: secrets in env block, agent prompt, digest section, file header (learning: 2026-03-14). This feature needs no new secrets.

**Key files:**

- `plugins/soleur/skills/community/scripts/github-community.sh` — add command
- `.github/workflows/scheduled-community-monitor.yml` — add to batch + rendering instructions
- `plugins/soleur/agents/support/community-manager.md` — update agent instructions + digest contract

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-28-community-monitor-interactions-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-community-monitor-interactions/spec.md`
- Issue: #1248
- GitHub API: `GET /repos/{owner}/{repo}/issues/comments` — returns `author_association` field
