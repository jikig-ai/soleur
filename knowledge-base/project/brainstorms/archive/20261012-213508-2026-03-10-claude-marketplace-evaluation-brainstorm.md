# Claude Marketplace Evaluation

**Date:** 2026-03-10
**Status:** No-go (revisit April 2026)
**Trigger:** Community member Arslan shared claude.com/platform/marketplace in Discord #general — "This could turn out to be a good way to get visibility and distribution."

## What We Investigated

Whether the Claude Marketplace at claude.com/platform/marketplace is a viable distribution channel for Soleur.

## What We Found

**The Claude Marketplace is not a plugin directory.** It is an enterprise procurement platform in limited preview where organizations use existing Anthropic spending commitments to pay for third-party Claude-powered solutions.

| Expected | Actual |
|----------|--------|
| Browse-and-install plugin directory | Enterprise procurement platform |
| Self-service listing | Partner waitlist + sales contact |
| Consumer/developer audience | Enterprise teams |
| Install counts, ratings, search | No public listings visible |
| Free to list | Revenue share model (terms unknown) |

### Key Facts

- **Limited preview** — no public listings, no self-service submission
- **Two CTAs only:** "Contact sales" (enterprise buyers) and "Join partner waitlist" (vendors)
- **Enterprise-focused:** "Claude-powered tools built for enterprise teams"
- **Billing layer:** Organizations deploy Anthropic spending commitment across partner apps
- **No overlap with plugin registry:** This is a separate surface from `claude plugin install`

## Why Not Now

1. **Soleur has no enterprise positioning.** Free open-source plugin with no pricing, no enterprise customers, and a PIVOT verdict saying "validate demand first."
2. **Revenue model undefined.** Can't participate in a procurement marketplace without a price.
3. **Platform too early.** Limited preview with no visible partner ecosystem yet.
4. **PIVOT validation takes priority.** The business validation (2026-03-09) says the next step is 10 founder interviews, not more distribution surface.

## Prior Analysis

This overlaps with the Feb 25 Cowork risk brainstorm "Option D: Ride Cowork's Distribution" — though the marketplace turned out to be a different surface entirely (enterprise procurement vs. plugin browsing). The strategic concerns about platform dependency still apply.

## Key Decisions

- **No-go for now.** The marketplace doesn't fit where Soleur is today.
- **Revisit in April 2026** when the marketplace matures and Soleur has clearer enterprise positioning.
- **Existing marketplace.json needs cleanup regardless** — it violates the brand guide (uses "plugin" twice) and miscategorizes as "productivity."

## Open Questions (for revisit)

- What are the actual partner terms (revenue share, listing requirements)?
- Does the marketplace support Claude Code plugins or only web apps?
- What does the partner ecosystem look like once it launches publicly?
- Would enterprise positioning align with the validated revenue model (if any)?
