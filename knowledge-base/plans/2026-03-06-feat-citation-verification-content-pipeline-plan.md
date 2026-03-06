---
title: "feat: add citation verification to content pipeline"
type: feat
date: 2026-03-06
---

# Add Citation Verification to Content Pipeline

## Enhancement Summary

**Deepened on:** 2026-03-06
**Sections enhanced:** 6
**Research sources:** 4 institutional learnings, agent-native-architecture skill, CMO delegation table analysis, agent compliance checklist, content-writer skill structure analysis

### Key Improvements
1. Added CMO delegation table update requirement -- fact-checker must be registered in `cmo.md` for the domain leader to route to it
2. Added disambiguation sentence requirements for 3 sibling agents (copywriter, growth-strategist, seo-aeo-analyst) -- both forward and reverse directions
3. Identified that no new skill registration is needed (modifying existing skill, not creating a new one) -- avoids the 6-file skill creation lifecycle
4. Specified claim extraction heuristics for the agent body to make verification deterministic
5. Added `--headless` bypass requirement for Phase 2.5 since content-writer may be invoked by pipelines

### Learnings Applied
- `2026-02-20-agent-description-token-budget-optimization.md`: Keep fact-checker description under 45 words, routing-only, no examples
- `2026-02-22-new-skill-creation-lifecycle.md`: No new skill registration needed (modifying existing content-writer)
- `adding-new-agent-domain-checklist.md`: Marketing domain already exists; only agent-level additions needed (README count, AGENTS.md count, CMO table)
- `2026-03-02-multi-agent-cascade-orchestration-checklist.md`: Content-writer invokes fact-checker via Task tool -- must ensure Task tool is available and the agent has a concrete output contract

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

#### Research Insights

**Agent Description (routing text only, under 45 words):**

Draft description (39 words):
> "Verify factual claims, statistics, and attributed quotes in content drafts by fetching cited URLs via WebFetch and confirming source support. Use copywriter for writing marketing copy; use content-writer skill for generating blog articles; use this agent for citation verification."

This follows the disambiguation pattern from the token budget optimization learning: core routing text + sibling disambiguation in a single compound sentence.

**Disambiguation updates required (both directions):**
- `copywriter.md`: Add "use fact-checker for citation and claim verification" to its existing disambiguation sentence
- `growth-strategist.md`: Add disambiguation if its description mentions content quality (it currently focuses on strategy, so likely no change needed)
- `cmo.md`: Add `fact-checker` row to the delegation table in the Delegate phase

**Claim extraction heuristics for agent body:**

The agent body should instruct the LLM to identify verifiable claims using these patterns:
1. **Hyperlinked text**: Any markdown link `[text](URL)` where the text makes a factual assertion
2. **Inline statistics**: Numbers with units or comparisons (e.g., "30M users", "grew 200%", "$1B acquisition")
3. **Attributed quotes**: Text in quotation marks followed by attribution (e.g., "..." -- Sam Altman)
4. **Temporal claims**: Dates or timeframes attached to events (e.g., "launched in 2023", "acquired in April 2012")
5. **Comparative claims**: Superlatives or rankings (e.g., "fastest-growing", "first to", "most popular")

Non-verifiable claims to skip: subjective opinions, rhetorical questions, definitions, the article's own thesis.

**WebFetch verification protocol for agent body:**

For each claim with a URL:
1. Fetch the URL via WebFetch
2. Search the page content for the specific claim (not just the topic)
3. For statistics: confirm the exact number appears on the page
4. For quotes: confirm the exact quote text (or close paraphrase) appears on the page
5. For facts: confirm the page supports the specific assertion, not just a related topic
6. If the page is behind a paywall, login wall, or returns no extractable content, mark as FAIL with "content not extractable"

### 2. Content-writer skill verification phase

Insert a new Phase 2.5 between draft generation (Phase 2) and user approval (Phase 3) in `plugins/soleur/skills/content-writer/SKILL.md`. This phase invokes the fact-checker agent via the Task tool, collects results, and annotates the draft presentation with verification status per claim.

```
Current:  Phase 2 (generate draft) -> Phase 3 (user approval)
Proposed: Phase 2 (generate draft) -> Phase 2.5 (verify citations) -> Phase 3 (user approval with verification status)
```

#### Research Insights

**Task tool invocation pattern:**

