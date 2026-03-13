# Marketing Strategy Unification: CMO Orchestration Pattern

**Date:** 2026-03-03
**Context:** Soleur marketing strategy review (issue #236)
**Pattern Type:** Cross-functional artifact generation and alignment
**Applicability:** Any project with fragmented strategic documents and stalled execution

---

## Problem

A strategy document exists but execution stalled. Multiple root causes often combine:

1. **Fragmentation**: Strategy is distributed across 5+ files (content plan, SEO audit, brand guide, competitive intelligence, business case) with no unifying narrative
2. **Staleness**: Individual pieces (e.g., content plan) are outdated relative to changed market conditions or product growth
3. **Capacity gap**: Original strategy assumed resources that are unavailable (blog infrastructure, marketing team, email systems)
4. **Cascade misalignment**: Supporting documents (content strategy, pricing strategy, competitor battlecards, SEO queue) either don't exist or were generated but never landed on main

### Why This Happens

Two mechanisms:
- **Parallel stagnation**: Everyone assumes someone else will consolidate the fragments → no one does
- **Capacity mismatch**: Strategy assumes T=0 execution but actual resources only allow T=2+ execution → documents sit in feature branches waiting for capacity that never arrives

For Soleur specifically: content plan (Feb 19) was detailed but unexecuted; 7 cascade documents were generated during competitive intelligence work but never committed to any branch.

---

## Solution: CMO Orchestration Pattern

Instead of manually merging fragments, delegate the unification to a domain expert (Chief Marketing Officer / Product Strategy Lead) who:

### Stage 1: Assessment
- Read all existing artifacts: brand guide, content plan, competitive intelligence, business validation, content audit, SEO audits
- Identify what is current and what is stale
- Diagnose the capacity bottleneck (blog infrastructure? team bandwidth? unclear priorities?)
- Surface open strategic questions

### Stage 2: Recommendation
- Produce a unified positioning and messaging hierarchy
- Identify the 3-5 validated moats that should inform all messaging
- Define realistic phased execution plan given actual constraints (not aspirational)
- Specify which cascade documents are needed and why

### Stage 3: Delegation
- Assign cascade document generation to specialist agents (growth-strategist, pricing-strategist, SEO-specialist, sales-architect)
- Each specialist reads the unified strategy and existing foundational docs
- Specialists generate their cascade documents aligned to the unified narrative
- CMO reviews for cross-domain consistency before commit

### Stage 4: Integration
- All documents link to each other via YAML `depends_on` fields
- Unified strategy includes a `review_cadence` field (e.g., quarterly) for future maintenance
- Documents carry `last_reviewed` and `last_updated` timestamps to prevent staleness

---

## Key Design Decisions

### 1. **Unified Strategy ≠ New Strategy**
The existing strategy is not wrong. The unified document accounts for why execution stalled and produces a realistic plan that is achievable with current constraints.

For Soleur: The Feb 19 content plan had high-quality keyword research and gap analysis. The unified strategy reframes execution as "capacity-constrained" and identifies infrastructure gaps (blog not built, email not wired) rather than strategy gaps.

### 2. **Cascade Documents Are Not Optional**
A unified strategy without supporting details is not actionable. Cascade documents are required:
- **Content strategy**: Translates the unified narrative into specific content gaps and execution sequencing
- **Pricing strategy**: Operationalizes the positioning into a revenue model
- **Competitive battlecards**: Arms sales and partnership teams with credible comparison narratives
- **SEO refresh queue**: Converts content gaps into specific pages/keywords to prioritize

Without these, the unified strategy stays abstract.

### 3. **Capacity Constraints Are Explicit**
The strategy must name what is missing:
- Blog infrastructure blocks all content marketing execution
- Email capture system blocks lead nurture workflows
- Pricing decision blocks pricing content
- Validation interviews block case study generation

These become line items in the execution plan, not hidden roadblocks.

### 4. **Three Validated Moats Inform All Messaging**
All cascade documents ladder up to at least one structural moat (not feature-based positioning).

For Soleur:
1. Compounding knowledge base (cross-domain institutional memory)
2. Cross-domain coherence (61 agents share context across 8 domains)
3. Workflow orchestration depth (brainstorm-plan-implement-review-compound lifecycle)

Every piece of content, every battlecard, every pricing page references one of these.

### 5. **Specialist Agents Regenerate Cascade Documents**
Rather than the CMO writing all cascade documents, they delegate:
- Growth-strategist writes content strategy (identifies content gaps, sequencing, pillar articles)
- Pricing-strategist writes pricing strategy (operationalizes the positioning, models revenue)
- SEO-specialist writes the refresh queue (maps content gaps to keywords, search volume, difficulty)
- Deal-architect writes battlecards (objection handling, competitive positioning per target buyer)

This parallelizes work and ensures each document has domain expertise.

---

## Artifact Structure

### Unified Marketing Strategy Document

```yaml
---
last_updated: YYYY-MM-DD
last_reviewed: YYYY-MM-DD
review_cadence: quarterly
depends_on:
  - knowledge-base/overview/brand-guide.md
  - knowledge-base/overview/competitive-intelligence.md
  - knowledge-base/overview/business-validation.md
  - knowledge-base/overview/content-strategy.md
  - knowledge-base/overview/pricing-strategy.md
---

# [Company] Marketing Strategy

## Executive Summary
[1-2 paragraph statement of position, competitive context, and strategic imperative]

## Current State Assessment
[What exists and works | What is broken or missing]

## Strategic Positioning
[Positioning statement | 3+ validated moats | Messaging hierarchy | Key objections and responses]

## Target Audience
[ICP | Psychographics | Jobs to be done]

## Distribution Channels
[Primary | Secondary | Testing]

## Success Metrics
[KPIs tied to strategic goals | Reporting cadence]

## Execution Plan (Phased)
[Phase 1 | Phase 2 | Phase 3 | Capacity assumptions | Infrastructure blockers]
```

### Cascade Document: Content Strategy

```yaml
---
last_updated: YYYY-MM-DD
last_reviewed: YYYY-MM-DD
review_cadence: quarterly
depends_on:
  - knowledge-base/overview/brand-guide.md
  - knowledge-base/overview/marketing-strategy.md
  - knowledge-base/overview/competitive-intelligence.md
---

# [Company] Content Strategy

## Purpose
[How this doc serves the unified strategy]

## Content Gap Analysis
[Gap 1 (Critical) | Gap 2 (Critical) | Gap 3-5 (High/Medium)]

For each gap:
- What is missing
- Why it matters (strategic + SEO + competitive)
- Content needed (pillar articles, comparison pages, schema markup)

## Content Sequencing
[Phase 1: foundational | Phase 2: moat differentiation | Phase 3: competitive]

## Infrastructure Requirements
[Blog platform | Email capture | CMS | Analytics]
```

### Cascade Document: Battlecards

```yaml
---
last_updated: YYYY-MM-DD
last_reviewed: YYYY-MM-DD
last_competitor_mention: YYYY-MM-DD
---

# Soleur vs. [Competitor]

## At a Glance
[1-line positioning]

## Head-to-Head Comparison
[Feature table or narrative]

## Key Objection: "[Buyer's concern]"
**Objection:** [How the objection is typically framed]
**Response:** [Soleur's positioned response]
**Proof point:** [Evidence or comparison]

## Messaging Takeaways
[3-5 bullets on how to position in conversations]
```

---

## What This Pattern Solves

### Before (Fragmented)
- Brand guide is current; content plan is stale
- Blog infrastructure doesn't exist; content calendar assumes it does
- Competitive intelligence identifies moats; but messaging doesn't reference them
- SEO audits show problems; but site copy never changed
- 7 cascade documents were generated but never merged

**Result:** Founder must manually stitch these together. Execution stalls because the gap between "what the content plan says to do" and "what we can actually build" is never explicitly named.

### After (Unified)
- One strategy document that accounts for current competitive context, product growth, and capacity constraints
- Cascade documents all reference the unified strategy
- Infrastructure blockers are explicitly named (blog not built, email not wired) so they don't become surprise roadblocks
- Phased execution plan is realistic given actual constraints
- All documents include review cadence and timestamps to prevent staleness

**Result:** Execution can begin immediately on achievable Phase 1 work. Founder sees the full map and doesn't discover halfway through "wait, we need a blog for this."

---

## Anti-Patterns

### 1. CMO Writes All Cascade Documents Alone
This defeats the purpose of the pattern. Cascade documents require specialist expertise (SEO-specialist understands keyword research, growth-strategist understands content sequencing). CMO's job is orchestration, not authorship.

### 2. Cascade Documents Are Optional
If you only produce a unified strategy with no cascade documents, you have a map but no navigation instructions. Content strategy explains which content gaps are critical, how to sequence them, and what moats they reinforce.

### 3. Unifying Strategy Without Diagnosing Why Execution Stalled
If you don't name the capacity blockers or the market shift that made the old plan obsolete, you'll reproduce the same stall with the new strategy.

For Soleur: The old content plan assumed blog infrastructure existed. The unified strategy names "blog infrastructure" as a blocker and adjusts execution plan accordingly. Without this, a founder would start writing content and discover mid-way "oh, we can't publish this without a blog."

### 4. Unified Strategy Is Too Abstract
All strategic documents must have a phased execution plan with explicit assumptions. "Here is what we should do" without "here is what Phase 1 looks like given we have 10 hours/week" is not useful.

### 5. Forgetting to Set Review Cadence
Strategies become stale. Include `last_reviewed`, `last_updated`, and `review_cadence` fields in every document. Quarterly is typical for marketing strategy. If it's not reviewed quarterly, it will ossify.

---

## When This Pattern Works Best

✓ Existing strategy is sound but fragmented across multiple files
✓ Execution stalled due to capacity constraints, not strategy flaws
✓ Market has shifted since the strategy was written (competitor entry, product growth, business model change)
✓ Cascade documents exist but were never merged or aligned
✓ Team has access to domain specialists who can orchestrate (even if they're agents, not humans)

✗ Strategy itself is fundamentally wrong (requires a separate strategy rethink, not unification)
✗ Execution stalled due to product roadblock (missing feature, infrastructure), not strategic misalignment
✗ No domain expertise available (can't orchestrate cascade documents without SMEs)

---

## Soleur Case Study

### Input State (March 3, 2026)
- Brand guide: current, strong, consistent
- Content plan: 15 pieces detailed, 0% executed, 14 days old, assumptions outdated
- Content audit: 0/10 actual informational content, 2/10 SEO score, 1.6/10 AEO score
- Competitive intelligence: current as of March 2, identifies 3 validated moats
- Cascade documents: 7 generated during research, never committed
- Blockers: blog infrastructure doesn't exist, email capture not wired, pricing undecided

### Process
1. CMO agent reads all input artifacts
2. CMO produces unified marketing strategy (executive summary + positioning + target audience + execution plan)
3. CMO delegates to specialist agents:
   - Growth-strategist: content strategy document (5 critical gaps identified, sequenced)
   - Pricing-strategist: pricing strategy document (freemium model with future upsell)
   - SEO-specialist: SEO refresh queue (top 20 pages to rewrite, grouped by gap)
   - Deal-architect: 4 competitive battlecards (Cowork, Cursor, Notion, Tanka)
4. All committed to feat-marketing-strategy-review branch with dependencies declared in YAML

### Output Artifacts
- `knowledge-base/overview/marketing-strategy.md` (executive summary, 3 moats, positioning, messaging hierarchy, phased execution)
- `knowledge-base/overview/content-strategy.md` (5 content gaps, sequencing, pillar articles, schema requirements)
- `knowledge-base/overview/pricing-strategy.md` (freemium model, future pricing, justification framework)
- `knowledge-base/marketing/seo-refresh-queue.md` (top 20 rewrites, keyword targets, difficulty, impact)
- `knowledge-base/sales/battlecards/tier-0-*.md` (Cowork, Cursor battlecards)
- `knowledge-base/sales/battlecards/tier-3-*.md` (Notion, Tanka battlecards)

### Result
- Unified narrative across all marketing domains
- Explicit acknowledgment of capacity constraints and infrastructure blockers
- Phased execution plan that is achievable given 10 hours/week founder bandwidth
- All 7 lost cascade documents now committed and interdependent
- Ready for execution of Phase 1 (content gaps, SEO rewrites) without surprise blockers

---

## Replication Checklist

When unifying a fragmented strategy for a different project:

- [ ] Identify all existing strategy artifacts and assess staleness
- [ ] Diagnosis the real reason execution stalled (capacity? market shift? infrastructure?)
- [ ] Assign a domain expert (CMO/product lead/strategist) to orchestrate
- [ ] That expert reads all existing artifacts and produces unified strategy
- [ ] Unified strategy includes: positioning, 3+ validated moats, messaging hierarchy, phased execution
- [ ] Unified strategy names explicit capacity constraints and infrastructure blockers
- [ ] Assign cascade document generation to specialists (not the orchestrator alone)
- [ ] Each cascade doc reads unified strategy and existing foundational sources
- [ ] All cascade docs include YAML metadata: `last_updated`, `last_reviewed`, `review_cadence`, `depends_on`
- [ ] CMO reviews cascade docs for alignment before merge
- [ ] Commit all artifacts with cross-linking

---

## Related Patterns

- **Domain Leader Extension**: Single person orchestrates across domains by delegating to specialists
- **Compound Artifacts**: Strategy documents that incorporate learnings from previous cycles
- **Cascade Architecture**: Unified documents that cascade dependencies through multiple layers (strategy → content strategy → SEO queue → individual article briefs)
- **Capacity-Aware Planning**: Plans that account for real constraints rather than ideal-state assumptions
