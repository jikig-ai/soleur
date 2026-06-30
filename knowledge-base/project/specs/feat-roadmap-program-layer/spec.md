---
feature: feat-roadmap-program-layer
date: 2026-06-30
lane: cross-domain
brand_survival_threshold: low
requires_cpo_signoff: false
type: feature
classification: workflow-skill-extension
branch: feat-roadmap-program-layer
draft_pr: 5753
brainstorm: knowledge-base/project/brainstorms/2026-06-30-roadmap-program-layer-brainstorm.md
plan: knowledge-base/project/plans/2026-06-30-feat-roadmap-program-layer-plan.md
source_inspiration: https://github.com/mattmccray/plan
---

# Spec: Roadmap Program Layer (report-only)

Two **read-only** sub-commands on `/soleur:product-roadmap`, adapting the "document is the state"
idea from [mattmccray/plan](https://github.com/mattmccray/plan). Re-scoped twice during planning
(see plan): consolidate-not-duplicate, then drop the write path → report-only (deepen-plan).

## Problem Statement

`roadmap.md` drifts from live GitHub milestone/issue state; the reconciliation logic is scattered
(the Inngest `cron-roadmap-review.ts` prompt, brainstorm Phase 0.25, a manual runbook). There's no
fast, codified, **read-only** way to ask "is the roadmap in sync, and what's the next action?"
without firing the 50-minute cloud cron.

## Goals
- **G1.** A shared **read-only** `roadmap-reconcile` module that reports roadmap↔GitHub drift on demand.
- **G2.** `product-roadmap next` — advisory next-action reporter (codeable → `/soleur:go #N`; else named operator action).
- **G3.** Consolidate brainstorm Phase 0.25 onto the shared module (DRY).

## Non-Goals
- **NG1.** No new top-level skills (sub-commands on product-roadmap).
- **NG2.** `next` never invokes `/soleur:one-shot` or any build.
- **NG3.** **No write path.** `validate` does not edit `roadmap.md`; the existing cron remains sole writer (via reviewed fix PRs). [Dropped `--apply` at deepen-plan — all 5 write-safety holes + ADR-070 + the bounded-region migration dissolved with it.]
- **NG4.** No new cron (the Inngest cron already runs weekly; ADR-033 Inngest > GHA).

## Functional Requirements
- **FR1.** `product-roadmap validate` reads `roadmap.md` + queries GitHub milestones (open AND closed) + issues, and prints verdicts `STALE_STATUS` / `MISSING_ISSUE` / `EMPTY_MILESTONE`. **Zero file writes.**
- **FR2.** When drift is found, the report ends with a remediation pointer: trigger the roadmap-review cron (`/soleur:trigger-cron cron/roadmap-review.manual-trigger`), which opens a reviewed PR. Writing stays with the cron.
- **FR3.** `product-roadmap next` reports current phase + exit-criteria status + the single next action; codeable → paste-ready `/soleur:go #N` (scrub closed `#N`); non-codeable → named operator action; explicit "no actionable next item" when none. Read-only.
- **FR4.** Brainstorm Phase 0.25 calls `roadmap-reconcile.sh` instead of its ad-hoc inline reconciliation.

## Technical Requirements
- **TR1.** Phase-row→milestone resolution via an explicit inline map (not title-guess). Milestone↔phase is **not 1:1** (Phase 4 milestone holds internal-tooling/Marketing-Gate issues not on roadmap rows); allowlist non-row members instead of false-flagging (spec-flow S2/S5).
- **TR2.** API-first: query both open and closed milestone states. Best-effort `roadmap.md` parse (read-only — a misparse prints a wrong report line, never corrupts the file).
- **TR3.** Shared module under `plugins/soleur/skills/product-roadmap/scripts/`; brainstorm Phase 0.25 and both sub-commands consume it.
- **TR4.** Milestone reads use `gh api`. No new test framework — existing `bun test`. SKILL.md `description:` stays within the ~1800-word cap (verify `bun test plugins/soleur/test/components.test.ts`).
- **TR5.** New-skills/user-facing governance (`hr-new-skills-agents-or-user-facing`): `semver:minor`, `## Changelog`, README counts, third-person description. (No CPO sign-off — threshold low, read-only.)

## Acceptance Criteria
- `validate` prints a drift report with zero file writes (git-clean post-run); exit 0 clean / non-zero on drift.
- Phase-row→milestone map handles row-label ≠ milestone-title; non-row milestone members allowlisted (only true zero-issue milestones → `EMPTY_MILESTONE`).
- Drift report includes the cron-trigger remediation pointer.
- `next` prints current phase + correct next action (a `/soleur:go #N` line or named operator action), with deterministic tie-break and an explicit empty-state; zero writes.
- Brainstorm Phase 0.25 calls the shared module; `bun test …/components.test.ts` passes; README + changelog updated.

## Sequencing
Build the shared read module first, then `validate` (thin CLI), then wire brainstorm Phase 0.25, then `next`, then governance.
