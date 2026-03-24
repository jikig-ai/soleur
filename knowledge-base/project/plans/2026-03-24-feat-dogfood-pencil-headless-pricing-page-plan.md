---
title: "feat: Dogfood Pencil Headless CLI via Pricing Page (#656)"
type: enhancement
issue: 656
branch: dogfood-pencil-headless
created: 2026-03-24
---

# Dogfood Pencil Headless CLI via Pricing Page

## Summary

Dogfood the pencil.dev headless CLI integration (PR #1087) by designing and building the soleur.ai pricing page (#656). Two-pass approach: mid-fi wireframe in .pen first, then HTML/Eleventy implementation with pencil-generated assets. Batch-file all integration issues at the end.

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

## Phase 0: Register Pencil Headless MCP

**Goal:** Get pencil MCP tools available in Claude Code.

### 0.1 Verify prerequisites

- Check Node.js >= 22.9.0 is available (`node --version` or probe nvm/fnm)
- Check pencil CLI is installed (`which pencil` or `~/.local/node_modules/.bin/pencil`)
- Check auth status (`pencil status`)

### 0.2 Run pencil-setup skill

- Run `pencil-setup` to register the headless MCP adapter
- The skill runs `check_deps.sh` which probes 4 tiers; headless CLI (Tier 0) should be preferred
- Registration: `claude mcp add -s user pencil -- <node> <adapter-path>`

### 0.3 Verify MCP is live

- Call `get_editor_state` to confirm the adapter responds
- Call `get_guidelines("landing-page")` to load design guidance
- **Dogfooding checkpoint:** Log any issues with setup flow

## Phase 1: Wireframe in Pencil (.pen)

**Goal:** Create a mid-fi wireframe of the pricing page layout with brand colors.

### 1.1 Set up design variables

- Call `set_variables` to load brand tokens:
  - `bg: #0A0A0A`, `surface: #141414`, `border: #2A2A2A`
  - `accent: #C9A962`, `ctaGradientStart: #D4B36A`, `ctaGradientEnd: #B8923E`
  - `textPrimary: #FFFFFF`, `textSecondary: #848484`

### 1.2 Design page sections via batch_design

Create the pricing page wireframe with these sections (top to bottom):

1. **Hero section** — badge "PRICING" (gold, uppercase, Inter 12px 600) + headline "Every department. One price." (Cormorant Garamond, white) + subheadline (Inter, secondary)
2. **Tier cards** (2 cards side by side):
   - Open Source: Free, CLI plugin, feature list
   - Hosted Pro: $49/mo + 10% rev share, web platform, feature list, "Coming Soon" badge
3. **Comparison table** — Soleur (free) vs Cursor ($20/mo) vs Devin ($20/mo) vs GitHub Copilot ($10-39/mo). Features: agents, departments, brand/legal/ops automation, open source
4. **Cost explainer** — "What does it actually cost?" section explaining Claude subscription/API costs with typical ranges ($20-100/mo)
5. **FAQ section** — 5-6 questions about pricing, Claude costs, competitors, future plans
6. **CTA section** — dual CTA: "Install the Plugin" (primary) + "Try the Web Platform" (secondary)

**Known gotchas from learnings:**

- Use `fill` not `textColor` for text color (silently ignored otherwise)
- Text nodes auto-size width — use two-pass centering: create, `snapshot_layout`, reposition
- Batch measurements into a single `snapshot_layout` call

### 1.3 Screenshot and review

- Call `get_screenshot` on the full canvas
- Call `get_screenshot` on individual sections for detail review
- **Dogfooding checkpoint:** Test `get_screenshot` with tracked node IDs from `batch_design` responses (unchecked acceptance test from PR #1087)

### 1.4 Iterate

- Review screenshots, adjust layout via additional `batch_design` calls
- Test concurrent tool calls (batch_design + get_screenshot in quick succession)
- **Dogfooding checkpoint:** Note any REPL parsing issues, timeouts, or command queue problems

## Phase 2: HTML/Eleventy Implementation

**Goal:** Build the pricing page from the wireframe.

### 2.1 Create the page file

- **File:** `plugins/soleur/docs/pages/pricing.njk`
- **Frontmatter:**

```yaml
---
title: Pricing
description: "Every department. One price. Soleur is free and open source. Compare to Cursor, Devin, and GitHub Copilot."
layout: base.njk
permalink: pages/pricing.html
---
```

### 2.2 Page structure (Nunjucks template)

Use existing CSS classes from the docs site:

| Section | CSS Classes | Notes |
|---------|-------------|-------|
| Hero | `.page-hero` | Badge + headline + subheadline |
| Tier cards | `.landing-section` + new `.pricing-grid` | 2-column, responsive to 1-column on mobile |
| Comparison table | `.landing-section` + new `.pricing-table` | Responsive: horizontal scroll or card-stack on mobile |
| Cost explainer | `.landing-section` + `.section-label` + `.section-title` | Prose content with concrete ranges |
| FAQ | `.faq-list` + `.faq-item` | Outside `.container` div per learning |
| CTA | `.landing-cta` | Dual buttons: `.btn-primary` + `.btn-secondary` |

**New CSS needed** (add to `plugins/soleur/docs/css/style.css`):

- `.pricing-grid` — 2-column grid, 1-column below 768px
- `.pricing-card` — tier card with featured state (gold border for recommended tier)
- `.pricing-price` — large Cormorant Garamond price number
- `.pricing-period` — smaller period text ("/mo")
- `.pricing-features` — feature checklist with checkmarks
- `.pricing-badge` — "Coming Soon" badge for Hosted Pro
- `.pricing-table` — comparison table with dark theme styling
- `.pricing-table-highlight` — highlight column for Soleur

### 2.3 Add navigation link

- **File:** `plugins/soleur/docs/_data/site.json`
- Add `{ "label": "Pricing", "url": "pages/pricing.html" }` to `nav` array (after "Vision")
- Add to `footerLinks` array

### 2.4 FAQPage JSON-LD

Add inline `<script type="application/ld+json">` with `FAQPage` schema. Questions:

1. "Is Soleur free?" — Yes, the open-source CLI plugin is completely free.
2. "What does Soleur cost?" — The plugin is free. You pay for your own Claude subscription ($20/mo) or API usage.
3. "How much does Claude cost for typical Soleur usage?" — Solo founders typically spend $20-100/mo on Claude depending on usage intensity.
4. "How does Soleur compare to Cursor/Devin/Copilot?" — Soleur covers 8 business departments, not just code. And it's free.
5. "Will Soleur always be free?" — The open-source plugin will always be free. A hosted Pro tier ($49/mo + rev share) is planned.
6. "What is the revenue share?" — Pro tier includes 10% revenue share on revenue generated with Soleur's help, after a threshold.

**Do NOT duplicate** the homepage FAQ "Is Soleur free?" — use distinct question wording.

### 2.5 OG/Twitter meta tags

Handled automatically by `base.njk` from frontmatter `title` and `description`. Use `{{ site.url }}{{ page.url }}` for `og:url` (no double slash per learning).

### 2.6 Grid divisibility check

Verify card counts at all breakpoints:

- Desktop (>1024px): 2 tier cards in 2 columns = even
- Tablet (769-1024px): 2 cards in 2 columns or 1 column = OK
- Mobile (<=768px): 1 column = OK

Comparison table: horizontal scroll on mobile or stack to card layout.

## Phase 3: Asset Generation via Pencil

**Goal:** Generate visual assets using pencil export tools.

### 3.1 OG image

- Design a 1200x630 OG image in pencil with:
  - Dark background (#0A0A0A)
  - "Every department. One price." headline (Cormorant Garamond, white)
  - "$0" large text with gold accent
  - Soleur branding
- Export via `export_nodes` as PNG
- Save to `plugins/soleur/docs/images/pricing-og.png`
- Update frontmatter to use custom OG image (may need `ogImage` variable in base.njk)

### 3.2 Comparison graphic (optional)

- If the comparison table needs a social-shareable graphic version
- Design in pencil, export as PNG
- Save to `plugins/soleur/docs/images/pricing-comparison.png`

### 3.3 Dogfooding checkpoints

- Test `export_nodes` with different formats (PNG, WebP)
- Test export of specific node IDs vs full canvas
- Note any quality/resolution issues

## Phase 4: Build Validation

### 4.1 Build the site

```bash
npx @11ty/eleventy --input=plugins/soleur/docs --output=_site
```

### 4.2 SEO validation

- Run `validate-seo.sh` against `_site/pages/pricing.html`
- Check: canonical URL, JSON-LD validity, og:title, Twitter card
- Verify FAQPage schema validates (no duplicate with homepage FAQ)

### 4.3 Visual verification

- Use Playwright to screenshot the pricing page at 3 breakpoints (1440px, 768px, 375px)
- Verify grid divisibility rule
- Check comparison table on mobile
- Verify brand compliance (colors, fonts, voice)

## Phase 5: Dogfooding Issue Roundup

### 5.1 Compile issue log

Review all issues encountered during Phases 0-4. For each:

- Summary of what happened
- Steps to reproduce
- Expected vs actual behavior
- Whether it was fixed inline or deferred
- Adapter log context if relevant

### 5.2 Batch-create GitHub issues

Create issues with labels:

- `domain/engineering` + `type/bug` for adapter issues
- `domain/engineering` + `type/chore` for ergonomics improvements
- Link all to PR #1087 (headless CLI integration) as related

### 5.3 Update brainstorm test matrix

Check off items in the dogfooding test matrix in the brainstorm document.

## Acceptance Criteria

- [ ] Pencil headless MCP registered and responding to tool calls
- [ ] Pricing page wireframe exists as .pen file with brand styling
- [ ] Screenshot of wireframe reviewed and approved
- [ ] HTML pricing page at `/pages/pricing.html` with Eleventy build passing
- [ ] Two tiers displayed: Free (open source) and Hosted Pro ($49/mo + 10% rev share)
- [ ] Competitor comparison table: Soleur vs Cursor vs Devin vs GitHub Copilot
- [ ] Claude cost guidance section with typical ranges ($20-100/mo)
- [ ] FAQPage JSON-LD schema validates
- [ ] OG image generated via pencil export
- [ ] Pricing link in site nav and footer
- [ ] Visual verification at 3 breakpoints (desktop, tablet, mobile)
- [ ] All integration issues filed on GitHub with reproduction steps
- [ ] Competitor prices shown with "as of March 2026" footnote

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

### Engineering (CTO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** MCP adapter's REPL parsing is the primary fragility point. Test: command serialization under concurrent tool calls, crash recovery, 30-second timeout adequacy for complex batch_design. Text node two-pass workflow is an ergonomics concern.

### Marketing (CMO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Headless CLI npm package is NOT publicly announced — no public marketing content should reference it. Pricing page itself is a P1 marketing win. Follow brand guide for voice, palette, and competitive positioning. Avoid prohibited terms ("AI-powered", "assistant", "plugin" in marketing copy).

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo
**Pencil available:** pending (registration is Phase 0 of this plan)

#### Findings

**spec-flow-analyzer:** Identified 15 gaps including CTA destination ambiguity (resolved: dual CTA), tier display question (resolved: free + hosted pro), Vision page contradiction (resolved: rev share is consistent), Claude cost guidance need (addressed in Phase 2 cost explainer section), mobile comparison table layout (addressed in Phase 2 with responsive CSS), and competitor pricing staleness (addressed with "as of" footnote).

**CPO (from brainstorm):** Pricing page exercises layout primitives common across all design tasks. Success validates headless CLI as viable design workflow. Key validation: wireframe-to-HTML utility of the artifacts produced.

## Test Scenarios

1. **Happy path:** User arrives from search "soleur pricing" → sees free tier + comparison → clicks "Install the Plugin" → lands on getting-started page
2. **Web platform path:** User clicks "Try the Web Platform" → lands on app.soleur.ai signup
3. **Claude cost question:** User reads FAQ "How much does Claude cost?" → gets $20-100/mo range with context
4. **Mobile comparison:** User on phone sees comparison table → table is readable (horizontal scroll or card stack)
5. **SEO validation:** Build produces valid HTML with FAQPage JSON-LD, canonical URL, OG tags
6. **Future tier update:** When pricing launches, update tier cards from "Coming Soon" to live — should be a content-only change

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `plugins/soleur/docs/pages/pricing.njk` | Create | Pricing page template |
| `plugins/soleur/docs/css/style.css` | Modify | Add pricing-specific CSS classes |
| `plugins/soleur/docs/_data/site.json` | Modify | Add "Pricing" to nav and footer |
| `plugins/soleur/docs/images/pricing-og.png` | Create | OG image generated via pencil |
| `pricing-wireframe.pen` | Create | Pencil wireframe (working file) |

## Build Sequence

```text
Phase 0: Register pencil MCP (5 min)
Phase 1: Wireframe in pencil (30-45 min)
Phase 2: HTML/Eleventy implementation (45-60 min)
Phase 3: Asset generation via pencil (15-20 min)
Phase 4: Build validation (10-15 min)
Phase 5: Issue roundup (15-20 min)
```
