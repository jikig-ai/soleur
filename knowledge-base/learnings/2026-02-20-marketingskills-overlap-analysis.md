---
title: marketingskills Plugin Overlap Analysis
category: discovery
tags:
  - marketing
  - competitive-analysis
  - growth
  - monitoring
module: marketing
date: 2026-02-20
next_review: 2026-05-20
---

# Learning: marketingskills Plugin Overlap Analysis

## Problem

The coreyhaines31/marketingskills plugin (8.5K stars, MIT license) has 29 skills covering CRO, SEO, paid ads, pricing, referrals, and growth strategy. Our growth-related components (4 agents + 3 skills) operate in the same space. The landscape discovery audit (Feb 2026) flagged this as the most comprehensive community marketing toolkit and recommended ongoing monitoring.

## Solution

Cataloged all 29 skills, reviewed 5 representative skills in depth (content-strategy, seo-audit, ai-seo, copywriting, pricing-strategy), and mapped overlap against our 7 marketing/growth components.

### Our Components

| Component | Type | Core Function |
|---|---|---|
| growth-strategist | Agent | Content strategy, keyword research, content auditing, AEO content analysis |
| seo-aeo-analyst | Agent | Technical SEO (JSON-LD, meta tags, sitemaps, llms.txt) for Eleventy |
| brand-architect | Agent | Brand identity workshops, brand guide generation |
| community-manager | Agent | Discord + GitHub engagement analysis and digests |
| growth | Skill | Delegates to growth-strategist: audit, fix, plan, aeo |
| seo-aeo | Skill | Delegates to seo-aeo-analyst: audit, fix, validate |
| content-writer | Skill | Article generation with brand voice, Eleventy frontmatter, JSON-LD |

### Their 29 Skills Catalog

| # | Skill | Category | Description |
|---|---|---|---|
| 1 | page-cro | CRO | Optimize marketing pages for conversions |
| 2 | signup-flow-cro | CRO | Enhance signup and trial activation |
| 3 | onboarding-cro | CRO | Improve post-signup activation |
| 4 | form-cro | CRO | Optimize lead capture forms |
| 5 | popup-cro | CRO | Design popups, modals, banners |
| 6 | paywall-upgrade-cro | CRO | In-app paywalls, upsell modals |
| 7 | copywriting | Content | Marketing copy for any page |
| 8 | copy-editing | Content | Edit and improve existing copy |
| 9 | cold-email | Content | B2B cold outreach emails |
| 10 | email-sequence | Content | Automated email flows and drip campaigns |
| 11 | social-content | Content | Social media content across platforms |
| 12 | seo-audit | SEO | Technical and on-page SEO diagnosis |
| 13 | ai-seo | SEO | Optimize for AI search engines and LLM citations |
| 14 | programmatic-seo | SEO | Create SEO pages at scale with templates |
| 15 | competitor-alternatives | SEO | Build comparison pages for SEO |
| 16 | schema-markup | SEO | Add and optimize structured data |
| 17 | paid-ads | Paid | Google, Meta, LinkedIn ad campaigns |
| 18 | ad-creative | Paid | Generate headlines, descriptions, ad creative |
| 19 | ab-test-setup | Measurement | Plan and implement A/B tests |
| 20 | analytics-tracking | Measurement | Set up analytics and event tracking |
| 21 | churn-prevention | Retention | Cancellation flows and payment recovery |
| 22 | free-tool-strategy | Growth | Plan free tools for lead gen |
| 23 | referral-program | Growth | Create referral and affiliate programs |
| 24 | marketing-ideas | Strategy | Generate SaaS marketing strategies |
| 25 | marketing-psychology | Strategy | Behavioral science for campaigns |
| 26 | launch-strategy | Strategy | Product launches and announcements |
| 27 | pricing-strategy | Strategy | Pricing decisions and monetization |
| 28 | product-marketing-context | Strategy | Product marketing context documentation |
| 29 | content-strategy | Strategy | Content planning and topic selection |

### Overlap Matrix

| Their Skill | Our Equivalent | Overlap | Differentiation | Convergence Risk |
|---|---|---|---|---|
| content-strategy | growth-strategist / growth plan | **High** | Both do keyword research and content planning. Theirs is general-purpose with pillar/cluster framework. Ours integrates brand voice and AEO. | Medium -- they could add AEO |
| seo-audit | seo-aeo-analyst / seo-aeo | **High** | Both audit technical SEO. Theirs is general-purpose across any site. Ours is Eleventy-specific with validation scripts and AEO dual focus. | Low -- framework specificity is deliberate |
| ai-seo | growth-strategist (AEO) + seo-aeo-analyst | **High** | Both optimize for AI discoverability. Theirs uses a Structure/Authority/Presence framework. Ours splits content-level AEO (growth-strategist) from technical AEO (seo-aeo-analyst). | Medium -- their framework is more structured |
| copywriting | content-writer | **Medium** | Theirs generates page copy (landing, pricing, about). Ours generates blog articles with Eleventy frontmatter and JSON-LD. Different content types. | Low -- different targets |
| schema-markup | seo-aeo-analyst | **Medium** | Theirs is dedicated structured data. Ours handles schema as part of broader SEO audit. | Low |
| copy-editing | content-writer (edit flow) | **Low** | Theirs edits existing copy. Ours generates new articles. | Low |
| social-content | discord-content | **Low** | Theirs covers all social platforms. Ours is Discord-specific with webhook posting. | Low |
| product-marketing-context | brand-architect | **Low** | Theirs creates PMM context docs. Ours creates brand identity guides. Different scope. | Low |
| page-cro (x6) | -- | **None** | No CRO equivalent in our toolkit | N/A |
| cold-email | -- | **None** | No email marketing skills | N/A |
| email-sequence | -- | **None** | No email automation skills | N/A |
| paid-ads | -- | **None** | No paid channel management | N/A |
| ad-creative | -- | **None** | No ad creative generation | N/A |
| ab-test-setup | -- | **None** | No A/B testing tools | N/A |
| analytics-tracking | -- | **None** | No analytics setup tools | N/A |
| churn-prevention | -- | **None** | No retention tools | N/A |
| free-tool-strategy | -- | **None** | No growth engineering tools | N/A |
| referral-program | -- | **None** | No referral program tools | N/A |
| marketing-ideas | -- | **None** | No ideation tools | N/A |
| marketing-psychology | -- | **None** | No behavioral science tools | N/A |
| launch-strategy | -- | **None** | No launch planning tools | N/A |
| pricing-strategy | -- | **None** | No pricing tools | N/A |
| programmatic-seo | -- | **None** | No programmatic SEO | N/A |
| competitor-alternatives | -- | **None** | No comparison page tools | N/A |

