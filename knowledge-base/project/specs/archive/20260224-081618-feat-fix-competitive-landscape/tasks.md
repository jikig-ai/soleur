# Tasks: Fix Competitive Landscape Tables and Tiers

## Phase 1: Table Formatting Normalization

- [ ] 1.1 Standardize all existing tier tables to use `Competitor | Approach | Differentiation from Soleur` headers
- [ ] 1.2 Fix Tier 1 table: rename "Overlap" column to "Approach"
- [ ] 1.3 Fix current Tier 4 table: rename "Platform" to "Approach", rename "Overlap" to "Differentiation from Soleur"
- [ ] 1.4 Normalize all separator lines to `|---|---|---|` format
- [ ] 1.5 Ensure blank line precedes every table (GFM rendering requirement)
- [ ] 1.6 Trim verbose cell content to 1-2 sentences maximum per cell

## Phase 2: Add CaaS Tier (New Tier 3)

- [ ] 2.1 Insert new section: **Tier 3: Company-as-a-Service / Full-stack business platforms**
- [ ] 2.2 Add flat table with 10 competitors: SoloCEO, Tanka, Lovable.dev, Bolt.new, v0.dev, Replit Agent, Notion AI 3.0, Systeme.io, Stripe Atlas, Firstbase
- [ ] 2.3 Verify all competitor URLs are valid and working
- [ ] 2.4 Renumber current Tier 3 (AI agent frameworks) to Tier 4
- [ ] 2.5 Renumber current Tier 4 (DIY stack) to Tier 5

## Phase 3: Update Analysis Sections

- [ ] 3.1 Add structural advantage #3: operational continuity vs. one-time diagnostics
- [ ] 3.2 Add structural advantage #4: full-domain coverage vs. partial overlap
- [ ] 3.3 Update "Assessment" to acknowledge expanded landscape while preserving PASS verdict
- [ ] 3.4 Update `last_updated` frontmatter date to 2026-02-24

## Phase 4: Verification

- [ ] 4.1 Render markdown in GitHub preview to verify all tables display correctly
- [ ] 4.2 Verify no broken links across all competitor URLs
- [ ] 4.3 Verify `##` heading contract is preserved (business-validator agent parsing compatibility)
- [ ] 4.4 Verify tier ordering reflects proximity of substitution (closest first, loosest last)
- [ ] 4.5 Verify all tiers use consistent 3-column format
