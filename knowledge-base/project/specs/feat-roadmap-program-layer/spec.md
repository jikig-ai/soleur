---
feature: feat-roadmap-program-layer
date: 2026-06-30
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
classification: workflow-skill-extension
branch: feat-roadmap-program-layer
draft_pr: 5753
brainstorm: knowledge-base/project/brainstorms/2026-06-30-roadmap-program-layer-brainstorm.md
source_inspiration: https://github.com/mattmccray/plan
---

# Spec: Roadmap Program Layer

Two sub-commands added to the existing `/soleur:product-roadmap` skill, adapting the durable
"document is the state" ideas from [mattmccray/plan](https://github.com/mattmccray/plan).

## Problem Statement

Soleur's `knowledge-base/product/roadmap.md` is the founder's program-level source of truth, but
keeping its phase statuses and open/closed counts aligned with live GitHub milestone/issue state is
a **manual** CPO chore (documented in `2026-03-24-monthly-roadmap-review-process.md`; the 2026-06-08
footer audit caught a real 4-issue count drift). No automation performs it. Separately, there is no
program-altitude "where am I / what's the next action" reporter — `/soleur:go` routes a *known*
task but does not read the roadmap to surface the *next* one, especially when that next action is
non-codeable (recruitment, interviews).

## Goals

- **G1.** Automate roadmap↔GitHub reconciliation as `product-roadmap validate`, replacing the manual
  weekly/monthly CPO sync, runnable on a `/soleur:schedule` weekly cron.
- **G2.** Provide an advisory `product-roadmap next` that reports the current phase and the single
  next action, routing codeable work to `/soleur:go #N` and naming non-codeable operator actions.
- **G3.** Extract a shared roadmap parse module so the existing workshop, `validate`, and `next`
  read `roadmap.md` through one parser (single-writer boundary).
- **G4.** Make every `roadmap.md` write safe: dry-run default, counts-only auto-fix, gated status /
  phase-complete writes, bounded write region.

## Non-Goals

- **NG1.** No new top-level skills (fold into `product-roadmap` per brainstorm D1).
- **NG2.** `next` does **not** auto-invoke `/soleur:one-shot` or any build (D6).
- **NG3.** No third `fix` verb — `validate --apply` covers mechanical fixes.
- **NG4.** No adoption of mattmccray/plan's "engine seam" or R6 "invariants" model.
- **NG5.** Auto-fix never rewrites the footer audit log, free-text status prose, or feature-row
  tables — only the bounded count region.

## Functional Requirements

- **FR1.** `product-roadmap validate` reads `roadmap.md` + queries GitHub milestones (**both open
  and closed states**) and issue states, then emits per-dimension verdicts reusing the existing
  vocabulary: `STALE_STATUS`, `MISSING_ISSUE`, `EMPTY_MILESTONE`.
- **FR2.** `validate` is **dry-run by default** (reports proposed changes only). `--apply` persists
  **mechanical count drift only** into the bounded `Current State` region.
- **FR3.** Any **status-enum** change or **phase-complete** stamp is an explicit approval gate in
  interactive mode; in headless/cron mode these are reported but **not** auto-applied (only counts
  are), and surfaced as a created issue/PR for human review.
- **FR4.** `validate` enforces **bidirectional** integrity (D9): flag roadmap features with no
  linked issue, and milestones absent from the roadmap.
- **FR5.** `product-roadmap next` reports: current phase, its exit-criteria status, and the single
  next actionable item. If the item is a codeable issue, output a ready-to-paste `/soleur:go #N`
  (scrubbing closed `#N` per go.md sharp edge). If non-codeable, name the operator action plainly.
- **FR6.** `next` is read-only — it makes **no** writes to `roadmap.md` and invokes no build skill.
- **FR7.** A `/soleur:schedule` weekly cron runs `product-roadmap validate` (counts-only auto-fix),
  disclosing API spend per `hr-autonomous-loop-skill-api-budget-disclosure`.

## Technical Requirements

- **TR1.** **Parse anchor = the `Current State` table** (`Dimension | Status` schema, "X open, Y
  closed" strings) — never the per-phase feature tables (inconsistent `Issue`/`Source`/`Trigger`
  columns). Wrap the writable region in `<!-- roadmap-state:begin -->` / `<!-- roadmap-state:end -->`
  delimiters (D3, D5).
- **TR2.** **Milestone↔phase is not 1:1.** Reconcile milestone counts against the Current-State
  milestone strings only, not feature-row tallies (roadmap.md:78 — Phase 4 milestone holds
  internal-tooling / Marketing-Gate issues). (D4)
- **TR3.** **API-first, file-second:** trust the GitHub API on conflict; **re-read** `open_issues` /
  `closed_issues` immediately before any write; stamp phase-complete only if `open==0 AND closed>0`
  (a 404/renamed milestone also reads 0 — never stamp on that). (D8)
- **TR4.** Shared parse module under `plugins/soleur/skills/product-roadmap/scripts/`; the existing
  Phase 2 workshop is refactored to call it (sole-writer boundary). (G3)
- **TR5.** Milestone assignment uses the REST API integer form (`gh api .../issues/N -X PATCH -f
  milestone=N`), not `--milestone <title>` (`2026-03-24` learning).
- **TR6.** Cron correctness: post-fire verification as a **real Actions step outside**
  `claude-code-action` (in-prompt `exit 1` is swallowed); `Ref #N` not `Closes #N`; no
  `show_full_output`; **grep-verify** any `.yml` edit (PreToolUse hooks can silently block writes).
  (`2026-05-07`, `2026-03-26` learnings)
- **TR7.** SKILL.md description stays within the cumulative ~1800-word cap; verify via
  `bun test plugins/soleur/test/components.test.ts`. Sub-commands add minimal description words
  (extend the existing `product-roadmap` description, do not add new top-level entries).
- **TR8.** Honor new-skills/user-facing governance (`hr-new-skills-agents-or-user-facing`):
  `semver:minor` bump path, `## Changelog`, README component counts, third-person description.

## Architecture Decision (plan deliverable)

Per D10 / `wg-architecture-decision-is-a-plan-deliverable`, the plan must produce an ADR capturing:
the `roadmap.md` machine-parse contract (Current-State region + HTML-comment delimiters), the
single-writer boundary (`validate --apply` is the sole mechanical-count writer; the workshop calls
the shared module), and the milestone↔phase non-1:1 reconciliation rule.

## Acceptance Criteria

- `product-roadmap validate` (dry-run) on the current `roadmap.md` reproduces the kind of finding in
  the 2026-06-08 footer audit (count drift detected, `0 MISSING_ISSUE` / `0 EMPTY_MILESTONE` when
  clean) without writing.
- `validate --apply` corrects only count drift inside the bounded region; status/phase-complete
  changes are gated (interactive) or report-only (headless), leaving a reviewable artifact.
- `product-roadmap next` prints the current phase and a correct next action: a `/soleur:go #N` line
  for a codeable open issue, or a named operator action for a non-codeable one — with zero file
  writes.
- A weekly scheduled workflow invokes `product-roadmap validate`, verified by a real post-fire
  Actions step, with API-spend disclosure.
- ADR committed; `bun test plugins/soleur/test/components.test.ts` passes (word budget); README +
  changelog updated.

## Sequencing

**validate first, then next.** `next` reads `roadmap.md` as source of truth; if counts are stale it
would surface the wrong phase, so `validate` (and its freshness guard) must land first. `next`
should warn (or suggest running `validate`) when `last_reviewed` is stale.
