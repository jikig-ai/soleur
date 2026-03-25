# Spec: Website Conversion Flow Review

**Issue:** #1142
**Branch:** feat-website-conversion-review
**Brainstorm:** [2026-03-25-website-conversion-review-brainstorm.md](../../brainstorms/2026-03-25-website-conversion-review-brainstorm.md)

## Problem Statement

The website still frames Soleur as a Claude Code plugin with CLI-install-first CTAs, contradicting the hosted cross-platform pivot. The primary conversion goal (waitlist signups) has no funnel — only the pricing page (unreachable from navigation) has a waitlist form. Visitors who land on the homepage encounter "plugin" framing and a Getting Started page that is 100% CLI instructions, causing the target audience (non-CLI founders) to bounce.

## Goals

- G1: Make waitlist signups the primary conversion action across the site
- G2: Remove all "plugin," "terminal-first," and CLI-primary framing from public-facing pages per brand guide
- G3: Create a focused funnel: Homepage (inline form) → Pricing (via nav + CTAs) → Waitlist
- G4: Split Getting Started into Cloud Platform (primary) and Self-Hosted (secondary) paths

## Non-Goals

- NG1: Post-signup email sequences or onboarding flows
- NG2: A/B testing infrastructure
- NG3: Tier interest capture in waitlist form (tracked in #1139)
- NG4: Urgency/scarcity framing (waitlist counter, founder pricing lock-in)
- NG5: Pricing tier simplification (keeping 4 tiers)
- NG6: About page creation (flagged as opportunity, separate scope)

## Functional Requirements

- FR1: Homepage hero displays platform positioning with inline email waitlist form
- FR2: Homepage hero CTA links to pricing page ("See Pricing & Join Waitlist")
- FR3: Secondary CTA on homepage for self-hosted path ("Or try the open-source plugin")
- FR4: Pricing link added to main navigation header
- FR5: Getting Started page presents two paths: Cloud Platform (primary) with waitlist CTA, and Self-Hosted (secondary) with CLI install instructions
- FR6: All pages with existing CTAs updated to point toward waitlist/pricing rather than CLI install
- FR7: Vision page updated to remove "Success Tax" revenue model language

## Technical Requirements

- TR1: Remove "plugin" and "terminal-first" from all meta descriptions, OG tags, and Twitter cards
- TR2: Update JSON-LD structured data: remove `"price": "0"` and `"softwareRequirements": "Claude Code CLI"`, update to reflect platform positioning
- TR3: Waitlist form uses Buttondown with `pricing-waitlist` tag (same as pricing page form)
- TR4: All changes are Eleventy template/content changes — no new build dependencies

## UX Gate (BLOCKING)

Per workflow rules, user-facing pages with product/UX implications require:

1. **ux-design-lead** wireframes for homepage and Getting Started layout changes
2. **copywriter** produces approved copy for hero, CTAs, and Getting Started content
3. **CMO reviews** both artifacts before implementation begins

Implementation MUST NOT proceed until these artifacts are produced and reviewed.

## Acceptance Criteria

- [ ] Homepage hero shows platform positioning with inline waitlist email form
- [ ] Homepage hero CTA links to pricing page
- [ ] Pricing appears in main navigation
- [ ] Getting Started shows two-path layout (cloud primary, self-hosted secondary)
- [ ] Zero instances of "plugin" as primary framing on any public page
- [ ] Meta descriptions updated on all pages (no "Claude Code plugin")
- [ ] JSON-LD structured data reflects platform, not free plugin
- [ ] Vision page updated (no "Success Tax" language)
- [ ] OG tags and Twitter cards render correctly in production
