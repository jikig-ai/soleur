---
title: "feat: Synthetic User Research Sprint + Outcome-Based Pricing Analysis"
type: feat
date: 2026-03-26
---

# feat: Synthetic User Research Sprint + Outcome-Based Pricing Analysis

## Overview

Run 10 synthetic founder personas through the interview guides, value prop framings, and pricing models. Produce a research brief that sharpens the next 8 real founder interviews. Then add outcome-based pricing to the pricing strategy document. Knowledge-base deliverables only — no code changes.

## Problem Statement

Soleur's PIVOT verdict requires 10 real founder interviews but only ~2 have been completed. Two interview guides exist (15-min outreach version and 30-min rigorous research instrument) — neither has been stress-tested. Three value prop framings compete with no data on which resonates. Outcome-based pricing has never been evaluated against the existing pricing strategy. The founder needs faster signal generation before the next batch of real conversations.

## Steps

### Step 1: Design 10 founder personas

Write 10 personas to `knowledge-base/product/research/personas/`. Vary across revenue stage ($0 / $1-5K / $5-50K MRR), technical depth (deep / moderate / low), domain pain (engineering / marketing / legal / ops), and industry (SaaS / dev tools / creative / consulting / e-commerce).

Each persona: 5-6 lines covering background, revenue, technical depth, primary pain, current tools, and AI attitude.

Constraints:

- At least 2 at pre-revenue
- At least 2 who do NOT use Claude Code (per 2026-03-22 validation finding)
- At least 1 AI skeptic and 1 non-technical founder
- Cover all 4 domain pain categories

### Step 2: Run personas through interview guides

Run each persona through both interview guides:

- 15-min version: `knowledge-base/marketing/validation-outreach-template.md` (6 questions)
- 30-min version: `knowledge-base/project/specs/feat-product-strategy/interview-guide.md` (12 questions)

For each question, note whether the response reveals genuine pain or falls flat. Rewrite flat/confused questions. Note what the guides miss.

**Output:** `knowledge-base/product/research/interview-prep-findings.md`

### Step 3: Test value prop framings

Show each persona three framings:

| Framing | Headline |
|---------|----------|
| **CaaS** | "Your AI company" — departments sharing one compounding knowledge base |
| **Pain-point** | "Stop hiring, start delegating" — 8 jobs delegated to AI agents |
| **Tool-replacement** | "One platform, 8 departments" — replace $765-3,190/month tool stack |

For each persona: which framing resonates, which confuses, and what's the top objection? No numerical scoring — just "this one won" or "none landed" per persona.

**Output:** `knowledge-base/product/research/value-prop-findings.md`

### Step 4: Test pricing models

Show each persona three models:

| Model | Structure |
|-------|-----------|
| **Flat subscription** | $49/month for everything |
| **Hybrid** | $29/month base + per-outcome bonuses |
| **Pure outcome-based** | $0 base, pay per measurable result |

Collect: objection patterns, whether they distinguish outcome-based from usage-based (the Replit backlash question), and what monthly budget feels right. The dollar amounts are not data — the objection themes are the deliverable.

**Output:** `knowledge-base/product/research/pricing-findings.md`

### Step 5: Write research brief

Compile findings from Steps 2-4 into one actionable brief.

**Output:** `knowledge-base/product/research/synthetic-research-brief.md`

Structure:

1. **Executive summary** — 3-5 top findings that change how the next 8 interviews are conducted
2. **Interview guide improvements** — specific question rewrites and additions
3. **Value prop recommendation** — lead framing, segment-specific variations
4. **Pricing signals** — objection patterns, model preference themes
5. **Confidence notes** — which findings were consistent across personas vs. split
6. **Limitations** — these are hypotheses, not validation evidence. CaaS novel-category risk flagged.

### Step 6: Add outcome-based pricing to pricing strategy

Add a 6th row to the "Alternative Models Considered" table in `knowledge-base/product/pricing-strategy.md`:

| Model | Pros | Cons | Verdict |
|-------|------|------|---------|
| **Outcome-based (per result)** | Aligns vendor/customer incentives. No CaaS competitor uses it — positioning wedge. Matches investor demand for measurable value. | Soleur's value is cross-domain compounding, not discrete tasks — Intercom's model doesn't map. Most domains produce advisory output (decision quality, not countable events). "Negative outcomes" (kill criteria) have value but no pricing unit. Unpredictability concern may trigger Replit backlash. BYOK creates double-pay perception. | Defer — structurally mismatched with compounding knowledge value. Re-evaluate after P4 validation when usage data shows which outcomes are discrete and attributable. Hybrid model deserves separate evaluation then. |

Add a note in "Next Steps" referencing the research brief as input for WTP conversations.

### Step 7 (optional): Interview rehearsals

If the founder has specific upcoming interviews, create rehearsal simulations matched to known founder profiles. Practice the full 15-minute flow including pushback. Skip if no interviews are imminent.

**Output (if done):** `knowledge-base/product/research/interview-rehearsals.md`

## Risks

| Risk | Mitigation |
|------|------------|
| Novel category limitation: personas can't reason about CaaS | Frame around known pain points (hiring costs, tool sprawl), not the CaaS label |
| Pricing sensitivity data is unreliable from synthetic personas | Treat as objection pattern collection, not WTP data. The value is in objection themes, not dollar amounts |

## Domain Review

**Domains relevant:** Product, Marketing, Finance (carried forward from brainstorm 2026-03-26)

- **CPO:** Directionally right but premature as product changes. Legitimate immediate use for interview prep. Defer productization.
- **CMO:** "Synthetic" is off-brand — reframe for user-facing use. Internal sprint yes, public positioning changes no.
- **CFO:** No cost model exists. Most domains produce advisory output. Add outcome-based as alternative, don't commit until gates pass.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-26-synthetic-users-outcome-pricing-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-synthetic-users-outcome-pricing/spec.md`
- Interview guides: `knowledge-base/marketing/validation-outreach-template.md`, `knowledge-base/project/specs/feat-product-strategy/interview-guide.md`
- Pricing strategy: `knowledge-base/product/pricing-strategy.md`
- Business validation (ICP): `knowledge-base/product/business-validation.md`
- Source article: [Synthetic Users and Outcome Pricing](https://ivelin117.substack.com/p/synthetic-users-and-outcome-pricing) (Ivelin, 2026)
- Issue: #1173
