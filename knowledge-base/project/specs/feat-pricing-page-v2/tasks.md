# Tasks: Pricing Page v2

## Phase 1: Template Rewrite

- [ ] 1.1 Rewrite hero section: "Every department. One price." headline, value-articulation subline
- [ ] 1.2 Add hiring comparison table section (6-8 roles: Marketing Director, General Counsel, CFO, Ops Manager, Product Manager, Sales Director, Support Lead, CTO — each with monthly cost vs. "Included")
- [ ] 1.3 Add department roster grid section (8 departments with icon, name, description, agent count — hardcoded from DOMAIN_META data)
- [ ] 1.4 Add scenario callout section (3 cards: "Need a privacy policy? Your CLO drafts it.", "Competitor drops pricing? Your CRO updates battlecards.", "Quarter closing? Your CFO runs the numbers.")
- [ ] 1.5 Redesign tier cards section
  - [ ] 1.5.1 Solo tier: $49/mo, 2 concurrent agents, feature list, "Join Waitlist" CTA + Coming Soon badge
  - [ ] 1.5.2 Startup tier: $149/mo, 5 concurrent agents, feature list, "Join Waitlist" CTA + Coming Soon badge
  - [ ] 1.5.3 Scale tier: $499/mo, unlimited agents, feature list, "Join Waitlist" CTA + Coming Soon badge
  - [ ] 1.5.4 Enterprise tier: "Contact Us", custom, rev share at $10M+ ARR, "Contact Us" CTA
  - [ ] 1.5.5 Self-hosted tier: Free (Apache-2.0), all agents, "Install Now" linking to getting-started
- [ ] 1.6 Rewrite FAQ section (5 questions: cost, concurrent slots, Claude cost, free option, launch timeline)
- [ ] 1.7 Rewrite final CTA section with waitlist email capture
- [ ] 1.8 Update frontmatter: new description, ogImageAlt
- [ ] 1.9 Replace all "plugin" instances with "platform" (FR10)

## Phase 2: CSS Updates

- [ ] 2.1 Add `.pricing-hiring-table` styles (two-column, alternating rows, highlight "Included" column)
- [ ] 2.2 Add `.department-roster` grid styles (4x2 → 2x4 → 1x8 responsive)
- [ ] 2.3 Add `.scenario-callout` card styles (3-column → 1-column responsive)
- [ ] 2.4 Update `.pricing-grid` for 5-card responsive layout (3+2 desktop → 2+2+1 tablet → 1x5 mobile)
- [ ] 2.5 Verify `.pricing-card-badge` "Coming Soon" styling works in new layout

## Phase 3: Schema & Meta

- [ ] 3.1 Update FAQPage JSON-LD with new 5 questions and answers
- [ ] 3.2 Add SoftwareApplication + Offer schema array (5 offers with availability status)
- [ ] 3.3 Update OG image alt text to remove "$0" framing

## Phase 4: Content Alignment

- [ ] 4.1 Update `knowledge-base/product/pricing-strategy.md` with decided pricing model

## Phase 5: Validation

- [ ] 5.1 Run Eleventy build — verify no errors
- [ ] 5.2 Screenshot at 1440px, 768px, 375px via Playwright
- [ ] 5.3 Visual review of all 7 sections
- [ ] 5.4 Verify zero "plugin" instances in rendered output
- [ ] 5.5 Verify FAQ and SoftwareApplication schema validates
