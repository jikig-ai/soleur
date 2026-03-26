---
title: "fix: SEO meta descriptions, Vision H1, and open-source keyword presence"
type: fix
date: 2026-03-26
issues:
  - "#1129"
  - "#1131"
  - "#1134"
source: "Growth Audit 2026-03-25 (#1128)"
deepened: 2026-03-26
---

# fix: SEO meta descriptions, Vision H1, and open-source keyword presence

## Enhancement Summary

**Deepened on:** 2026-03-26
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, new Research Insights)
**Research sources:** WebSearch (meta description best practices 2026, H1 tag SEO 2026, SaaS keyword strategy), GEO/AEO learning (Princeton KDD 2024), seo-aeo-analyst agent checklist, brand-guide.md, constitution.md

### Key Improvements

1. **Meta description length constraint added:** Proposed homepage description (167 chars) exceeds the 155-160 char optimal range and will be truncated in SERPs. Revised to 155 chars.
2. **Agent count hardcoding blocked:** Issue #1129 suggested "63 AI agents" in meta descriptions, but constitution line 79 prohibits hardcoded counts (stats.js computes at build time) and Nunjucks variables do not render in YAML frontmatter strings. Plan avoids hardcoded counts.
3. **Vision H1 length validated:** Proposed H1 at exactly 60 characters, at the upper bound of the 50-60 char H1 recommendation.
4. **GEO/AEO anti-pattern flagged:** Keyword stuffing hurts AI visibility by -10% (Princeton GEO research). Copy changes use natural placement, not forced repetition.

### New Considerations Discovered

- Mobile meta descriptions truncate at ~120 chars -- front-load the most important keywords ("open-source", "company-as-a-service") before the 120-char mark
- The `description` frontmatter field feeds `<meta name="description">`, `og:description`, AND `twitter:description` via `base.njk` -- one change propagates to all three
- The hero-sub paragraph (line 11 of index.njk) uses `{{ stats.agents }}` and `{{ stats.departments }}` Nunjucks variables, so adding "open-source" there must not break template syntax

## Overview

