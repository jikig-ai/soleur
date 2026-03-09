# Tasks: Add X/Twitter Support to Community Agent

**Issue:** #127
**Plan:** `knowledge-base/plans/2026-03-09-feat-community-agent-platform-adapter-plan.md`

## Phase 1: X/Twitter Integration

### 1.0 Pre-work
- [x] Update spec.md TR2 to include `openssl` in allowed dependencies
- [x] Verify X API Free tier endpoints (hard gate -- scope depends on result)
- [x] Document actual Free tier scope vs. brainstorm assumptions

### 1.1 Create x-setup.sh
- [x] Implement `validate-credentials` (GET /2/users/me with OAuth 1.0a)
- [x] Implement `write-env` (write 4 env vars to `.env` with chmod 600)
- [x] Implement `verify` (round-trip API check)
- [x] Suppress curl stderr during auth requests

### 1.2 Create x-community.sh
- [x] Implement OAuth 1.0a signing helper function (HMAC-SHA1 via openssl)
- [x] Implement `x_request` helper (HTTP status capture, 429 retry with max 3 depth, auth error handling)
- [x] Implement `fetch-metrics` (GET /2/users/me -- follower/following/tweet counts)
- [x] Implement `post-tweet` (POST /2/tweets with optional --reply-to TWEET_ID)
- [x] Only add read commands (fetch-mentions, fetch-timeline) if Free tier verification confirms support
- [x] Test openssl absence detection (clear error message)

## Phase 2: Community SKILL.md + Agent Update

### 2.1 Create SKILL.md
- [x] Write frontmatter (name: community, third-person description)
- [x] Implement platform detection (check all required env vars per platform)
- [x] Implement `digest` sub-command (multi-platform data collection, unified digest file)
- [x] Implement `health` sub-command (cross-platform metrics display)
- [x] Implement `platforms` sub-command (list, validate, report status)
- [x] Add `--headless` bypass for all prompts
- [x] Add `$ARGUMENTS` passthrough for programmatic callers

### 2.2 Register skill
- [x] Add `community` to `SKILL_CATEGORIES` in `docs/_data/skills.js`

### 2.3 Update community-manager.md
- [x] Update description to mention X alongside Discord and GitHub
- [x] Add social-distribute disambiguation sentence
- [x] Add X env var requirements to prerequisites
- [x] List x-community.sh and x-setup.sh in scripts section
- [x] Add X metrics section to digest capability (additive -- preserve existing headings)
- [x] Include X metrics in health report
- [x] Analyze X activity in content suggestions
- [x] Note X channel notes from brand guide for tone

### 2.4 Update supporting files
- [x] Update CCO delegation table in cco.md (unconditional -- capabilities expanded)
- [x] Run agent description token budget check (under 2500 words)

### 2.5 Verification
- [ ] Test X credentials and API access with real account
- [ ] Test multi-platform digest generation
- [ ] Test platform detection with partial env vars
- [ ] Verify Discord functionality not regressed (existing scripts untouched)
- [ ] Verify `/soleur:community` is invocable and discoverable
- [ ] Verify skill appears on docs site

## Deferred (file as separate issues)

- [ ] File issue: `engage` sub-command for interactive X mention engagement
- [ ] File issue: Platform adapter interface refactor (for when platform #4 arrives)
- [ ] File issue: X monitoring commands requiring Basic tier (fetch-mentions, fetch-timeline)
- [ ] File issue: discord-community.sh recursive 429 retry bug (pre-existing, no depth limit)
