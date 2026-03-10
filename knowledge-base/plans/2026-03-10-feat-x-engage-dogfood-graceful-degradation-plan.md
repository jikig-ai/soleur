# Plan: X Engage Dogfood — Graceful Degradation on Free Tier

**Spec:** [spec.md](../specs/feat-x-engage-dogfood/spec.md)
**Brainstorm:** [2026-03-10-x-engage-dogfood-brainstorm.md](../brainstorms/2026-03-10-x-engage-dogfood-brainstorm.md)
**Issue:** #496
**Deferred Expense:** #497
**PR:** #495

## Summary

Add graceful degradation to the X engage workflow so it works on the Free API tier. When `fetch-mentions` fails with a 403 `client-not-enrolled` error, the community-manager agent falls back to prompting the user for mention URLs manually. The rest of the pipeline (brand-voice draft, approval, post-tweet --reply-to) runs unchanged.

Also: add X engagement guardrails to the brand guide and mark the `get_request` 403 error message as an agent contract.

## Spec Clarifications (from SpecFlow Analysis)

| Gap | Resolution |
|-----|-----------|
| "paste tweet text" is ambiguous (no tweet ID) | Simplify to "paste a mention URL or tweet ID". Raw text without an ID is not supported — the agent needs an ID for `--reply-to`. |
| Where does fallback logic live? | **community-manager.md Capability 4**, after Step 1 (fetch). SKILL.md gets a brief note. The agent runs the bash command and sees stderr, so the agent is the right place. |
| Headless + 403 conflict | Report error and exit. Manual fallback requires interactive input, so headless mode cannot degrade. |
| Manual session loop | After processing one mention, ask "Paste another URL/ID, or type 'done':" to continue. Loop until done. |
| Proactive engagement (not just mentions) | Intentional. Manual mode is broader — supports replying to any tweet (cold-start #buildinpublic strategy). Summary says "Tweets replied to" in manual mode. |
| Bare tweet IDs | Accepted. If input is all-numeric, treat as tweet ID directly. |
| URL variants (mobile, vxtwitter) | Only `x.com` and `twitter.com` per TR2. Re-prompt on unrecognized. |
| stderr contract fragility | Add a comment in `x-community.sh` marking the 403 error message as an agent contract. Comment-only, compatible with TR4. |
| `.soleur/` gitignored | Already gitignored (line 36). No action needed. |

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `plugins/soleur/agents/support/community-manager.md` | Add 403 fallback in Capability 4 after Step 1 | ~252-271 |
| `plugins/soleur/skills/community/SKILL.md` | Add note about 403 graceful degradation in engage section | ~85-95 |
| `knowledge-base/overview/brand-guide.md` | Add X engagement guardrails under Channel Notes > X/Twitter | ~150-165 |
| `plugins/soleur/skills/community/scripts/x-community.sh` | Add contract comment above 403 error message in `get_request` | ~326 |
| `test/x-community.test.ts` | Add test for manual URL parsing patterns | new tests |

## Implementation

### Task 1: Add 403 Fallback to community-manager.md Capability 4

**File:** `plugins/soleur/agents/support/community-manager.md`

Insert a new **Step 1b: Handle Fetch Failure** after existing Step 1 (Fetch Mentions):

```markdown
#### Step 1b: Handle Fetch Failure (Free Tier Fallback)

If `fetch-mentions` exits non-zero:

1. Check stderr output for "requires paid API access" (client-not-enrolled signal).
2. If found — **switch to manual mode:**
   - Report: "fetch-mentions requires paid API access (Free tier). Switching to manual mode."
   - Enter manual loop:
     a. Prompt via AskUserQuestion: "Paste a tweet URL or numeric tweet ID to reply to (or 'done' to finish):"
     b. Parse input:
        - If URL matches `https://(x\.com|twitter\.com)/.+/status/(\d+)` — extract tweet ID from capture group
        - If all-numeric — use directly as tweet ID
        - Otherwise — report "Unrecognized format. Expected a tweet URL (x.com or twitter.com) or numeric tweet ID." and re-prompt
     c. Draft a brand-voice reply for this tweet (follow Step 3 constraints)
     d. Present for approval (follow Step 4 flow, without "Skip all remaining" since there is no remaining list)
     e. If accepted, post via `x-community.sh post-tweet "<reply_text>" --reply-to <tweet_id>`
     f. After processing, return to (a) — loop until user types "done"
   - Do NOT update since-id state file in manual mode
   - Display session summary with "Tweets replied to" (not "Mentions processed")
3. If "requires paid API access" NOT found in stderr — this is a different 403 error (permissions, suspension). Report the full error and stop. Do not enter manual mode.
4. If the error is not a 403 at all (network failure, 401, etc.) — report error and stop. Do not enter manual mode.

**Headless mode:** If `--headless` is set and fetch-mentions returns 403 with client-not-enrolled, report: "Cannot engage in headless mode on Free tier — fetch-mentions requires paid API access and manual fallback requires interactive input." Display summary with 0 processed and stop.
```

### Task 2: Add Degradation Note to SKILL.md Engage Section

**File:** `plugins/soleur/skills/community/SKILL.md`

Insert after the since-id state file paragraph (around line 94), before the agent spawn instruction:

```markdown
**Free tier degradation:** If `fetch-mentions` returns 403 (client-not-enrolled), the community-manager agent switches to manual mode — prompting for tweet URLs instead of fetching mentions automatically. The rest of the pipeline (brand-voice draft, approval, post-tweet) runs unchanged. See Capability 4 Step 1b. When the paid tier activates, this fallback is never triggered.
```

### Task 3: Add X Engagement Guardrails to Brand Guide

**File:** `knowledge-base/overview/brand-guide.md`

Add a new `#### Engagement Guardrails` subsection under `### X/Twitter` (after the existing formatting rules around line 162):

```markdown
#### Engagement Guardrails

**Topics to avoid:**
- Politics, partisan issues, or social commentary unrelated to technology
- Direct competitor criticism or comparisons (let the work speak)
- Speculation about other companies' strategies or internal decisions
- Anything requiring legal review (pricing commitments, partnership claims)

**When to skip a mention/thread:**
- Abusive, harassing, or clearly spam content
- Off-topic mentions with no connection to dev tools, AI, or building
- Rage-bait or controversy-farming threads
- Mentions from accounts with <10 followers and no bio (likely bots)

**Reply cadence:**
- Maximum 10 replies per engage session
- Space replies at least 2 minutes apart to avoid appearing automated
- If unsure whether to reply, skip — silence is always safe

**Tone in replies:**
- Match the register of the original tweet (casual thread = casual reply)
- Never argue or defend — if challenged, share a link and disengage
- One reply per thread unless directly asked a follow-up question
```

### Task 4: Add Contract Comment in x-community.sh

**File:** `plugins/soleur/skills/community/scripts/x-community.sh`

Add a comment above the `client-not-enrolled` error message in `get_request` (around line 326):

```bash
    if [[ "$reason" == "client-not-enrolled" ]]; then
        # CONTRACT: community-manager agent matches on this string for 403 fallback detection.
        # Changing this message requires updating agents/support/community-manager.md Capability 4 Step 1b.
        echo "This endpoint requires paid API access." >&2
```

### Task 5: Add Tests for URL Parsing Patterns

**File:** `test/x-community.test.ts`

Add test cases validating the URL patterns the agent will use:

```
URL parsing patterns (for agent reference, not script logic):
- https://x.com/user/status/1234567890 → 1234567890
- https://twitter.com/user/status/1234567890 → 1234567890
- https://x.com/user/status/1234567890?s=20&t=abc → 1234567890
- https://twitter.com/user/status/1234567890/photo/1 → 1234567890
- 1234567890 (bare ID) → 1234567890
- https://vxtwitter.com/user/status/123 → rejected
- random text without ID → rejected
```

Note: Since the URL parsing happens in LLM instructions (not script code), these tests serve as a specification/contract for the expected behavior. They verify the regex pattern extracts the correct tweet ID from various URL formats. Implementation as a bash function in a test helper or as documentation assertions.

## Acceptance Criteria

- [ ] `community engage` on Free tier catches 403, prompts for manual URL, drafts reply, posts successfully
- [ ] `community engage` on paid tier works unchanged (FR4 — fallback never triggered)
- [ ] Headless mode + 403 = clean error message, no hanging
- [ ] Brand guide has engagement guardrails section under X/Twitter
- [ ] Contract comment exists in x-community.sh get_request 403 handler
- [ ] URL parsing handles both domains, query params, bare IDs
- [ ] Since-id not updated in manual mode
- [ ] Non-enrolled 403 triggers manual mode; other 403s (suspension, permissions) stop with error

## Out of Scope

- Changes to `x_request` (POST helper) 403 handling — only `get_request` is relevant for fetch-mentions
- Rate-limit tracking for 50 tweets/month cap (separate issue)
- Full moderation runbook with SLAs
- Browser automation for thread discovery
- Fixes for #478 or #492

## Risks

| Risk | Mitigation |
|------|-----------|
| Future edits to x-community.sh 403 message break agent fallback | Contract comment marks the string as a dependency |
| Agent misparses stderr (network error vs. 403) | Agent checks for specific "requires paid API access" string, not just exit code |
| 50 tweets/month cap hit mid-session | Known limitation — user manages manually. Post-tweet 429 retry logic may mask this. |
| Brand guide guardrails are too restrictive/loose | Human-in-the-loop on every reply is the real safety net; guardrails are guidance for the drafting agent |
