# Tasks: SEO/AEO/GEO Content Plan Alignment

**Plan:** `knowledge-base/plans/2026-03-20-docs-reconcile-seo-aeo-content-strategy-plan.md`
**Issue:** #661
**Branch:** feat-seo-aeo-content-plan

---

## Phase 1: Update content-strategy.md

- [x] 1.1 Update YAML frontmatter (`last_updated`, `last_reviewed`, fix stale `depends_on` paths from `knowledge-base/overview/` to actual paths under `knowledge-base/marketing/` and `knowledge-base/product/`, add 2026-03-17 audit paths)
- [x] 1.2 Mark Gap 2 (CaaS Category Definition) as COMPLETED with publication note
- [x] 1.3 Mark Gap 6 (Cursor Agent Platform) as COMPLETED with publication note
- [x] 1.4 Update Gap 1 (Cross-Domain Compounding): narrow to dedicated pillar, note partial coverage
- [x] 1.5 Update Gap 3 (IDE Positioning): note 3 comparisons done, narrow to "Agent Platform vs AI Organization"
- [x] 1.6 Update Gap 4 (Engineering-in-Context): align with "Vibe Coding vs Agentic Engineering" (P2-1, 18/20)
- [x] 1.7 Update Gap 5 (Autopilot vs Decision-Maker): align with audit P2-3
- [x] 1.8 Update Gap 7 (Copilot Cowork): lower to P3, note partial coverage
- [x] 1.9 Add Gap 10: Listicle Presence (Critical, audit OS-1)
- [x] 1.10 Add Gap 11: About/Founder Page (High, audit C5)
- [x] 1.11 Add Gap 12: External Citations on Non-Blog Pages (High, audit C1)
- [x] 1.12 Update Pillar 1 table: mark CaaS as PUBLISHED, update remaining pieces
- [x] 1.13 Update Pillar 2 table: mark "Why Tools Plateau" as PUBLISHED, add "Vibe Coding" article
- [x] 1.14 Update Pillar 3 table: mark 3 comparisons as PUBLISHED, add new articles from audit
- [x] 1.15 Update Pillar 4 table: mark 5 case studies as PUBLISHED, add About page
- [x] 1.16 Replace 4-week calendar with rolling quarterly calendar (March-June 2026)
- [x] 1.17 Update AEO checklist: add `updated` frontmatter, visible "Last Updated", external citation requirements
- [x] 1.18 Update sources footer with 2026-03-17 audit references

## Phase 2: Update marketing-strategy.md

- [x] 2.1 Update YAML frontmatter (`last_updated`, `last_reviewed`, fix stale `depends_on` paths, fix 3 internal body text references to `knowledge-base/overview/content-strategy.md`). **Warning:** `scripts/weekly-analytics.sh` reads growth targets from lines 335-339 — verify line positions after structural changes.
- [x] 2.2 Refresh Executive Summary metrics (content score, AEO score, blog infra, comparisons)
- [x] 2.3 Update "What Exists and Works" table (content plan executed, blog live, AEO progress)
- [x] 2.4 Update "What Is Broken or Missing" table (resolve completed items, add new items)
- [x] 2.5 Update Phase 0 status: COMPLETE
- [x] 2.6 Update Phase 1 status: IN PROGRESS with progress notes
- [x] 2.7 Update Phase 2 status: PARTIALLY STARTED
- [x] 2.8 Update Phase 3 status: EARLY PROGRESS
- [x] 2.9 Add current baselines to KPI tables
- [x] 2.10 Update Content Strategy Summary section to align with Phase 1 changes

## Phase 3: Update seo-refresh-queue.md

- [x] 3.1 Update YAML frontmatter (`last_updated`, fix stale `depends_on` paths from `knowledge-base/overview/` to actual paths)
- [x] 3.2 Mark completed Priority 1 items (homepage FAQ, agents H1, skills H1, getting-started paragraph, llms.txt)
- [x] 3.3 Mark completed Priority 2 items (comparison pages, CaaS article, articles index)
- [x] 3.4 Add new Priority 1 items from audit (FAQ JSON-LD gaps, "plugin" removal, Vision H1, `updated` frontmatter)
- [x] 3.5 Add new Priority 2 items from audit (FAQ sections on case studies, external citations, About page, OG images)
- [x] 3.6 Update competitor monitoring current status with 2026-03-17 data

## Phase 4: Consistency Verification

- [x] 4.1 Verify all `depends_on` file paths exist
- [x] 4.2 Cross-check quarterly calendar against campaign-calendar.md
- [x] 4.3 Confirm pillar table status consistency between content-strategy.md and marketing-strategy.md
- [x] 4.4 Run grep for stale claims: "0% informational", "No blog", "Zero executed", "1.6/10", "Content score 2/10", "Does not exist.*Cannot publish"
- [x] 4.5 Verify `scripts/weekly-analytics.sh` growth target line references still work after marketing-strategy.md changes
- [x] 4.6 Final read-through of all three updated documents
