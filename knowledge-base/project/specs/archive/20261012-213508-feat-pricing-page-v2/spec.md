---
feature: pricing-page-v2
issue: 656
status: draft
created: 2026-03-25
---

# Pricing Page v2 — Value-First Redesign

## Problem Statement

The current pricing page (PR #1096) was built as a pencil.dev dogfooding exercise without product/marketing/sales input. It presents unvalidated pricing, leads with "free" when the business needs to establish value, and has superficial competitive positioning. The page needs a complete redesign aligned with the new concurrent-agent-slot pricing model.

## Goals

- G1: Establish Soleur as worth paying for through value articulation (replacement stack math + expertise access)
- G2: Introduce the concurrent-agent-slot pricing model as marketing infrastructure (Coming Soon + waitlist)
- G3: Capture demand signals via waitlist email collection
- G4: Serve as a validation artifact for founder interviews

## Non-Goals

- Payment infrastructure (no Stripe, no checkout)
- Free cloud tier (web platform not built yet)
- Interactive cost calculator (defer to v3)
- Competitor comparison table (replaced by hiring comparison)

## Functional Requirements

- FR1: Hero section with "Every department. One price." headline and value subline
- FR2: Hiring comparison table showing role costs (Marketing Director $8k/mo, General Counsel $15k/mo, etc.) vs. "Included with Soleur"
- FR3: Department roster displaying all 8 departments with domain leaders and specialist agent counts
- FR4: Scenario callout cards showing real-world value (privacy policy drafting, competitor response, etc.)
- FR5: Tier cards for Solo ($49), Startup ($149), Scale ($499), Enterprise (Contact us), and Self-hosted (Free)
- FR6: All paid tiers display "Coming Soon" badge with waitlist CTA
- FR7: Self-hosted tier links to getting-started page
- FR8: FAQ section addressing top objections (why pay for AI, concurrent slots explained, Claude cost, rev share, product status)
- FR9: Final CTA section with waitlist email capture
- FR10: Zero instances of the word "plugin" — use "platform" per brand guide

## Technical Requirements

- TR1: Eleventy/Nunjucks template using existing `base.njk` layout
- TR2: FAQPage JSON-LD schema for pricing questions
- TR3: SoftwareApplication + Offer schema for tier pricing
- TR4: Updated OG image reflecting new messaging (not "$0")
- TR5: Responsive layout tested at 1440px, 768px, 375px breakpoints
- TR6: Dynamic stats from `_data/site.json` (agent count, skill count, department count)
- TR7: Brand guide color palette and typography compliance
