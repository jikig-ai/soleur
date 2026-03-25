---
title: "feat: Website Conversion Flow Review — Waitlist-First Funnel"
type: feat
date: 2026-03-25
---

# Website Conversion Flow Review — Waitlist-First Funnel

## Overview

Reframe the Soleur marketing site (soleur.ai) from a Claude Code plugin landing page to a hosted platform waitlist funnel. The site currently directs all visitors to CLI install instructions, contradicting the cross-platform pivot. This plan restructures the conversion flow: homepage inline waitlist form, pricing in navigation, Getting Started split into cloud/self-hosted paths, and full plugin language removal site-wide.

**Brainstorm:** `knowledge-base/project/brainstorms/2026-03-25-website-conversion-review-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-website-conversion-review/spec.md`
**Issue:** #1142

## Problem Statement

Every public-facing page frames Soleur as a "Claude Code plugin" with `claude plugin install soleur` as the primary CTA. The homepage hero ("Build a Billion-Dollar Company. Alone.") has three CTAs all pointing to Getting Started (CLI install). The brand guide (2026-03-22) prohibits "plugin" and "terminal-first" in public content. The pricing page has a waitlist form but is the **only** waitlist surface on the site. Business validation confirmed the target audience (non-CLI founders) bounces when they see terminal commands as the entry point.

## Proposed Solution

Focused funnel approach: two conversion surfaces (homepage hero + pricing page), CTA buttons on other pages linking to pricing. All plugin language replaced with platform positioning per brand guide.

## Technical Approach

### Architecture

All changes are Eleventy template/content modifications — no new build dependencies, no JavaScript framework, no backend changes. The site uses Nunjucks templates with a single `base.njk` layout, `site.json` for navigation config, and a single `style.css` (1,399 lines, `@layer` architecture: reset, tokens, base, layout, components, utilities).

**Eleventy-Specific Gotchas (from learnings):**

- Nunjucks does NOT resolve variables in YAML frontmatter — dynamic content must be in template body
- `{% block extraHead %}` requires `{% block content %}{{ content | safe }}{% endblock %}` wrapping in base layout
- Full-width sections (hero, CTA) must sit OUTSIDE `<div class="container">` — use `landing-section` class
- CSS variable is `--color-accent` (not `--accent`). New classes go in `@layer components` block
- `.site-header` has `backdrop-filter: blur(12px)` which breaks `position: fixed` descendants
- Build from repo root: `npx @11ty/eleventy --input=plugins/soleur/docs --output=plugins/soleur/docs/_site`
- SEO CI gate (`validate-seo.sh`) requires canonical URL, JSON-LD, og:title, Twitter cards on all pages
- Getting Started is currently `.md` with embedded HTML — will need conversion to `.njk` for richer layout

### Files to Modify

| File | Change | Priority |
|------|--------|----------|
| `plugins/soleur/docs/_data/site.json` | ~~Add Pricing to nav~~ Already present (position 4). **Update `description` field (line 6) — currently says "A Claude Code plugin"** (CPO: HIGH) | P0 |
| `plugins/soleur/docs/index.njk` | Rewrite hero, CTAs, add inline waitlist form | P0 |
| `plugins/soleur/docs/pages/getting-started.md` | Split into cloud/self-hosted two-path layout | P0 |
| `plugins/soleur/docs/_includes/base.njk` | Update meta descriptions, OG tags, JSON-LD structured data | P1 |
| `plugins/soleur/docs/_includes/newsletter-form.njk` | Review copy to differentiate newsletter vs waitlist | P1 |
| `plugins/soleur/docs/pages/vision.njk` | Remove "Success Tax" revenue model, align with platform positioning | P1 |
| `plugins/soleur/docs/css/style.css` | Add styles for inline waitlist form on homepage, two-path Getting Started layout | P1 |
| `plugins/soleur/docs/pages/pricing.njk` | Minor copy alignment (ensure CTAs are consistent with homepage flow) | P2 |
| `plugins/soleur/docs/llms.txt.njk` | Update product description (remove plugin framing) | P2 |

### Implementation Phases

#### Phase 0: UX Gate — Wireframes and Copy (BLOCKING)

**This phase must complete before any implementation begins.**

Per workflow rules and learnings from #637 (5 screens built without design review), user-facing page changes require specialist artifacts first.

