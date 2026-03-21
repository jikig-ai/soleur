# Tasks: X Engage Dogfood — Graceful Degradation

**Plan:** [2026-03-10-feat-x-engage-dogfood-graceful-degradation-plan.md](../../plans/2026-03-10-feat-x-engage-dogfood-graceful-degradation-plan.md)
**Issue:** #496

## Phase 1: Core Implementation

### 1.1 Add 403 fallback to community-manager.md Capability 4

- [x] Read `plugins/soleur/agents/support/community-manager.md`
- [x] Insert Step 1b (Handle Fetch Failure) after Step 1 (Fetch Mentions)
- [x] Include: 403 client-not-enrolled detection via stderr string matching
- [x] Include: manual URL/ID prompt loop (AskUserQuestion → parse → draft → approve → post → loop)
- [x] Include: URL parsing regex for x.com and twitter.com domains
- [x] Include: bare numeric tweet ID acceptance
- [x] Include: headless mode + 403 behavior (report and exit)
- [x] Include: non-enrolled vs other 403 distinction
- [x] Include: since-id not updated in manual mode
- [x] Include: session summary says "Tweets replied to" in manual mode

### 1.2 Add degradation note to SKILL.md engage section

- [x] Read `plugins/soleur/skills/community/SKILL.md`
- [x] Insert free tier degradation paragraph after since-id state file section (~line 94)
- [x] Reference Capability 4 Step 1b

### 1.3 Add contract comment in x-community.sh

- [x] Read `plugins/soleur/skills/community/scripts/x-community.sh`
- [x] Add contract comment above "This endpoint requires paid API access." in `get_request` 403 handler (~line 326)
- [x] Comment references community-manager.md Capability 4 Step 1b

## Phase 2: Verification

### 2.1 Verify integration

- [x] Run existing test suite to confirm no regressions
- [x] Verify SKILL.md engage section references the fallback correctly
- [x] Verify community-manager.md Capability 4 flows logically (paid path unchanged, free path degrades)
- [x] Verify contract comment in x-community.sh is accurate
