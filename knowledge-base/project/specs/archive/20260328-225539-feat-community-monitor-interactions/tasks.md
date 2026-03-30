# Tasks: Community Monitor GitHub Interactions

**Issue:** #1248
**Plan:** `knowledge-base/project/plans/2026-03-28-feat-community-monitor-github-interactions-plan.md`

## Phase 1: Core Implementation

### 1.1 Add `fetch-interactions` command to `github-community.sh`

- [ ] Add `cmd_fetch_interactions()` function with `days` parameter (default: 1)
- [ ] Fetch comments via `gh api repos/${repo}/issues/comments?since=${since}&per_page=100 --paginate`
- [ ] Merge paginated output with `jq -s 'add // []'`
- [ ] Filter by `author_association` (keep NONE, CONTRIBUTOR, FIRST_TIMER, FIRST_TIME_CONTRIBUTOR)
- [ ] Filter out bots: primary `.user.type != "Bot"`, fallback `.user.login | test("\\[bot\\]$") | not`
- [ ] Extract issue number from `issue_url` (split on `/`, take last segment)
- [ ] Truncate body_snippet: strip newlines, take first 120 chars
- [ ] Output JSON: `{repo, since, interactions: [{user, issue_number, body_snippet, url, created_at}]}`
- [ ] Add `fetch-interactions)` case to `main()` dispatch
- [ ] Update usage block in header comment

**File:** `plugins/soleur/skills/community/scripts/github-community.sh`

### 1.2 Update scheduled workflow

- [ ] Add `bash $ROUTER github fetch-interactions 1` to Batch 2 semicolon chain
- [ ] Add digest rendering instructions for `**Community Interactions:**` sub-section in Step 4

**File:** `.github/workflows/scheduled-community-monitor.yml`

### 1.3 Update community-manager agent

- [ ] Add `$ROUTER github fetch-interactions 7` to Capability 1 Step 1 data collection
- [ ] Update digest heading contract to document optional `**Community Interactions:**` sub-heading

**File:** `plugins/soleur/agents/support/community-manager.md`

## Phase 2: Verification

### 2.1 Manual testing

- [ ] Run `bash plugins/soleur/skills/community/scripts/github-community.sh fetch-interactions 7` and verify JSON output
- [ ] Verify bot comments excluded
- [ ] Verify org-member comments excluded
- [ ] Verify empty array returned when no external comments exist
