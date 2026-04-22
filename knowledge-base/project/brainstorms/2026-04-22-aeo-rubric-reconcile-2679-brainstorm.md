---
date: 2026-04-22
topic: AEO audit rubric reconciliation (#2679, #2615)
issue: 2679
related_issues: [2615, 2596, 2647, 2678]
status: complete
---

# Brainstorm: AEO Audit Rubric Reconciliation

## What We're Building

Pin a **dual-rubric AEO audit template** (SAP headline + 8-component AEO diagnostic) so future runs of `scheduled-growth-audit.yml` produce deterministic, comparable scorecards. Close #2615 citing the 2026-04-21 audit where Presence scored 20/25 (80%), well above the ≥55/D threshold. Update the re-audit runbook to match.

## Why This Approach

The 04-18 → 04-19 → 04-21 rubric flip is drift, not a migration:

| Date | Rubric | Presence | Overall |
|---|---|---|---|
| 2026-04-18 | SAP | 40/F | 72 |
| 2026-04-19 | 8-component AEO | — (row absent) | 81/B |
| 2026-04-21 | SAP | **20/25 (80%)** | 78/B+ |

**Root cause:** Neither `.github/workflows/scheduled-growth-audit.yml` nor `plugins/soleur/agents/marketing/growth-strategist.md` prescribes a specific scorecard template. The workflow says "produce a structured scoring table"; the agent describes SAP dimensions qualitatively without pinning weights or grading scale. Each run freelances a table shape.

The 8-component rubric that appeared on 04-19 is actually richer (source citations, authority, entity clarity, FAQ schema are split out), but it drops the cross-audit Presence comparison #2615 depends on. A dual-rubric template keeps SAP as the stable year-over-year headline while surfacing the richer diagnostic detail.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Rubric strategy | Dual: SAP headline + 8-component AEO diagnostic | Preserves cross-audit comparability for #2615 while capturing richer diagnostic signal |
| #2615 verification | Close using 2026-04-21 audit (Presence 20/25 = 80%) | Evidence already exists; no need to wait another cron cycle |
| Pin location | Workflow prompt **and** agent doc | Belt-and-suspenders: covers both cron and ad-hoc `/soleur:growth aeo` invocations |
| Runbook update | Same PR | Atomic change: workflow + agent + runbook + #2615 closure land together |
| Rubric weights (SAP) | Structure 40, Authority 35, Presence 25 (per 04-21 audit) | Matches the existing documented SAP framework; grading scale reused verbatim |
| Rubric weights (AEO diagnostic) | FAQ 20, Answer density 15, Statistics 15, Source citations 15, Conversational 10, Entity clarity 10, Authority/E-E-A-T 10, Citation-friendly 5 | Matches the 04-19 run's weights; preserves the richer signal for trend-line analysis |

## Non-Goals

- Creating a separate audit workflow for AEO-only runs (the dual template folds into the existing scheduled-growth-audit cron).
- Re-scoring past audits retroactively. The 04-19 audit stays as-is; the 04-21 audit is the verification baseline.
- Touching `seo-aeo-analyst.md` — it owns technical SEO (JSON-LD, meta tags, sitemaps), not the content-level AEO scorecard.
- Adding new audit outputs (dashboards, trend charts, alerting). YAGNI — two tables in one markdown file suffices.

## Acceptance Criteria

1. `.github/workflows/scheduled-growth-audit.yml` Step 2 prompt prescribes the exact SAP + AEO template (dimensions, weights, grading scale) by reference to the agent doc or inline.
2. `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section includes both scorecard templates with weights and grading scale.
3. `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md` Phase 2 anchor logic handles both rubrics (or points to the pinned template).
4. #2615 closed referencing the 2026-04-21 audit (Presence 20/25 = 80% ≥ 55/D threshold).
5. #2679 closed by the PR.

## Open Questions

- Does the agent need an explicit instruction to produce BOTH tables, or is prescribing the headline SAP template + secondary "Detailed AEO Diagnostic" section enough? (Leaning toward explicit "produce both" instruction to prevent single-table freelancing.)
- Should the runbook move to `knowledge-base/engineering/ops/runbooks/` for better discoverability? (Out of scope for this PR; worth a separate cleanup.)

## Domain Assessments

**Assessed:** Marketing

### Marketing

**Summary:** Rubric pinning is a CMO operational concern (content audit determinism). SAP remains the canonical public-facing framework per `plugins/soleur/agents/marketing/growth-strategist.md`; the 8-component rubric is the diagnostic layer. Dual-template matches how the auditor already produced both framings across the three audits. No brand-guide implications.
