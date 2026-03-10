---
title: "feat: add X engagement guardrails to brand guide"
type: feat
date: 2026-03-10
---

# feat: add X engagement guardrails to brand guide

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 6
**Research sources:** Hootsuite brand safety guide, Avenue Z X organic guide, Willow brand rules, Brand Safety Institute, 5 institutional learnings, constitution.md, existing codebase patterns

### Key Improvements
1. Added "brand association risk" as a skip criterion -- any interaction with an account ties Soleur's brand to that account's content (Hootsuite brand safety research)
2. Added anti-automation pacing guidance -- X's algorithm penalizes rapid-fire bursts that look automated, validating the cadence guardrail with platform-specific reasoning (Avenue Z 2026 guide)
3. Added "religion and sex" to topics-to-avoid alongside politics -- industry standard per Willow/Brand Safety Institute research
4. Added manual-mode applicability note -- guardrails apply equally in automatic (fetch-mentions) and manual (Free tier 403 fallback) modes, per learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`
5. Added exception rule pattern for topic bans -- learning `2026-02-21-marketing-audit-brand-violation-cascade.md` shows that blanket prohibitions without exception rules break legitimate contexts

### Applied Learnings
- `2026-02-12-brand-guide-contract-and-inline-validation.md` -- heading contract preserved, inline validation pattern means no separate enforcement agent needed
- `2026-02-21-marketing-audit-brand-violation-cascade.md` -- term bans need boundary exception rules; guardrails should state exceptions at the same time as prohibitions
- `2026-02-22-agent-context-blindness-vision-misalignment.md` -- agents that produce content must read canonical sources; guardrails become part of the canonical source the community-manager reads
- `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- Free tier manual mode means guardrails must not assume automatic fetch-mentions context
- `2026-03-09-external-api-scope-calibration.md` -- X API scope constraints inform guardrail design (10 mentions/session aligns with API credit conservation)

## Overview

Add an `#### Engagement Guardrails` subsection under `### X/Twitter` in `knowledge-base/overview/brand-guide.md`. This section codifies rules for topics to avoid, when to skip mentions/threads, reply cadence, and tone guidance for X engagement.

**Issue:** #503
**Split from:** #496 (graceful degradation plan review identified guardrails as orthogonal)

## Problem Statement / Motivation

The community-manager agent's Capability 4 (Mention Engagement) drafts replies using brand voice from `## Voice` and `## Channel Notes > ### X/Twitter`. However, the brand guide currently provides only positive guidance (what to say, how to say it) with no negative guardrails (what to avoid, when to stay silent).

Without guardrails:
- The agent has no signal for when NOT to reply (spam, rage-bait, political topics)
- Reply cadence is unbounded -- rapid consecutive replies look automated
- Tone matching is undefined -- a casual mention and a formal complaint get the same reply style
- The human reviewer has no documented criteria for what constitutes a "skip"

The guardrails section gives both the community-manager agent and the human reviewer a shared reference for engagement boundaries.

### Research Insights: Motivation

**Best Practices (from Hootsuite brand safety guide):**
- Brand safety is defined as "a set of measures taken to protect a brand's image and reputation from being associated with inappropriate, offensive, or harmful content." This applies to engagement replies, not just ad placement -- any interaction ties the brand to the content being replied to.
- The "dirty dozen" industry-standard exclusion categories (military conflict, hate speech, terrorism, fake news, etc.) provide a baseline, but "not every category applies equally to every brand." Soleur should define its own boundaries.

**Best Practices (from Willow brand rules):**
- Brands must "avoid the robotic tone" -- engagement must sound human, which is especially relevant for AI-generated drafts.
- Cultural sensitivity is paramount: "be cautious when discussing sensitive topics such as religion, sex, and politics."

**Platform Behavior (from Avenue Z 2026 guide):**
- X's algorithm filters aggressively for patterns that look automated: "repetitive posting, copy-paste threads, engagement bait, or rapid-fire bursts." This provides a platform-level reason for the cadence guardrail beyond brand safety -- X may suppress replies that come too fast.

## Proposed Solution

Add a single `#### Engagement Guardrails` heading under the existing `### X/Twitter` section in `brand-guide.md`, between the current prose guidance (line ~165) and the `#### Profile Banner` sub-heading (line ~167). The section covers four areas.

**Applicability:** These guardrails apply in both automatic mode (fetch-mentions) and manual mode (Free tier 403 fallback where the user pastes tweet URLs). The human reviewer is the enforcement mechanism in both cases.

### 1. Topics to Avoid

