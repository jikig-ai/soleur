---
title: "fix: Add external source citations across homepage, blog, and case studies"
type: fix
date: 2026-03-26
---

# fix: Add external source citations across homepage, blog, and case studies

## Overview

The Growth Audit 2026-03-25 (#1128) identified that the homepage, AI Agents guide, and all 5 case studies contain zero or minimal external source citations. The Princeton GEO research (KDD 2024) shows source citations provide +30-40% visibility improvement with AI engines (Perplexity, Google AI Overviews, ChatGPT). The CaaS pillar post (`what-is-company-as-a-service.md`) already achieves 5/5 SAP score with 10+ inline citations -- the same pattern must be applied to the remaining high-traffic pages.

This plan addresses three issues:

- **#1130 [P0]**: Homepage has zero external source citations
- **#1132 [P1]**: AI Agents for Solo Founders guide has zero external citations
- **#1133 [P1]**: Case study cost comparisons cite no sources

## Problem Statement

### Homepage (#1130)

`plugins/soleur/docs/index.njk` contains no external source citations. The hero section claims "Build a Billion-Dollar Company. Alone." with no third-party validation. The CaaS pillar post already contains Amodei, Altman, and Krieger quotes with verified URLs that can be reused.

### AI Agents Guide (#1132)

`plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md` is a 3,000+ word guide targeting "AI agents for solo founders" -- a competitive keyword -- with zero external citations, no market data, no third-party statistics, and no named sources. Current SAP score: 3.9/5.0.

### Case Study Cost Comparisons (#1133)

All 5 case studies present market-rate claims as facts without source links:

- `case-study-legal-document-generation.md`: "EUR 300-500/hour" for technology lawyers, "EUR 9,000-25,000" for a legal suite
- `case-study-business-validation.md`: "$200-400/hour" for startup strategy consultants, "$4,000-16,000" for validation
- `case-study-competitive-intelligence.md`: "$150-300/hour" for competitive intelligence consultants, "$6,000-18,000" for analysis
- `case-study-brand-guide-creation.md`: "$5,000-15,000" for brand strategy agency, "$2,000-5,000" for freelance
- `case-study-operations-management.md`: "$100-250/hour" for operations consultant, "$1,500-6,250" for setup

## Proposed Solution

Add inline markdown link citations following the pattern established in `what-is-company-as-a-service.md`. Each citation uses `[Source Name](URL)` format with named authorities.

### Phase 1: Homepage Citations (#1130)

**File:** `plugins/soleur/docs/index.njk`

Add 2-3 authoritative citations to the homepage body. Candidate insertion points:

1. **Quote section (lines 78-83)**: Replace the self-attributed "The Soleur Thesis" blockquote with an external authority quote. Reuse one of the verified quotes from the CaaS pillar post:
   - Fortune: Sam Altman on the one-person unicorn betting pool
   - Inc.com: Dario Amodei's 70-80% prediction for billion-dollar solo company
   - Inc.com: Mike Krieger on managing Instagram with just two co-founders and Claude

2. **Problem section (lines 52-75)**: Add a citation supporting the one-person unicorn trend or AI agent adoption statistics in the descriptive text.

3. **FAQ section (lines 142-170)**: Weave in external source links within FAQ answers where claims are made.

**Citation sources (already verified in CaaS post):**

- `https://fortune.com/2024/02/04/sam-altman-one-person-unicorn-silicon-valley-founder-myth/` - Sam Altman one-person unicorn
- `https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609` - Amodei 70-80% prediction and Krieger quote
- `https://techcrunch.com/2025/02/01/ai-agents-could-birth-the-first-one-person-unicorn-but-at-what-societal-cost/` - TechCrunch on one-person unicorn

**Constraint:** The homepage is HTML (Nunjucks), not Markdown. Citations must use `<a href="URL">Source Name</a>` tags, not markdown link syntax.

### Phase 2: AI Agents Guide Citations (#1132)

**File:** `plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md`

Add external citations throughout the guide. Target sections:

1. **Introduction (lines 13-19)**: Add market data on solo founder growth or AI agent adoption to ground the opening.

2. **What Makes an AI Agent Different (lines 21-35)**: Reference Anthropic's definition or industry analysis of agent capabilities.

3. **The Eight Domains (lines 37-57)**: Add BLS or similar data on business function requirements.

4. **Why Point Solutions Fail (lines 59-71)**: Reference market analysis or research on tool fragmentation costs.

5. **What to Look For (lines 73-83)**: Cite industry analysis or framework for evaluating AI agents.

6. **The Compound Knowledge Advantage (lines 85-97)**: Reference the Princeton GEO research or similar on knowledge compounding value.

7. **What a Full AI Organization Looks Like (lines 99-112)**: Add Fortune/TechCrunch citations on the one-person unicorn trend (reuse from CaaS post).

8. **Getting Started (lines 114-128)**: Reference successful solo founder examples or adoption data.

**Citation sources to research and verify:**

- Reuse verified URLs from CaaS pillar post (Amodei, Altman, Krieger, BLS, TechCrunch, Lovable)
- Anthropic 2026 Agentic Coding Trends Report (if publicly available -- verify URL exists)
- Fortune/Inc.com on one-person unicorn trend
- BLS/Statista on solo founder or small business growth rates
- Any verifiable AI agent adoption statistics

### Phase 3: Case Study Cost Citations (#1133)

**Files (all 5):**

- `plugins/soleur/docs/blog/case-study-legal-document-generation.md`
- `plugins/soleur/docs/blog/case-study-business-validation.md`
- `plugins/soleur/docs/blog/case-study-competitive-intelligence.md`
- `plugins/soleur/docs/blog/case-study-brand-guide-creation.md`
- `plugins/soleur/docs/blog/case-study-operations-management.md`

For each case study, add inline source URLs for cost claims in "The Cost Comparison" section. Each cost claim needs a link to an industry salary survey or rate guide.

**Source categories needed:**

- **Legal rates**: Bar association rate surveys, Robert Half Legal Salary Guide, Glassdoor
- **Strategy consulting rates**: Management consulting rate guides, Glassdoor, Clutch.co
- **Competitive intelligence rates**: CI analyst salary data, consulting rate benchmarks
- **Brand strategy rates**: AIGA design salary surveys, Clutch.co agency pricing
- **Operations consulting rates**: Fractional COO rate guides, Toptal/Upwork rate data

**Format:** Add "as of [date]" freshness signals alongside each source link. Example: `According to [Robert Half's 2026 Legal Salary Guide](url), technology lawyers charge EUR 300-500/hour (as of 2026).`

**Also update:** Each case study has FAQ `<details>` sections and JSON-LD structured data that repeat cost claims. These must be updated to match the cited body text.

## Acceptance Criteria

- [ ] Homepage (`index.njk`) contains at least 2 external source citations with `<a>` tags linking to verified URLs
- [ ] AI Agents guide (`2026-03-24-ai-agents-for-solo-founders.md`) contains at least 5 external source citations using markdown link syntax
- [ ] All 5 case study cost comparison sections contain at least 1 source citation per cost claim
- [ ] All citation URLs are verified (return HTTP 200, not 404)
- [ ] Citations use named sources (e.g., "Bureau of Labor Statistics", "Robert Half") not bare URLs
- [ ] FAQ `<details>` sections and JSON-LD structured data in case studies are updated to match cited body text
- [ ] No existing content is removed -- citations are additive only
- [ ] Citation style matches the pattern in `what-is-company-as-a-service.md` (inline links with named authorities)

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed
**Assessment:** This is a pure AEO/GEO content optimization task. The CMO domain is directly responsible for citation quality and content credibility. Key concerns: (1) all citations must use authoritative, brand-appropriate sources -- no blog aggregators or low-authority sites; (2) citations should name the person or institution (e.g., "Dario Amodei, CEO of Anthropic") not just the publication; (3) the homepage quote section replacement must maintain the current emotional impact while adding external authority; (4) case study cost citations must not undermine the value comparison by linking to sources that contradict the claimed rates.

## Test Scenarios

- Given the homepage is loaded, when viewing the page source, then at least 2 external `<a href>` links to third-party domains are present in the body content
- Given the AI Agents guide is loaded, when counting external markdown links, then at least 5 links to third-party domains exist
- Given any case study's "Cost Comparison" section, when reading the cost claims, then each numeric rate or price range has an inline citation link
- Given any citation URL in any modified file, when fetching the URL, then the response is HTTP 200 (not 404, 301 to unrelated page, or paywall-only)
- Given the CaaS pillar post citations, when comparing with reused citations on the homepage, then the URLs match exactly (no drift)

## Context

### Key Learning: Citation Verification Required

From `knowledge-base/project/learnings/2026-03-06-blog-citation-verification-before-publish.md`: The CaaS pillar post had 6 factual inaccuracies in its first draft -- wrong URLs, unverifiable statistics, misattributed quotes. Every citation URL must be fetched and verified before committing. The "no naked numbers" rule applies: every quantitative claim needs a linked, retrievable source.

### Key Learning: GEO Research

From `knowledge-base/project/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`: Princeton GEO paper (KDD 2024) found source citations provide +30-40% AI engine visibility. This is the single highest-impact GEO technique.

### Existing Citation Pattern

The CaaS pillar post (`what-is-company-as-a-service.md`) establishes the citation pattern:

- Inline markdown links: `[Source Name](URL)`
- Named authorities: "Dario Amodei, CEO of Anthropic, [predicted in an interview with Inc.com](url)"
- Publication attribution: "[Bureau of Labor Statistics](url) describes..."
- Quote attribution: `Sam Altman, CEO of OpenAI, described a [betting pool among tech CEOs](url)`

### Verified URLs from CaaS Post (reusable)

- BLS: `https://www.bls.gov/ooh/management/top-executives.htm`
- Sam Altman / Fortune: `https://fortune.com/2024/02/04/sam-altman-one-person-unicorn-silicon-valley-founder-myth/`
- TechCrunch one-person unicorn: `https://techcrunch.com/2025/02/01/ai-agents-could-birth-the-first-one-person-unicorn-but-at-what-societal-cost/`
- Dario Amodei / Inc.com: `https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609`
- Cursor $1B ARR / CNBC: `https://www.cnbc.com/2026/02/24/cursor-announces-major-update-as-ai-coding-agent-battle-heats-up.html`
- Lovable ARR / TechCrunch: `https://techcrunch.com/2025/11/19/as-lovable-hits-200m-arr-its-ceo-credits-staying-in-europe-for-its-success/`
- Anthropic Cowork Plugins / TechCrunch: `https://techcrunch.com/2026/02/24/anthropic-launches-new-push-for-enterprise-agents-with-plugins-for-finance-engineering-and-design/`
- Notion Custom Agents: `https://www.notion.com/releases/2026-02-24`

### Files to Modify

| File | Issue | Change Type |
|------|-------|-------------|
| `plugins/soleur/docs/index.njk` | #1130 | Add HTML `<a>` citations |
| `plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md` | #1132 | Add markdown link citations |
| `plugins/soleur/docs/blog/case-study-legal-document-generation.md` | #1133 | Add cost source citations |
| `plugins/soleur/docs/blog/case-study-business-validation.md` | #1133 | Add cost source citations |
| `plugins/soleur/docs/blog/case-study-competitive-intelligence.md` | #1133 | Add cost source citations |
| `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` | #1133 | Add cost source citations |
| `plugins/soleur/docs/blog/case-study-operations-management.md` | #1133 | Add cost source citations |

## References

- Growth Audit: #1128
- Homepage citations: #1130
- AI Agents guide citations: #1132
- Case study cost citations: #1133
- CaaS pillar post (citation pattern reference): `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- Princeton GEO paper: arxiv:2311.09735
- Citation verification learning: `knowledge-base/project/learnings/2026-03-06-blog-citation-verification-before-publish.md`
- GEO methodology learning: `knowledge-base/project/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`