- [ ] **0.1** Run ux-design-lead: wireframes for homepage hero + inline form layout, Getting Started two-path layout
- [ ] **0.2** Run copywriter: hero headline, subheadline, CTA copy, Getting Started cloud/self-hosted path copy, **homepage FAQ rewrite (all 6 Q&A pairs)**, and **differentiated form success messages** (waitlist vs newsletter). Copywriter MUST read `knowledge-base/marketing/brand-guide.md` before writing (learning: context-blindness caused onboarding artifacts to describe wrong product)
- [ ] **0.3** CMO reviews both artifacts. No code until approved.

**Artifact outputs:**

- Homepage wireframe (.pen file or markdown mockup) — must resolve the three-CTA hierarchy (inline form vs. pricing button vs. self-hosted link) for both desktop and mobile
- Getting Started wireframe (.pen file or markdown mockup)
- Approved copy document for: hero, CTAs, FAQ (6 Q&A pairs), form success messages, `site.json` description

#### Phase 1: Base Layout and Metadata

- [ ] ~~**1.1** Add Pricing to nav~~ — **Already done** in PR #1136. Pricing is at position 4 in `site.json` nav array.
- [ ] **1.1b** Update `site.json` `description` field (line 6) — currently says "A Claude Code plugin that gives solo founders a full AI organization." This feeds into JSON-LD `WebSite` schema site-wide. Replace with platform positioning from approved copy. **(CPO: HIGH — structural source of plugin framing)**
  - File: `plugins/soleur/docs/_data/site.json`
- [ ] **1.2** Update `<meta name="description">` in `base.njk` (line 6) — remove "Claude Code plugin," replace with platform positioning per brand guide
  - File: `plugins/soleur/docs/_includes/base.njk`
- [ ] **1.3** Update OG tags (`og:description`, `twitter:description`) in `base.njk` — same language as meta description
  - File: `plugins/soleur/docs/_includes/base.njk`
- [ ] **1.4** Update JSON-LD structured data in `base.njk` (lines 24-63) — the `SoftwareApplication` schema (homepage only, line 39) has `"price": "0"` and `"softwareRequirements": "Claude Code CLI"`. Update `applicationCategory`, `description`, remove free pricing, reflect platform positioning
  - File: `plugins/soleur/docs/_includes/base.njk`
- [ ] **1.5** Update `<title>` pattern in `base.njk` (line 66) — homepage currently says "Soleur - The Company-as-a-Service Platform" (acceptable) but verify no "plugin" language
  - File: `plugins/soleur/docs/_includes/base.njk`
- [ ] **1.6** Verify Eleventy build succeeds: `npx @11ty/eleventy --input=plugins/soleur/docs --output=plugins/soleur/docs/_site --dryrun`

#### Phase 2: Homepage Reframe

Implement from approved wireframe and copy (Phase 0 output).