Explicit list of topics the account does not engage with on X:
- Political, partisan, or religiously divisive topics
- Competitor criticism or comparisons (state what Soleur does, never what others lack)
- Unverified claims or speculation about roadmap dates
- Anything requiring legal review (pricing commitments, data handling details beyond what the privacy policy states)
- Trending hashtags or memes with unclear associations -- meanings shift fast, and a hashtag that looks harmless can be tied to controversial communities

**Exception:** Engaging with the #solofounder, #buildinpublic, and AI/developer tooling communities is encouraged even when those conversations touch on industry trends. The prohibition targets partisan, religious, and inflammatory topics, not the broader tech ecosystem.

### Research Insights: Topics to Avoid

**Best Practices:**
- The Hootsuite "dirty dozen" provides an industry baseline of 12 content categories to exclude from brand association. For a developer-tools brand like Soleur, the most relevant exclusions are: hate speech, fake news, military conflict, and terrorism. Categories like adult content and drugs are unlikely to intersect with Soleur's mention stream but should still trigger a skip if encountered.
- Willow's research emphasizes that some brands (like Nike) have taken calculated risks on controversial topics. This is a deliberate strategic choice, not a default. For an early-stage brand, the cost of a misaligned engagement far outweighs the visibility benefit.
- Learning `2026-02-21-marketing-audit-brand-violation-cascade.md` demonstrates that term bans need exception rules written at the same time as the prohibition. The plan's "Exception" paragraph above follows this pattern.

