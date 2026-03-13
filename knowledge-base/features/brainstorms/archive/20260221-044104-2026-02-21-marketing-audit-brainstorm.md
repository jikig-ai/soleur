# Marketing Audit Brainstorm

**Date:** 2026-02-21
**Participants:** User, CMO Agent, Repo Research Agent, Learnings Researcher
**Status:** Complete

## What We're Building

A comprehensive marketing audit and alignment pass across all public-facing surfaces (website, GitHub, brand guide, docs) plus a marketing strategy document that sequences future work. This is the first dogfood run of the CMO Domain Leader agent.

### Scope

1. **Brand consistency fix** -- Fix all brand voice violations across GitHub description, README, llms.txt, and stale brand guide counts
2. **README restructure** -- Transform root README from vision manifesto + install guide into focused product README
3. **GitHub metadata alignment** -- Set homepage URL, update description, optimize topics
4. **Brand guide refresh** -- Update stale component counts (31 agents/40 skills -> 45/45)
5. **Plausible analytics** -- Add privacy-respecting analytics to the docs site (cookie-free, no consent banner needed)
6. **Star CTA** -- Add subtle star badge to website (no CLI prompts, no aggressive growth loops)
7. **Getting-started page** -- Add "why Soleur" context before the install command
8. **Marketing strategy document** -- Comprehensive strategy covering content pillars, distribution channels, email capture, social media, and conversion optimization

### Out of Scope (This Phase)

- Creating social media accounts (strategy doc only)
- Implementing email capture form (strategy doc only)
- Writing blog content or pillar pages (strategy doc only)
- Comparison/alternatives pages
- Pricing page
- Light mode (Solar Radiance)

## Why This Approach

### Current State Assessment (CMO Findings)

**Overall grade:** Technically excellent product with pre-launch marketing maturity.

**Key metrics:**
- 465 unique cloners in 14 days -- strong adoption signal
- 3 stars -- 99.4% silent users (critical conversion gap)
- 2 organic search visits in 14 days -- SEO is non-functional despite solid infrastructure
- Zero social media presence, zero blog content, zero email capture

**What's working:**
- Brand guide is comprehensive and well-structured (B+)
- Website design faithfully executes brand guide (B)
- Technical SEO infrastructure is ahead of most projects (B+)
- AEO with llms.txt is ahead of the curve (A-)
- Legal pages are complete (A)
- Product velocity is real (51 releases)

**What's broken:**
- Brand voice leaks: "meant to be" (hedging), "AI-powered" (prohibited), "plugin" (prohibited)
- GitHub homepage URL is blank
- Root README mixes vision manifesto with install docs
- Brand guide component counts stale (31/40 vs actual 45/45)
- Zero content marketing (blog, social, email)
- No analytics -- completely blind on visitor behavior
- Getting-started page jumps to install with no context
- Website has zero social proof

### Brand Consistency Scorecard

| Dimension | Score (1-5) |
|-----------|-------------|
| Voice consistency | 3.5 |
| Visual consistency | 4.5 |
| Messaging hierarchy | 3.0 |
| Terminology discipline | 2.5 |
| Data accuracy | 2.0 |

## Key Decisions

1. **README approach:** Focused product README. Move vision/thesis to website or VISION.md.
2. **Star conversion:** Subtle mentions only (star badge on website, getting-started mention). No CLI prompts or aggressive loops. Let the product earn stars.
3. **Content scope:** Fix foundations + produce strategy doc. No new content pages in this phase.
4. **Analytics:** Add Plausible (cookie-free, GDPR-compliant without consent banner).
5. **Social media:** Document strategy only. No account creation yet.
6. **Email capture:** Document in strategy only. Implement later.

## Related GitHub Issues

### Open Issues (Will Be Addressed or Linked)

- **#188** - Add cookie consent banner when analytics are added
  - NOTE: Plausible is cookie-free and GDPR-compliant. This issue may NOT be triggered. Update issue with Plausible decision and close or defer.
- **#133** - Add Sign up Waitlist Form to website
  - Related to email capture strategy. Will be referenced in the marketing strategy doc but not implemented this phase.

### Closed Issues (Prior Art)

- **#174** - Merge marketingskills into Soleur (CLOSED) -- established the 12 marketing agents
- **#165** - Research marketingskills overlap (CLOSED) -- competitive analysis complete
- **#164** - Study seo-geo for GEO/AEO methodology (CLOSED) -- Princeton research incorporated
- **#154** - CMO agent exploration (CLOSED) -- CMO domain leader now exists
- **#153** - Growth-strategist execution capabilities (CLOSED)
- **#148** - Growth-strategist agent + skill (CLOSED)
- **#149** - Community hub page (CLOSED)
- **#131** - Add SEO/AEO to website (CLOSED)
- **#94** - Update brand identity and website messaging (CLOSED)
- **#88** - Publish brand website (CLOSED)
- **#76** - Integrate brand-architect into brainstorm (CLOSED)
- **#71** - Brand vision, strategy & marketing tools (CLOSED)
- **#59** - Automate release announcements on social media (CLOSED)
- **#35** - Community & contributor audit (CLOSED)

## CMO Priority Recommendations

### Critical (This Phase -- Implement Now)

| # | Gap | Action |
|---|-----|--------|
| 1 | GitHub description hedges | Rewrite: remove "meant to be", use declarative brand voice |
| 2 | Homepage URL missing from GitHub | `gh repo edit --homepage https://soleur.ai` |
| 3 | Brand guide counts stale | Update 31/40 to 45/45 |
| 4 | Root README identity crisis | Restructure as focused product README |
| 5 | No analytics | Add Plausible to docs site base template |
| 6 | Star conversion gap | Add subtle star badge to website |
| 7 | Getting-started lacks "why" | Add value prop before install command |

### Strategy Doc (This Phase -- Document for Later Execution)

| # | Topic | Notes |
|---|-------|-------|
| 8 | Content pillar strategy | 3-5 pillar topics for SEO |
| 9 | Social media plan | Platform choice, cadence, content types |
| 10 | Email capture plan | Tool, placement, messaging |
| 11 | Social proof strategy | Testimonials, case studies, star growth |
| 12 | Comparison pages | "Soleur vs X" competitive positioning |
| 13 | Programmatic SEO | "Soleur for [framework]" pages |
| 14 | GitHub topics optimization | Add high-traffic tags |
| 15 | URL canonical alignment | Verify soleur.ai vs www.soleur.ai |

## Open Questions

1. Should the vision manifesto go to a `VISION.md` in the repo or exclusively to the website?
2. What Plausible plan? Self-hosted or cloud? (Affects analytics implementation)
3. Should #188 (cookie consent) be closed as "won't need" since Plausible is cookie-free, or kept open as a safeguard?

## Institutional Knowledge Applied

- **marketingskills overlap analysis** -- Our moats: Eleventy specificity, AEO dual focus, brand voice enforcement, lifecycle integration, knowledge-base output
- **GEO/AEO methodology** -- Citations +30-40%, statistics +40%, keyword stuffing -10%. Authority > keywords.
- **Brand guide contract** -- Exact headings: Identity, Voice, Visual Direction, Channel Notes. Contracts beat schemas.
- **Static docs from brand guide** -- Extract CSS vars directly from brand guide. Component inventory reads from source.
- **GitHub Pages + Cloudflare wiring** -- Correct DNS ordering documented. URL canonical issues noted.
