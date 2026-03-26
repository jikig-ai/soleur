# Synthetic User Research & Outcome-Based Pricing Brainstorm

**Date:** 2026-03-26
**Participants:** Founder, CPO, CMO, CFO
**Source:** [Synthetic Users and Outcome Pricing](https://ivelin117.substack.com/p/synthetic-users-and-outcome-pricing) by Ivelin (2026)
**Status:** Decided

## What We're Building

Two workstreams from a single exploration:

### Workstream 1: Internal Synthetic Research Sprint (Immediate)

A structured synthetic persona sprint to sharpen Soleur's own validation pipeline. 8-12 AI-generated founder personas run through three sequential gates:

1. **Interview prep gate** — Personas answer the existing interview guide (validation-outreach-template.md). Identify flat/unhelpful questions, rewrite them.
2. **Value prop gate** — Test three framings: (a) CaaS positioning, (b) pain-point-first ("stop hiring, start delegating"), (c) tool-replacement ("one platform, 8 departments"). Score resonance and confusion.
3. **Pricing gate** — Test $49/mo flat, $29/mo base + per-outcome hybrid, and pure outcome-based pricing. Collect objection patterns and directional willingness-to-pay signals.

Output: a research brief that informs the next 8 real founder interviews, plus rehearsal simulations for specific upcoming interviews.

### Workstream 2: User-Facing Capability (Deferred)

Productize synthetic user research as a Soleur capability for founders. Architecture TBD — decided after dogfooding Workstream 1 internally. Candidates: standalone skill, embedded in business-validator, or cross-domain research agent.

## Why This Approach

**Article thesis:** Traditional SaaS validation (100 interviews, per-seat pricing) is obsolete. AI-generated personas compress months of research into hours. Outcome-based pricing aligns vendor/customer incentives.

**Why it matters for Soleur now:**

- PIVOT verdict requires 10 real founder interviews; ~2 completed. Synthetic personas accelerate question refinement without replacing real conversations.
- 0/5 pricing gates passed. Synthetic pricing sensitivity tests surface objection patterns before real willingness-to-pay conversations.
- CaaS is a novel category — synthetic personas may struggle with the category framing but CAN reason about the underlying pain points (hiring costs, context switching, tool sprawl).

**Why Hybrid A+C approach:**

- Structured sprint (A) produces a reusable research brief and becomes the prototype for the user-facing capability.
- Interview rehearsal (C) directly improves the quality of the next real conversations.
- Combining both means the sprint output feeds directly into execution.

## Key Decisions

1. **Synthetic results are hypotheses only, never validation evidence.** The 10 real founder interviews remain the gold standard. Synthetic personas sharpen questions and surface patterns — they don't pass validation gates.

2. **Frame around known pain points, not the CaaS label.** The article warns synthetic users fail in novel categories. CaaS is a novel label but the underlying needs (delegation, business ops automation, tool consolidation) are well-understood. Personas should react to problems, not category names.

3. **Include pricing sensitivity testing.** Test three models ($49/mo flat, hybrid base+outcome, pure outcome-based) against personas. Even if premature to commit, objection patterns inform real interview design.

4. **Dogfood before productizing.** Run the internal sprint first. Use what we learn about persona design, gate structure, and signal quality to decide how to build this for Soleur users. Architecture decision deferred.

5. **Record outcome-based pricing in pricing strategy, don't commit.** Add it as a 5th alternative model in pricing-strategy.md with the analysis from this brainstorm. Don't promote it to the recommendation until pricing gates have data.

## Open Questions

1. **Persona design quality.** What demographic/psychographic dimensions matter most for solo founder personas? Revenue stage ($0, $1-10K, $10-50K MRR)? Technical depth? Industry vertical? Domain pain (marketing-heavy vs. engineering-heavy)?

2. **Measurable outcomes per domain.** If outcome-based pricing is ever viable, what is the atomic unit per domain? Engineering: merged PR. Legal: completed contract. Marketing: published content. But advisory domains (finance, product) produce decision quality, not countable events.

3. **Rebranding "synthetic."** The CMO flagged that "synthetic" is off-brand (3 content audit flags on "synthetic labor"). Candidate terms for user-facing capability: "AI research personas," "founder-proxy interviews," "simulated validation." Decision deferred to productization phase.

4. **Compounding value problem.** The CFO identified that Soleur's value compounds over time (the 100th brainstorm > the 1st). Outcome-based pricing treats each event as equal. Does a hybrid model (base subscription + outcome bonuses) solve this, or does it add billing complexity that a pre-PMF product shouldn't have?

5. **Negative outcome pricing.** The CFO raised: a kill criterion that saves 3 months of wasted work has enormous value but no natural pricing unit. How does outcome-based pricing account for "we prevented you from making a mistake"?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Sequencing problem — both concepts are directionally right but premature to implement as product changes. Synthetic user research has a legitimate immediate use (sharpening interview questions). Outcome-based pricing faces a fundamental attribution problem: Soleur's value is cross-domain compounding knowledge, not discrete tasks. The $49/mo hypothesis should not be displaced until pricing gates have real data. Recommended path: record concepts, use synthetic personas for interview prep, defer productization.

### Marketing (CMO)

**Summary:** "Synthetic" is already flagged as off-brand in 3 content audits — needs reframing for any user-facing use. Outcome-based pricing contradicts the existing rejection of usage-based pricing (Replit backlash) unless clearly differentiated. Strong opportunity: no CaaS competitor uses outcome-based pricing, making it a potential positioning wedge against Polsia. The $300B SaaS correction narrative should inform internal strategy, not external messaging. Recommended: internal research sprint yes, public positioning changes no.

### Finance (CFO)

**Summary:** No cost model exists yet (flagged as overdue). Outcome-based pricing introduces revenue forecasting complexity before there is revenue to forecast. Core problem: most Soleur domains produce advisory outputs where value accrues over time, not per execution. Intercom's model works because each chat resolution is discrete and attributable — Soleur's cross-domain compounding doesn't decompose that way. Hybrid model (base + outcome bonus) deserves evaluation as a compromise. Recommended: build per-user cost model first, add outcome-based as 5th alternative in pricing strategy, don't commit.

## Capability Gaps

- **Per-user cost model:** CFO flagged this as overdue. Cannot evaluate any pricing model without knowing marginal costs. Required before outcome-based pricing can be seriously analyzed.
- **Synthetic user research methodology:** No existing tooling, personas, or research protocols. The internal sprint will establish the first version.
- **Outcome metering infrastructure:** If outcome-based pricing is ever adopted, the platform needs event tracking, attribution, and per-domain outcome counting. Not needed now but noted for architecture awareness.
