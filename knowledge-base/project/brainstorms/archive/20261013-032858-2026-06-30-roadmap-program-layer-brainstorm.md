---
date: 2026-06-30
topic: roadmap-program-layer
feature: feat-roadmap-program-layer
type: feature
classification: workflow-skill-extension
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-roadmap-program-layer
draft_pr: 5753
source_inspiration: https://github.com/mattmccray/plan
---

# Brainstorm: Roadmap Program Layer (`product-roadmap validate` + `next`)

## What We're Building

Two new **sub-commands of the existing `/soleur:product-roadmap` skill** (not new top-level
skills), adapting the durable ideas from the external tool [mattmccray/plan](https://github.com/mattmccray/plan)
— a coarse, resumable program/epic layer whose philosophy is *"the document is the state."*

1. **`product-roadmap validate`** — a drift-check that reconciles `knowledge-base/product/roadmap.md`
   against live GitHub milestone/issue state. Reuses the verdict vocabulary already in the
   roadmap footer (`STALE_STATUS` / `MISSING_ISSUE` / `EMPTY_MILESTONE`). **Dry-run by default**;
   `--apply` auto-fixes **mechanical count drift only**; status-enum and phase-complete writes are
   always approval-gated. Wired to a weekly cron via `/soleur:schedule`, automating the
   currently-manual monthly/weekly CPO reconciliation
   (`knowledge-base/project/learnings/2026-03-24-monthly-roadmap-review-process.md`).

2. **`product-roadmap next`** — an **advisory read-only** program-altitude reporter. Reads
   `roadmap.md` + live milestones → reports the current phase and the single next action. If that
   action is a codeable feature, it routes to `/soleur:go #N`; if it's a non-codeable operator
   action (e.g. `#1439 recruit founders`, `#1440 problem interviews`), it names that action
   directly. **Never auto-invokes a build.**

A shared roadmap **parse module** (script under `product-roadmap/scripts/`) is extracted so the
skill's existing workshop, `validate`, and `next` all read the file through one parser — preventing
a three-writer divergence on `roadmap.md`.

## Why This Approach

The original ask was "two new top-level skills, with `next` driving `/soleur:one-shot`." The
CPO + CTO + research triad converged on a revised shape, accepted by the operator:

- **Fold, don't proliferate.** Soleur has ~90 skills and a near-full ~1800-word cumulative
  skill-description budget. Both capabilities are *about the roadmap* and share context, so they
  belong as sub-commands beside the existing `community`/`growth`/`seo-aeo` pattern — one roadmap
  surface, no new `/help` entries.
- **`next` advisory, not a driver.** Phase 4's actual open work is recruitment / interviews /
  onboarding — **not codeable**. A driver that auto-handed the "next" issue to `/soleur:one-shot`
  would point a non-technical founder at engineering when the real blocker is outreach. AGENTS.md
  also cautions against `/goal`-style drivers layered on `one-shot`. Advisory-read serves the
  target user better *and* is lower-risk.
- **`validate` is a real, unautomated gap.** The reconciliation is documented and done by hand
  (the 2026-06-08 footer audit caught a 4-issue count drift); no GitHub Actions workflow performs
  it. Codifying it + a cron directly serves "automate everything, never defer operator actions."

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Fold as `product-roadmap` **sub-commands**, not new top-level skills | Skill-proliferation + word-budget cap (CPO); cron can call `/soleur:product-roadmap validate` |
| D2 | `validate` **dry-run default**; `--apply` writes; auto-fix **counts only**; status/phase-complete **gated** | Data-integrity write-boundary (CTO + write-boundary-sentinel learnings) |
| D3 | Parse-anchor on the **`Current State` table**, not per-phase feature tables | Feature tables have inconsistent column schemas (`Issue`/`Source`/`Trigger`); `Current State` is a stable `Dimension \| Status` schema with machine-readable "X open, Y closed" strings (CTO) |
| D4 | Reconcile **milestone counts ⇄ Current-State strings only**, never against feature-row tallies | Milestone↔phase is **not 1:1** — the Phase 4 milestone also holds internal-tooling / Marketing-Gate issues not on roadmap rows (CTO, roadmap.md:78) |
| D5 | Wrap the writable region in HTML-comment delimiters (`<!-- roadmap-state:begin/end -->`) | Bounded, safe write region for the auto-fixer (CTO) |
| D6 | `next` is **advisory read-only**; routes codeable work to `/soleur:go #N`, names non-codeable operator actions | Target-user fit; avoids `/goal`-driver anti-pattern (CPO) |
| D7 | Reuse existing footer verdicts `STALE_STATUS` / `MISSING_ISSUE` / `EMPTY_MILESTONE` | Continuity with the manual practice; don't invent new vocabulary (verified in roadmap.md footer) |
| D8 | API-first, file-second; query **both** open and closed milestone states; re-read counts immediately before any write | Stale-snapshot guard; stamp phase-complete only if `open==0 AND closed>0` (CTO + cpo-stale-milestone-data learning) |
| D9 | Bidirectional integrity: every roadmap feature links an issue **AND** every milestone appears in the roadmap | One-way rules allow drift (`2026-04-03-milestone-roadmap-integrity-audit.md`) |
| D10 | Capture an **ADR** for the roadmap.md machine-parse contract + single-writer boundary | Architecture decision is a plan deliverable (CTO; `wg-architecture-decision-is-a-plan-deliverable`) |
| D11 | Cron via `/soleur:schedule`; post-fire verification as a real Actions step (not in-prompt); `Ref #N` not `Closes #N`; no `show_full_output`; grep-verify `.yml` edits | Scheduled-workflow gotchas (`2026-05-07-claude-code-action-boundaries`, `2026-03-26-milestone-enforcement-workflow-edits`) |

## Open Questions

1. **Resumable state for `next`** — read-only `next` derives everything from `roadmap.md` + live
   milestones each run ("document is the state"), so it likely needs **no** separate state file.
   Confirm at plan time vs. the learnings suggestion of `.github/roadmap-state.json` (which was
   premised on the driver variant, now demoted).
2. **`validate` ⇄ `product-roadmap` writer boundary** — `validate` should be the **sole**
   mechanical-count writer; the existing Phase 2 workshop should call the shared module rather than
   re-implement count-sync. Decide in the ADR (D10).
3. **Cron model spend disclosure** — weekly `validate` cron must disclose API spend
   (`hr-autonomous-loop-skill-api-budget-disclosure`). Size at plan time.
4. **Bonus R5 "divergences" convention** — adopt an inline signed-off deviation log per roadmap
   phase? Low priority; defer unless cheap to fold into the ADR.

## User-Brand Impact

- **Artifact:** the `/soleur:product-roadmap validate` auto-fixer's write path into `roadmap.md`.
- **Vector:** a mis-parse or stale-snapshot read causes the auto-fixer to silently corrupt roadmap
  status/counts (e.g. stamp a phase complete on a 404'd/renamed milestone), so the founder steers
  the company off a falsified source of truth.
- **Threshold:** single-user incident.
- Mitigations are first-class in the design: dry-run default, counts-only auto-fix, gated status
  writes, bounded write region (D5), `open==0 AND closed>0` guard (D8).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(load-bearing: Product + Engineering; others not relevant to internal roadmap tooling)

### Product (CPO)

**Summary:** `validate` is a justified, documented, recurring need a non-technical founder cannot do
by hand. `next` should be advisory-only — Phase 4's open work is recruitment/interviews, not code,
so an auto-driver would mis-direct. Fold both as `product-roadmap` sub-commands to avoid
proliferation and the word-budget cap.

### Engineering (CTO)

**Summary:** Not a duplicate verb, but a second writer to `roadmap.md` — needs a shared parse/write
module and `validate` as sole count-writer. Anchor on the `Current State` table (feature tables
have inconsistent schemas); milestone↔phase is not 1:1. HIGH data-integrity risk → dry-run default,
counts-only auto-fix, gated phase-complete, re-read before write. `next` must terminate into
`/soleur:go`, not bypass to `one-shot`. Capture an ADR for the parse contract. Build validate first.

## Out of Scope

- mattmccray/plan's "engine seam / composable constellation" philosophy — Soleur is intentionally
  integrated, not opt-in single-purpose tools.
- "Invariants as DoD overlay" (R6) — already over-served by AGENTS.md hard rules + exit criteria.
- `next` as an autonomous driver that builds via `one-shot` (explicitly demoted per D6).
- A separate `fix` sub-command — `validate --apply` covers mechanical fixes (avoid a 3rd verb).
