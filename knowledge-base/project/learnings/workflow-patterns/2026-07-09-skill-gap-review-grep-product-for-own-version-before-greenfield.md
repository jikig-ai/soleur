---
date: 2026-07-09
category: workflow-patterns
tags: [brainstorm, skill-library-review, premise-validation, domain-leader]
source_pr: 6259
source_issue: 6260
---

# Skill-gap review: grep the product for its OWN version of a capability before accepting a "no skill exists" gap as greenfield

## Context

During a skill-library review that converged on a missing `/soleur:invoice` skill, the CPO
lens framed it as "a hard Phase-4 payments prerequisite — no skill sends an invoice." A
30-second grep of the product before spawning the finance/legal/eng leaders showed that was
half-stale:

- `apps/web-platform/` already has a **billing page + Stripe webhook + `lib/stripe.ts`**.
- Roadmap **3.14 "Invoice history + failed payment handling" (#1079) → Done**.
- Roadmap **4.10 "Stripe live mode activation" (#1444) → Done**.

That infra is **Soleur billing its founders** (its own subscription revenue) — already shipped.
The genuine gap was a *different* thing: a founder invoicing **their own customers**, on a
**different Stripe account** (the MCP OAuth plane, not the product `STRIPE_SECRET_KEY`).

## The pattern

A domain leader assessing "what capability is missing" reasons about the *product category*,
and can conflate **the product's own use of a capability** (often already built) with **the
end-user's use of it** (the real gap). The two frequently differ by *whose account / whose data*.

**Before accepting a "no skill/capability exists" gap as greenfield:** grep the product
codebase + roadmap for the product's own version of that capability. If it exists, re-frame
the gap precisely — usually it survives, but as a *different actor/account/data* scope than the
leader stated, which changes the credential model, compliance surface, and design.

## Applies to

Any skill-library or capability-gap brainstorm where the missing capability (invoice, email,
auth, analytics, notifications) is something the *product itself* also does. The tell: the
capability name appears both in the product's runtime code AND as a proposed new user-facing skill.

Related: the brainstorm-skill premise-validation rules already say to verify cited PR/issue
state and capability claims against `main` — this is the same discipline applied to a
*domain-leader's* framing, not just an issue body.