- [ ] **2.1** Rewrite hero section (lines 8-16) — current H1: "Build a Billion-Dollar Company. Alone." with subheadline referencing `stats.agents` and `stats.departments`. Replace with platform positioning from approved copy. Hero uses `.landing-hero` class (style.css:417-438)
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.1b** Update homepage frontmatter description (line 3) — currently says "a Claude Code plugin that gives solo founders..." This feeds into `<meta name="description">` and all OG/Twitter tags for the homepage specifically, overriding the base template. **(CPO: HIGH — homepage meta still says "plugin" after base template changes)**
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.2** Add inline waitlist email form to hero — use Buttondown endpoint with **`homepage-waitlist` tag** (distinct from pricing page's `pricing-waitlist` to enable per-surface conversion measurement — CPO recommendation). Include honeypot field (`name="url"`) and Plausible event tracking (`plausible('Waitlist Signup', { props: { location: 'homepage-hero' } })`). Reuse the JS handler in `base.njk` (lines 119-148) but update it to support per-form success messages via `data-success-message` attribute and per-form Plausible event names. The form must sit inside the `.landing-hero` section but outside `.container` for full-width treatment.
  - File: `plugins/soleur/docs/index.njk`
  - Reference: `plugins/soleur/docs/pages/pricing.njk:329-353` (existing waitlist form markup)
- [ ] **2.3** Primary CTA: "See Pricing & Join Waitlist" → `/pages/pricing.html`
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.4** Secondary CTA: "Or try the open-source version" → `/pages/getting-started.html` (self-hosted path anchor)
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.5** Rewrite homepage FAQ section (lines 127-159) — all 6 Q&A pairs from approved copy. Update FAQ JSON-LD schema (lines 161-216) to match. Current FAQ answers say "delivered as a Claude Code plugin," "The Soleur plugin is open source and free to install," and "Install the plugin with `claude plugin install soleur`" — all brand violations. **(CPO: FAQ copy must be in Phase 0 scope)**
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.5b** Remove "plugin" framing from homepage body copy outside FAQ (department cards, feature sections, quote)
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.5c** Update mid-page CTA (line 73-75) and final CTA (lines 218-223) — both currently say "Start building your AI organization" → Getting Started. Change to "See Pricing & Join Waitlist" → pricing page. **(spec-flow-analyzer: competing funnels if left pointing to Getting Started)**
  - File: `plugins/soleur/docs/index.njk`
- [ ] **2.6** Add CSS for inline waitlist form in `@layer components` block — reuse `.newsletter-form` pattern (style.css:1041-1074) but adapted for hero context. Use `--color-accent` for submit button, `.btn-primary` gold gradient
  - File: `plugins/soleur/docs/css/style.css`
- [ ] **2.7** Test homepage at all three breakpoints (mobile/tablet/desktop) — learning: grid orphan regression shipped due to single-breakpoint testing

#### Phase 3: Getting Started Split

Implement from approved wireframe and copy (Phase 0 output).

- [ ] **3.1** Convert `getting-started.md` to `getting-started.njk` for richer layout, then restructure into two-path layout:
  - **Cloud Platform (primary):** "Coming Soon" messaging, value prop, waitlist CTA → `pricing.html#waitlist` (link directly to form, not top of pricing page — spec-flow-analyzer: "Join the Waitlist" CTA that loads a full pricing page feels like an upsell ambush)
  - **Self-Hosted (secondary):** Current CLI install instructions, workflow commands
  - **Update Getting Started FAQ** — "How much does Soleur cost?" currently says "free and open source" with no mention of paid tiers. Must cover both paths.
  - File: `plugins/soleur/docs/pages/getting-started.md` → `.njk`
- [ ] **3.2** Add CSS for two-path layout — card-based or side-by-side, with clear visual hierarchy (cloud is primary)
  - File: `plugins/soleur/docs/css/style.css`
- [ ] **3.3** Test responsive behavior at all three breakpoints

#### Phase 4: Vision Page and Site-Wide Cleanup

- [ ] **4.1** Remove "Success Tax" revenue model section from vision page (lines 151-181, specifically "The Success Tax" card at lines 168-171 describing "tiered revenue-share model") — replace with brief mention of subscription model aligned to pricing page
  - File: `plugins/soleur/docs/pages/vision.njk`
- [ ] **4.2** Remove "terminal-first" language from vision page
  - File: `plugins/soleur/docs/pages/vision.njk`
- [ ] **4.3** Update `llms.txt.njk` — remove plugin framing, describe as platform
  - File: `plugins/soleur/docs/llms.txt.njk`
- [ ] **4.4** Audit all remaining pages for "plugin" as primary framing:
  - `plugins/soleur/docs/pages/community.njk`
  - `plugins/soleur/docs/pages/agents.njk`
  - `plugins/soleur/docs/pages/skills.njk`
  - Blog posts (leave as-is — historical content, dated)
- [ ] **4.5** Update newsletter form partial (`newsletter-form.njk`):
  - Add `<input type="hidden" name="tag" value="newsletter" />` for subscriber segmentation (spec-flow-analyzer: without this, cannot distinguish newsletter from waitlist in Buttondown)
  - Review copy — ensure "Stay in the loop — Monthly updates about Soleur" clearly differentiates from waitlist messaging
  - File: `plugins/soleur/docs/_includes/newsletter-form.njk`
- [ ] **4.5b** Update form JS handler in `base.njk` (lines 119-148):
  - Support per-form success messages via `data-success-message` attribute (waitlist: "You're on the list. We'll email you when early access opens." vs newsletter: "Check your email to confirm.")
  - Unify Plausible event naming: read event name from `data-plausible-event` attribute (default "Newsletter Signup"). Waitlist forms use "Waitlist Signup"
  - File: `plugins/soleur/docs/_includes/base.njk`
- [ ] **4.6** Verify legal docs don't need updating — the homepage already has a newsletter form via `base.njk` (collecting email). Adding a second form with the same Buttondown endpoint should not require legal changes. However, if the copy changes introduce new data collection claims, grep for `"does not collect"` and `"no personal data"` in `plugins/soleur/docs/pages/legal/` and `docs/legal/` to verify no contradictions (learning: first PII collection requires 6 file edits across 3 policies)

#### Phase 5: Verify and Test

- [ ] **5.1** Full Eleventy build from repo root: `npx @11ty/eleventy --input=plugins/soleur/docs --output=plugins/soleur/docs/_site` — verify clean output
- [ ] **5.2** Check all internal links — no broken references after CTA changes
- [ ] **5.3** Verify OG tags render in production HTML (CMO flagged P0: OG tags not rendering despite being in templates)
- [ ] **5.4** Test waitlist form submission on homepage — verify Buttondown receives email with `pricing-waitlist` tag
- [ ] **5.5** Verify Plausible analytics events fire for homepage waitlist form
- [ ] **5.6** Screenshot all modified pages at mobile/tablet/desktop for PR
- [ ] **5.7** Configure Plausible goals for conversion tracking: waitlist signups by page, pricing page visits, CTA clicks (learning: analytics baselines needed before evaluating conversion changes)

## Acceptance Criteria

### Functional Requirements

- [ ] Homepage hero shows platform positioning with inline waitlist email form
- [ ] Homepage hero CTA links to pricing page ("See Pricing & Join Waitlist")
- [ ] Secondary CTA links to Getting Started self-hosted path
- [ ] Pricing link in main navigation confirmed working (already present from PR #1136)
- [ ] Getting Started shows two-path layout (Cloud Platform primary, Self-Hosted secondary)
- [ ] Vision page contains no "Success Tax" or "terminal-first" language
- [ ] Zero instances of "plugin" as primary framing on any public page (secondary mentions in self-hosted context are acceptable)

### Non-Functional Requirements

- [ ] Meta descriptions on all pages updated (no "Claude Code plugin")
- [ ] JSON-LD structured data reflects platform, not free plugin
- [ ] OG tags and Twitter cards render correctly in production HTML
- [ ] Homepage waitlist form uses `pricing-waitlist` Buttondown tag
- [ ] Plausible analytics events fire for homepage waitlist submissions
- [ ] All pages responsive at mobile/tablet/desktop breakpoints

### Quality Gates

- [ ] UX gate: wireframes reviewed and approved by CMO before implementation
- [ ] Copy gate: all conversion copy approved before implementation
- [ ] Eleventy build produces clean output with no errors
- [ ] PR includes screenshots of all modified pages at 3 breakpoints

## Domain Review

**Domains relevant:** Marketing, Product

### Marketing (CMO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Site hasn't caught up to pivot. Homepage says "plugin," pricing unreachable from nav, broken OG tags persist across audit cycles. Recommends conversion-optimizer + ux-design-lead artifacts in parallel, then copywriter. No implementation before specialist review.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial — ux-design-lead wireframes pending)
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead (in progress)
**Pencil available:** TBD

#### CPO Findings (9 action items)

1. **`site.json` description says "plugin"** (HIGH) — Added to Phase 1.1b
2. **Homepage frontmatter description says "plugin"** (HIGH) — Added to Phase 2.1b
3. **FAQ copy not in Phase 0 scope** (MEDIUM) — Expanded Phase 0.2
4. **Homepage FAQ JSON-LD schema has plugin language** (MEDIUM) — Added to Phase 2.5
5. **Spec FR3 says "open-source plugin"** (LOW) — Fix spec to say "open-source version"
6. **Use distinct Buttondown tag for homepage** (MEDIUM) — Changed to `homepage-waitlist`
7. **Assign #1142 to milestone** — Post-plan action
8. **Update roadmap.md after merge** — M2, M5 pulled forward from Pre-Phase 4
9. **#1121 OG tags P0 bug** (HIGH) — Acknowledged; fix scope is separate (#1121)

#### Spec-Flow-Analyzer Findings (7 key gaps)

1. **Success message dead end** — No post-signup CTAs. Added to copywriter scope.
2. **Three-CTA hierarchy in hero** — Wireframe must resolve. Added to Phase 0.1 deliverable.
3. **Mid-page and final CTAs point to Getting Started** — Added Phase 2.5c.
4. **Plausible event naming inconsistency** — Added Phase 4.5b data-attribute approach.
5. **Footer form has no Buttondown tag** — Added to Phase 4.5.
6. **Getting Started Cloud path links to pricing top** — Changed to `#waitlist` anchor.
7. **Form success messages are generic** — Added `data-success-message` to Phase 4.5b.

## Test Scenarios

- Given a visitor lands on the homepage, when they look at the hero, then they see platform positioning (not plugin framing) and an email input field for the waitlist
- Given a visitor enters their email in the homepage waitlist form, when they submit, then Buttondown receives the email with `pricing-waitlist` tag and Plausible fires a "Waitlist Signup" event with location "homepage-hero"
- Given a visitor clicks "See Pricing & Join Waitlist" on the homepage, when the pricing page loads, then it shows the v2 pricing page with tier cards and bottom waitlist form
- Given a visitor navigates to Getting Started, when the page loads, then they see two paths: Cloud Platform (primary) and Self-Hosted (secondary)
- Given a search engine crawls the homepage, when it reads meta/OG/JSON-LD, then no instance of "plugin," "terminal-first," or `"price": "0"` appears
- Given a visitor views the site on a mobile device, when they scroll the homepage, then the inline waitlist form is fully usable and the two-path Getting Started layout stacks vertically

## Success Metrics

- Waitlist signup rate increases (baseline to be established via Plausible before launch)
- Pricing page visits increase (now reachable from nav and homepage CTAs)
- Getting Started page bounce rate decreases for non-CLI visitors
- Zero "plugin" framing on conversion-critical pages

## Dependencies and Risks

| Risk | Mitigation |
|------|------------|
| UX gate delays implementation | Launch wireframe + copy work immediately. Focused scope (2 pages) limits review time. |
| Buttondown form duplication issues | Reuse exact form markup from pricing page. Same endpoint, same tag. |
| OG tags still not rendering in production | Investigate existing P0 issue during Phase 5.3. May be a build/deployment issue, not template. |
| Plugin language in blog posts | Leave historical blog content as-is (dated). Only clean conversion-critical pages. |

## Institutional Learnings Applied

| Learning | Applied In |
|----------|-----------|
| Engineering workflows skip cross-domain gates (#637) | Phase 0 UX Gate is BLOCKING — no code until wireframes + copy approved |
| Context-blindness causes messaging misalignment | Phase 0.2 — copywriter must read brand guide before writing |
| Grid orphan regression at tablet breakpoint | Phase 2.7, 3.3 — test all three breakpoints |
| Plausible not operationalized (no baselines/goals) | Phase 5.7 — configure Plausible goals before evaluating changes |
| UX review gap: visual polish ≠ information architecture | Phase 5 — explicitly test user journey (30-second comprehension) |
| Nunjucks variables don't resolve in YAML frontmatter | Phase 1-2 — dynamic meta content built in template body, not frontmatter |
| Full-width sections must be outside `.container` | Phase 2 — hero waitlist form uses `landing-section` pattern |
| CSS variable is `--color-accent` not `--accent` | Phase 2.6 — all new CSS references verified |
| `backdrop-filter` breaks fixed positioning | Phase 2-3 — no fixed-position elements inside `.site-header` |
| Eleventy build must run from repo root | Phase 5.1 — correct `--input` and `--output` flags |
| Brand violation cascade (prohibited terms) | Phase 4.4 — grep for prohibited terms before writing copy |
| First PII collection triggers legal doc updates | Phase 4.6 — verify no new data collection claims contradict legal docs |

## References

### Internal

- Brand guide: `knowledge-base/marketing/brand-guide.md`
- Pricing strategy: `knowledge-base/product/pricing-strategy.md`
- Pricing page v2 spec: `knowledge-base/project/specs/feat-pricing-page-v2/spec.md`
- Roadmap: `knowledge-base/product/roadmap.md`
- Business validation: `knowledge-base/product/business-validation.md`

### File Paths

- Homepage: `plugins/soleur/docs/index.njk`
- Base layout: `plugins/soleur/docs/_includes/base.njk`
- Nav config: `plugins/soleur/docs/_data/site.json`
- Getting Started: `plugins/soleur/docs/pages/getting-started.md`
- Vision: `plugins/soleur/docs/pages/vision.njk`
- Pricing: `plugins/soleur/docs/pages/pricing.njk`
- Newsletter form: `plugins/soleur/docs/_includes/newsletter-form.njk`
- CSS: `plugins/soleur/docs/css/style.css`
- LLMs.txt: `plugins/soleur/docs/llms.txt.njk`
- Eleventy config: `eleventy.config.js`

### Related Issues

- #1142 — Website conversion flow review (this feature)
- #1141 — Draft PR
- #1139 — Waitlist signup system
- #656 — Pricing page v2
