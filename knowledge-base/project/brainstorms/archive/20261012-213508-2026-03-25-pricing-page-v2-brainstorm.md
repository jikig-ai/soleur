---
date: 2026-03-25
topic: Pricing page v2 — proper redesign with pricing model and value-first structure
status: accepted
issue: "#656"
---

# Pricing Page v2

## What We're Building

A complete redesign of the soleur.ai pricing page. The previous version (PR #1096) was built as a pencil.dev dogfooding exercise without proper product/marketing/sales input. It presented a fictional $49/mo tier, had a superficial comparison table, and didn't align with the pricing strategy or business validation findings.

The new page introduces a real pricing model (concurrent agent slots by company stage), leads with value articulation rather than "free", and serves as marketing infrastructure for the web platform waitlist.

## Why This Approach

The v1 pricing page had three fundamental problems:

1. **Presented unvalidated pricing.** "Hosted Pro $49/mo + 10% revenue share" was not a real offering — the pricing strategy doc explicitly said "pricing is undecided" and 0/5 validation gates had passed.
2. **Wrong framing.** Led with "free" when the business needs to establish that Soleur is *worth paying for*. Self-hosted free is an option, not the headline.
3. **Superficial competitive positioning.** Compared against coding tools (Cursor, Devin, Copilot) with dashes for non-engineering domains, ignoring that competitors have expanded (Cursor: 30+ marketplace plugins, Notion: 21,000+ agents, Polsia: multi-domain).

## Key Decisions

### 1. Pricing Model: Concurrent Agent Slots by Company Stage

| Tier | Price | Concurrent Agents | Includes |
|------|-------|-------------------|----------|
| **Solo** | $49/mo | 2 | All 8 departments, full agent roster |
| **Startup** | $149/mo | 5 | Priority execution, all departments |
| **Scale** | $499/mo | Unlimited | Dedicated infrastructure, all departments |
| **Enterprise** | Rev share (sliding scale) | Custom | Kicks in at $10M+ ARR, replaces subscription |
| **Self-hosted** | Free (Apache-2.0) | N/A | CLI plugin, local knowledge base |

**Why concurrent slots:** Maps directly to compute cost (more parallel = more infra), creates natural expansion as company grows, preserves "integration IS the product" thesis (all departments always accessible), and enables the "cheaper than people" comparison.

### 2. Enterprise Revenue Share: Sliding Scale by ARR Band

- 10% at $10M-25M ARR
- 7% at $25M-50M ARR
- 5% at $50M+ ARR

Revenue share replaces subscription at enterprise scale. Does NOT position against Polsia's rev share — find different competitive angles instead.

### 3. Page Structure: Value-First Flow

1. **Hero** — "Every department. One price." + subline about what Soleur replaces
2. **Hiring comparison table** — Role-by-role cost comparison (Marketing Director $8k/mo → Included, etc.)
3. **Department roster** — All 8 departments with domain leaders and specialist agents
4. **Scenario callouts** — "Need a privacy policy? Your CLO drafts it." Real-world value proof.
5. **Tier cards** — Solo/Startup/Scale/Enterprise with "Join Waitlist" CTAs (Coming Soon)
6. **Self-hosted callout** — Free option mentioned, not the lead
7. **FAQ** — Objection-handling disguised as questions
8. **Final CTA** — Waitlist capture

### 4. Framing: Expertise Access, Not Just Cost Savings

The page must communicate two value layers:

- **Layer 1 (math):** Hiring comparison — $50k+/mo in roles vs. from $49/mo
- **Layer 2 (capability):** Expertise you can't otherwise access — a solo founder doesn't have a CLO, CFO, or CRO at any price. Soleur provides domain expertise that would be impossible to hire at this stage.

### 5. Current Status: Marketing Infrastructure, Not Payment Infrastructure

- All paid tiers show "Coming Soon" with waitlist email capture
- No payment flow, no Stripe integration
- Page serves as validation artifact for founder interviews
- Self-hosted CLI plugin remains the only live offering
- Web platform (app.soleur.ai) is not yet built

### 6. Brand Compliance

- Remove all instances of "plugin" — use "platform" per brand guide
- No leading with "free" — self-hosted is an option, not the identity
- Follow brand voice: declarative, no hedging, no qualifiers

## Open Questions

1. **FAQ content:** What objections should the FAQ preemptively address? CRO identified 5 expected objections (price anchoring against $20 tools, "why pay for AI?", concurrent slots comprehension, rev share concern, "where's the product?").
2. **Department roster format:** Visual org chart grid vs. icon-based cards vs. expandable list?
3. **Social proof:** No customer testimonials yet. What replaces social proof on the page? Build stats (420+ PRs across 8 domains)?
4. **Waitlist implementation:** Simple email capture or more structured form (company stage, departments interested in)?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** The redesign is a complete persuasion architecture rebuild — from "Soleur is free" to "Soleur is worth paying for." Replace all 7 instances of "plugin" with "platform." CTAs must match the actual user journey (waitlist for paid, install for self-hosted). Recommends conversion-optimizer for layout review, copywriter for full page copy, and fact-checker for competitor pricing claims. Biggest risk: shipping specific prices before validation.

### Product (CPO)

**Summary:** Recommends treating this as marketing infrastructure (no payment flow). The concurrent-agent-slot model is strategically sound — preserves integration thesis, maps to compute cost, natural expansion. Key gap: no free cloud tier for founders who won't self-host. Suggests using the redesigned page as a validation artifact in founder interviews to test whether "concurrent agent slots" is comprehensible. Engineering needs to eventually build concurrency enforcement; Finance needs a per-slot cost model.

### Sales (CRO)

**Summary:** The tier structure is competitive if the page leads with the replacement-stack frame ($49 vs. $50k+/mo in roles). Revenue share at Enterprise directly conflicts with anti-Polsia "you keep 100%" messaging — resolved by keeping rev share but dropping the Polsia angle. The $149 Startup tier is a 3x jump from Solo — may need justification via concrete feature differences. Recommends an interactive "replacement cost calculator" as the strongest conversion element.