**Summary:** 3 High overlaps, 2 Medium, 3 Low, 21 None. Our overlap is concentrated in content strategy + SEO. Their breadth (CRO, paid, pricing, retention) is well beyond our scope.

### Skills Reviewed in Depth

**1. content-strategy** -- Comprehensive content planning with searchable vs shareable content distinction, pillar/cluster architecture, and a scoring matrix (customer impact, content-market fit, search potential, resources). Well-structured diagnostic approach. More detailed than our growth plan sub-command on content architecture, but lacks brand voice integration and AEO.

**2. seo-audit** -- Broad technical SEO audit covering crawlability, Core Web Vitals, E-E-A-T signals, and content depth. Notably warns about false positives from JavaScript-injected schema markup that web scraping cannot detect. General-purpose (not framework-specific). Our seo-aeo skill is narrower (Eleventy only) but deeper with validation scripts and AEO dual focus.

**3. ai-seo** -- Three-pillar framework: Structure (machine-extractable content), Authority (statistics +40% boost, expert attribution +30%), and Presence (third-party mentions). References monitoring tools (Otterly AI, Peec AI, ZipTie). More systematic framework than our AEO approach, which is split across two agents. Their authority pillar with citation-boosting percentages is actionable.

**4. copywriting** -- Page copy generation with modular section framework (hero, social proof, problem, solution, mechanism, objection handling, CTA). Establishes voice consistency upfront. Targets landing pages and marketing pages, not blog content. Complementary to our content-writer which targets blog articles.

**5. pricing-strategy** -- SaaS pricing with Van Westendorp and MaxDiff research methods, Good-Better-Best tier framework, value metric selection. Entirely outside our scope. No overlap.

## Key Insight

The marketingskills plugin is broad (29 skills across 8 categories) while we are deep (7 components focused on content + SEO + AEO). Only 3 of their 29 skills have high overlap with ours. Our moats are:

1. **Eleventy specificity** -- seo-aeo has validation scripts, template awareness, build integration
2. **AEO dual focus** -- content-level (growth-strategist) + technical (seo-aeo-analyst) is unique
3. **Brand voice enforcement** -- content-writer and growth require brand-guide.md
4. **Lifecycle integration** -- growth plan -> content-writer -> seo-aeo fix is a coherent pipeline
5. **Knowledge-base output** -- our tools write to learnings/, brainstorms/, plans/

Their moats are breadth (CRO, paid ads, pricing, retention, referrals) and general-purpose applicability. They serve a different user: a marketing generalist optimizing across channels. We serve a developer building and documenting a product.

**No convergence threat in the short term.** Their growth is horizontal (more marketing domains). Ours is vertical (deeper integration in our stack). Watch for: if they add AEO capabilities or framework-specific modes.

### Technique Opportunities

**1. Structure/Authority/Presence framework (from ai-seo).** Their three-pillar AEO model is more systematic than our current approach. Consider adopting the framework terminology in growth-strategist's AEO audit output. The authority pillar's citation-boosting statistics (+40% for data, +30% for expert quotes) could inform our AEO content recommendations.

**2. Searchable vs shareable content distinction (from content-strategy).** Useful mental model for content planning. Our growth plan sub-command could classify recommended content pieces this way.

**3. JavaScript schema detection warning (from seo-audit).** Their explicit warning about false positives from JS-injected structured data is a valid concern. Our seo-aeo-analyst should note this limitation when auditing built output vs source templates.

All three are patterns to consider, not immediate actions. Attribution: coreyhaines31/marketingskills (MIT license).

## Quarterly Monitoring Cadence

Suggested quarterly review of the marketingskills plugin:

- **Next review:** May 2026
- **What to check:** Star count trend, new skills added (compare against 29 current), changelog for AEO or framework-specific additions
- **Update this document** with any changes to the overlap matrix
- **Escalate** if they add Eleventy/framework-specific modes or dedicated AEO skills

No automated tooling needed -- manual review of their GitHub repository is sufficient at this cadence.

## Related

- Landscape audit: `knowledge-base/learnings/2026-02-19-full-landscape-discovery-audit.md`
- CMO agent exploration: issue #154
- This monitoring task: issue #165
