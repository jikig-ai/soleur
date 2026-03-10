---
title: "feat: distribute CaaS blog post to X and Discord"
type: feat
date: 2026-03-10
issue: 502
branch: feat-post-blog-social
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5 (Credential Setup, Thread Posting, Rate Limits, Failure Recovery, Risks)
**Research sources:** X API v2 docs, X Developer Community forums, project learnings corpus

### Key Improvements
1. Corrected X API Free tier rate limits (500+ posts/month, not 17/day as originally stated)
2. Added concrete thread posting sequence with error handling between tweets
3. Added `.env` sourcing details -- worktree `.env` has Discord webhook but X credentials need separate verification
4. Added pre-flight credential verification step before running social-distribute skill
5. Added thread recovery procedure for partial posting failures

### New Considerations Discovered
- X API may have transitioned to consumption-based billing (Developer Console) -- verify current tier before posting
- `x-community.sh post-tweet` uses OAuth 1.0a signing which requires `openssl` -- already a dependency
- Thread tweets share a `conversation_id` (the hook tweet's ID) regardless of depth -- useful for later retrieval

# Distribute "What Is Company-as-a-Service?" to X and Discord

## Overview

Execute the existing `social-distribute` skill to distribute the blog post `plugins/soleur/docs/blog/what-is-company-as-a-service.md` to X/Twitter and Discord. The skill already exists (built in PR #457). This plan covers prerequisite verification, credential setup, execution, and X API thread posting (which was deferred to v2 in the original plan but is now needed).

## Problem Statement

The first blog article ("What Is Company-as-a-Service?") shipped 2026-03-05 but has never been distributed to social channels. Issue #502 requests posting to X and Discord. The `social-distribute` skill generates content variants but currently only auto-posts to Discord -- X/Twitter outputs formatted text for manual posting. The X account (@soleur_ai) and Developer Portal app exist (provisioned per `2026-03-09-x-provisioning-playwright-automation.md` learning), but the X API credentials are not loaded in the current shell environment.

## Proposed Solution

### Phase 1: Prerequisites & Credential Setup

1. **Source `.env` credentials** -- The `.env` file in the worktree contains `DISCORD_WEBHOOK_URL`. X API credentials (`X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) need to be either:
   - Already in `.env` (check via `grep X_ .env`)
   - Added to `.env` via `x-setup.sh write-env` if the user has them available
   - Set manually by the user via `export`

2. **Verify X API access** -- Run `x-setup.sh verify` or `x-community.sh fetch-metrics` to confirm the X API credentials work and the account has post permissions (OAuth 1.0a Read+Write).

3. **Verify Discord webhook** -- Source `.env` and confirm `DISCORD_WEBHOOK_URL` is set.

#### Research Insights: Credential Loading

**Current state (verified):**
- Worktree `.env` contains: `DISCORD_WEBHOOK_URL` (confirmed present)
- Worktree `.env` does NOT contain: `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`
- Main repo `.env` does NOT contain X credentials either
- The `x-setup.sh write-env` command can write X credentials to `.env` with `chmod 600`

**Credential loading sequence:**

```bash
# Step 1: Source existing .env for Discord webhook
source .env

# Step 2: Check if X credentials are present
if [[ -z "${X_API_KEY:-}" ]]; then
  echo "X API credentials not found. Options:"
  echo "  a) Export them: export X_API_KEY=... X_API_SECRET=... X_ACCESS_TOKEN=... X_ACCESS_TOKEN_SECRET=..."
  echo "  b) Run: bash plugins/soleur/skills/community/scripts/x-setup.sh write-env"
  echo "  c) Source from another location if credentials exist elsewhere"
fi

# Step 3: Verify round-trip API call
bash plugins/soleur/skills/community/scripts/x-community.sh fetch-metrics
```

**Security (from learnings):**
- Never pass tokens as CLI arguments -- visible in `ps aux` and shell history
- `x-community.sh` already suppresses curl stderr (`2>/dev/null`) to prevent auth header leakage
- `.env` files are written with `chmod 600` by `x-setup.sh write-env`

### Phase 2: Run social-distribute Skill

1. Source `.env` to load environment variables
2. Invoke the skill: `skill: soleur:social-distribute plugins/soleur/docs/blog/what-is-company-as-a-service.md`
3. The skill will:
   - Read the blog post and parse frontmatter
   - Gather current stats (62 agents, 57 skills, 9 departments)
   - Build article URL: `https://soleur.ai/blog/what-is-company-as-a-service/`
   - Read brand guide voice and channel notes (Discord + X/Twitter sections exist)
   - Generate 5 platform variants (Discord, X/Twitter, IndieHackers, Reddit, HN)
   - Present all variants for review
   - Post to Discord after approval
   - Output X/Twitter thread as formatted text

#### Research Insights: Content Generation

**Brand guide channel notes verified present:**
- `### Discord` -- builder-to-builder tone, direct, collaborative
- `### X/Twitter` -- hook-first threads, 280-char per tweet, numbered body tweets (2/ 3/ 4/), links only in final tweet, no emojis in hook tweet, metrics-driven opening

**Stats to resolve (current as of 2026-03-10):**
- `{{ stats.agents }}` = 62
- `{{ stats.skills }}` = 57
- `{{ stats.departments }}` = 9
- `{{ site.url }}` = `https://soleur.ai`

### Phase 3: Post X/Twitter Thread via API

After the skill outputs the X/Twitter thread text, use `x-community.sh post-tweet` to post the thread programmatically:

1. Post the hook tweet (no reply-to)
2. Capture the tweet ID from the response
3. Post each subsequent tweet as a reply to the previous tweet using `--reply-to <tweet_id>`
4. Verify each tweet posted successfully before continuing the thread

```bash
# Pattern for posting a thread:
# 1. Post hook tweet
RESULT=$(bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "hook tweet text")
TWEET_ID=$(echo "$RESULT" | jq -r '.id')

# 2. Post replies in sequence
RESULT=$(bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "2/ reply text" --reply-to "$TWEET_ID")
TWEET_ID=$(echo "$RESULT" | jq -r '.id')

# Continue for each tweet in thread...
```

#### Research Insights: Thread Posting

**X API v2 thread mechanics (verified via docs.x.com):**
- Threads are created by posting sequential replies using `POST /2/tweets` with `{"reply": {"in_reply_to_tweet_id": "<id>"}}`
- All tweets in a thread share the same `conversation_id` (the hook tweet's ID)
- There is no batch/atomic thread endpoint -- each tweet is a separate API call
- Each reply must reference the immediately preceding tweet's ID (not the hook tweet's ID) to maintain linear thread order

**Implementation pattern:**

```bash
# Post hook tweet and validate response
HOOK_RESULT=$(bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "hook text")
HOOK_ID=$(echo "$HOOK_RESULT" | jq -r '.id')
if [[ -z "$HOOK_ID" || "$HOOK_ID" == "null" ]]; then
  echo "Error: Failed to post hook tweet. Aborting thread." >&2
  exit 1
fi
echo "Hook tweet posted: https://x.com/soleur_ai/status/$HOOK_ID"

# Post each reply, chaining to the previous tweet
PREV_ID="$HOOK_ID"
for tweet_text in "2/ body text" "3/ body text" "4/ final text with link"; do
  REPLY_RESULT=$(bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "$tweet_text" --reply-to "$PREV_ID")
  REPLY_ID=$(echo "$REPLY_RESULT" | jq -r '.id')
  if [[ -z "$REPLY_ID" || "$REPLY_ID" == "null" ]]; then
    echo "Error: Failed to post reply. Thread is partial (last successful: $PREV_ID)." >&2
    echo "Resume from: --reply-to $PREV_ID" >&2
    exit 1
  fi
  PREV_ID="$REPLY_ID"
  echo "Reply posted: https://x.com/soleur_ai/status/$REPLY_ID"
done
```

**Key considerations:**
- Add a brief delay (1-2 seconds) between tweets to avoid triggering automated behavior detection
- Validate each tweet ID before posting the next reply -- a `null` or empty ID means the previous post failed silently
- The `x-community.sh` script outputs JSON `{id, text}` on success and prints "Tweet posted successfully." to stderr
- On rate limit (429), the script retries up to 3 times with exponential backoff

### Phase 4: Verification

1. Confirm Discord post appeared in the channel
2. Confirm X thread is visible at `https://x.com/soleur_ai`
3. Report distribution summary

#### Research Insights: Verification

**Discord verification:** The webhook returns HTTP 2xx on success. The social-distribute skill already reports success/failure status.

**X verification options:**
- Check the profile page at `https://x.com/soleur_ai` (manual or via Playwright MCP `browser_navigate`)
- Use `x-community.sh fetch-timeline --max 5` to confirm the thread tweets appear in the timeline
- The hook tweet URL is `https://x.com/soleur_ai/status/<HOOK_ID>` -- this is the canonical thread URL to share

## Non-Goals

- IndieHackers, Reddit, Hacker News posting (manual copy-paste from skill output)
- Modifying the social-distribute skill itself
- Engagement monitoring or analytics
- Modifying the blog post content

## Technical Considerations

### X API Rate Limits

**Corrected rate limits (verified 2026-03-10 via [docs.x.com](https://docs.x.com/x-api/fundamentals/rate-limits)):**

The X API Free tier allows:
- **500 posts per month** (some documentation indicates up to 1,500 -- X may have recently increased the limit or transitioned to consumption-based billing via the new Developer Console)
- A 4-5 tweet thread consumes 4-5 of the monthly quota -- well within limits
- `x-community.sh` handles 429 rate limit responses with depth-limited retry logic (up to 3 attempts, per `2026-03-09-depth-limited-api-retry-pattern.md`)

**Pre-flight check:** Before posting the thread, run `x-community.sh fetch-metrics` to verify the API responds. This is a read endpoint that confirms credentials work without consuming a post.

### X API Credential Pairing

Per the `2026-03-09-x-provisioning-playwright-automation.md` learning: regenerating the Consumer Key invalidates existing Access Tokens. The credential pair must be generated together (Consumer Key first, then Access Token).

### Discord Webhook Safety

Per constitution: all Discord webhook payloads include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields. The social-distribute skill already implements this.

### Thread Posting Failure Recovery

If a tweet in the middle of the thread fails (rate limit, network error):
- The thread will be incomplete but not corrupted -- each posted tweet is permanent
- Individual tweets can be deleted via `DELETE /2/tweets/:id` if needed (requires the tweet ID from the post response)
- To resume: post the remaining tweets using `--reply-to <last_successful_tweet_id>`
- The `--reply-to` mechanism ensures thread continuity regardless of when the next tweet is posted

#### Research Insights: Recovery

**Partial thread recovery procedure:**
1. Note the last successfully posted tweet ID (printed to stdout during posting)
2. Diagnose the failure (rate limit? network? auth?)
3. Fix the issue (wait for rate limit reset, reconnect, re-auth)
4. Resume by posting the next tweet with `--reply-to <last_successful_id>`
5. Continue the chain from there

**Deletion if needed:**
- The X API v2 supports `DELETE /2/tweets/:id` but `x-community.sh` does not implement this command yet
- For the first distribution, manual deletion via the X web interface is acceptable
- If this becomes a pattern, add a `delete-tweet` command to `x-community.sh`

### Shell API Hardening (from learnings)

The `x-community.sh` script has been hardened against five failure modes (per `2026-03-09-shell-api-wrapper-hardening-patterns.md`):
1. jq fallback chains (`|| echo "fallback"`) for malformed responses
2. curl stderr suppression (`2>/dev/null`) to prevent auth header leakage
3. JSON validation on 2xx responses before consuming
4. Float-safe `retry_after` handling for bash arithmetic
5. Input validation on tweet IDs and parameters

No additional hardening is needed for this execution task.

## Acceptance Criteria

- [x] X API credentials are loaded and verified (fetch-metrics returns account info)
- [x] Discord webhook URL is loaded and verified
- [x] social-distribute skill generates all 5 variants from the blog post
- [x] Discord announcement posted successfully (HTTP 2xx from webhook)
- [x] X/Twitter thread posted as connected replies (not isolated tweets)
- [x] Each tweet in the thread is verified before posting the next
- [x] Distribution summary confirms Discord and X posted

## Test Scenarios

- Given X API credentials are set, when `x-community.sh fetch-metrics` is run, then account info is returned with username `soleur_ai`
- Given the social-distribute skill is invoked with the blog path, when content is generated, then all `{{ stats.agents }}` variables are resolved to actual numbers (62)
- Given the Discord webhook URL is set, when the user approves the Discord variant, then the post appears in the Discord channel
- Given the hook tweet is posted successfully, when reply tweets are sent with `--reply-to`, then they appear as a connected thread on X
- Given a tweet in the thread fails with 429, when `x-community.sh` retries (up to 3 times), then the retry succeeds or a clear error is reported
- Given the thread is partially posted, when the user resumes with `--reply-to <last_id>`, then the remaining tweets are added to the existing thread

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| X API credentials not in env | Cannot post to X | Source .env or prompt user to export credentials; run `x-setup.sh write-env` if needed |
| X API Free tier monthly post limit (500-1,500/month) | Thread consumes 4-5 posts from monthly quota | Well within limits; verify with fetch-metrics pre-flight |
| X API consumption-based billing transition | Pricing model may differ from documented tiers | Run a single test tweet first to verify posting works before committing the full thread |
| Discord webhook URL not loaded | Cannot auto-post to Discord | Source .env; skill degrades to manual output gracefully |
| Network failure mid-thread | Partial thread posted | Record each tweet ID; resume from last successful tweet with `--reply-to` |
| X automated behavior detection | Rapid sequential posting may trigger spam filters | Add 1-2 second delay between thread tweets |
| OAuth credential invalidation | Regenerated Consumer Key breaks Access Token pairing | Do not regenerate keys before posting; verify with fetch-metrics first |

## References

### Internal

- social-distribute skill: `plugins/soleur/skills/social-distribute/SKILL.md`
- X community script: `plugins/soleur/skills/community/scripts/x-community.sh`
- X setup script: `plugins/soleur/skills/community/scripts/x-setup.sh`
- Blog post: `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- Brand guide: `knowledge-base/overview/brand-guide.md`
- Site config: `plugins/soleur/docs/_data/site.json`
- Original social-distribute plan: `knowledge-base/plans/2026-03-06-feat-social-distribute-plan.md`

### Learnings Applied

- `2026-03-09-x-provisioning-playwright-automation.md` -- X account exists, credential pairing gotcha
- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- Five-layer defense in shell API wrappers (already applied)
- `2026-03-09-depth-limited-api-retry-pattern.md` -- Bounded retry with depth parameter (already applied)
- `2026-03-09-external-api-scope-calibration.md` -- Verify API tier capabilities before building (rate limits corrected)
- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` -- Always use `allowed_mentions: {parse: []}`
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md` -- Explicit username/avatar_url in payloads
- `2026-02-18-token-env-var-not-cli-arg.md` -- Credentials via env vars, never CLI args

### External

- [X API Rate Limits](https://docs.x.com/x-api/fundamentals/rate-limits) -- Official rate limit documentation
- [X API Conversation ID](https://docs.x.com/x-api/fundamentals/conversation-id) -- Thread mechanics and conversation_id behavior
- [X Developer Community: Thread Posting](https://devcommunity.x.com/t/is-there-a-way-to-post-a-twitter-thread-in-api/174942) -- Community examples of API thread creation
- [X Developer Community: Free Tier Replies](https://devcommunity.x.com/t/is-it-possible-to-reply-to-a-tweet-post-using-free-v2-api/214763) -- Confirmation that Free tier supports reply posting
