# Marketing Audit and Brand Alignment Spec

**Date:** 2026-02-21
**Branch:** feat-marketing-audit
**Brainstorm:** knowledge-base/brainstorms/2026-02-21-marketing-audit-brainstorm.md

## Problem Statement

Soleur's internal marketing infrastructure (12 agents, CMO domain leader, SEO/AEO skill) far exceeds its external marketing presence. Brand voice violations exist across multiple public surfaces. GitHub metadata is incomplete. The root README conflates vision with product docs. Zero analytics means no measurement foundation. 465 unique cloners with 3 stars represents a 99.4% silent-user rate.

## Goals

1. Achieve brand voice consistency across all public surfaces (GitHub, README, llms.txt, docs)
2. Restructure root README as focused product documentation
3. Complete GitHub metadata (homepage URL, description, topics)
4. Add privacy-respecting analytics to the docs site
5. Improve getting-started page conversion for cold visitors
6. Produce a comprehensive marketing strategy document for future execution

## Non-Goals

- Creating social media accounts
- Implementing email capture form
- Writing blog content or pillar pages
- Building comparison/alternatives pages
- Implementing pricing page
- Shipping light mode (Solar Radiance)

## Functional Requirements

- **FR1:** GitHub repo description must use declarative brand voice (no hedging, no prohibited words)
- **FR2:** GitHub homepage URL must point to soleur.ai
- **FR3:** Root README must lead with product value, install, and workflow -- not vision manifesto
- **FR4:** All public surfaces must use "platform" instead of "plugin" or "tool" per brand guide
- **FR5:** Brand guide component counts must reflect actual counts (45 agents, 45 skills)
- **FR6:** Getting-started page must explain what Soleur is and why before the install command
- **FR7:** Website must include a subtle GitHub star badge
- **FR8:** Marketing strategy document must cover content pillars, distribution channels, email capture, social proof, and conversion optimization
- **FR9:** Marketing strategy must cross-reference existing GitHub issues (#133, #188)

## Technical Requirements

- **TR1:** Plausible analytics script must be added to docs site base template
- **TR2:** Plausible integration must be cookie-free (no consent banner requirement)
- **TR3:** GitHub topics must include high-traffic tags for discoverability
- **TR4:** All changes must pass existing SEO validation CI (`validate-seo.sh`)
- **TR5:** llms.txt must be updated to use "platform" terminology

## Success Criteria

- Zero brand voice violations across GitHub description, README, llms.txt
- GitHub About section shows soleur.ai homepage link
- Root README can be read by a cold visitor in under 30 seconds and they understand what to do
- Plausible analytics tracking page views on soleur.ai
- Marketing strategy document exists with actionable recommendations and issue references
- Brand guide counts match reality
