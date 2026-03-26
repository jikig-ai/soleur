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

- [x] **0.1** ux-design-lead wireframes — **DONE.** Saved to `knowledge-base/product/design/website/homepage-getting-started-wireframes.pen`. Hero CTA hierarchy resolved: inline form (primary) → "See Pricing" button (secondary) → "try open-source" link (tertiary).
- [x] **0.2** Run copywriter — **DONE.** `knowledge-base/project/specs/feat-website-conversion-review/copy-deck.md`
- [x] **0.3** CMO reviews copy artifacts — **DONE** (approved per commit 47362f80).

#### Phase 1: All Content and Template Changes

One file = one task. All edits are independent — no dependency chain.

- [x] **1.1** `site.json` — Updated description, removed "plugin"
- [x] **1.2** `base.njk` — JSON-LD: BusinessApplication, no softwareRequirements/offers. Form-aware success messages (waitlist vs newsletter)
- [x] **1.3** `index.njk` — Hero rewrite, inline waitlist form, CTAs, FAQ + JSON-LD, mid/final CTAs, body copy cleanup
- [x] **1.4** `getting-started.md` → `.njk` — Two-path layout, FAQ + JSON-LD, old .md deleted
- [x] **1.5** `vision.njk` — Success Tax removed, var(--accent) fixed (3 instances)
- [x] **1.6** `newsletter-form.njk` — Added `newsletter` Buttondown tag
- [x] **1.7** `llms.txt.njk` — Removed 3 plugin framing instances
- [x] **1.8** `style.css` — Hero form + two-path layout in `@layer components`
- [x] **1.9** `pricing.njk` — No changes needed, CTAs already aligned

**Out of scope (file separate issues):**

- Legal documents (111 "plugin" references in 7 legal docs — these use "plugin" as a defined legal term and require careful legal review, not find-and-replace)
- Blog posts (historical content, dated)
- `agents.njk`, `skills.njk`, `community.njk` (grep confirms zero "plugin" instances)

#### Phase 2: Build, Test, Ship

- [x] **2.1** Full Eleventy build — 41 files, 0 errors
- [x] **2.2** Internal link verification — all targets exist in build output
- [x] **2.3** OG tag verification — no "plugin" in meta/OG/Twitter descriptions
- [x] **2.4** Homepage form test — `homepage-waitlist` tag present, form renders correctly
- [x] **2.5** Responsive screenshots — homepage + getting-started at 3 breakpoints, vision verified

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
