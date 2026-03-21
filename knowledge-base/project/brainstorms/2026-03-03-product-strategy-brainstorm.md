# Product Strategy Brainstorm

**Date:** 2026-03-03
**Participants:** User, CPO Agent, Repo Research Analyst, Learnings Researcher
**Status:** Complete

---

## What We're Building

A **validation-first product strategy** for Soleur, replacing a traditional feature roadmap with a structured validation plan that has decision gates. The strategy combines two validation motions:

1. **Dogfood-Out** (lead motion): Publicly document Soleur's own multi-domain usage as case studies to attract early adopters organically
2. **Compressed Parallel Validation** (layered in): Once inbound interest surfaces candidates, run split-cohort validation -- problem interviews + product usage tracks simultaneously

This approach acknowledges that Soleur is engineering-mature (v3.10.1, 61 agents, 55 skills, 420+ PRs) but commercially pre-seed (zero confirmed external users).

## Why This Approach

### The CPO's Core Argument

A feature roadmap is premature. The business validation document (2026-02-25) issued a PIVOT verdict: stop building, start validating. The demand evidence gate was flagged -- only 1-2 conversations, below the 5-person threshold. Building a roadmap without external validation risks spending months on the wrong thing.

### Institutional Learnings That Informed This Decision

1. **Context-blindness cascades** (2026-02-22): Strategic agents that produce artifacts without reading canonical sources of truth create compounding misalignment. Any strategy must anchor to the brand guide's CaaS positioning.
2. **Differentiation is in composition** (2026-02-19): Individual capabilities are commoditized; the moat is lifecycle orchestration (brainstorm -> plan -> work -> review -> compound). Roadmap decisions should deepen integration, not add isolated features.
3. **Plan review shrinks scope 30-50%** (2026-02-06): Multiple learnings confirm that parallel reviewers consistently cut over-engineering. Never skip the review gate.
4. **Separate IA review from visual review** (2026-02-17): Adoption-critical issues (navigation, onboarding flow) are missed by surface-level reviews.

### Competitive Pressure

The window is narrowing. Key threats from the competitive intelligence report (2026-03-02):

- **Anthropic Cowork Plugins:** 11 first-party plugins covering 6+ of Soleur's 8 domains. Free, bundled with the platform.
- **Notion Custom Agents:** 21K agents in early testing. Category overlap with CaaS positioning.
- **Devin 2.0:** Dropped from $500 to $20/month. Engineering-only, but aggressive pricing compression.
- **Cursor:** $29.3B valuation, $1B ARR. Engineering-only but deep.

Soleur's strongest differentiator: **compounding cross-domain knowledge base**. No competitor replicates institutional memory that compounds across brainstorms, plans, reviews, and learnings.

## Key Decisions

### 1. Validation-first, not roadmap-first

No feature roadmap until external validation data exists. The strategy document is a validation plan with decision gates, not a feature backlog with timelines.

### 2. Dogfood-Out + Compressed Parallel Validation

- Lead with authentic case studies of Soleur's own non-engineering domain usage
- Layer in structured validation when inbound interest provides candidates
- Fallback: if zero inbound after 4-6 weeks, switch to cold outreach for the compressed track

### 3. All 5 blocking questions tackled in parallel

No single question prioritized over others:

| # | Blocking Question | Method |
|---|-------------------|--------|
| 1 | Do solo founders independently describe multi-domain pain? | 10+ problem interviews (no demo) |
| 2 | Which non-engineering domains deliver value first? | Guided onboarding with 5+ founders, observe behavior |
| 3 | Will users pay for non-engineering value? | Direct WTP questions after 2-week unassisted usage |
| 4 | Is Claude Code the right distribution surface? | Monitor Cowork roadmap, evaluate multi-platform architecture |
| 5 | What is the actual activation rate? | Instrument basic telemetry (install count, domain usage, session depth) |

### 4. Pricing deferred entirely

