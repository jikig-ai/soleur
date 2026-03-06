---
title: "feat: add citation verification to content pipeline"
type: feat
date: 2026-03-06
---

# Add Citation Verification to Content Pipeline

## Overview

Add a dedicated fact-checker agent and verification phase to the content-writer skill so that every factual claim, statistic, and attributed quote in generated blog articles is verified against its cited source URL before user approval. This prevents LLM-confabulated citations from reaching publication.

## Problem Statement / Motivation

The first published blog article ("What Is Company-as-a-Service?") contained 6 factual inaccuracies that passed both generation and human review:

1. Wrong citation URL (Lovable link pointed to a Cursor CNBC article)
2. Unverifiable statistic ("9,000 Claude Code plugins" -- source didn't support the claim)
3. Wrong number ("six domains" for Anthropic Cowork -- actual count was 10+)
4. Misattributed quote (Sam Altman quote sourced from a page that didn't contain it)
5. Duplicate paragraph (WhatsApp section appeared twice)
6. Wrong factual claim (Instagram "billion users" at acquisition -- actual was 30M users)

All errors were LLM-generated content published without source verification. The LLM that generates content cannot reliably self-verify its own citations -- a separate verification step is needed. The learning at `knowledge-base/learnings/2026-03-06-blog-citation-verification-before-publish.md` documents this incident.

## Proposed Solution

Three changes, ordered by dependency:

### 1. Fact-checker agent (`agents/marketing/fact-checker.md`)

A new marketing domain agent whose sole job is citation and claim verification. It extracts all URLs, statistics, quotes, and factual claims from a draft, fetches each cited URL via WebFetch, and confirms the page supports the specific claim cited. Returns a structured pass/fail verdict per claim.

### 2. Content-writer skill verification phase

Insert a new Phase 2.5 between draft generation (Phase 2) and user approval (Phase 3) in `plugins/soleur/skills/content-writer/SKILL.md`. This phase invokes the fact-checker agent via the Task tool, collects results, and annotates the draft presentation with verification status per claim.

```
Current:  Phase 2 (generate draft) -> Phase 3 (user approval)
Proposed: Phase 2 (generate draft) -> Phase 2.5 (verify citations) -> Phase 3 (user approval with verification status)
```

### 3. Constitution rule

Add a content verification rule to `knowledge-base/overview/constitution.md` under a new `## Content` section.

## Non-Goals

- Automated rewriting of failed claims (the user decides how to handle flagged claims)
- Verification of non-URL claims (e.g., general knowledge assertions without citations)
- Retroactive scanning of already-published content (regression test covers the fixed article only)
- Real-time verification during generation (verification runs as a post-generation batch)
- Extending verification to the social-distribute skill (social posts derive from already-verified articles)

## Technical Considerations

### Agent token budget

Current cumulative agent description word count is 2,454 (limit: 2,500). The fact-checker agent description must be kept to ~40 words maximum to stay under budget. Detailed instructions go in the agent body, not the description.

### Agent structure

The fact-checker agent follows the project's agent conventions:
- YAML frontmatter with `name`, `description` (routing text only), `model: inherit`
- Disambiguation sentence referencing the copywriter agent (adjacent scope in marketing domain)
- Body contains verification protocol, not examples or commentary

### Skill integration pattern

The content-writer skill currently has 4 phases (Prerequisites, Parse Input, Generate Draft, User Approval, Write to Disk). The verification phase inserts between Phase 2 and Phase 3 as Phase 2.5.

The skill already has a guideline at line 124: "Every factual claim, statistic, and attributed quote must have a verifiable source URL." This plan replaces that passive guideline with active enforcement via the fact-checker agent.

### WebFetch dependency

The fact-checker agent relies on WebFetch to retrieve cited URLs. WebFetch is already used by 11 files across the plugin (research agents, competitive intelligence, growth strategist, etc.). No new tool dependencies are introduced.

### Verification output contract

The fact-checker agent must produce a structured output with heading-level contract (per constitution preference for producer-consumer heading contracts):

```markdown
## Verification Report

### Verified Claims
- [claim text] -- Source: [URL] -- PASS

### Failed Claims
- [claim text] -- Source: [URL] -- FAIL: [reason]

### Unsourced Claims
- [claim text] -- No citation provided

### Summary
- Total claims: N
- Verified: N
- Failed: N
- Unsourced: N
```

### Content-writer presentation

During Phase 3 (User Approval), each claim in the draft gets a status indicator:
- PASS: claim verified against source
- FAIL: source does not support the claim (with reason)
- UNSOURCED: no citation provided for a quantitative or attributed claim

The user sees the verification summary before deciding Accept/Edit/Reject.

## Acceptance Criteria

- [ ] `plugins/soleur/agents/marketing/fact-checker.md` agent exists with WebFetch-based verification protocol
- [ ] Agent description is under 45 words and includes disambiguation sentence
- [ ] Agent cumulative description word count stays under 2,500
- [ ] `plugins/soleur/skills/content-writer/SKILL.md` includes Phase 2.5 that invokes fact-checker via Task tool
- [ ] Phase 2.5 passes the generated draft content to the fact-checker agent
- [ ] Each citation in a draft is fetched via WebFetch and verified (pass/fail per claim)
- [ ] Naked numbers (stats without source URLs) are flagged as UNSOURCED
- [ ] Attributed quotes are checked against the cited page content
- [ ] Verification report follows the structured heading contract
- [ ] User sees verification status per claim during Phase 3 approval
- [ ] Constitution rule added under `## Content` section
- [ ] `plugins/soleur/AGENTS.md` directory tree unchanged (marketing/ already exists)
- [ ] `plugins/soleur/AGENTS.md` CMO domain leader table updated if agent count changes
- [ ] README.md agent count verified after adding the new agent

## Test Scenarios

- Given a draft with a correct citation URL, when the fact-checker fetches the URL, then the claim is marked PASS with evidence from the page
- Given a draft with a citation URL that does not support the claim, when the fact-checker fetches the URL, then the claim is marked FAIL with the reason
- Given a draft with a statistic but no source URL, when the fact-checker scans the draft, then the claim is marked UNSOURCED
- Given a draft with an attributed quote, when the fact-checker fetches the cited URL, then it checks whether the quote text appears on the page
- Given the fact-checker encounters a URL that returns HTTP 4xx/5xx, when verification runs, then the claim is marked FAIL with "URL not reachable" (not silently skipped)
- Given a draft with zero citations (e.g., opinion piece), when the fact-checker runs, then it reports "No verifiable claims found" and Phase 3 proceeds normally
- Given the existing fixed blog article (CaaS), when the fact-checker runs against it, then all claims pass (regression test)

## Success Metrics

- Zero factual inaccuracies in future published articles that have fetchable source URLs
- Every quantitative claim in published content has a verified source
- Content-writer skill presents verification status before user approval

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| WebFetch rate limiting or timeouts on many URLs | Fetch sequentially with reasonable delays; mark timed-out URLs as FAIL with "timeout" reason |
| Agent description pushes over 2,500 word budget | Keep description to ~40 words; move all protocol details to agent body |
| False negatives (page content changed after citation) | Mark as FAIL -- the user decides whether the claim is still valid |
| WebFetch cannot render JavaScript-heavy pages | Accept this limitation; mark as FAIL with "page content not extractable" |
| Verification adds latency to content-writer workflow | Acceptable tradeoff -- verification runs once per draft, not per edit cycle |

## Semver Intent

`semver:minor` -- new agent and new skill phase (additive, no breaking changes).

## References & Research

### Internal References

- Learning: `knowledge-base/learnings/2026-03-06-blog-citation-verification-before-publish.md`
- Content-writer skill: `plugins/soleur/skills/content-writer/SKILL.md`
- Copywriter agent (sibling): `plugins/soleur/agents/marketing/copywriter.md`
- CMO agent (domain leader): `plugins/soleur/agents/marketing/cmo.md`
- Constitution: `knowledge-base/overview/constitution.md`
- Agent compliance checklist: `plugins/soleur/AGENTS.md`

### Related Work

- Issue: #459
- PR #457: Fixed 6 inaccuracies in CaaS blog article (the incident that motivated this)
- PR #458: Added social-distribute skill (latest marketing skill addition)
