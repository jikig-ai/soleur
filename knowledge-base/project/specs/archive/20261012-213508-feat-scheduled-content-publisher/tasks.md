# Tasks: Scheduled Content Publisher

## Phase 1: Setup

- [x] 1.1 Verify content files are accessible (merged to main or available on this branch)
- [x] 1.2 Create `scripts/content-publisher.sh` with shebang, `set -euo pipefail`, and usage message
- [x] 1.3 Implement `resolve_content()` with case-study-to-file mapping (`case` statement on input number)
  - [x] 1.3.1 Map number to content file path, case study name, and manual platform list
  - [x] 1.3.2 Validate content file exists with clear error message referencing merge prerequisite
- [x] 1.4 Implement `extract_section()` function to parse content between `## <heading>` markers
  - [x] 1.4.1 Handle "Not scheduled for [platform] distribution" placeholder sections (studies 2, 4)
  - [x] 1.4.2 Handle last section in file (no trailing heading delimiter -- `## Hacker News`)
- [x] 1.5 Implement `extract_tweets()` function to parse X/Twitter Thread section into individual tweets
  - [x] 1.5.1 Split on `**Tweet N` pattern, strip label lines
  - [x] 1.5.2 Return empty/error if no tweets found

## Phase 2: Core Implementation

- [x] 2.1 Implement `post_discord()` function using `curl` + `jq -n` payload construction
  - [x] 2.1.1 Include `username: Sol`, `avatar_url`, `allowed_mentions: {parse: []}`
  - [x] 2.1.2 Handle HTTP response codes (2xx success, 4xx/5xx error with clear message)
  - [x] 2.1.3 Skip gracefully if `DISCORD_WEBHOOK_URL` is not set
- [x] 2.2 Implement `post_x_thread()` function using `x-community.sh post-tweet`
  - [x] 2.2.1 Post hook tweet first, capture tweet ID from JSON output (`.id`)
  - [x] 2.2.2 Chain body tweets with `--reply-to <previous_id>` (each reply references preceding tweet, not hook)
  - [x] 2.2.3 Detect HTTP 402 specifically and create fallback issue instead of failing
  - [x] 2.2.4 Handle partial thread failure -- create resume issue with last tweet ID
  - [x] 2.2.5 Skip gracefully if X API credentials are not set
- [x] 2.3 Implement `create_dedup_issue()` with title-based deduplication
  - [x] 2.3.1 Search for existing open issue with exact title match before creating
  - [x] 2.3.2 Skip creation if duplicate found, log the existing issue number
- [x] 2.4 Implement `create_manual_issues()` function using `gh issue create`
  - [x] 2.4.1 Extract platform-specific content (IndieHackers, Reddit, HN sections)
  - [x] 2.4.2 Create issue with `action-required` and `content-publisher` labels
  - [x] 2.4.3 Include case study name, platform name, and full pre-written content in issue body
  - [x] 2.4.4 Skip platforms with empty/missing content sections
- [x] 2.5 Implement `create_x_fallback_issue()` and `create_partial_thread_issue()` helpers
- [x] 2.6 Implement `main()` dispatch logic per case study number
  - [x] 2.6.1 Discord posting (all studies)
  - [x] 2.6.2 X/Twitter thread posting (all studies)
  - [x] 2.6.3 Manual platform issues (studies 1, 3, 5 only)
  - [x] 2.6.4 Each platform failure does not abort subsequent platforms
- [x] 2.7 Create `scheduled-content-publisher.yml` workflow file
  - [x] 2.7.1 `workflow_dispatch` trigger with `case_study` choice input (1-5)
  - [x] 2.7.2 Concurrency group, permissions (`contents: read`, `issues: write`), `timeout-minutes: 10`
  - [x] 2.7.3 Label pre-creation step (`action-required`, `content-publisher`)
  - [x] 2.7.4 Main step invoking `scripts/content-publisher.sh` with all secrets as env vars
  - [x] 2.7.5 Discord failure notification step (copy pattern from `scheduled-community-monitor.yml`)
  - [x] 2.7.6 Pin `actions/checkout` to SHA `34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
  - [x] 2.7.7 Security comment header documenting that no untrusted inputs are used

## Phase 3: Testing

- [x] 3.1 Create `test/content-publisher.test.ts` with unit tests for content extraction functions
  - [x] 3.1.1 Test `extract_section()` against sample content file (Discord, X, IndieHackers, Reddit, HN)
  - [x] 3.1.2 Test `extract_section()` handles "Not scheduled" placeholder text (returns empty)
  - [x] 3.1.3 Test `extract_tweets()` against sample X/Twitter Thread section (4-tweet thread)
  - [x] 3.1.4 Test `extract_tweets()` returns error for missing X section
  - [x] 3.1.5 Test `resolve_content()` returns correct file and platform set for each study (1-5)
  - [x] 3.1.6 Test `resolve_content()` exits 1 for invalid input (0, 6, "abc")
- [ ] 3.2 Manual validation via `workflow_dispatch` for case study 1
  - [ ] 3.2.1 Verify Discord message content, username "Sol", and avatar
  - [ ] 3.2.2 Verify X thread chaining (hook + body + final, 4 tweets)
  - [ ] 3.2.3 Verify manual platform issues created for IH, Reddit, HN with correct labels
  - [ ] 3.2.4 Verify re-run does not create duplicate issues
- [ ] 3.3 Add cron triggers after workflow_dispatch validation passes (Phase 2 of rollout)
  - [ ] 3.3.1 Use non-zero minutes (`:07`) to avoid top-of-hour congestion