**Edge Cases:**
- A mention asking "How does Soleur compare to [competitor]?" is a comparison question, not competitor criticism. The guardrail applies to Soleur's reply content (do not criticize the competitor), not to the question topic itself. The reply should focus on what Soleur does without referencing the competitor.
- A trending hashtag (#buildinpublic) that temporarily becomes controversial does not permanently ban engagement with that hashtag. Evaluate per-session.

### 2. When to Skip Mentions/Threads

Criteria for skipping a mention rather than replying:
- Abusive, harassing, or spam content
- Off-topic mentions with no connection to Soleur or solo-founder topics
- Rage-bait or provocative threads designed to generate outrage
- Likely bot accounts (no profile image, alphanumeric handle, zero followers)
- Threads where replying would amplify negative sentiment
- Mentions that are simply retweets or quote-tweets of Soleur content (engagement through the RT is sufficient)
- Accounts whose recent content creates brand association risk -- any reply ties Soleur to that account's content

### Research Insights: When to Skip

**Best Practices:**
- Hootsuite: "Any interaction with a creator -- whether a paid collaboration or a simple comment -- ties your brand to their content." Before replying, glance at the account's recent posts. If the account's content includes hate speech, misinformation, or inflammatory material, replying creates a visible association.
- Willow: "For trolls: the best policy is often not to engage. Do not get into a public argument." The existing brand guide already says "Never argue or debate" -- the skip criteria operationalize this for the pre-reply decision.
- X's "Hide Reply" feature can be used for replies on Soleur's own tweets that are abusive, but this is a reactive tool, not a replacement for the skip decision on mentions.

**Edge Cases:**
- A legitimate user asks a genuine question but their account also has unrelated controversial content. Judgment call: reply if the mention itself is on-topic and professional. The skip criterion targets accounts that are primarily provocative, not accounts that occasionally post opinions.
- A mention @-tags Soleur alongside other accounts in a group complaint. Replying enters a multi-party thread where control is lost. Default to skip unless the complaint is specifically about Soleur.

### 3. Reply Cadence

Guardrails for reply pacing:
- Maximum 10 replies per engagement session (matches `--max-results` default in `fetch-mentions`)
- Default to skipping when unsure -- silence is safer than a misaligned reply
- One reply per thread -- do not enter extended back-and-forth conversations on X (escalate to Discord or docs for complex questions)
- Space replies naturally -- do not post 10 replies in 2 minutes

### Research Insights: Reply Cadence

**Best Practices:**
- Avenue Z 2026 guide: X's algorithm filters aggressively for "rapid-fire bursts that feel automated." Even if the content is high-quality, posting many replies in quick succession triggers algorithmic suppression. This validates spacing replies rather than posting all 10 immediately.
- The community skill's `--max-results` default of 10 aligns with the cadence guardrail. If the user overrides with `--max-results 50`, the cadence guardrail (max 10 replies per session) takes precedence over the fetch count. The extra mentions are presented for review but most should be skipped.

**Performance Considerations:**
- X API credit conservation (learning `2026-03-09-external-api-scope-calibration.md`): On the pay-per-use tier, each reply costs credits. The 10-reply cap also serves as an implicit cost control. On the Free tier (manual mode), the cap prevents rapid manual posting that looks automated.

**Edge Cases:**
- If all 10 fetched mentions are from the same user (e.g., a bug report thread), reply to the most recent one and skip the rest. Multiple replies to the same user in a session looks like spam.
- "One reply per thread" means the first engagement in a thread. If the user had previously replied in a thread in a past session, it is acceptable to reply again in a new session -- the guideline prevents same-session back-and-forth, not lifetime thread participation.

### 4. Tone Matching

Additional tone guidance specific to engagement replies:
- Match the register of the original tweet (technical question gets a technical answer, casual mention gets a concise acknowledgment)
- Never argue or debate -- state the position once, then disengage
- Redirect complex questions to docs or Discord rather than attempting a 280-character answer
- Credit the person's insight when replying to feature suggestions ("Solid idea. Filed as #N." not "Thanks for the feedback!")
- Maintain a human voice -- avoid phrases that sound templated or auto-generated

### Research Insights: Tone Matching

**Best Practices:**
- Willow: "Avoid the robotic tone! Speak as a human would." This is especially critical for AI-drafted replies. The community-manager agent generates drafts, and the human reviewer must verify the draft does not sound like a chatbot response.
- Willow: "B2C brands can be warm and welcoming; B2B companies in serious sectors should maintain professionalism while remaining approachable." Soleur sits in between -- it is a developer tool (B2B-adjacent) but targets solo founders (B2C energy). The existing brand voice ("declarative, concrete, no hedging") already captures the right balance.
- Hootsuite: "Conduct a background check on [content] and associations" before engaging. For tone matching, this means: if the mention is from a well-known developer or community figure, the reply's register should reflect awareness of that context (concise and respectful, not over-explained).

**Edge Cases:**
- A sarcastic mention ("Oh great, another AI tool") can be read as dismissive or as genuine skepticism. Default to treating it as genuine skepticism and replying with a concrete differentiator. Do not match sarcasm with sarcasm.
- Feature requests phrased as complaints ("Why doesn't Soleur do X?") should receive the same treatment as genuine feature suggestions. Acknowledge, file if valid, redirect to docs if it already exists.

## Technical Considerations

### Brand Guide Heading Contract

The brand guide's heading contract (from learning `2026-02-12-brand-guide-contract-and-inline-validation.md`) defines required headings at the `##` level. The new `#### Engagement Guardrails` heading is nested under the existing `### X/Twitter` (which is under `## Channel Notes`). This does not modify the top-level contract.

The community-manager agent already reads `## Channel Notes > ### X/Twitter` for tone guidance. The new `#### Engagement Guardrails` sub-heading falls within this section and will be read as part of the same context. No agent code changes are required -- the agent reads the full `### X/Twitter` section, and the new content becomes available automatically.

### Research Insights: Heading Contract

**Best Practices:**
- Learning `2026-02-12-brand-guide-contract-and-inline-validation.md`: "Contracts beat schemas for human-produced documents." The `####` level heading is below the contract threshold (`##`), so it can be added, renamed, or restructured without breaking downstream consumers.
- Learning `2026-02-22-agent-context-blindness-vision-misalignment.md`: Agents that produce content must read canonical sources before making decisions. The guardrails section becomes part of the canonical source the community-manager agent reads at Step 2 (Read Brand Guide). No code changes are needed because the agent reads the full `### X/Twitter` section, not specific sub-headings within it.

**Edge Cases:**
- If the `### X/Twitter` section grows too large for the agent's context window, the guardrails could be the content that pushes it over. Current `### X/Twitter` is ~30 lines; the guardrails add ~25-30 lines. At ~60 lines total, this is well within a single context read. Monitor if future additions to the X/Twitter section approach 100+ lines.

### Downstream Consumers

Two components currently read `### X/Twitter`:

1. **community-manager agent** (Capability 4, Step 2: Read Brand Guide) -- reads `## Voice` and `## Channel Notes > ### X/Twitter` for draft generation. The guardrails add "when NOT to reply" context that improves draft quality and skip decisions.

2. **social-distribute skill** -- reads brand guide for thread formatting. The guardrails section is about engagement replies, not broadcasting, so this consumer is unaffected.

### No Code Changes

This is a documentation-only change. The guardrails become effective through the community-manager agent's existing Read step -- no script, skill, or agent file modifications are needed.

### Research Insights: No Code Changes

**Validation:** The inline validation pattern (learning `2026-02-12`) confirms that no separate enforcement agent is needed. The community-manager agent reads the brand guide inline during Step 2 and applies it during Step 3 (Draft Replies). Adding content to the brand guide is sufficient -- the agent's existing instructions already say to follow the `### X/Twitter` section.

**Manual mode note:** In the Free tier 403 fallback (learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`), the community-manager agent enters manual mode where the user pastes tweet URLs. The agent still reads the brand guide in Step 2 before drafting replies, so the guardrails apply to manual-mode drafts as well. No additional code path is needed.

## Non-Goals

- Modifying the community-manager agent's instructions (the agent already reads the full `### X/Twitter` section)
- Adding automated enforcement of guardrails (the human reviewer is the enforcement mechanism)
- Moderation tooling or blocklist management
- Guardrails for platforms other than X/Twitter (Discord has separate norms in `### Discord`)
- Reply templates or canned responses
- Algorithmic optimization (posting times, hashtag strategy) -- that belongs in a growth/distribution plan, not guardrails

## Acceptance Criteria

- [ ] `#### Engagement Guardrails` section exists under `### X/Twitter` in `knowledge-base/overview/brand-guide.md`
- [ ] Section covers: topics to avoid, when to skip, reply cadence, tone matching
- [ ] Topics to avoid includes exception clause for legitimate tech ecosystem conversations
- [ ] When to skip includes brand association risk criterion
- [ ] Reply cadence includes anti-automation spacing guidance
- [ ] Heading contract preserved -- `## Voice`, `## Channel Notes`, `### X/Twitter` headings unchanged
- [ ] `#### Profile Banner` sub-heading remains below the new section (document structure intact)
- [ ] Content follows brand guide writing conventions (imperative/infinitive form, no second person)
- [ ] Guardrails apply to both automatic (fetch-mentions) and manual (403 fallback) modes -- no mode-specific language

## Test Scenarios

- Given the brand guide exists with `### X/Twitter`, when the guardrails section is added, then it appears between the existing X/Twitter prose and the Profile Banner sub-heading
- Given the community-manager agent reads `### X/Twitter`, when it processes the updated brand guide, then the guardrails content is available in its context without code changes
- Given a mention about a political topic, when the human reviewer reads the guardrails, then the "Topics to Avoid" list provides a clear basis for skipping
- Given 15 mentions are fetched, when the reviewer applies the cadence guardrail, then they know to process at most 10 and skip the rest
- Given a mention from an account with controversial recent content, when the reviewer applies the skip criteria, then the "brand association risk" criterion provides a basis for skipping
- Given a trending hashtag (#buildinpublic) that is part of Soleur's target community, when the reviewer reads the topics to avoid, then the exception clause clarifies that tech ecosystem engagement is encouraged
- Given the Free tier 403 fallback is active (manual mode), when the user pastes a tweet URL, then the agent still reads and applies the guardrails during reply drafting

## Semver Intent

`semver:patch` -- documentation update to an existing brand guide section. No new agents, commands, or skills.

## Files Changed

| File | Change |
|------|--------|
| `knowledge-base/overview/brand-guide.md` | Add `#### Engagement Guardrails` subsection under `### X/Twitter` |

## References

- `knowledge-base/overview/brand-guide.md` -- target file, current `### X/Twitter` section at lines 150-165
- `plugins/soleur/agents/support/community-manager.md` -- Capability 4 reads `### X/Twitter` for engagement
- `plugins/soleur/skills/community/SKILL.md` -- `engage` sub-command, `--max-results` default of 10
- `knowledge-base/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` -- heading contract pattern
- `knowledge-base/learnings/2026-02-21-marketing-audit-brand-violation-cascade.md` -- term bans need exception rules
- `knowledge-base/learnings/2026-02-22-agent-context-blindness-vision-misalignment.md` -- agents must read canonical sources
- `knowledge-base/learnings/2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- Free tier manual mode applicability
- `knowledge-base/learnings/2026-03-09-external-api-scope-calibration.md` -- X API credit conservation
- `knowledge-base/plans/2026-03-10-feat-x-engage-dogfood-graceful-degradation-plan.md` -- split source (Task 3 removed, filed as #503)
- [Hootsuite: 6 brand safety best practices](https://blog.hootsuite.com/brand-safety/)
- [Willow: 6 Essential Rules for Brands on X](https://www.willow.co/blog/6-rules-for-brands-on-twitter)
- [Avenue Z: 2025/2026 X Organic Social Media Guide for Brands](https://avenuez.com/blog/2025-2026-x-twitter-organic-social-media-guide-for-brands/)
- [Brand Safety Institute: X and Brand Safety](https://www.brandsafetyinstitute.com/resources/topics/twitter-brand-safety)
- Issue: #503
