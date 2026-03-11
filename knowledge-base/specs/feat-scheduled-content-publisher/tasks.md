# Tasks: Scheduled Content Publisher

## Phase 1: Setup

- [ ] 1.1 Verify content files are accessible (merged to main or available on this branch)
- [ ] 1.2 Create `scripts/content-publisher.sh` with shebang, `set -euo pipefail`, and usage message
- [ ] 1.3 Implement case-study-to-file mapping (`case` statement on input number)
- [ ] 1.4 Implement `extract_section()` function to parse content between `## <heading>` markers
- [ ] 1.5 Implement `extract_tweets()` function to parse X/Twitter Thread section into individual tweets

## Phase 2: Core Implementation

- [ ] 2.1 Implement `post_discord()` function using `curl` + `jq -n` payload construction
  - [ ] 2.1.1 Include `username: Sol`, `avatar_url`, `allowed_mentions: {parse: []}`
  - [ ] 2.1.2 Handle HTTP response codes (2xx success, 4xx/5xx error with clear message)
  - [ ] 2.1.3 Skip gracefully if `DISCORD_WEBHOOK_URL` is not set
- [ ] 2.2 Implement `post_x_thread()` function using `x-community.sh post-tweet`
  - [ ] 2.2.1 Post hook tweet first, capture tweet ID from JSON output
  - [ ] 2.2.2 Chain body tweets with `--reply-to <previous_id>`
  - [ ] 2.2.3 Detect HTTP 402 specifically and create fallback issue instead of failing
  - [ ] 2.2.4 Skip gracefully if X API credentials are not set
- [ ] 2.3 Implement `create_manual_issue()` function using `gh issue create`
  - [ ] 2.3.1 Extract platform-specific content (IndieHackers, Reddit, HN sections)
  - [ ] 2.3.2 Create issue with `action-required` and `content-publisher` labels
  - [ ] 2.3.3 Include case study name, platform name, and full pre-written content in issue body
- [ ] 2.4 Implement platform dispatch logic per case study number
  - [ ] 2.4.1 Studies 1, 3, 5: Discord + X + manual platform issues
  - [ ] 2.4.2 Studies 2, 4: Discord + X only
- [ ] 2.5 Create `scheduled-content-publisher.yml` workflow file
  - [ ] 2.5.1 `workflow_dispatch` trigger with `case_study` choice input (1-5)
  - [ ] 2.5.2 Concurrency group, permissions, timeout-minutes
  - [ ] 2.5.3 Label pre-creation step
  - [ ] 2.5.4 Main step invoking `scripts/content-publisher.sh`
  - [ ] 2.5.5 Discord failure notification step (copy pattern from scheduled-community-monitor.yml)
  - [ ] 2.5.6 Pin `actions/checkout` SHA

## Phase 3: Testing

- [ ] 3.1 Create `test/content-publisher.test.ts` with unit tests for content extraction functions
  - [ ] 3.1.1 Test `extract_section()` against sample content file
  - [ ] 3.1.2 Test `extract_tweets()` against sample X/Twitter Thread section
  - [ ] 3.1.3 Test case-study mapping returns correct file and platform set
- [ ] 3.2 Manual validation via `workflow_dispatch` for case study 1
  - [ ] 3.2.1 Verify Discord message content and formatting
  - [ ] 3.2.2 Verify X thread chaining (hook + body + final)
  - [ ] 3.2.3 Verify manual platform issue content and labels
- [ ] 3.3 Add cron triggers after workflow_dispatch validation passes (Phase 2 of rollout)
