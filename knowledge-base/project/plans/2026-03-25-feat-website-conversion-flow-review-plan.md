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

All changes are Eleventy template/content modifications — no new build dependencies, no JavaScript framework, no backend changes. The site uses Nunjucks templates with a single `base.njk` layout, `site.json` for navigation config, and a single `style.css` (1,399 lines, `@layer` architecture).

**Key Eleventy gotchas:** Nunjucks does NOT resolve variables in YAML frontmatter. Full-width sections must be OUTSIDE `.container`. CSS variable is `--color-accent` (not `--accent`). New classes go in `@layer components`. Build from repo root: `npx @11ty/eleventy --input=plugins/soleur/docs --output=plugins/soleur/docs/_site`. SEO CI gate requires canonical URL, JSON-LD, og:title, Twitter cards on all pages.

### Implementation Phases

#### Phase 0: UX Gate — Wireframes and Copy (BLOCKING)

**This phase must complete before any implementation begins.**

- [ ] **0.1** ux-design-lead wireframes — **DONE.** Saved to `knowledge-base/product/design/website/homepage-getting-started-wireframes.pen`. Hero CTA hierarchy resolved: inline form (primary) → "See Pricing" button (secondary) → "try open-source" link (tertiary).
- [ ] **0.2** Run copywriter: hero headline/subheadline, CTA copy, homepage FAQ (all 6 Q&A pairs), Getting Started cloud/self-hosted copy, `site.json` description. Copywriter MUST read `knowledge-base/marketing/brand-guide.md` first.
- [ ] **0.3** CMO reviews copy artifacts. No code until approved.

#### Phase 1: All Content and Template Changes

One file = one task. All edits are independent — no dependency chain.

- [ ] **1.1** `site.json` — Update `description` field (line 5): currently says "A Claude Code plugin." Feeds into JSON-LD `WebSite` schema site-wide.
  - `plugins/soleur/docs/_data/site.json`

- [ ] **1.2** `base.njk` — One editing session for all metadata:
  - Update `<meta name="description">` (line 6) — remove "plugin"
  - Update OG tags and Twitter cards (lines 8-23) — same language
  - Update JSON-LD `SoftwareApplication` schema (lines 24-62, homepage only via line 39 conditional) — remove `"price": "0"`, `"softwareRequirements": "Claude Code CLI"`, change `applicationCategory` from `DeveloperApplication` to `BusinessApplication`
  - Verify `<title>` (line 66) has no plugin language
  - `plugins/soleur/docs/_includes/base.njk`

- [ ] **1.3** `index.njk` — Full homepage reframe from approved wireframe + copy:
  - Update frontmatter `description` (line 3) — currently says "a Claude Code plugin" (CPO: HIGH)
  - Rewrite hero section (lines 8-16) with platform positioning
  - Add inline waitlist form in hero — copy markup from `pricing.njk:329-353`, use `homepage-waitlist` Buttondown tag, include honeypot, fire `plausible('Waitlist Signup', { props: { location: 'homepage-hero' } })`
  - Primary CTA: "See Pricing & Join Waitlist" → `/pages/pricing.html`
  - Secondary CTA: "Or try the open-source version" → `/pages/getting-started.html`
  - Rewrite all 6 FAQ Q&A pairs (lines 127-159) + update FAQ JSON-LD schema (lines 161-216) to match
  - Remove "plugin" from body copy (department cards, features, quote)
  - Update mid-page CTA (lines 73-75) and final CTA (lines 218-223) → pricing page
  - `plugins/soleur/docs/index.njk`

- [ ] **1.4** `getting-started.md` → `.njk` — Convert and restructure:
  - Two-path layout from wireframe: Cloud Platform (primary, gold border, "Coming Soon") + Self-Hosted (secondary, gray border, "Available Now")
  - Cloud CTA links to `pricing.html#waitlist` (anchor to form directly)
  - Move all CLI install content to Self-Hosted path
  - Update FAQ answers to cover both paths (currently says "free and open source" with no paid tiers mention)
  - Update JSON-LD FAQ schema to match new FAQ content
  - `plugins/soleur/docs/pages/getting-started.md` → `.njk`

- [ ] **1.5** `vision.njk` — Remove "Success Tax" revenue section (lines 151-181). Replace with brief subscription model mention. Fix `var(--accent)` → `var(--color-accent)` in 4 places (pre-existing bug, zero marginal cost since already editing).
  - `plugins/soleur/docs/pages/vision.njk`

