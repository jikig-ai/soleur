# Tasks: AEO External Citations (#1130, #1132, #1133)

## Phase 1: Homepage Citations (#1130)

- [ ] 1.1 Read `plugins/soleur/docs/index.njk`
- [ ] 1.2 Replace the self-attributed blockquote (lines 78-83) with an externally cited quote using `<a href>` tags
- [ ] 1.3 Add at least 1 additional external citation in the problem section or FAQ answers
- [ ] 1.4 Verify all citation URLs return HTTP 200

## Phase 2: AI Agents Guide Citations (#1132)

- [ ] 2.1 Read `plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md`
- [ ] 2.2 Research and verify external source URLs for solo founder market data, AI adoption stats, and industry analysis
- [ ] 2.3 Add citations to introduction and "What Makes an AI Agent Different" sections
- [ ] 2.4 Add citations to "The Eight Domains" and "Why Point Solutions Fail" sections
- [ ] 2.5 Add citations to "The Compound Knowledge Advantage" and "What a Full AI Organization Looks Like" sections
- [ ] 2.6 Add citations to "Getting Started" section
- [ ] 2.7 Verify all citation URLs return HTTP 200 and content matches claims

## Phase 3: Case Study Cost Citations (#1133)

- [ ] 3.1 Research and verify source URLs for professional service rate data (legal, consulting, CI, brand, ops)
- [ ] 3.2 Add cost source citations to `case-study-legal-document-generation.md` "Cost Comparison" section
- [ ] 3.3 Add cost source citations to `case-study-business-validation.md` "Cost Comparison" section
- [ ] 3.4 Add cost source citations to `case-study-competitive-intelligence.md` "Cost Comparison" section
- [ ] 3.5 Add cost source citations to `case-study-brand-guide-creation.md` "Cost Comparison" section
- [ ] 3.6 Add cost source citations to `case-study-operations-management.md` "Cost Comparison" section
- [ ] 3.7 Update FAQ `<details>` sections in all 5 case studies to match cited body text
- [ ] 3.8 Update JSON-LD structured data in all 5 case studies to match cited body text
- [ ] 3.9 Verify all citation URLs return HTTP 200

## Phase 4: Validation

- [ ] 4.1 Build docs site locally (`npx @11ty/eleventy`) and verify no build errors
- [ ] 4.2 Spot-check rendered pages for correct link formatting
- [ ] 4.3 Run compound before commit
