# feat: Non-Technical Founder Voice — Dual-Register Brand Guide + Content-Writer Audience Flag

**Issue:** #1004
**Branch:** non-technical-founder-voice
**Brainstorm:** [2026-03-29-non-technical-founder-voice-brainstorm.md](../brainstorms/2026-03-29-non-technical-founder-voice-brainstorm.md)

## Problem

The brand guide speaks exclusively to technical builders. The content-writer skill has no mechanism to vary voice by audience. Business validation confirmed non-technical founders want Soleur but hit "this isn't for me" at every touchpoint. The ICP was annotated for softening in the 2026-03-22 review but never actually rewritten.

## Changes

### 1. Brand Guide — Audience Voice Profiles (`knowledge-base/marketing/brand-guide.md`)

Add a new `### Audience Voice Profiles` subsection under `## Voice` (after `### Do's and Don'ts`, before `### Value Proposition Framings`). This section defines two registers:

**Technical register** (default for HN, GitHub, Discord, technical blog posts):

- Current voice — no changes needed
- Uses engineering metaphors, proof points like "420+ merged PRs"
- Assumes reader understands agents, CLI, workflows

**General register** (default for website, LinkedIn, X/Twitter, onboarding content):

- Plain language — no jargon without immediate definition
- Business-outcome proof points ("saves 15 hours/week on marketing, legal, and ops")
- Analogies over technical terms ("your AI team" not "61 agents")
- Explain concepts in business terms: "agents" = "AI specialists that handle specific business functions", "knowledge base" = "your company's institutional memory", "compounding" = "gets smarter the more you use it"

### 2. Brand Guide — Tone Spectrum Row

Add a "Non-Technical Founder" row to the Tone Spectrum table (line 58):

| Context | Tone | Example |
|---------|------|---------|
| Non-technical founders | Clear, outcome-focused, no jargon | "Your AI marketing team writes copy, plans campaigns, and tracks competitors — without you hiring anyone." |

### 3. Brand Guide — Parallel Thesis

Add a `**General thesis:**` line after the existing thesis (line 30):

> **General thesis:** "Running a company alone shouldn't mean doing everything alone. Soleur gives you a full team of AI specialists — marketing, legal, operations, finance — that learn your business and work together."

### 4. Brand Guide — Who Is Soleur For? Section

Add a new `### Who Is Soleur For?` subsection under `## Identity` (after `### Target Audience`, before `### Positioning`):

| Segment | Description | Channels |
|---------|-------------|----------|
| Technical builders | Founders who code, use Claude Code, think in systems. The beachhead. | HN, GitHub, Discord, technical blog posts |
| Non-technical founders | Founders who use AI tools (ChatGPT, Notion) but don't code. Want business leverage, not technical leverage. | Website, LinkedIn, X/Twitter, onboarding |

### 5. Brand Guide — Do's Addition

Add to the Do list (after line 70):

- When writing for non-technical founders: define technical terms on first use, lead with business outcomes, use "your AI team" instead of "61 agents"

### 6. Content-Writer Skill — `--audience` Parameter (`plugins/soleur/skills/content-writer/SKILL.md`)

**a)** Update argument format (line 14) to include `[--audience <audience>]`

**b)** Add parse entry in Phase 1: `--audience "technical|general"` (optional): audience register. Defaults to channel-appropriate (blog → technical, landing page → general).

**c)** Update Phase 2 brand guide reading (after line 63) to add:

> 4. If `--audience` is set, read `### Audience Voice Profiles` from brand guide and apply the matching register's vocabulary, explanation depth, and proof point selection rules. If not set, infer from `--path` or topic context.

### 7. Marketing Strategy ICP Rewrite (`knowledge-base/marketing/marketing-strategy.md`)

Apply the two existing annotations that were never enacted:

**Line 115** — Replace the `[INVALIDATED]` annotated bullet with:
>
> - Uses AI tools for some business tasks but lacks cross-domain integration

**Line 116** — Replace the `[SOFTEN]` annotated bullet with:
>
> - Technical background is helpful but not required — the web platform serves both technical and non-technical founders

**Lines 129-131** — Update "Beachhead Segment" to align: replace "Claude Code power users" with "AI-tool-active solo founders" and adjust the three criteria.

**Lines 137-144** — Update "Channels to Reach Them" table: keep Claude Code Discord but lower priority; add "Website (app.soleur.ai)" as P1.

## Acceptance Criteria

- [x] Brand guide has `### Audience Voice Profiles` with technical and general registers
- [x] Tone Spectrum table has "Non-technical founders" row
- [x] Parallel general thesis added under positioning
- [x] "Who Is Soleur For?" section with two segments
- [x] Do's list includes non-technical founder guidance
- [x] Content-writer skill accepts `--audience` parameter
- [x] Content-writer Phase 2 reads audience-specific voice rules
- [x] Marketing strategy ICP rewritten (annotations applied, not just commented)
- [x] Beachhead segment and channel table updated

## Test Scenarios

**Scenario 1 — Content-writer with --audience general:** Run `skill: soleur:content-writer` with `--audience general` on a topic like "What is Soleur?" Verify output uses plain language, defines technical terms, and uses business-outcome proof points.

**Scenario 2 — Content-writer with --audience technical:** Run the same topic with `--audience technical`. Verify output uses engineering language, cites merged PRs, and assumes developer familiarity.

**Scenario 3 — Content-writer without --audience:** Run on a blog topic. Verify it defaults to channel-appropriate register (technical for blog).

## Domain Review

**Domains relevant:** Marketing

### Marketing (CMO)

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** The gap is validated by user research. Dual-register approach preserves technical conviction while adding accessibility. The highest-stakes decision (thesis framing) is resolved: keep engineering thesis for technical channels, add parallel thesis for non-technical. Website landing page copy changes should involve conversion-optimizer for layout review when implementing.