Three SEO/content issues from the Growth Audit 2026-03-25 (#1128) that address brand guide compliance and keyword gaps on the highest-traffic pages. All three are text-only changes to frontmatter descriptions and HTML headings/body copy -- no structural or layout changes.

### Current State Assessment

**#1129 -- Meta descriptions use "plugin" (P0):** The meta descriptions in `index.njk` and `getting-started.njk` have **already been updated** by the website conversion review (#1141). Neither frontmatter `description` field contains the word "plugin" anymore. However, the issue's suggested copy includes stronger messaging (agent counts, "free and open source") that the current descriptions lack. The remaining work is to strengthen the meta descriptions with the suggested copy.

**#1131 -- Vision page H1 "Vision" has zero keyword value (P1):** The `<h1>Vision</h1>` on `vision.njk` is still a single generic word. This is the strongest on-page SEO signal and currently wastes keyword opportunity.

**#1134 -- "Open source" underrepresented on homepage (P1):** The phrase "open source" appears only in the secondary CTA link ("Or try the open-source version") and FAQ answers. It is absent from headings, the meta description, and above-the-fold body text. "Solopreneur" is entirely absent from the homepage.

## Problem Statement

The Growth Audit identified three content gaps that reduce search visibility and weaken competitive differentiation:

1. Meta descriptions are the primary SERP text and lack the strongest differentiators (agent count, open-source, free)
2. The Vision page H1 misses keyword ranking opportunity for "company-as-a-service vision"
3. "Open source" and "free" -- Soleur's strongest competitive differentiators vs. Cowork ($20/mo), Cursor ($20-200/mo) -- are underrepresented on the highest-traffic page

## Proposed Solution

Text-only edits to three files. No structural changes, no new pages, no layout modifications.

### File 1: `plugins/soleur/docs/index.njk`

**Meta description (line 3):**

Current (196 chars -- truncated in SERPs):

```text
description: "The company-as-a-service platform for solo founders. AI agents across every business department — engineering, marketing, legal, finance, sales, and more — orchestrated from a single platform."
```

Proposed (155 chars -- within optimal 150-160 range):

```text
description: "The open-source company-as-a-service platform for solo founders. AI agents across every business department. Free forever."
```

Rationale: Adds "open-source" and "free" as the two strongest competitive differentiators. "Solo founders" appears before the 120-char mobile truncation point. Drops department list from meta (it is already in body text) to stay within the 155-160 char limit.

### Research Insights: Meta Description

- **Optimal length:** 150-160 characters for desktop, 120 characters for mobile. The current description (196 chars) is heavily truncated. The proposed description (155 chars) fits within the optimal range.
- **Front-load keywords:** Search engines measure snippet display space by pixel width. Place "open-source" and "company-as-a-service" in the first 120 chars to survive mobile truncation.
- **No hardcoded agent counts:** Issue #1129 suggested "63 AI agents" but constitution line 79 says component counts are computed by `stats.js` at build time. Nunjucks `{{ stats.agents }}` does not render inside YAML frontmatter strings. Omit specific counts from meta descriptions.
- **Propagation scope:** The `description` frontmatter field feeds three tags via `base.njk`: `<meta name="description">`, `<meta property="og:description">`, and `<meta name="twitter:description">`. One edit updates all social sharing previews.
- **GEO/AEO consideration:** Keyword stuffing hurts AI visibility by -10% (Princeton GEO KDD 2024 research). Place keywords naturally, do not repeat them. "Open-source" appears once in meta, once in hero-sub -- that is sufficient.

**Body text additions for #1134:**

- Add "solopreneur" to the "Who is Soleur for?" FAQ answer (natural context: "Solo founders and solopreneurs who refuse to accept...")
- Update the corresponding JSON-LD FAQ entry to match the visible text
- Add "open-source" to the hero-sub paragraph (line 11). The hero-sub currently reads: "The company-as-a-service platform for solo founders." Change to: "The open-source company-as-a-service platform for solo founders." This preserves the Nunjucks template variables (`{{ stats.agents }}`, `{{ stats.departments }}`) that follow.

### File 2: `plugins/soleur/docs/pages/getting-started.njk`

**Meta description (line 3):**

Current (168 chars -- truncated):

```text
description: "Get started with Soleur — the company-as-a-service platform. Choose the cloud platform or self-hosted open-source version to deploy AI agents across every business department."
```

Proposed (156 chars -- within optimal range):

```text
description: "Get started with Soleur in one command. Deploy AI agents across engineering, marketing, legal, finance, and every business department. Free and open source."
```

Rationale: Adds "free and open source" to capture searches for open-source AI platforms. Action-oriented opening ("in one command") improves CTR. "Free and open source" appears within the 160-char desktop limit.

### File 3: `plugins/soleur/docs/pages/vision.njk`

**H1 (line 10):**

Current:

```html
<h1>Vision</h1>
```

Proposed (60 chars -- at the upper bound of the 50-60 char recommendation):

```html
<h1>The Soleur Vision: Company-as-a-Service for the Solo Founder</h1>
```

Rationale: Captures "company-as-a-service" and "solo founder" keywords in the strongest on-page SEO signal. At 60 characters, it sits at the upper bound of the recommended H1 length (50-60 chars per Backlinko/Rankability 2026 case studies).

### Research Insights: H1 Tag

- **Single H1 per page:** 93.5% of top-ranking pages use one H1. The Vision page already has a single H1 -- this edit preserves that.
- **Natural keyword placement:** "Company-as-a-Service" and "Solo Founder" read as a natural headline, not a forced keyword phrase. This aligns with the GEO finding that keyword stuffing hurts AI visibility.
- **Search intent alignment:** Users searching "company-as-a-service vision" or "AI platform for solo founders" will see a directly relevant H1.
- **Subtitle unchanged:** The `<p>Where Soleur is headed.</p>` subtitle (line 11) remains as-is -- it provides narrative context that the keyword-rich H1 needs.

## Acceptance Criteria

- [ ] Homepage meta description contains "open-source" -- `plugins/soleur/docs/index.njk` line 3
- [ ] Homepage meta description is between 150-160 characters -- `plugins/soleur/docs/index.njk` line 3
- [ ] Homepage meta description does NOT contain "plugin" -- `plugins/soleur/docs/index.njk` line 3
- [ ] Homepage meta description does NOT hardcode agent/skill counts -- `plugins/soleur/docs/index.njk` line 3
- [ ] Homepage body text contains "solopreneur" at least once -- `plugins/soleur/docs/index.njk`
- [ ] Homepage hero sub-paragraph includes "open-source" -- `plugins/soleur/docs/index.njk` line 11
- [ ] Homepage JSON-LD FAQ entry for "Who is Soleur for?" matches visible text -- `plugins/soleur/docs/index.njk`
- [ ] Getting Started meta description contains "free and open source" -- `plugins/soleur/docs/pages/getting-started.njk` line 3
- [ ] Getting Started meta description is between 150-160 characters -- `plugins/soleur/docs/pages/getting-started.njk` line 3
- [ ] Getting Started meta description does NOT contain "plugin" -- `plugins/soleur/docs/pages/getting-started.njk` line 3
- [ ] Vision page H1 contains "Company-as-a-Service" and "Solo Founder" keywords -- `plugins/soleur/docs/pages/vision.njk`
- [ ] Vision page H1 is NOT the single word "Vision" -- `plugins/soleur/docs/pages/vision.njk`
- [ ] Vision page H1 is under 65 characters -- `plugins/soleur/docs/pages/vision.njk`
- [ ] No brand guide violations introduced (no new "plugin" or "tool" references in public-facing copy)
- [ ] Nunjucks template variables in hero-sub paragraph remain intact after edit -- `plugins/soleur/docs/index.njk` line 11
- [ ] Site builds successfully with `npx @11ty/eleventy` (no template errors)

## Test Scenarios

- Given the homepage is loaded, when viewing the page source, then the `<meta name="description">` tag contains "open-source" and does not contain "plugin"
- Given the homepage meta description, when counting characters, then the count is between 150 and 160
- Given the Getting Started page is loaded, when viewing the page source, then the `<meta name="description">` tag contains "free and open source"
- Given the Getting Started meta description, when counting characters, then the count is between 150 and 160
- Given the Vision page is loaded, when viewing the page, then the H1 contains "Company-as-a-Service" and "Solo Founder"
- Given the homepage body text, when searching for "solopreneur", then at least one match is found in the FAQ section
- Given the homepage hero section, when reading above-the-fold copy, then "open-source" appears in the hero sub-paragraph
- Given the homepage JSON-LD, when comparing the "Who is Soleur for?" answer text, then it matches the visible FAQ answer (including "solopreneurs")
- Given the homepage source, when grepping for `{{ stats.agents }}`, then the Nunjucks variable is still present and intact in the hero-sub paragraph

**Build verification:**

- Run `npx @11ty/eleventy` from the docs directory -- expect exit code 0 with no errors
- Inspect `_site/index.html` and verify `<meta name="description">` renders the expected text
- Inspect `_site/pages/vision.html` and verify the `<h1>` contains the full keyword-rich heading

## Domain Review

**Domains relevant:** Marketing, Product

### Marketing (CMO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** The 2026-03-25 website conversion review brainstorm (#1141) and the 2026-03-20 SEO/AEO content plan brainstorm both identified these exact issues as P1 technical fixes. The CMO recommended these as high-priority, low-effort SEO wins. The meta description fix was originally P1-3, Vision H1 was P1-4, and open-source keyword presence was P1-6 in the SEO/AEO content plan. All three align with brand guide compliance (line 82: do not call it a "plugin" in public-facing content) and competitive differentiation strategy.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

These are text-only copy changes to existing pages. No new pages, no new UI components, no structural changes. The Product domain assessment from the website conversion review brainstorm already covers these pages. ADVISORY tier auto-accepts in pipeline context per plan skill protocol.

## Edge Cases and Pitfalls

### Nunjucks Template Variable Safety

The hero-sub paragraph (line 11 of `index.njk`) contains Nunjucks variables:

```text
{{ stats.agents }} AI agents across {{ stats.departments }} departments
```

When adding "open-source" to this paragraph, the edit must not break the template syntax. Insert the word into the static text portion only, not inside or adjacent to `{{ }}` delimiters.

### OG Image Alt Text

The `base.njk` template uses `ogImageAlt | default(site.name + ' - ' + site.tagline)` for the OG image alt text. The meta description change does not affect this -- `ogImageAlt` is a separate frontmatter field.

### SEO Validator CI Check

The `validate-seo.sh` script (from the seo-aeo skill) checks that all pages have valid meta descriptions. The proposed changes maintain valid descriptions, so no CI failures expected. Per the learning `2026-03-05-seo-validator-skip-redirect-pages.md`, the validator already handles redirect pages correctly.

### Duplicate Keyword Risk

Adding "open-source" to both the meta description AND the hero-sub paragraph is intentional and acceptable -- the meta description serves SERP display while the hero-sub serves on-page content. Per GEO research, 2 natural occurrences on a page is standard; 5+ starts to trigger stuffing penalties.

## Context

### Brand Guide Reference

From `knowledge-base/marketing/brand-guide.md` line 82:
> Do not call it a "plugin" or "tool" in public-facing content -- it is a platform. **Exception:** "plugin" is permitted in literal CLI commands (`claude plugin install`), in legal documents where "Plugin" is a defined term, and in technical documentation describing the installation mechanism.

### Files with Remaining "plugin" References (Out of Scope)

The following files still contain "plugin" but are **excluded** from this plan because they fall under brand guide exceptions:

- Blog posts (competitive analysis context, describing competitors' plugin architectures)
- `getting-started.njk` CLI command: `claude plugin install soleur` (literal CLI command exception)
- Legal documents (defined term exception)
- `_includes/base.njk` JSON-LD (technical metadata)

### Related Issues and PRs

- #1128 -- Growth Audit 2026-03-25 (source audit)
- #1141 -- Website Conversion Review PR (already updated meta descriptions to remove "plugin")
- #661 -- Growth Audit 2026-03-17 (earlier audit that first identified these issues)

## References

- `plugins/soleur/docs/index.njk` -- Homepage template
- `plugins/soleur/docs/pages/getting-started.njk` -- Getting Started template
- `plugins/soleur/docs/pages/vision.njk` -- Vision page template
- `plugins/soleur/docs/_includes/base.njk` -- Base layout (meta tag rendering)
- `knowledge-base/marketing/brand-guide.md` -- Brand guide (line 82: platform not plugin)
- `knowledge-base/project/brainstorms/2026-03-25-website-conversion-review-brainstorm.md` -- Conversion review brainstorm
- `knowledge-base/project/brainstorms/2026-03-20-seo-aeo-content-plan-brainstorm.md` -- SEO/AEO content plan
- `knowledge-base/project/learnings/2026-02-20-geo-aeo-methodology-incorporation.md` -- GEO/AEO methodology (Princeton KDD 2024)
- `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md` -- Eleventy frontmatter patterns
- [Meta Description Length Best Practices 2026 (Safari Digital)](https://www.safaridigital.com.au/blog/meta-description-length/)
- [H1 Tag Best Practices 2026 (DevTrios)](https://devtrios.com/blog/h1-tag-best-practices/)
- [H1 Tags as Google Ranking Factor 2026 (Rankability)](https://www.rankability.com/ranking-factors/google/h1-tags/)
- [How to Write Meta Descriptions for SEO and CTR (Analytify)](https://analytify.io/how-to-write-meta-descriptions-for-seo-and-ctr/)
