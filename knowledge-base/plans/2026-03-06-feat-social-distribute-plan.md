---
title: "feat: social distribution workflow for blog content"
type: feat
date: 2026-03-06
issue: 458
pr: 457
branch: feat-social-distribute
---

# Social Distribution Workflow

## Overview

Build a `social-distribute` skill that takes a published blog article and generates platform-specific content variants for 5 social channels, posting to Discord (webhook) and X/Twitter (API) automatically, with formatted text output for IndieHackers, Reddit, and Hacker News. Also fix inaccuracies in the CaaS blog article and extend the brand guide with social channel notes.

## Problem Statement

The first blog article shipped 2026-03-05 with zero social distribution. The marketing strategy describes distribution as a step but no executable workflow exists. The discord-content skill handles Discord only. No skill covers multi-platform distribution.

## Proposed Solution

A single `social-distribute` skill following the discord-content pattern (prerequisites -> generate -> approve -> post) expanded to 5 platforms. Brand guide gets new channel notes sections. Blog article gets an accuracy fix pass.

### Architecture

```
User invokes /soleur:social-distribute <blog-path>

  1. Prerequisites check (brand guide, env vars)
  2. Read blog post + resolve template variables + strip HTML
  3. Read brand guide Voice + Channel Notes per platform
  4. Read content repurposing table (optional editorial brief)
  5. Generate 5 variants via copywriter agent delegation
  6. Present all variants, sequential per-platform approval
  7. Post to Discord (webhook) and X/Twitter (API)
  8. Output formatted text for manual platforms
```

### Key design decisions from research

