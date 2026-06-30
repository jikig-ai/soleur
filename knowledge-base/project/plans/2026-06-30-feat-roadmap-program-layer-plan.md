---
date: 2026-06-30
feature: feat-roadmap-program-layer
issue: 5755
type: feature
classification: workflow-skill-extension
lane: cross-domain
brand_survival_threshold: low
branch: feat-roadmap-program-layer
worktree: .worktrees/feat-roadmap-program-layer
draft_pr: 5753
brainstorm: knowledge-base/project/brainstorms/2026-06-30-roadmap-program-layer-brainstorm.md
spec: knowledge-base/project/specs/feat-roadmap-program-layer/spec.md
source_inspiration: https://github.com/mattmccray/plan
---

# Plan: Roadmap Program Layer — `product-roadmap validate` (report-only) + `next`

✨ Two read-only sub-commands on the existing `/soleur:product-roadmap` skill, adapting the
"document is the state" idea from [mattmccray/plan](https://github.com/mattmccray/plan).

## Enhancement Summary (deepen-plan, 2026-06-30)

Three independent reviewers (data-integrity-guardian, architecture-strategist, code-simplicity-reviewer)
**converged**: the `validate --apply` write path was all-risk, no capability the existing cron
doesn't already provide. **Decision (operator-approved): drop `--apply`; `validate` is dry-run
report-only.** The existing Inngest `cron-roadmap-review.ts` remains the sole writer (via
human-reviewed fix PRs). This dissolved: 5 data-integrity holes (fused count/status cell, no atomic
write, no open-PR conflict guard, unenforced single-writer, no idempotency), the bounded-region
roadmap.md migration, **ADR-070**, and the brand-survival surface (threshold single-user-incident →
**low**; CPO sign-off no longer required). Honest architecture: **`validate` reads/reports; the cron
writes-via-PR.** Net scope ~60% smaller than the pre-deepen plan.

## Overview

**Problem.** `roadmap.md` drifts from live GitHub milestone/issue state, and the reconciliation
logic is scattered (cron prompt, brainstorm Phase 0.25, a manual runbook). There's no fast,
codified, **read-only** way for the operator (or a skill) to ask "is the roadmap currently in sync,
and what's the next action?" without firing the 50-minute cloud cron.

**Solution.** A shared **read-only** `roadmap-reconcile` module + two sub-commands:
`product-roadmap validate` (dry-run drift report) and `product-roadmap next` (advisory next-action).
Neither writes to `roadmap.md`. When `validate` reports drift, it points the operator at the
existing cron (manual-trigger) to *fix* it via a reviewed PR — preserving the cron as sole writer.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "No automation; wire a new `/soleur:schedule` GHA cron (FR7)" | `cron-roadmap-review.ts` is a live Tier-1 **Inngest** cron (Mon 09:00 UTC + manual trigger) already emitting `MISSING_ISSUE`/`EMPTY_MILESTONE`/`STALE_STATUS` + a fix PR | **FR7 dropped.** No new cron (ADR-033: Inngest > GHA). |
| "`validate` auto-fixes count drift (`--apply`)" | The cron already fixes drift via reviewed PRs; an in-place mechanical writer duplicates it and adds the only real risk | **`--apply` dropped** (deepen-plan). `validate` is report-only; the cron stays sole writer. |
| Milestone↔phase is 1:1 | Not 1:1 — Phase 4 milestone holds internal-tooling/Marketing-Gate issues not on roadmap rows | Inline phase-row→milestone map + non-row-member allowlist in the read module (no ADR needed for a reporter). |

## Implementation Phases

### Phase 0 — Shared read-only reconcile module
- Create `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh` (bash; existing `bun test` harness; no new framework):
  - Parse `roadmap.md`'s `Current State` table best-effort (read-only — a misparse only prints a wrong report line the operator eyeballs; **no migration, no bounded-region markers, no ADR** — the architecture reviewer's marker-duplication / cron-corruption / single-writer hazards all vanish without a write path).
  - Fetch milestones **open AND closed** (`gh api '…/milestones?state=all&per_page=100'`) + issues.
  - Emit verdicts `STALE_STATUS` / `MISSING_ISSUE` / `EMPTY_MILESTONE` (reuse the cron's vocabulary).
  - Inline **phase-row→milestone map** (not title-guess) + **allowlist** milestone members absent from roadmap rows so internal-tooling issues aren't false-flagged (spec-flow S2/S5 — still relevant for report accuracy).
  - **Writes nothing.** Exit 0 when clean; non-zero + verdict list on drift.

### Phase 1 — `product-roadmap validate` sub-command (report-only)
- Extend `product-roadmap/SKILL.md` with a `validate` sub-command (community/growth/seo-aeo pattern) = a thin CLI over `roadmap-reconcile.sh`. Prints the drift report. **No `--apply`, no write path, no mode matrix.**
- When drift is found, the report ends with: "To fix: trigger the roadmap-review cron (`/soleur:trigger-cron cron/roadmap-review.manual-trigger`), which opens a reviewed PR." (read-only stays read-only; writing stays with the cron).

### Phase 2 — Consolidate brainstorm Phase 0.25
- Replace brainstorm Phase 0.25's ad-hoc inline milestone-count reconciliation with a `roadmap-reconcile.sh` call (the genuine dedup win — two read consumers now share one parser).

### Phase 3 — `product-roadmap next` sub-command (advisory, read-only)
- Reports current phase (first non-Complete row) + exit-criteria status + the single next action.
- **Classification (spec-flow S6):** codeable vs operator-action by **label**; deterministic tie-break (lowest issue #); explicit "no actionable next item" output (never empty). Codeable → paste-ready `/soleur:go #N` (scrub closed `#N`). **Zero writes; never invokes one-shot.**

### Phase 4 — Governance (lite)
- Extend product-roadmap's `description:` minimally (≤ measured headroom; verify `bun test plugins/soleur/test/components.test.ts`); `## Changelog` entry; README + plugin.json component counts; `semver:minor`. **No ADR, no CPO sign-off** (threshold = low; read-only).

## Files to Create
- `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh`
- `plugins/soleur/test/.../roadmap-reconcile.test.ts` (path per the runner's discovery globs)

## Files to Edit
- `plugins/soleur/skills/product-roadmap/SKILL.md` — add `validate` + `next` sub-commands; extend `description:` (budget-gated)
- `plugins/soleur/skills/brainstorm/SKILL.md` — Phase 0.25 calls the shared module
- `plugins/soleur/README.md` + `plugins/soleur/.claude-plugin/plugin.json` — component counts/desc

*(No edit to `knowledge-base/product/roadmap.md` — read-only; no migration. No ADR file. The Inngest cron is untouched — with no markers there's nothing for it to corrupt, so the architecture reviewer's in-PR cron-guard is moot.)*

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** `product-roadmap validate` on current `roadmap.md` prints a drift report (verdicts `STALE_STATUS`/`MISSING_ISSUE`/`EMPTY_MILESTONE`) and makes **zero file writes** (git status clean after run). Exit 0 when clean, non-zero on drift.
- **AC2 (S2).** Phase-row→milestone resolution uses an explicit inline map; test with a fixture where row label ≠ milestone title.
- **AC3 (S5).** Milestone members absent from roadmap rows are allowlisted (not flagged); only true zero-issue milestones emit `EMPTY_MILESTONE`.
- **AC4.** Drift report ends with the cron-trigger remediation pointer (writing stays with the cron).
- **AC5 (S6).** `next` defines the label-based codeable signal, deterministic tie-break, and an explicit "no actionable next item" output (never empty). Codeable item → valid `/soleur:go #N`; zero writes.
- **AC6.** Brainstorm Phase 0.25 calls `roadmap-reconcile.sh` (grep shows the inline reconciliation replaced).
- **AC7.** `bun test plugins/soleur/test/components.test.ts` passes (description budget); `## Changelog` + README counts updated.

### Post-merge (operator)
- *(none — read-only feature, no infra.)*

## Domain Review
**Domains relevant:** Product, Engineering (carry-forward). CTO: read-only module, no write contract needed. CPO: advisory `next` + report-only `validate` fit the non-technical operator. **Product/UX Gate:** none (no UI surface).

## User-Brand Impact
- **If this lands broken, the user experiences:** `validate`/`next` print an inaccurate drift report or wrong next-action — a *display* error the operator eyeballs; nothing is written, nothing breaks.
- **If this leaks:** n/a — reads public-project metadata (`gh` issues/milestones) + a committed roadmap doc; no PII, no secrets, no writes.
- **Brand-survival threshold:** **low** — read-only; no write path to `roadmap.md`; the cron (unchanged) remains the only writer. Files touched are SKILL.md / bash / README (no sensitive-path match).

## Observability
```yaml
liveness_signal:   { what: "validate/next are operator-invoked (on-demand) + brainstorm Phase 0.25", cadence: on-demand, alert_target: "n/a (no server/cron surface this PR)", configured_in: "SKILL.md" }
error_reporting:   { destination: "operator session stdout (non-zero exit, explicit verdict list)", fail_loud: true }
failure_modes:
  - { mode: "milestone 404/rename", detection: "reconcile.sh resolves nothing for the row", alert_route: "EMPTY_MILESTONE/STALE verdict to stdout (read-only — no write to mis-stamp)" }
  - { mode: "roadmap.md misparse", detection: "n/a (best-effort read)", alert_route: "operator eyeballs the printed report; no write occurs" }
  - { mode: "gh API/auth failure", detection: "non-zero gh exit", alert_route: "fail loud, non-zero exit, explicit message" }
logs:              { where: "operator terminal / brainstorm session transcript", retention: "session" }
discoverability_test: { command: "bash plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh", expected_output: "drift report; exit 0 when clean (NO ssh)" }
```

## Architecture Decision (ADR/C4)
**No ADR.** A read-only reporter makes no architectural decision — the deepen-plan removal of the write path dissolved the machine-parse contract / single-writer boundary that ADR-070 would have governed. The non-1:1 phase→milestone reconciliation is inline read-logic, not a cross-cutting decision. **C4:** no impact (enumerated against all three `.c4` files: Founder `model.c4:8`, GitHub `:196`, Inngest cron layer `:155` all already modeled; `roadmap.md` is a knowledge-base artifact, not a runtime container).

## Infrastructure (IaC)
None. Read-only; no server, secret, vendor, cron, or persistent process. Uses existing `gh` auth.

## Open Code-Review Overlap
None (checked at plan time; re-verify at work Phase 0).

## Follow-ups (optional, low priority)
- The cron *could* later call `/soleur:product-roadmap validate` for its read/report half (keeping its own PR-write half) to fully unify the parser — but it works fine as-is and touches a live Tier-1 cron + the ADR-054 exemption, so it's optional, not required by this feature.

## Risks & Sharp Edges
- `roadmap.md` count strings are embedded in prose cells; the **read** parser must be tolerant (best-effort) — a misparse is a wrong report line, not a corruption (no write path).
- Extending product-roadmap's `description:` risks the ~1800-word cap — measure headroom first (`cq-skill-description-budget-headroom`).
- Keep `validate`/`next` strictly read-only — any future urge to "just fix it inline" must route through the cron's reviewed-PR path (that separation is the whole point of the deepen-plan re-scope).

## Test Strategy
`bun test` (existing harness; confirm via `package.json` scripts.test; no new framework). Synthesized golden-file fixtures for roadmap.md + mocked `gh` output (no live API, no LLM in the assert path). Assert **zero file writes** (git-clean post-run) as a first-class test.
