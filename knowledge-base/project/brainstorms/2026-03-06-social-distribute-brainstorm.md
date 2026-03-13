---
date: 2026-03-06
status: decided
issue: "#457"
branch: feat-social-distribute
---

# Social Distribution Workflow Brainstorm

## What We're Building

A single `social-distribute` skill that closes the operational gap between publishing blog content and distributing it across social channels. The first blog article ("What Is Company-as-a-Service?") was published 2026-03-05 with zero social distribution because no workflow, accounts, or automation exist.

### Two parallel deliverables:

1. **Blog accuracy audit** -- Deep verification of all claims, statistics, and links in the CaaS article before wider distribution.
2. **Social distribution system** -- A skill + supporting artifacts that generate platform-specific content variants from a published article and post to channels with API access.

## Why This Approach

### Problem

The marketing strategy and content strategy both describe social distribution as a step ("Share articles on X/Twitter, IndieHackers, HN" -- content-strategy.md Week 2). But 7 operational links are missing between "article deployed" and "article shared":

1. No trigger after blog merge
2. No workflow to decide "now distribute"
3. No content adaptation for each platform
4. Social accounts don't exist (except Discord webhook)
5. Only Discord has posting infrastructure (discord-content skill)
6. No engagement monitoring
7. No performance feedback loop

### Approach selected: Single `social-distribute` skill (Approach A)

Evaluated 3 approaches:

- **A: Single skill** -- One skill handles all platforms. Simple, YAGNI-friendly. **Selected.**
- **B: Channel-specific skills** -- Separate skills per platform. More modular but premature given 1 founder and 1-2 articles/week.
- **C: CI-triggered pipeline** -- GitHub Action auto-distributes. Most automated but hardest to review content pre-post.

Approach A was selected because: solo founder, low article cadence, YAGNI. If a channel becomes complex enough, extract it later.

### Skill design

The `social-distribute` skill will:
- Read a published blog article (by path or URL)
- Read the content repurposing table from content-strategy.md
- Read brand guide channel notes for each target platform
- Generate platform-specific variants: X/Twitter thread, Discord post, IndieHackers update, Reddit post, HN submission title
- Post to Discord via existing webhook
- Post to X/Twitter via API (when account + API keys exist; graceful degradation to text output)
- Output formatted text for manual platforms (IndieHackers, Reddit, HN)
- User approval before each post (mirrors discord-content pattern)

### Dependencies

| Dependency | Status | Blocker? |
|-----------|--------|----------|
| Discord webhook | Exists (discord-content skill) | No |
| X/Twitter account | Does not exist | Yes, for X posting only |
| X/Twitter API keys | Does not exist | Yes, for X posting only |
| Brand guide channel notes (X, IH, Reddit, HN) | Only Discord exists | Yes, for brand-consistent output |
| Content repurposing table | Exists in content-strategy.md | No |
| Copywriter agent | Exists, can write platform-specific copy | No |

## Key Decisions

1. **Single skill, not multiple** -- One `social-distribute` skill handles all platforms. Extract per-channel skills only if needed.
2. **Full automation where possible** -- Post to Discord (webhook) and X (API) automatically. Manual copy-paste for platforms without APIs.
3. **Brand guide extension required** -- Add channel notes for X/Twitter, IndieHackers, Reddit, HN before building the skill.
4. **Post-publish checklist as interim** -- While the skill is being built, a markdown checklist prevents distribution from being forgotten.
5. **Blog audit first** -- Fix inaccuracies before distributing the CaaS article more widely.
6. **Graceful degradation for X** -- Skill generates X thread content even without API keys. Posts when keys are configured, outputs text otherwise.

## Open Questions

1. What X/Twitter handle? (@soleur, @soleur_ai, @getsoleur?)
2. Should the post-publish checklist be a standalone document or embedded in the content-strategy?
3. Should the skill also handle article updates (re-distribute when an article is significantly revised)?
4. What's the approval flow? One approval for all platforms or per-platform?

## Capability Gaps

| Gap | Domain | What's Missing | Why Needed |
|-----|--------|---------------|------------|
| Brand guide social channel notes | Marketing | X/Twitter, IndieHackers, Reddit, HN voice/format guidance | Copywriter agent needs platform-specific guidance to produce brand-consistent social content |
| X/Twitter posting infrastructure | Marketing | Account, API keys, posting mechanism | Second-highest-priority channel for validation phase after Discord |
| Post-publish trigger | Engineering | No automation connects blog merge to distribution workflow | Currently relies on founder memory to trigger distribution |

## Deliverables Summary

| Deliverable | Type | Priority |
|-------------|------|----------|
| Blog deep accuracy audit (CaaS article) | Content fix | P0 -- before any distribution |
| Brand guide channel notes (X, IH, Reddit, HN) | Brand guide update | P1 -- prerequisite for skill |
| Post-publish distribution checklist | Knowledge-base document | P1 -- interim until skill exists |
| `social-distribute` skill | New skill | P1 -- core deliverable |
| X/Twitter account creation | Manual founder action | P1 -- required for X automation |
