# Newsletter Brainstorm

**Date:** 2026-03-10
**Issue:** #501
**Branch:** feat-newsletter
**Status:** Decided

## What We're Building

A two-phase email capture and newsletter system for soleur.ai using Buttondown as the newsletter platform.

**Phase A (Now):** Email signup form embedded in three locations (site footer, homepage CTA section, blog page) with double opt-in. No newsletter sends — just collecting subscribers for future outreach and content distribution.

**Phase B (Later — gated on 100+ weekly visitors + 4+ published articles):** Monthly newsletter sends via Buttondown with curated content: changelog highlights, blog article summaries, and community updates.

## Why This Approach

### Why Buttondown over alternatives

| Criterion | Buttondown | Resend | Loops |
|-----------|-----------|--------|-------|
| Newsletter-native | Yes (subscribe, opt-in, unsubscribe, archives) | No (transactional API — build everything yourself) | Yes |
| Static site compatibility | Embed form, no backend | API only, needs backend | Embed form |
| GDPR compliance built-in | Yes (double opt-in, unsubscribe) | You implement | Yes |
| Free tier | 100 subscribers | 3,000 emails/mo (but no sub management) | 1,000 contacts |
| MCP server | Community, low quality | Official, high quality | Unknown |

**MCP bundling is irrelevant** — all three use API key auth, which cannot be bundled in `plugin.json` (only OAuth/HTTP servers can). MCP tools are operator-only convenience, not a user-facing feature.

**Buttondown wins on simplicity.** The issue says "investigate if there is a tool we can use instead of building this ourselves." Resend would require building subscriber storage, double opt-in flow, unsubscribe handling, and archive pages from scratch — exactly what the issue wants to avoid. Buttondown handles the entire newsletter lifecycle natively.

### Why sequenced (capture now, send later)

- Marketing strategy gates newsletter sends at Phase 4 (Weeks 17+, 100+ weekly visitors). Currently at ~Week 6 with 1 blog article.
- Email capture serves Phase 2 validation outreach — different use case, different gate.
- Avoids premature infrastructure while still building a subscriber list.
- A newsletter with nothing to say damages the brand.

### Why three placements

- **Footer (global):** Low friction, always visible on every page. Standard for early-stage capture.
- **Homepage CTA:** Prominent placement for visitors evaluating the product.
- **Blog page:** Captures readers already engaged with content — most relevant audience.

## Key Decisions

1. **Platform:** Buttondown (newsletter-native, handles compliance, free for 100 subs, $9/mo at 1k)
2. **Consent model:** Double opt-in (CNIL best practice, strongest GDPR Art. 7 proof)
3. **Form placement:** Site footer (global) + homepage CTA section + blog page
4. **Phase A scope:** Email capture only — no newsletter sends
5. **Phase B trigger:** 100+ weekly visitors AND 4+ published articles
6. **Data minimization:** Collect email address only — no name, company, or other fields

## Open Questions

1. **Buttondown EU-US data transfer compliance:** Is Buttondown certified under the EU-US Data Privacy Framework? If not, are SCCs available? Must verify before implementation.
2. **Buttondown DPA availability:** Need a Data Processing Agreement (GDPR Art. 28) from Buttondown as they act as data processor.
3. **Tracking pixels:** Does Buttondown embed tracking pixels in emails? If so, requires additional disclosure in privacy docs.
4. **Archive hosting:** When Phase B launches, should the newsletter archive live on soleur.ai (pulled into Eleventy at build time) or on Buttondown's hosted page?
5. **Content workflow for Phase B:** Who writes the newsletter? Manual curation or automated from changelog + blog RSS?
6. **Form copy and CTA text:** Needs brand-aligned copy — delegate to copywriter when implementing.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|-----------|
| No email marketing skills (cold-email, email-sequence equivalents) | Marketing | Identified in marketingskills overlap analysis — Soleur has no email marketing capability compared to competitors |
| No form optimization skills (form-cro, signup-flow-cro equivalents) | Marketing | Lead capture form optimization is a recognized gap |
| MCP API key auth bundling | Engineering/Plugin | API-key-only MCP servers cannot be distributed via plugin.json — blocks all newsletter MCP tools from being user-facing |

## Domain Leader Assessments

### CMO Assessment

- Email capture is an identified infrastructure blocker in the marketing strategy
- Two-step approach recommended: capture now (Phase 2 validation), send later (Phase 4)
- Newsletter positions Soleur as category thought leader
- Delegate form placement/copy to conversion-optimizer and copywriter

### COO Assessment

- Adding $9/mo Buttondown brings recurring spend to ~$34/mo (115% increase)
- Plausible trial ends 2026-03-24 ($9/mo) — avoid stacking two $9/mo tools simultaneously
- DNS changes needed for sender domain verification (Cloudflare)
- MCP is not a vendor differentiator — pick the tool that requires least engineering

### CLO Assessment

- **This is the first PII collection on soleur.ai** — significant privacy posture change
- Current legal docs claim "no personal data collection" — must be updated before launch
- Three critical document updates: Privacy Policy, GDPR Policy, Data Protection Disclosure
- GDPR Art. 6(1)(a) consent is the lawful basis (not legitimate interest)
- Must verify Buttondown's EU-US data transfer mechanism (DPF or SCCs)
- CAN-SPAM requires physical mailing address in emails (25 rue de Ponthieu, 75008 Paris)
