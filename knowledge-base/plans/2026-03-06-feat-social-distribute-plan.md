---
title: "feat: social distribution workflow for blog content"
type: feat
date: 2026-03-06
issue: 458
pr: 457
branch: feat-social-distribute
semver: minor
---

# Social Distribution Workflow

## Overview

Build a `social-distribute` skill that takes a published blog article and generates platform-specific content variants for 5 social channels, posting to Discord (webhook) automatically and outputting formatted text for X/Twitter, IndieHackers, Reddit, and Hacker News. Also fix inaccuracies in the CaaS blog article and extend the brand guide with channel notes for Discord and X/Twitter.

[Updated 2026-03-06: X/Twitter API posting deferred to v2 -- account doesn't exist yet. Headless mode deferred. Distribution checklist doc cut. IndieHackers/Reddit/HN channel notes deferred until posting history exists.]

## Problem Statement

The first blog article shipped 2026-03-05 with zero social distribution. The marketing strategy describes distribution as a step but no executable workflow exists. The discord-content skill handles Discord only. No skill covers multi-platform distribution.

## Proposed Solution

A single `social-distribute` skill following the discord-content pattern (prerequisites -> generate -> approve -> post) expanded to 5 platforms. Brand guide gets channel notes for Discord and X/Twitter. Blog article gets an accuracy fix pass.

### Architecture

```
User invokes /soleur:social-distribute <blog-path>

  1. Prerequisites check (brand guide, Discord webhook env var)
  2. Read blog post, pass content + current stats as context
  3. Read brand guide Voice + Channel Notes per platform
  4. Generate 5 variants (LLM handles content adaptation)
  5. Present all variants, approval for Discord only
  6. Post to Discord (webhook)
  7. Output formatted text for X/Twitter, IndieHackers, Reddit, HN
```

### Key design decisions from research

| Decision | Rationale | Source |
|----------|-----------|--------|
| Inline Discord posting (don't call discord-content) | Skills cannot invoke other skills | `implementation-patterns/2026-02-18-skill-cannot-invoke-skill.md` |
| Include `allowed_mentions: {parse: []}` in webhook | Constitution mandate + discord-content has this bug | `2026-03-05-discord-allowed-mentions.md` |
| Inline brand voice validation (no separate phase) | Three independent reviews killed the separate validator idea | `2026-02-12-brand-guide-contract.md` |
| Sequential per-platform approval | Matches discord-content pattern; rejection skips platform, doesn't abort | SpecFlow analysis |
| Pass current stats as LLM context (not template resolution) | Blog source has `{{ stats.agents }}` 8+ times; LLM handles naturally with context | Plan review simplification |
| LLM ignores markup artifacts with prompt instruction | JSON-LD and FAQ accordions are meaningless in social posts; no preprocessing needed | Plan review simplification |

## Technical Considerations

### Template Variable Handling

Blog posts contain Nunjucks variables (`{{ stats.agents }}`, `{{ site.url }}`). Rather than reimplementing template resolution, the skill:
1. Runs simple shell commands to get current counts: `find agents -name '*.md' | wc -l` etc.
2. Reads `plugins/soleur/docs/_data/site.json` for `site.url`
3. Passes the raw article content plus current stats as context to the LLM generation prompt
4. The LLM naturally substitutes the correct values when generating social variants

No preprocessing pipeline needed — the LLM handles markup stripping, table normalization, and variable substitution implicitly via prompt instruction.

### X/Twitter (Deferred to v2)

X/Twitter API posting is deferred until an account and API keys exist. In v1, the skill generates an X/Twitter thread as formatted text output. When API integration is added later, it will use OAuth 1.0a with env vars: `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`.

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
- IndieHackers, Reddit, HN channel notes deferred until posting history exists (v2)

### Approval Flow

```
1. Show all 5 variants in a summary view
2. For Discord:
   - AskUserQuestion: Accept / Edit / Skip
   - Accept → post via webhook
   - Edit → regenerate with feedback, re-present
   - Skip → move to manual output
3. For all other platforms (X/Twitter, IndieHackers, Reddit, HN):
   - Output formatted text to terminal
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

## Non-Goals

- X/Twitter API posting (deferred to v2 when account exists)
- Headless/autonomous mode (deferred until generation quality is validated)
- Distribution checklist document (the skill IS the checklist)
- IndieHackers/Reddit/HN brand guide channel notes (write after posting history exists)
- Engagement monitoring or analytics
- Scheduled posting / delayed publishing
- Email newsletter distribution

## Rollback Plan

All changes are additive (new skill, new brand guide sections, blog fixes). Rollback = revert the PR. No data migrations, no infrastructure changes.

## Affected Teams

Solo founder only. No external dependencies. Discord webhook already exists and is used by discord-content and release-announce.

## Acceptance Criteria

- [ ] `/soleur:social-distribute <path>` generates 5 platform variants from a blog post
- [ ] All variants contain actual numbers, not template syntax like `{{ stats.agents }}`
- [ ] Discord post includes `allowed_mentions: {parse: []}` in webhook payload
- [ ] Discord post sent via webhook after user approval
- [ ] X/Twitter, IndieHackers, Reddit, HN formatted text output to terminal
- [ ] Skipping Discord continues to manual platform output
- [ ] Brand guide has `### X/Twitter` channel notes
- [ ] CaaS blog article inaccuracies fixed (wrong Lovable link, duplicate WhatsApp paragraph)
- [ ] discord-content skill's missing `allowed_mentions` fixed
- [ ] Skill registered in skills.js and skill counts updated across repo

## Test Scenarios

- Given a valid blog post path with template variables, when social-distribute runs, then all variants contain resolved numbers
- Given no `DISCORD_WEBHOOK_URL` env var, when social-distribute runs, then Discord is skipped and manual output proceeds
- Given a Discord webhook that returns 500, when posting, then the skill outputs the draft text and shows the error
- Given user selects "Skip" for Discord, when approval continues, then manual platform output still proceeds
- Given a blog post with `<script>` JSON-LD block, when generating variants, then no schema markup appears in any social post

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| X/Twitter account doesn't exist yet | Can't test API posting | Text output only in v1; API posting is a v2 follow-up |
| Brand guide X/Twitter channel notes don't exist yet | Can't generate brand-consistent X variants | Write notes in Phase 1 before building skill |
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
- `2026-02-18-token-env-var-not-cli-arg.md` — Secrets via env vars, never CLI args