No pricing analysis, framework, or commitments until validation data exists. The $49-99/month hypothesis is under competitive pressure (Devin at $20, Cowork free), but pricing without demand evidence is speculation.

### 5. Full validation plan with concrete action items

The strategy document will include actionable plans for closing all 3 capability gaps: interview framework, telemetry instrumentation, and onboarding audit for external users.

## Validation Plan

### Phase 0: Dogfood-Out Content (Weeks 1-4)

**Goal:** Publicly document Soleur's non-engineering domain usage to attract early adopters.

**Actions:**

- Identify 5-7 authentic case studies from existing non-engineering usage (legal docs, brand guide, competitive intelligence, ops decisions, marketing strategy)
- Publish as blog posts, Discord posts, or social content with specific before/after comparisons
- Track inbound interest metrics (Discord joins, GitHub stars, plugin installs if measurable)

**Gate:** At least 5 inbound expressions of interest (Discord messages, GitHub issues, social replies asking "how do I try this?")

**If gate fails after 4-6 weeks:** Fall back to cold outreach (IndieHackers, solo founder communities, Claude Code Discord)

### Phase 1: Problem Interviews (Weeks 2-6, overlaps Phase 0)

**Goal:** Validate that multi-domain pain exists outside the builder's own experience.

**Actions:**

#### Customer Interview Framework

**Recruitment:**

- Source from Phase 0 inbound interest first
- Fallback: IndieHackers, solo founder communities, Claude Code Discord, Twitter/X
- Target: solo technical founders who use AI tools for work beyond coding
- Screening question: "Have you ever used an AI tool for something other than writing code? What?"

**Interview Structure (30 minutes):**

1. **Context (5 min):** What are you building? How far along? Team size?
2. **Pain Discovery (15 min):**
   - Walk me through what you did last week that wasn't coding.
   - Which of those tasks felt like a distraction from your core work?
   - Have you tried using AI for any of those non-coding tasks? What happened?
   - What would change for you if those tasks were handled automatically?
3. **Domain Probing (5 min):**
   - [Show list: legal, marketing, ops, finance, sales, support]
   - Which of these have you spent time on in the last month?
   - Which ones are you ignoring that you probably shouldn't be?
4. **Willingness Signal (5 min):**
   - If a tool existed that handled [their top pain domain] with AI, what would it need to do?
   - How much time per week would it save you?
   - What would you pay for that? (Open-ended, not anchored)

**Analysis Framework:**

- Code each interview for: domains mentioned, pain intensity (1-5), existing solutions, WTP signals
- Track frequency of each domain across all interviews
- Pattern-match: do founders converge on 2-3 domains, or diverge across all 8?

**Gate:** 5/10 founders independently describe multi-domain pain at intensity >= 3. At least 2 domains appear in >= 6/10 interviews.

### Phase 2: Product Usage Test (Weeks 5-10)

**Goal:** Test whether Soleur's non-engineering domains deliver real value to external users.

**Actions:**

**Cohort Design (10 founders, split):**

- **Cohort A (5):** Problem interview first, then 2 weeks of guided Soleur usage
- **Cohort B (5):** 2 weeks of guided Soleur usage first, then debrief interview

**Guided Onboarding Script:**

1. Install Soleur (`claude plugin install soleur`)
2. Run `/soleur:sync` on their project
3. Walk through one non-engineering domain task together (legal doc, competitive analysis, brand guide)
4. Leave them for 2 weeks of unassisted usage

**Observation Metrics:**

- Which domains do they activate on their own?
- How many sessions include non-engineering domain usage?
- What questions do they ask during onboarding?
- What breaks or confuses them?

**Gate:** 3/10 founders use a non-engineering domain unprompted during unassisted period. Average satisfaction >= 4/5 on domain output quality.

### Phase 3: Retention + WTP (Weeks 8-12)

**Goal:** Test retention and willingness to pay.

**Actions:**

