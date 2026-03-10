---
title: "feat: add X engagement guardrails to brand guide"
type: feat
date: 2026-03-10
---

# feat: add X engagement guardrails to brand guide

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

## Proposed Solution

Add a single `#### Engagement Guardrails` heading under the existing `### X/Twitter` section in `brand-guide.md`, between the current prose guidance (line ~165) and the `#### Profile Banner` sub-heading (line ~167). The section covers four areas:

### 1. Topics to Avoid

Explicit list of topics the account does not engage with on X:
- Political or partisan topics
- Competitor criticism or comparisons (state what Soleur does, never what others lack)
- Unverified claims or speculation about roadmap dates
- Anything requiring legal review (pricing commitments, data handling details beyond what the privacy policy states)

### 2. When to Skip Mentions/Threads

Criteria for skipping a mention rather than replying:
- Abusive, harassing, or spam content
- Off-topic mentions with no connection to Soleur or solo-founder topics
- Rage-bait or provocative threads designed to generate outrage
- Likely bot accounts (no profile image, alphanumeric handle, zero followers)
- Threads where replying would amplify negative sentiment
- Mentions that are simply retweets or quote-tweets of Soleur content (engagement through the RT is sufficient)

### 3. Reply Cadence

Guardrails for reply pacing:
- Maximum 10 replies per engagement session (matches `--max-results` default in `fetch-mentions`)
- Default to skipping when unsure -- silence is safer than a misaligned reply
- One reply per thread -- do not enter extended back-and-forth conversations on X (escalate to Discord or docs for complex questions)

### 4. Tone Matching

Additional tone guidance specific to engagement replies:
- Match the register of the original tweet (technical question gets a technical answer, casual mention gets a concise acknowledgment)
- Never argue or debate -- state the position once, then disengage
- Redirect complex questions to docs or Discord rather than attempting a 280-character answer
- Credit the person's insight when replying to feature suggestions ("Solid idea. Filed as #N." not "Thanks for the feedback!")

## Technical Considerations

### Brand Guide Heading Contract

The brand guide's heading contract (from learning `2026-02-12-brand-guide-contract-and-inline-validation.md`) defines required headings at the `##` level. The new `#### Engagement Guardrails` heading is nested under the existing `### X/Twitter` (which is under `## Channel Notes`). This does not modify the top-level contract.

The community-manager agent already reads `## Channel Notes > ### X/Twitter` for tone guidance. The new `#### Engagement Guardrails` sub-heading falls within this section and will be read as part of the same context. No agent code changes are required -- the agent reads the full `### X/Twitter` section, and the new content becomes available automatically.

### Downstream Consumers

Two components currently read `### X/Twitter`:

1. **community-manager agent** (Capability 4, Step 2: Read Brand Guide) -- reads `## Voice` and `## Channel Notes > ### X/Twitter` for draft generation. The guardrails add "when NOT to reply" context that improves draft quality and skip decisions.

2. **social-distribute skill** -- reads brand guide for thread formatting. The guardrails section is about engagement replies, not broadcasting, so this consumer is unaffected.

### No Code Changes

This is a documentation-only change. The guardrails become effective through the community-manager agent's existing Read step -- no script, skill, or agent file modifications are needed.

## Non-Goals

- Modifying the community-manager agent's instructions (the agent already reads the full `### X/Twitter` section)
- Adding automated enforcement of guardrails (the human reviewer is the enforcement mechanism)
- Moderation tooling or blocklist management
- Guardrails for platforms other than X/Twitter (Discord has separate norms in `### Discord`)
- Reply templates or canned responses

## Acceptance Criteria

- [ ] `#### Engagement Guardrails` section exists under `### X/Twitter` in `knowledge-base/overview/brand-guide.md`
- [ ] Section covers: topics to avoid, when to skip, reply cadence, tone matching
- [ ] Heading contract preserved -- `## Voice`, `## Channel Notes`, `### X/Twitter` headings unchanged
- [ ] `#### Profile Banner` sub-heading remains below the new section (document structure intact)
- [ ] Content follows brand guide writing conventions (imperative/infinitive form, no second person)

## Test Scenarios

- Given the brand guide exists with `### X/Twitter`, when the guardrails section is added, then it appears between the existing X/Twitter prose and the Profile Banner sub-heading
- Given the community-manager agent reads `### X/Twitter`, when it processes the updated brand guide, then the guardrails content is available in its context without code changes
- Given a mention about a political topic, when the human reviewer reads the guardrails, then the "Topics to Avoid" list provides a clear basis for skipping
- Given 15 mentions are fetched, when the reviewer applies the cadence guardrail, then they know to process at most 10 and skip the rest

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
- `knowledge-base/plans/2026-03-10-feat-x-engage-dogfood-graceful-degradation-plan.md` -- split source (Task 3 removed, filed as #503)
- Issue: #503
