# Tasks: Pricing Page v2

## Implementation (pricing.njk + style.css)

- [ ] 1.1 Rewrite hero section: "Every department. One price." headline, value subline, breadth stat line
- [ ] 1.2 Add hiring comparison table (6-8 roles with monthly cost, "Included" column, scenario proof per row)
- [ ] 1.3 Redesign tier cards section (5 tiers)
  - [ ] 1.3.1 Solo: $49/mo, 2 concurrent agents, feature list, "Join Waitlist" + Coming Soon
  - [ ] 1.3.2 Startup: $149/mo, 5 concurrent agents, feature list, "Join Waitlist" + Coming Soon
  - [ ] 1.3.3 Scale: $499/mo, unlimited agents, feature list, "Join Waitlist" + Coming Soon
  - [ ] 1.3.4 Enterprise: "Contact Us", custom, rev share at $10M+ ARR
  - [ ] 1.3.5 Self-hosted: Free (Apache-2.0), all agents, "Install Now" → getting-started
- [ ] 1.4 Rewrite FAQ (5 questions: cost, concurrent slots, Claude cost, free option, launch timeline)
- [ ] 1.5 Rewrite final CTA with waitlist email capture (reuse newsletter form pattern)
- [ ] 1.6 Update FAQPage JSON-LD with new 5 questions
- [ ] 1.7 Update frontmatter: description, ogImageAlt (remove "$0")
- [ ] 1.8 Replace all "plugin" with "platform" (FR10)
- [ ] 1.9 CSS: `.pricing-hiring-table` styles, expand `.pricing-grid` for 5 cards, verify `.pricing-card-badge`

## Validation

- [ ] 2.1 Run Eleventy build — verify no errors
- [ ] 2.2 Screenshot at 1440px, 768px, 375px via Playwright
- [ ] 2.3 Visual review of all sections
- [ ] 2.4 Verify zero "plugin" instances in rendered output
- [ ] 2.5 Verify FAQPage schema validates
