# Spec: SEO/AEO/GEO Content Plan Alignment

**Issue:** #661
**Branch:** feat-seo-aeo-content-plan
**Created:** 2026-03-20

---

## Problem Statement

The 2026-03-17 growth audit revealed that the existing content strategy (last updated 2026-03-12) and marketing strategy (last updated 2026-03-13) are significantly stale. Both documents describe a pre-blog, pre-content state that no longer reflects reality (8 blog posts published, AEO score 68/100, 3 comparison articles live). New audit findings (FAQ JSON-LD gaps, listicle presence gap, dateModified signals) are not captured in any strategy document. Without reconciliation, the strategy docs cannot drive execution.

## Goals

1. Update `content-strategy.md` to reflect current content state, incorporate 2026-03-17 audit findings, and produce a rolling quarterly content calendar (March-June 2026)
2. Update `marketing-strategy.md` to reflect actual metrics and progress against the phased plan
3. Produce an execution-ready plan for P1 technical SEO/AEO fixes and highest-priority new content

## Non-Goals

- Executing the P1 fixes (that's a follow-up plan/implementation task)
- Writing new articles (that's downstream of the updated strategy)
- Off-site listicle outreach (separate workstream)
- Rewriting either document from scratch (layered update approach chosen)

## Functional Requirements

- FR1: Mark completed content gaps in `content-strategy.md` (CaaS article, Cursor comparison, case studies, blog infra)
- FR2: Update remaining content gaps with 2026-03-17 audit data (keyword volumes, competitive shifts, priority scores)
- FR3: Add new content gaps from audit (listicle presence, About/Founder page, external citations on non-blog pages)
- FR4: Replace stale 4-week content calendar with rolling quarterly calendar (March-June 2026) organized by month
- FR5: Refresh `marketing-strategy.md` current state assessment with actual metrics (8 blog posts, AEO 68/100, 3 comparisons, 5 case studies)
- FR6: Update phased execution plan in `marketing-strategy.md` to reflect Phase 0 complete and Phase 1 partially complete
- FR7: Align content pillar tables with what has been published vs. what remains

## Technical Requirements

- TR1: All document updates use the existing YAML frontmatter format (`last_updated`, `last_reviewed`, `depends_on`)
- TR2: Updated documents must reference the 2026-03-17 audit reports as source data
- TR3: Content calendar entries must align with campaign-calendar.md scheduling format
