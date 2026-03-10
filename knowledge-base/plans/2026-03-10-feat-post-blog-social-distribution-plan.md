---
title: "feat: distribute CaaS blog post to X and Discord"
type: feat
date: 2026-03-10
issue: 502
branch: feat-post-blog-social
semver: patch
---

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

### Phase 4: Verification

1. Confirm Discord post appeared in the channel
2. Confirm X thread is visible at `https://x.com/soleur_ai`
3. Report distribution summary

## Non-Goals

- IndieHackers, Reddit, Hacker News posting (manual copy-paste from skill output)
- Modifying the social-distribute skill itself
- Engagement monitoring or analytics
- Modifying the blog post content

## Technical Considerations

### X API Rate Limits

The X API Free tier has strict rate limits:
- POST /2/tweets: 17 tweets per 24 hours (Free tier) or 100 per 24 hours (Basic tier)
- A 4-tweet thread consumes 4 of those posts
- `x-community.sh` handles 429 rate limit responses with retry logic (up to 3 attempts)

### X API Credential Pairing

Per the `2026-03-09-x-provisioning-playwright-automation.md` learning: regenerating the Consumer Key invalidates existing Access Tokens. The credential pair must be generated together (Consumer Key first, then Access Token).

### Discord Webhook Safety

Per constitution: all Discord webhook payloads include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields. The social-distribute skill already implements this.

### Thread Posting Failure Recovery

If a tweet in the middle of the thread fails (rate limit, network error):
- The thread will be incomplete but not corrupted
- Individual tweets can be deleted and re-posted
- The `--reply-to` mechanism ensures thread continuity

## Acceptance Criteria

- [ ] X API credentials are loaded and verified
- [ ] Discord webhook URL is loaded and verified
- [ ] social-distribute skill generates all 5 variants from the blog post
- [ ] Discord announcement posted successfully
- [ ] X/Twitter thread posted as connected replies (not isolated tweets)
- [ ] Distribution summary confirms Discord and X posted

## Test Scenarios

- Given X API credentials are set, when `x-community.sh fetch-metrics` is run, then account info is returned
- Given the social-distribute skill is invoked with the blog path, when content is generated, then all `{{ stats.agents }}` variables are resolved to actual numbers (62)
- Given the Discord webhook URL is set, when the user approves the Discord variant, then the post appears in the Discord channel
- Given the hook tweet is posted successfully, when reply tweets are sent with `--reply-to`, then they appear as a connected thread on X

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| X API credentials not in env | Cannot post to X | Source .env or prompt user to export credentials |
| X API Free tier rate limit (17 tweets/day) | Thread may exhaust daily quota | Keep thread to 4-5 tweets; verify quota before posting |
| X API paid tier requirement for some endpoints | `post-tweet` may require paid API | `POST /2/tweets` is available on Free tier; verify with test post |
| Discord webhook URL not loaded | Cannot auto-post to Discord | Source .env; skill degrades to manual output |
| Network failure mid-thread | Partial thread posted | Individual tweets are atomic; can resume from last successful tweet |

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
- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` -- Always use `allowed_mentions: {parse: []}`
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md` -- Explicit username/avatar_url in payloads
- `2026-02-18-token-env-var-not-cli-arg.md` -- Credentials via env vars, never CLI args
