---
feature: aeo-rubric-reconcile-2679
issue: 2679
related_issues: [2615, 2596, 2647]
status: draft
created: 2026-04-22
owner: CMO
---

# Spec: AEO Audit Rubric Reconciliation

## Problem Statement

The `scheduled-growth-audit.yml` cron produces non-deterministic AEO scorecards. Between 2026-04-18 and 2026-04-21, three consecutive audits used three different scorecard shapes (SAP → 8-component AEO → SAP), preventing cross-audit comparison. #2615's exit criteria (Presence score lift from 40/F → ≥55/D) could not be evaluated against the 04-19 audit because that run dropped the Presence row entirely. Neither the workflow prompt nor the `growth-strategist` agent doc prescribes a deterministic scorecard template.

## Goals

- **G1.** Pin a dual-rubric audit template (SAP headline + 8-component AEO diagnostic) so every future run produces both tables.
- **G2.** Close #2615 by citing the 2026-04-21 audit where Presence scored 20/25 (80%), well above the ≥55/D threshold.
- **G3.** Update the re-audit runbook (`knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md`) Phase 2 anchor logic to match the pinned template.

## Non-Goals

- **NG1.** Creating a separate AEO-only audit workflow. The dual template folds into the existing growth-audit cron.
- **NG2.** Retroactively re-scoring past audits. 04-19 stays as-is; 04-21 is the verification baseline.
- **NG3.** Modifying `seo-aeo-analyst.md` — it owns technical SEO, not content-level AEO scorecards.
- **NG4.** Adding dashboards, trend charts, or alerting. Two tables in one markdown file suffices.
- **NG5.** Moving the runbook to `knowledge-base/engineering/ops/runbooks/`. Worth a separate cleanup.

## Functional Requirements

- **FR1.** The growth-strategist agent, when invoked with an AEO audit prompt, MUST produce both the SAP scorecard and the 8-component AEO diagnostic table in the same audit report.
- **FR2.** The SAP scorecard MUST use weights Structure=40, Authority=35, Presence=25 and the grading scale defined in the 2026-04-21 audit (A ≥90, B 80-89, B+ 75-79, C 60-74, D <60).
- **FR3.** The 8-component AEO diagnostic MUST use weights FAQ=20, Answer density=15, Statistics=15, Source citations=15, Conversational=10, Entity clarity=10, Authority/E-E-A-T=10, Citation-friendly=5.
- **FR4.** `scheduled-growth-audit.yml` Step 2 prompt MUST reference or inline the pinned template so cron runs produce deterministic output.
- **FR5.** The re-audit runbook Phase 2 MUST document how to extract Presence score from the pinned SAP table.
- **FR6.** #2615 MUST be closed by the merge commit, referencing the 04-21 audit as verification.

## Technical Requirements

- **TR1.** Template pinning MUST live in both `.github/workflows/scheduled-growth-audit.yml` (inline prompt) AND `plugins/soleur/agents/marketing/growth-strategist.md` (agent spec). Workflow-only pinning would leave ad-hoc `/soleur:growth aeo` invocations unpinned; agent-only pinning repeats the 04-19 failure mode (agent freelanced despite SAP mention).
- **TR2.** The PR body MUST include `Closes #2679` and `Closes #2615`.
- **TR3.** No code changes to `growth-strategist.md` Execution section or `seo-aeo-analyst.md` — scope is limited to the GEO/AEO Content Audit section's scorecard specification.
- **TR4.** The pinned template MUST preserve backward compatibility: the SAP table column names (Dimension, Weight, Score, Weighted, Notes) must match the 04-21 audit so historical SAP audits remain comparable.

## Acceptance Criteria

1. `gh issue view 2679 --json state` returns `CLOSED`.
2. `gh issue view 2615 --json state` returns `CLOSED`.
3. `scheduled-growth-audit.yml` Step 2 prompt contains the SAP and AEO scorecard templates (or a reference to the agent doc section that does).
4. `growth-strategist.md` GEO/AEO Content Audit section contains both scorecard templates with weights and grading scale.
5. The re-audit runbook Phase 2 extracts Presence from the SAP table anchor.
6. A manual `gh workflow run scheduled-growth-audit.yml` trigger (post-merge verification) produces an audit file with both tables.

## Out of Scope (Tracked Separately)

- Off-site Presence work: #2599, #2600, #2601, #2602, #2603, #2604 remain open and will further lift the Presence score.
- Moving runbook to engineering/ops/runbooks/ directory.
- Adding rubric-comparison or trend-line tooling.