- After 2-week unassisted period, run debrief interviews
- Direct WTP question: "Would you pay for this? How much per month?"
- NPS-style: "Would you recommend this to another solo founder?"
- Churn signal: "If I removed Soleur from your setup tomorrow, what would you miss?"

**Gate:** 3/10 express clear WTP at >= $25/month. Average NPS >= 7. At least 2 would "definitely miss" a non-engineering domain.

### Phase 4: Decision Point (Week 12)

At week 12, assess all gates:

| Gate | Passed? | Implication |
|------|---------|------------|
| Multi-domain pain validated | Yes/No | CaaS thesis confirmed or invalidated |
| Top 2-3 domains identified | Yes/No | Focus investment or broaden/narrow |
| WTP at viable price point | Yes/No | Revenue model feasible or needs rethinking |
| Product delivers value unprompted | Yes/No | Product-market fit signal or product gap |
| Distribution surface viable | Yes/No | Stay Claude Code or go multi-platform |

**If 4/5 gates pass:** Build a real roadmap. You've earned it.
**If 2-3 gates pass:** Iterate on the failing dimensions for another 4-week cycle.
**If 0-1 gates pass:** Fundamental pivot or wind down.

## Capability Gaps -- Action Items

### Gap 1: Telemetry / Analytics Instrumentation

**Problem:** Cannot measure install counts, activation rates, domain usage, or retention.

**Action Items:**

- Evaluate lightweight telemetry options that respect the BSL license and user privacy
- Minimum viable metrics: install count, first-run completion, domain activation (which C-level agents are invoked), session count per week
- Consider opt-in telemetry with clear disclosure (aligned with existing privacy policy)
- Investigate whether Claude Code plugin marketplace provides any install/usage data
- Timeline: implement before Phase 2 (product usage test) begins

### Gap 2: Customer Interview Framework

**Problem:** No interview scripts, recording templates, or analysis framework.

**Action Items:**

- Interview script: captured above in Phase 1
- Create a simple spreadsheet or markdown template for coding interview responses
- Columns: founder name, stage, team size, domains mentioned, pain intensity per domain, existing solutions, WTP signal, key quotes
- No recording needed -- live notes are sufficient for 10 interviews
- Timeline: ready before first interview (Week 2)

### Gap 3: Onboarding for External Users

**Problem:** Product was built by its creator for its creator. No evidence of onboarding optimization for first-time users.

**Action Items:**

- Run a "fresh eyes" test: have someone install Soleur from scratch and observe where they get stuck
- Audit the Getting Started page against the IA learning (2026-02-17): is it discoverable? Is the first action clear?
- Create a "first 5 minutes" onboarding flow: install -> sync -> one domain task -> see result
- Identify and fix any assumptions that require creator-specific context (knowledge-base structure, project conventions)
- Timeline: complete before Phase 2 (product usage test) begins

## Open Questions

1. **Content distribution channels:** Where should Dogfood-Out content be published for maximum reach to solo founders? Blog? Twitter/X? IndieHackers? Discord?
2. **Telemetry privacy:** How to instrument usage without compromising the privacy-respecting brand? Opt-in only? Aggregated only?
3. **Cowork risk:** If Anthropic ships a Cowork plugin that directly competes with Soleur's CaaS positioning, what is the contingency? Multi-platform escape hatch?
4. **Knowledge base portability:** Is the knowledge base format portable enough that users wouldn't lose their institutional memory if they switch tools?
5. **Team features:** At what point does "solo founder" positioning limit growth? When should team support be considered?

## Capability Gaps

| Missing Capability | Domain | Why Needed |
|-------------------|--------|------------|
| Telemetry / analytics instrumentation | Engineering | Cannot measure install counts, activation rates, domain usage, or retention. Phase 2 is flying blind without it. |
| Customer interview framework | Product | No interview scripts, recording templates, or analysis framework for the 10+ problem interviews. |
| Onboarding flow for external users | Product / UX | Product was built by its creator for its creator. No evidence of onboarding optimization for first-time external users. |