The content-writer skill invokes fact-checker as a Task agent, not as a direct function call. Per the multi-agent cascade learning, this requires:
1. The Task tool must be available in the execution context (it is by default in local Claude Code sessions; CI workflows need explicit `--allowedTools Task`)
2. The fact-checker agent must have a concrete output contract (the Verification Report heading structure)
3. The fact-checker agent must produce a writable artifact (the verification report is returned inline, not written to disk -- this is correct since it's ephemeral)

**Phase 2.5 wording pattern (follows existing skill conventions):**

```markdown
## Phase 2.5: Citation Verification

<validation_gate>

After generating the draft, verify all factual claims before presenting to the user.

Invoke the fact-checker agent via the Task tool, passing the full draft content:

Task fact-checker: "Verify all citations, statistics, and attributed quotes in this draft. For each claim with a URL, fetch the URL and confirm the page supports the claim. Return a Verification Report with Verified Claims, Failed Claims, Unsourced Claims, and Summary sections.

Draft content:
[full draft text]"

Parse the returned Verification Report. If any claims are marked FAIL or UNSOURCED, annotate the draft presentation in Phase 3 with inline status markers.

If the fact-checker agent is unavailable (e.g., tool not accessible), warn: "Citation verification skipped -- fact-checker agent not available. Proceed with manual verification." Continue to Phase 3.

</validation_gate>
```

**Headless mode bypass:**

Per constitution, skills invoked by pipelines may need `--headless` bypass. Phase 2.5 is non-interactive (no user prompts), so headless mode has no effect on it. However, if verification fails completely (agent unavailable), headless mode should log a warning and continue rather than aborting.

**Re-verification on edit cycles:**

When the user selects "Edit" in Phase 3 and provides feedback, Phase 2 regenerates the draft. Phase 2.5 should re-run verification on the regenerated draft. This ensures edits don't introduce new unverified claims. Add a note: "Re-verification runs after each Edit cycle."

### 3. Constitution rule

Add a content verification rule to `knowledge-base/overview/constitution.md` under a new `## Content` section.

#### Research Insights

**Proposed rule text:**

```markdown
## Content

### Always

- Verify all quantitative claims, attributed quotes, and factual assertions against their cited source URL via WebFetch before presenting content for user approval. If the source cannot be verified (URL unreachable, content not extractable, page doesn't support the claim), flag the claim for user review -- do not silently publish unverified claims
- Every published statistic must have a linked, fetchable source URL ("no naked numbers" rule)

### Never

- Never publish content with unverified citations. If verification is not possible (e.g., fact-checker agent unavailable), warn the user that manual verification is required

### Prefer

- Prefer softening unverifiable claims (e.g., "thousands" instead of "9,000") over removing them entirely, when the general direction is supported by available evidence
```

**Placement:** After `## Business` and before `## Specs` (content is a cross-cutting concern closer to business than to engineering specs).

**Tooling enforcement note (per constitution convention):** The fact-checker agent is the enforcement mechanism. The constitution rule should note `[enforced: fact-checker agent via content-writer Phase 2.5]` for bidirectional traceability.

## Non-Goals

- Automated rewriting of failed claims (the user decides how to handle flagged claims)
- Verification of non-URL claims (e.g., general knowledge assertions without citations)
- Retroactive scanning of already-published content (regression test covers the fixed article only)
- Real-time verification during generation (verification runs as a post-generation batch)
- Extending verification to the social-distribute skill (social posts derive from already-verified articles)
- Adding the fact-checker to CI workflows (local-only for now; CI integration is a future enhancement if content generation moves to automated pipelines)

## Technical Considerations

### Agent token budget

Current cumulative agent description word count is 2,454 (limit: 2,500). The fact-checker agent description must be kept to ~40 words maximum to stay under budget. Detailed instructions go in the agent body, not the description.

**Budget verification command:** `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` -- run before and after adding the agent. If the new total exceeds 2,500, trim the fact-checker description first.

### Agent structure

The fact-checker agent follows the project's agent conventions:
- YAML frontmatter with `name`, `description` (routing text only), `model: inherit`
- Disambiguation sentence referencing the copywriter agent (adjacent scope in marketing domain)
- Body contains verification protocol, not examples or commentary
- No `<example>` blocks in description (per token budget optimization learning)

### Skill integration pattern

The content-writer skill currently has 5 phases (Phase 0: Prerequisites, Phase 1: Parse Input, Phase 2: Generate Draft, Phase 3: User Approval, Phase 4: Write to Disk). The verification phase inserts between Phase 2 and Phase 3 as Phase 2.5.

The skill already has a guideline at line 124: "Every factual claim, statistic, and attributed quote must have a verifiable source URL." This plan replaces that passive guideline with active enforcement via the fact-checker agent. The existing line should be updated to reference Phase 2.5 rather than stating a passive rule.

**No new skill registration needed.** Per the skill creation lifecycle learning, adding a new skill requires 6+ file updates (skills.js, README, plugin.json, CHANGELOG, etc.). This plan modifies an existing skill, so none of those registration steps apply. The only documentation updates are for the new agent (README count, AGENTS.md CMO table).

### WebFetch dependency

The fact-checker agent relies on WebFetch to retrieve cited URLs. WebFetch is already used by 11 files across the plugin (research agents, competitive intelligence, growth strategist, etc.). No new tool dependencies are introduced.

**Edge cases for WebFetch:**
- **Paywalled content:** WebFetch cannot bypass paywalls. Mark as FAIL with "paywall detected" if the response is truncated or contains paywall indicators.
- **JavaScript-rendered pages:** WebFetch may not execute JavaScript. Single-page apps or dynamically loaded content may appear empty. Mark as FAIL with "content not extractable."
- **Redirects:** Some URLs redirect (e.g., shortened URLs). WebFetch follows redirects by default. The final URL should be reported if it differs from the cited URL.
- **Rate limiting:** If fetching many URLs sequentially, some sites may rate-limit. The agent should process claims sequentially (not in parallel) and handle HTTP 429 by marking as FAIL with "rate limited."

### Verification output contract

The fact-checker agent must produce a structured output with heading-level contract (per constitution preference for producer-consumer heading contracts):

```markdown
## Verification Report

### Verified Claims
- [claim text] -- Source: [URL] -- PASS: [brief evidence from page]

### Failed Claims
- [claim text] -- Source: [URL] -- FAIL: [reason -- e.g., "page mentions 30M users, not 1B"]

### Unsourced Claims
- [claim text] -- No citation provided

### Summary
- Total claims: N
- Verified: N
- Failed: N
- Unsourced: N
```

**Evidence requirement:** For PASS verdicts, include a brief excerpt or paraphrase from the source page that supports the claim. This lets the user quickly confirm the verification is genuine, not hallucinated by the fact-checker itself.

### Content-writer presentation

During Phase 3 (User Approval), each claim in the draft gets a status indicator:
- PASS: claim verified against source
- FAIL: source does not support the claim (with reason)
- UNSOURCED: no citation provided for a quantitative or attributed claim

The user sees the verification summary before deciding Accept/Edit/Reject.

**Presentation format:** Show the Verification Report summary first (N verified, N failed, N unsourced), then the full draft. Failed and unsourced claims should be called out with inline markers in the draft text (e.g., `[FAIL: reason]` after the claim) so the user can see exactly which parts need attention.

### Registration updates (new agent in existing domain)

Per the agent domain checklist learning, adding a new agent to an existing domain (marketing) requires:

1. **Create agent file:** `plugins/soleur/agents/marketing/fact-checker.md`
2. **Update CMO delegation table:** Add `| fact-checker | Citation and claim verification for content drafts |` to `cmo.md` Phase 3 delegation table
3. **Update sibling disambiguation:** Add reverse disambiguation to `copywriter.md` (the closest sibling)
4. **Update README.md:** Agent count 61 -> 62 in the stats table
5. **Update AGENTS.md:** CMO "Agents Orchestrated" count from "11 specialists" to "12 specialists" in the domain leader table
6. **Verify token budget:** Run word count check after adding

**Not needed (marketing domain already exists):**
- No `docs/_data/agents.js` changes (domain already registered)
- No `docs/css/style.css` changes (CSS variable already exists)
- No `skills.js` changes (no new skill)
- No brainstorm routing changes (marketing domain already has routing)

## Acceptance Criteria

- [ ] `plugins/soleur/agents/marketing/fact-checker.md` agent exists with WebFetch-based verification protocol
- [ ] Agent description is under 45 words and includes disambiguation sentence
- [ ] Agent cumulative description word count stays under 2,500
- [ ] `plugins/soleur/skills/content-writer/SKILL.md` includes Phase 2.5 that invokes fact-checker via Task tool
- [ ] Phase 2.5 passes the generated draft content to the fact-checker agent
- [ ] Each citation in a draft is fetched via WebFetch and verified (pass/fail per claim)
- [ ] Naked numbers (stats without source URLs) are flagged as UNSOURCED
- [ ] Attributed quotes are checked against the cited page content
- [ ] Verification report follows the structured heading contract with evidence for PASS verdicts
- [ ] User sees verification status per claim during Phase 3 approval
- [ ] Re-verification runs after each Edit cycle in Phase 3
- [ ] Constitution rule added under `## Content` section with enforcement annotation
- [ ] CMO delegation table in `cmo.md` includes fact-checker row
- [ ] Copywriter agent description updated with reverse disambiguation
- [ ] README.md agent count updated (61 -> 62)
- [ ] `plugins/soleur/AGENTS.md` CMO domain leader table updated (11 -> 12 specialists)
- [ ] Graceful degradation: if fact-checker is unavailable, warn and continue

## Test Scenarios

- Given a draft with a correct citation URL, when the fact-checker fetches the URL, then the claim is marked PASS with brief evidence excerpt from the page
- Given a draft with a citation URL that does not support the claim, when the fact-checker fetches the URL, then the claim is marked FAIL with a specific reason (e.g., "page says 30M users, not 1B")
- Given a draft with a statistic but no source URL, when the fact-checker scans the draft, then the claim is marked UNSOURCED
- Given a draft with an attributed quote, when the fact-checker fetches the cited URL, then it checks whether the quote text appears on the page
- Given the fact-checker encounters a URL that returns HTTP 4xx/5xx, when verification runs, then the claim is marked FAIL with "URL not reachable" (not silently skipped)
- Given a draft with zero citations (e.g., opinion piece), when the fact-checker runs, then it reports "No verifiable claims found" and Phase 3 proceeds normally
- Given the existing fixed blog article (CaaS), when the fact-checker runs against it, then all claims pass (regression test)
- Given the fact-checker agent is unavailable, when Phase 2.5 runs, then a warning is displayed and Phase 3 proceeds with a note that manual verification is required
- Given the user selects "Edit" in Phase 3 and the draft is regenerated, when Phase 2.5 re-runs, then the new draft is re-verified

## Success Metrics

- Zero factual inaccuracies in future published articles that have fetchable source URLs
- Every quantitative claim in published content has a verified source
- Content-writer skill presents verification status before user approval

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| WebFetch rate limiting or timeouts on many URLs | Fetch sequentially with reasonable delays; mark timed-out URLs as FAIL with "timeout" reason |
| Agent description pushes over 2,500 word budget | Draft description is 39 words; verify with word count command after creation |
| False negatives (page content changed after citation) | Mark as FAIL -- the user decides whether the claim is still valid |
| WebFetch cannot render JavaScript-heavy pages | Accept this limitation; mark as FAIL with "content not extractable" |
| Verification adds latency to content-writer workflow | Acceptable tradeoff -- verification runs once per draft, not per edit cycle |
| Paywalled sources return truncated content | Mark as FAIL with "paywall detected"; user can manually verify |
| Fact-checker itself hallucinates verification results | Require evidence excerpts in PASS verdicts so user can spot-check |
| Task tool unavailable in some execution contexts | Graceful degradation -- warn and continue without verification |

## Semver Intent

`semver:minor` -- new agent and new skill phase (additive, no breaking changes).

## Files Modified

| File | Change |
|---|---|
| `plugins/soleur/agents/marketing/fact-checker.md` | **Create** -- new agent |
| `plugins/soleur/skills/content-writer/SKILL.md` | **Modify** -- add Phase 2.5, update line 124 guideline |
| `knowledge-base/overview/constitution.md` | **Modify** -- add `## Content` section |
| `plugins/soleur/agents/marketing/cmo.md` | **Modify** -- add fact-checker to delegation table |
| `plugins/soleur/agents/marketing/copywriter.md` | **Modify** -- add reverse disambiguation sentence |
| `plugins/soleur/README.md` | **Modify** -- update agent count 61 -> 62 |
| `plugins/soleur/AGENTS.md` | **Modify** -- update CMO specialist count 11 -> 12 |

## References & Research

### Internal References

- Learning: `knowledge-base/learnings/2026-03-06-blog-citation-verification-before-publish.md`
- Learning: `knowledge-base/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md`
- Learning: `knowledge-base/learnings/implementation-patterns/2026-02-22-new-skill-creation-lifecycle.md`
- Learning: `knowledge-base/learnings/integration-issues/adding-new-agent-domain-checklist.md`
- Learning: `knowledge-base/learnings/2026-03-02-multi-agent-cascade-orchestration-checklist.md`
- Content-writer skill: `plugins/soleur/skills/content-writer/SKILL.md`
- Copywriter agent (sibling): `plugins/soleur/agents/marketing/copywriter.md`
- CMO agent (domain leader): `plugins/soleur/agents/marketing/cmo.md`
- Constitution: `knowledge-base/overview/constitution.md`
- Agent compliance checklist: `plugins/soleur/AGENTS.md`

### Related Work

- Issue: #459
- PR #457: Fixed 6 inaccuracies in CaaS blog article (the incident that motivated this)
- PR #458: Added social-distribute skill (latest marketing skill addition)
