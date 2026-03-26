---
title: "fix: SEO meta descriptions, Vision H1, and open-source keyword presence"
type: fix
date: 2026-03-26
issues:
  - "#1129"
  - "#1131"
  - "#1134"
source: "Growth Audit 2026-03-25 (#1128)"
---

# fix: SEO meta descriptions, Vision H1, and open-source keyword presence

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

Current:

```text
description: "The company-as-a-service platform for solo founders. AI agents across every business department -- engineering, marketing, legal, finance, sales, and more -- orchestrated from a single platform."
```

Proposed (from #1129 suggested fix, adapted for current framing):

```text
description: "The open-source company-as-a-service platform. AI agents across every business department -- engineering, marketing, legal, finance, and more. Built for solo founders."
```

Rationale: Adds "open-source" to the meta description (highest-impression text), keeps platform framing, adds "Built for solo founders" for keyword match.

**Body text additions for #1134:**

- Add "solopreneur" to the "Who is Soleur for?" FAQ answer (natural context: "Solo founders and solopreneurs who refuse to accept...")
- Add "open source" to the hero subtitle or the hero sub-section. The hero sub already mentions "AI agents across departments" -- prepend "open-source" before "company-as-a-service platform" in the hero-sub paragraph.

### File 2: `plugins/soleur/docs/pages/getting-started.njk`

**Meta description (line 3):**

Current:

```text
description: "Get started with Soleur -- the company-as-a-service platform. Choose the cloud platform or self-hosted open-source version to deploy AI agents across every business department."
```

Proposed (from #1129 suggested fix, adapted):

```text
description: "Get started with Soleur in one command. Deploy AI agents across engineering, marketing, legal, finance, and every business department. Free and open source."
```

Rationale: Adds "free and open source" to capture searches for open-source AI platforms. More action-oriented opening.

### File 3: `plugins/soleur/docs/pages/vision.njk`

**H1 (line 10):**

Current:

```html
<h1>Vision</h1>
```

Proposed (from #1131):

```html
<h1>The Soleur Vision: Company-as-a-Service for the Solo Founder</h1>
```

Rationale: Captures "company-as-a-service" and "solo founder" keywords in the strongest on-page SEO signal.

## Acceptance Criteria

- [ ] Homepage meta description contains "open-source" -- `plugins/soleur/docs/index.njk` line 3
- [ ] Homepage meta description does NOT contain "plugin" -- `plugins/soleur/docs/index.njk` line 3
- [ ] Homepage body text contains "solopreneur" at least once -- `plugins/soleur/docs/index.njk`
- [ ] Homepage hero sub-paragraph includes "open-source" -- `plugins/soleur/docs/index.njk`
- [ ] Getting Started meta description contains "free and open source" -- `plugins/soleur/docs/pages/getting-started.njk` line 3
- [ ] Getting Started meta description does NOT contain "plugin" -- `plugins/soleur/docs/pages/getting-started.njk` line 3
- [ ] Vision page H1 contains "Company-as-a-Service" and "Solo Founder" keywords -- `plugins/soleur/docs/pages/vision.njk`
- [ ] Vision page H1 is NOT the single word "Vision" -- `plugins/soleur/docs/pages/vision.njk`
- [ ] No brand guide violations introduced (no new "plugin" or "tool" references in public-facing copy)
- [ ] Site builds successfully with `npx @11ty/eleventy` (no template errors)

## Test Scenarios

- Given the homepage is loaded, when viewing the page source, then the `<meta name="description">` tag contains "open-source" and does not contain "plugin"
- Given the Getting Started page is loaded, when viewing the page source, then the `<meta name="description">` tag contains "free and open source"
- Given the Vision page is loaded, when viewing the page, then the H1 contains "Company-as-a-Service" and "Solo Founder"
- Given the homepage body text, when searching for "solopreneur", then at least one match is found
- Given the homepage hero section, when reading above-the-fold copy, then "open-source" appears in the hero sub-paragraph

**Build verification:**

- Run `npx @11ty/eleventy` from the docs directory -- expect exit code 0 with no errors

## Domain Review

**Domains relevant:** Marketing, Product

### Marketing (CMO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** The 2026-03-25 website conversion review brainstorm (#1141) and the 2026-03-20 SEO/AEO content plan brainstorm both identified these exact issues as P1 technical fixes. The CMO recommended these as high-priority, low-effort SEO wins. The meta description fix was originally P1-3, Vision H1 was P1-4, and open-source keyword presence was P1-6 in the SEO/AEO content plan. All three align with brand guide compliance (line 82: do not call it a "plugin" in public-facing content) and competitive differentiation strategy.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

These are text-only copy changes to existing pages. No new pages, no new UI components, no structural changes. The Product domain assessment from the website conversion review brainstorm already covers these pages. ADVISORY tier auto-accepts in pipeline context per plan skill protocol.

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
- `knowledge-base/marketing/brand-guide.md` -- Brand guide (line 82: platform not plugin)
- `knowledge-base/project/brainstorms/2026-03-25-website-conversion-review-brainstorm.md` -- Conversion review brainstorm
- `knowledge-base/project/brainstorms/2026-03-20-seo-aeo-content-plan-brainstorm.md` -- SEO/AEO content plan
