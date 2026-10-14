# Spec: Synthetic User Research Sprint + Outcome-Based Pricing Analysis

**Status:** Draft
**Branch:** synthetic-users-outcome-pricing
**Brainstorm:** [2026-03-26-synthetic-users-outcome-pricing-brainstorm.md](../../brainstorms/2026-03-26-synthetic-users-outcome-pricing-brainstorm.md)

## Problem Statement

Soleur's PIVOT verdict requires 10 real founder interviews but only ~2 have been completed. The current interview guide and value proposition framing are untested at scale. Meanwhile, 0/5 pricing gates have passed and outcome-based pricing (a model gaining traction in the $300B SaaS correction) has never been evaluated against the existing pricing strategy. The founder needs a faster way to sharpen validation questions, test value prop framings, and surface pricing objection patterns before the next batch of real conversations.

## Goals

1. **G1:** Produce a synthetic research brief that directly improves the next 8 real founder interviews (question quality, value prop clarity, anticipated objections).
2. **G2:** Test three pricing models ($49/mo flat, hybrid base+outcome, pure outcome-based) against synthetic personas to surface objection patterns.
3. **G3:** Record outcome-based pricing as a formally evaluated alternative in pricing-strategy.md.
4. **G4:** Establish a reusable persona design and research gate methodology that can later be productized for Soleur users.

## Non-Goals

- Replacing real founder interviews with synthetic results.
- Committing to a pricing model change.
- Building a user-facing synthetic research capability (deferred until after internal dogfooding).
- Running synthetic research on emotionally-laden or regulated verticals.

## Functional Requirements

- **FR1:** Design 8-12 synthetic founder personas covering the ICP spectrum (varying by revenue stage, technical depth, domain pain, industry vertical).
- **FR2:** Run interview prep gate — each persona answers the existing validation-outreach-template.md interview guide. Identify weak questions.
- **FR3:** Run value prop gate — test CaaS positioning, pain-point-first, and tool-replacement framings. Score resonance per persona.
- **FR4:** Run pricing gate — present three pricing models, collect objection patterns and directional WTP signals.
- **FR5:** Produce a research brief synthesizing findings across all three gates with actionable recommendations for real interviews.
- **FR6:** Run rehearsal simulations for any specific upcoming interviews using persona variants matched to known founders.

## Technical Requirements

- **TR1:** All persona definitions and research outputs stored in knowledge-base/ for compounding value.
- **TR2:** Research brief must reference which findings are high-confidence (consistent across personas) vs. low-confidence (split or contradictory).
- **TR3:** Pricing analysis must be compatible with the existing pricing-strategy.md structure for seamless integration.