- [ ] **1.6** `newsletter-form.njk` — Add `<input type="hidden" name="tag" value="newsletter" />` for subscriber segmentation.
  - `plugins/soleur/docs/_includes/newsletter-form.njk`

- [ ] **1.7** `llms.txt.njk` — Remove 3 instances of plugin framing (2 paragraphs + 1 link description).
  - `plugins/soleur/docs/llms.txt.njk`

- [ ] **1.8** `style.css` — Add hero waitlist form styles and Getting Started two-path layout in `@layer components`. Use `--color-accent` for submit button, `.btn-primary` gold gradient.
  - `plugins/soleur/docs/css/style.css`

- [ ] **1.9** `pricing.njk` — Minor CTA copy alignment if needed for consistency with homepage flow.
  - `plugins/soleur/docs/pages/pricing.njk`

**Out of scope (file separate issues):**

- Legal documents (111 "plugin" references in 7 legal docs — these use "plugin" as a defined legal term and require careful legal review, not find-and-replace)
- Blog posts (historical content, dated)
- `agents.njk`, `skills.njk`, `community.njk` (grep confirms zero "plugin" instances)

#### Phase 2: Build, Test, Ship

- [ ] **2.1** Full Eleventy build: `npx @11ty/eleventy --input=plugins/soleur/docs --output=plugins/soleur/docs/_site`
- [ ] **2.2** Verify all internal links work (no broken references after CTA changes)
- [ ] **2.3** Verify OG tags render in built HTML (existing P0 bug #1121 — investigate if still broken)
- [ ] **2.4** Test homepage waitlist form — verify Buttondown receives email with `homepage-waitlist` tag
- [ ] **2.5** Responsive testing: screenshot all modified pages at mobile (≤768px), tablet (769-1024px), desktop (>1024px)

#### Post-Merge

- [ ] Assign #1142 to milestone (Pre-Phase 4 or "Marketing Positioning")
- [ ] Update `knowledge-base/product/roadmap.md` — mark M2, M5 as pulled forward from Pre-Phase 4
- [ ] File issue for legal docs "plugin" cleanup (separate scope)

## Acceptance Criteria

- [ ] Homepage hero shows platform positioning with inline waitlist email form
- [ ] Homepage hero CTA links to pricing page
- [ ] Secondary CTA links to Getting Started self-hosted path
- [ ] Getting Started shows two-path layout (Cloud Platform primary, Self-Hosted secondary)
- [ ] Vision page contains no "Success Tax" language
- [ ] Zero instances of "plugin" as primary framing on any public page (secondary mentions in self-hosted context acceptable)
- [ ] Meta descriptions on all pages updated (no "Claude Code plugin")
- [ ] JSON-LD structured data reflects platform, not free plugin
- [ ] Homepage waitlist form uses `homepage-waitlist` Buttondown tag
- [ ] Newsletter footer form uses `newsletter` Buttondown tag
- [ ] All pages responsive at mobile/tablet/desktop breakpoints
- [ ] PR includes screenshots of all modified pages at 3 breakpoints

## Domain Review

**Domains relevant:** Marketing, Product

### Marketing (CMO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Site hasn't caught up to pivot. Recommends conversion-optimizer + ux-design-lead artifacts before implementation. Wireframes completed.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Pencil available:** yes

**Key findings incorporated:** `site.json` + homepage frontmatter description say "plugin" (added to 1.1, 1.3). FAQ copy expanded in Phase 0 scope. Distinct `homepage-waitlist` tag for per-surface measurement. Mid-page and final CTAs updated. Getting Started Cloud path links to `#waitlist` anchor.

## Test Scenarios

- Visitor lands on homepage → sees platform positioning and email input for waitlist (not plugin framing)
- Visitor submits homepage waitlist form → Buttondown receives email with `homepage-waitlist` tag, Plausible fires "Waitlist Signup" event
- Visitor clicks "See Pricing" → pricing page loads with tier cards and waitlist form
- Visitor navigates to Getting Started → sees two paths: Cloud Platform (primary) and Self-Hosted (secondary)
- Search engine crawls homepage → meta/OG/JSON-LD contains no "plugin," "terminal-first," or `"price": "0"`
- Mobile visitor scrolls homepage → inline waitlist form is usable, Getting Started stacks vertically

## References

- Brand guide: `knowledge-base/marketing/brand-guide.md`
- Wireframes: `knowledge-base/product/design/website/homepage-getting-started-wireframes.pen`
- Roadmap: `knowledge-base/product/roadmap.md`
- Related: #1142 (this), #1141 (draft PR), #1139 (waitlist system), #656 (pricing v2), #1121 (OG tags bug)
