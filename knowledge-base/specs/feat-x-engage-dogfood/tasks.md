# Tasks: X Engage Dogfood — Graceful Degradation

**Plan:** [2026-03-10-feat-x-engage-dogfood-graceful-degradation-plan.md](../../plans/2026-03-10-feat-x-engage-dogfood-graceful-degradation-plan.md)
**Issue:** #496

## Phase 1: Core Implementation

### 1.1 Add 403 fallback to community-manager.md Capability 4
- [ ] Read `plugins/soleur/agents/support/community-manager.md`
- [ ] Insert Step 1b (Handle Fetch Failure) after Step 1 (Fetch Mentions)
- [ ] Include: 403 client-not-enrolled detection via stderr string matching
- [ ] Include: manual URL/ID prompt loop (AskUserQuestion → parse → draft → approve → post → loop)
- [ ] Include: URL parsing regex for x.com and twitter.com domains
- [ ] Include: bare numeric tweet ID acceptance
- [ ] Include: headless mode + 403 behavior (report and exit)
- [ ] Include: non-enrolled vs other 403 distinction
- [ ] Include: since-id not updated in manual mode
- [ ] Include: session summary says "Tweets replied to" in manual mode

### 1.2 Add degradation note to SKILL.md engage section
- [ ] Read `plugins/soleur/skills/community/SKILL.md`
- [ ] Insert free tier degradation paragraph after since-id state file section (~line 94)
- [ ] Reference Capability 4 Step 1b

### 1.3 Add contract comment in x-community.sh
- [ ] Read `plugins/soleur/skills/community/scripts/x-community.sh`
- [ ] Add contract comment above "This endpoint requires paid API access." in `get_request` 403 handler (~line 326)
- [ ] Comment references community-manager.md Capability 4 Step 1b

## Phase 2: Verification

### 2.1 Verify integration
- [ ] Run existing test suite to confirm no regressions
- [ ] Verify SKILL.md engage section references the fallback correctly
- [ ] Verify community-manager.md Capability 4 flows logically (paid path unchanged, free path degrades)
- [ ] Verify contract comment in x-community.sh is accurate
