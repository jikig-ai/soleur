---
title: "feat: Dogfood Pencil Headless CLI via Pricing Page (#656)"
type: enhancement
issue: 656
branch: dogfood-pencil-headless
created: 2026-03-24
updated: 2026-03-25
---

# Dogfood Pencil Headless CLI via Pricing Page

## Summary

Dogfood the pencil.dev headless CLI integration (PR #1087) by designing and building the soleur.ai pricing page (#656). Quick wireframe in .pen (15 min tool coverage), then HTML/Eleventy implementation, then pencil-generated OG image. Batch-file all integration issues at the end.

## Context

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-24-dogfood-pencil-headless-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-dogfood-pencil-headless/spec.md`
- Pricing strategy: `knowledge-base/product/pricing-strategy.md`
- Brand guide: `knowledge-base/marketing/brand-guide.md`
- Related: PR #1087 (headless CLI integration), Issue #656 (pricing page)

## Pricing Model (Confirmed)

Two tiers only — Soleur IS the team (AI agents), not a multi-seat product:

| Tier | Price | Delivery | Target |
|------|-------|----------|--------|
| **Open Source** | Free | CLI plugin (`claude plugin install soleur`) | All users |
| **Hosted Pro** | $49/mo + 10% rev share | Web platform (app.soleur.ai) | Solo founders with active products |

The 10% revenue share IS the "Success Tax" from the Vision page — these are consistent. No Vision page update needed.

## Phase 0: Setup

**Goal:** Get pencil MCP tools available in Claude Code.

- Run `pencil-setup` skill (handles Node.js detection, CLI install, auth check, and MCP registration)
- Verify MCP responds: call `get_editor_state`
- **Dogfooding checkpoint:** Log any issues with setup flow

## Phase 1: Quick Wireframe in Pencil (15 min)

**Goal:** Exercise pencil MCP tools (batch_design, set_variables, get_screenshot) with a real layout. Not a production artifact — a tool validation pass.

- Call `set_variables` to load brand tokens (bg, surface, accent, text colors)
- Call `batch_design` to create page sections: hero, 2 tier cards, comparison table, FAQ, CTA
- Call `get_screenshot` on full canvas and individual node IDs (tests tracked ID from batch_design response — unchecked acceptance test from PR #1087)
- **Known gotcha:** Use `fill` not `textColor` for text color (silently ignored otherwise)
- **Known gotcha:** Text nodes auto-size width — use two-pass centering if needed

No iteration loops. Screenshot once, note issues, move to HTML.

## Phase 2: HTML/Eleventy Implementation

**Goal:** Build the pricing page as the production deliverable.

### Page file

- **File:** `plugins/soleur/docs/pages/pricing.njk`
- Frontmatter: `title: Pricing`, `description`, `layout: base.njk`, `permalink: pages/pricing.html`

### Page structure

Use existing CSS classes. New CSS limited to `.pricing-grid` (2-col responsive) and `.pricing-card` (tier card with featured state).

| Section | Pattern | Content |
|---------|---------|---------|
| Hero | `.page-hero` | "PRICING" badge + "Every department. One price." headline |
| Tier cards | `.landing-section` + `.pricing-grid` | Free (open source) + Hosted Pro ($49/mo + 10% rev share, "Coming Soon") |
| Comparison | `.landing-section` + responsive table | Soleur vs Cursor ($20/mo) vs Devin ($20/mo) vs Copilot ($10-39/mo). Prices as of March 2026. |
| Cost explainer | `.landing-section` + `.section-label` | "What does it actually cost?" — Claude $20-100/mo typical |
| FAQ | `.faq-list` outside `.container` | 4 questions focused on pricing mechanics (not duplicating homepage FAQ) |
| CTA | `.landing-cta` | "Install the Plugin" (primary) + "Try the Web Platform" (secondary) |

### FAQ questions (FAQPage JSON-LD)

1. "What does Soleur cost?" — The open-source plugin is free. You pay for your Claude subscription ($20/mo) or API usage.
2. "How much does Claude cost for typical Soleur usage?" — Solo founders typically spend $20-100/mo depending on usage intensity.
3. "What is the Hosted Pro plan?" — $49/mo + 10% revenue share for the web platform experience. Coming soon.
4. "What is the revenue share?" — 10% on revenue generated with Soleur's help, after a threshold. Aligns incentives.

### Navigation

- Add `{ "label": "Pricing", "url": "pages/pricing.html" }` to `nav` and `footerLinks` in `site.json`

## Phase 3: OG Image via Pencil

- Design 1200x630 OG image in pencil: dark bg, "Every department. One price." headline, "$0" in gold
- Export via `export_nodes` as PNG to `plugins/soleur/docs/images/pricing-og.png`
- **Dogfooding checkpoint:** Test export_nodes format and quality

## Phase 4: Validation and Issue Roundup

### Build and verify

- Run Eleventy build: `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`
- Run `validate-seo.sh` — check canonical URL, JSON-LD, og:title, Twitter card
- Playwright screenshots at 3 breakpoints (1440px, 768px, 375px)

### File issues

- Compile all pencil integration issues from Phases 0-3
- Batch-create GitHub issues with `domain/engineering` + `type/bug` labels and reproduction steps
- Update brainstorm test matrix checkboxes

## Acceptance Criteria

- [ ] Pencil headless MCP registered and responding to tool calls
- [ ] Wireframe created in .pen exercising batch_design, set_variables, get_screenshot
- [ ] HTML pricing page at `/pages/pricing.html` with Eleventy build passing
- [ ] Two tiers displayed: Free and Hosted Pro ($49/mo + 10% rev share)
- [ ] Competitor comparison table with "as of March 2026" footnote
- [ ] FAQPage JSON-LD validates
- [ ] OG image generated via pencil export
- [ ] Pricing link in site nav and footer
- [ ] Visual verification at 3 breakpoints
- [ ] All integration issues filed on GitHub

## Domain Review

**Domains relevant:** Engineering, Product, Marketing. See brainstorm doc for full assessments.

**Key constraints:** Headless CLI npm package is NOT publicly announced — no public content should reference it. Pricing page follows brand guide voice (declarative, no hedging). Avoid prohibited terms in marketing copy.

**Product/UX Gate:** Blocking (new user-facing page). spec-flow-analyzer identified 15 gaps — all resolved: dual CTA, free + hosted pro tiers, rev share consistent with Vision, Claude cost guidance added, mobile responsive table.

## Files to Create/Modify

| File | Action |
|------|--------|
| `plugins/soleur/docs/pages/pricing.njk` | Create |
| `plugins/soleur/docs/css/style.css` | Modify (add `.pricing-grid`, `.pricing-card`) |
| `plugins/soleur/docs/_data/site.json` | Modify (add nav + footer link) |
| `plugins/soleur/docs/images/pricing-og.png` | Create (pencil export) |
| `pricing-wireframe.pen` | Create (working file, not shipped) |
