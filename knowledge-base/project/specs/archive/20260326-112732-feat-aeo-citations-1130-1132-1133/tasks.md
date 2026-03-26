# Tasks: AEO External Citations (#1130, #1132, #1133)

## Phase 1: Homepage Citations (#1130)

- [x] 1.1 Read `plugins/soleur/docs/index.njk`
- [x] 1.2 Replace the self-attributed blockquote (lines 78-83) with a Dario Amodei or Sam Altman quote using `<a href>` tags with `rel="noopener noreferrer"`
- [x] 1.3 Add at least 1 additional external citation in the problem section or FAQ answers
- [x] 1.4 Ensure HTML entities (`&ldquo;`, `&rsquo;`) are used consistently in inserted quotes
- [x] 1.5 Verify all citation URLs return HTTP 200 via WebFetch

## Phase 2: AI Agents Guide Citations (#1132)

- [x] 2.1 Read `plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md`
- [x] 2.2 Add Carta Solo Founders Report citation (36.3% statistic) to the introduction
- [x] 2.3 Add BLS citation to "The Eight Domains" section (reuse from CaaS post)
- [x] 2.4 Add Cursor $1B ARR / CNBC citation to "Why Point Solutions Fail" section
- [x] 2.5 Add Fortune/TechCrunch one-person unicorn citations to "What a Full AI Organization Looks Like" section
- [x] 2.6 Add Dario Amodei / Inc.com or Fortune / Alibaba citations for authority
- [x] 2.7 Ensure at least 5 total external citations across the article
- [x] 2.8 Do NOT add the Anthropic "80% of developers" statistic -- it is unverifiable
- [x] 2.9 Update FAQ JSON-LD `"text"` fields if any FAQ answer now references a cited statistic
- [x] 2.10 Verify all citation URLs return HTTP 200 via WebFetch

## Phase 3: Case Study Cost Citations (#1133)

- [x] 3.1 Read all 5 case study files
- [x] 3.2 Add Robert Half 2026 Legal Salary Guide citation to `case-study-legal-document-generation.md` cost section
- [x] 3.3 Add Clutch.co Consulting Pricing citation to `case-study-business-validation.md` cost section
- [x] 3.4 Add Salary.com CI Analyst or consulting rate guide citation to `case-study-competitive-intelligence.md` cost section
- [x] 3.5 Add Clutch.co Branding Pricing citation to `case-study-brand-guide-creation.md` cost section
- [x] 3.6 Add fractional COO rate guide citation to `case-study-operations-management.md` cost section
- [x] 3.7 Add "as of [year]" freshness signals to all cost citations
- [x] 3.8 Update FAQ `<details>` sections in all 5 case studies to match cited body text
- [x] 3.9 Update JSON-LD structured data `"text"` fields in all 5 case studies to match cited body text
- [x] 3.10 Use consultant/agency rate guides (not employee salary surveys) to avoid contradicting claimed rates
- [x] 3.11 Verify all citation URLs return HTTP 200 via WebFetch

## Phase 4: Validation

- [ ] 4.1 Run fact-checker agent on each modified file to verify all citations
- [x] 4.2 Build docs site locally (`npx @11ty/eleventy`) and verify no build errors
- [x] 4.3 Spot-check rendered pages for correct link formatting
- [ ] 4.4 Run compound before commit