| Decision | Rationale | Source |
|----------|-----------|--------|
| Inline Discord posting (don't call discord-content) | Skills cannot invoke other skills | `implementation-patterns/2026-02-18-skill-cannot-invoke-skill.md` |
| Include `allowed_mentions: {parse: []}` in webhook | Constitution mandate + discord-content has this bug | `2026-03-05-discord-allowed-mentions.md` |
| Inline brand voice validation (no separate phase) | Three independent reviews killed the separate validator idea | `2026-02-12-brand-guide-contract.md` |
| Sequential per-platform approval | Matches discord-content pattern; rejection skips platform, doesn't abort | SpecFlow analysis |
| Resolve template vars by reading `_data/stats.js` and `_data/site.json` | Blog source has `{{ stats.agents }}` 8+ times; literal syntax in tweets is broken | SpecFlow analysis |
| Strip `<script>` and `<details>` blocks before generation | JSON-LD and FAQ accordions are meaningless in social posts | SpecFlow analysis |
| Graceful degradation on API failure (not just missing keys) | 401, 403, 429, timeout all degrade to text output | SpecFlow analysis |
| Support `--headless` flag | CMO/community-manager may invoke autonomously | `2026-03-03-headless-mode.md` |

## Technical Considerations

### Template Variable Resolution

Blog posts contain Nunjucks variables (`{{ stats.agents }}`, `{{ site.url }}`). The skill must:
1. Read `plugins/soleur/docs/_data/stats.js` and execute the counting logic (count `.md` files in agent/skill/command dirs)
2. Read `plugins/soleur/docs/_data/site.json` for `site.url`
3. Replace `{{ stats.agents }}`, `{{ stats.skills }}`, `{{ stats.commands }}`, `{{ stats.departments }}`, `{{ site.url }}` in the article text before passing to content generation

### Content Preprocessing Pipeline

Before generating variants, the skill strips:
- `<script>` blocks (JSON-LD schema markup)
- `<details>` blocks (FAQ accordions)
- YAML frontmatter (already parsed for title/description)
- Markdown tables (converted to prose by the LLM during generation)

### X/Twitter API v2 Integration

**Environment variables:**
- `X_BEARER_TOKEN` — App-only authentication (read operations)
- `X_API_KEY` — OAuth 1.0a consumer key
- `X_API_SECRET` — OAuth 1.0a consumer secret
- `X_ACCESS_TOKEN` — OAuth 1.0a user access token
- `X_ACCESS_TOKEN_SECRET` — OAuth 1.0a user access secret

OAuth 1.0a is required for tweet posting (write operations). OAuth 2.0 PKCE would require a token refresh mechanism — too complex for v1.

**Thread posting:**
1. Post first tweet via `POST https://api.twitter.com/2/tweets`
2. Post each subsequent tweet with `reply.in_reply_to_tweet_id` set to the previous tweet's ID
3. On failure mid-thread: report posted tweets with URLs, output remaining tweets as text

**Graceful degradation triggers:**
- Missing env vars → output text
- 401/403 (auth failure) → output text, show error
- 429 (rate limit) → output text, show retry-after
- Network timeout → output text, show error

### Discord Webhook

Same curl pattern as discord-content but with `allowed_mentions`:

```json
{
  "content": "<generated post>",
  "username": "Sol",
  "avatar_url": "https://soleur.ai/images/logo-mark-512.png",
  "allowed_mentions": {"parse": []}
}
```

### Brand Guide Channel Notes (New Sections)

Exact heading strings (skill parses by heading contract):
- `### X/Twitter` — Thread format, 280-char limit, hook-first, numbering convention, link placement
- `### IndieHackers` — Building update format, transparent metrics, markdown support
- `### Reddit` — Subreddit targets (r/ClaudeAI, r/SaaS, r/solopreneur), self-post vs. link-post guidance, anti-self-promotion norms
- `### Hacker News` — Title conventions, "Show HN" vs. direct submit guidance, no marketing language

### Approval Flow

```
1. Show all 5 variants in a summary view
2. For each platform with API posting (Discord, X/Twitter):
   - AskUserQuestion: Accept / Edit / Skip
   - Accept → post immediately
   - Edit → regenerate with feedback, re-present
   - Skip → move to next platform
3. For manual platforms (IndieHackers, Reddit, HN):
   - Output formatted text to terminal
   - Optionally write to file
4. Show distribution summary (posted, skipped, manual)
```

### File Registration (6-file checklist)

New skill requires updates to:
1. `plugins/soleur/skills/social-distribute/SKILL.md` — Skill definition
2. `plugins/soleur/docs/_data/skills.js` — Add to `SKILL_CATEGORIES` map
3. `plugins/soleur/README.md` — Update skill count and add to skill table
4. `plugins/soleur/plugin.json` — Update description skill count only (NOT version)
5. Root `README.md` — Update skill count
6. `knowledge-base/overview/brand-guide.md` — Update component counts if referenced

## Acceptance Criteria

- [ ] `/soleur:social-distribute <path>` generates 5 platform variants from a blog post
- [ ] Template variables (`{{ stats.agents }}` etc.) are resolved to actual values in all variants
- [ ] Discord post includes `allowed_mentions: {parse: []}` in webhook payload
- [ ] Discord post sent via webhook after user approval
- [ ] X/Twitter thread posted via API after user approval (or text output if no keys/API failure)
- [ ] IndieHackers, Reddit, HN formatted text output to terminal
- [ ] Rejection of one platform skips it without aborting others
- [ ] Brand guide has `### X/Twitter`, `### IndieHackers`, `### Reddit`, `### Hacker News` channel notes
- [ ] Post-publish distribution checklist exists at `knowledge-base/marketing/post-publish-distribution.md`
- [ ] CaaS blog article inaccuracies fixed (wrong Lovable link, duplicate WhatsApp paragraph, verify 9K plugins claim)
- [ ] Skill registered in skills.js and skill counts updated across repo
- [ ] `--headless` flag supported for autonomous invocation

## Test Scenarios

- Given a valid blog post path with template variables, when social-distribute runs, then all variants contain resolved numbers (not `{{ stats.agents }}`)
- Given no `X_API_KEY` env var, when social-distribute runs, then X/Twitter variant is output as text (no API call attempted)
- Given a Discord webhook that returns 500, when posting, then the skill outputs the draft text and shows the error
- Given user selects "Skip" for Discord, when approval continues, then X/Twitter and manual platforms still proceed
- Given `--headless` flag, when invoked, then all platforms are auto-approved and posted/output without AskUserQuestion prompts
- Given a blog post with `<script>` JSON-LD block, when generating variants, then no schema markup appears in any social post
- Given X/Twitter thread posting where tweet 4 of 7 fails, then tweets 1-3 are reported with URLs and tweets 5-7 are output as text

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| X/Twitter account doesn't exist yet | Can't test API posting | Skill degrades to text output; X integration is additive |
| Brand guide channel notes don't exist yet | Can't generate brand-consistent variants | Write notes in Phase 1 before building skill |
| discord-content has `allowed_mentions` bug | Inconsistency if not fixed | Fix as part of this PR |
| Content repurposing table only has 3 articles | Skill works without it (table is optional editorial context) | Skill generates variants from article content alone; table is bonus |

## References

### Internal

- discord-content skill pattern: `plugins/soleur/skills/discord-content/SKILL.md`
- Copywriter agent: `plugins/soleur/agents/marketing/copywriter.md`
- Brand guide (channel notes): `knowledge-base/overview/brand-guide.md:128`
- Content repurposing table: `knowledge-base/overview/content-strategy.md:234`
- Stats data: `plugins/soleur/docs/_data/stats.js`
- Site data: `plugins/soleur/docs/_data/site.json`
- Brainstorm: `knowledge-base/brainstorms/2026-03-06-social-distribute-brainstorm.md`
- Spec: `knowledge-base/specs/feat-social-distribute/spec.md`

### Learnings Applied

- `2026-02-18-skill-cannot-invoke-skill.md` — Skills can't call skills; inline Discord posting
- `2026-03-05-discord-allowed-mentions.md` — Always include `allowed_mentions` in webhook payloads
- `2026-02-12-brand-guide-contract.md` — Inline brand voice validation, no separate phase
- `2026-02-19-discord-bot-identity.md` — Webhook payloads must include explicit `username` and `avatar_url`
- `2026-02-22-new-skill-creation-lifecycle.md` — 6-file registration checklist
- `2026-02-22-skill-count-propagation.md` — Grep old count across repo before updating
- `2026-03-03-headless-mode.md` — Support `--headless` for autonomous invocation
- `2026-02-18-token-env-var-not-cli-arg.md` — Secrets via env vars, never CLI args
