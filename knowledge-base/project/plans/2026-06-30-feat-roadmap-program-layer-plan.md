---
date: 2026-06-30
feature: feat-roadmap-program-layer
issue: 5755
type: feature
classification: workflow-skill-extension
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-roadmap-program-layer
worktree: .worktrees/feat-roadmap-program-layer
draft_pr: 5753
brainstorm: knowledge-base/project/brainstorms/2026-06-30-roadmap-program-layer-brainstorm.md
spec: knowledge-base/project/specs/feat-roadmap-program-layer/spec.md
source_inspiration: https://github.com/mattmccray/plan
---

# Plan: Roadmap Program Layer — `product-roadmap validate` + `next` (re-scoped: consolidate, don't duplicate)

✨ Two sub-commands on the existing `/soleur:product-roadmap` skill, adapting the
"document is the state" idea from [mattmccray/plan](https://github.com/mattmccray/plan).

## Overview

**Problem.** `knowledge-base/product/roadmap.md` drifts from live GitHub milestone/issue
state. The reconciliation logic exists but is **scattered and non-deterministic**: it lives as
a 48-line verbatim prompt embedded in an Inngest cron, as a lightweight inline check in
brainstorm Phase 0.25, and as a manual learning runbook — three drifting copies, none with a
write-safety contract.

**Solution (re-scoped).** Extract the reconciliation into ONE codified, deterministic
`product-roadmap validate` skill + shared parse module that the operator can run on-demand and
that brainstorm Phase 0.25 calls — adding the bounded-region / dry-run / counts-only write
contract the improvised paths lack. Plus a net-new advisory `product-roadmap next` reporter.

## Research Reconciliation — Spec vs. Codebase

The original spec premise ("automate the manual monthly process; no cron exists") was **stale**.
Premise validation at plan time (reading ADR-054 → `cron-roadmap-review.ts`) corrected it:

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "No automation performs the reconciliation; wire a new `/soleur:schedule` GHA cron (FR7)" | **`apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`** is a live Tier-1 **Inngest** cron (Mon 09:00 UTC + manual trigger `cron/roadmap-review.manual-trigger`). Its prompt already emits `MISSING_ISSUE`/`EMPTY_MILESTONE`/`STALE_STATUS` + bidirectional gate + fix PR. | **FR7 dropped.** No new cron. The cron is the consolidation *target* (follow-up), not a thing to duplicate. Contradicts ADR-033 (Inngest > GHA) otherwise. |
| "`validate` is net-new automation" | ~80% exists as the cron's embedded prompt; brainstorm Phase 0.25 also does a lite count-sync | `validate` is re-scoped to **extraction + determinism + on-demand surface**, not greenfield automation |
| Roadmap `Current State` table is machine-parseable | Count strings are **embedded in free-text prose** cells (`"32 open, 127 closed (milestone). Marketing Gate complete…"`, roadmap.md:78); sibling rows are non-count (`0 of 5`, `Beta users | 0`) | One-time migration: wrap a clean count-only region in `<!-- roadmap-state:begin/end -->`; parser/writer touch only that region (spec-flow S3) |
| Milestone↔phase is 1:1 | **Not 1:1** — Phase 4 milestone holds internal-tooling + Marketing-Gate issues not on roadmap rows (roadmap.md:78) | ADR-070 defines an explicit phase-row→milestone map + customer-row completion semantics (spec-flow S2) |

## Implementation Phases (validate-first)

### Phase 0 — Shared parse/reconcile module + roadmap.md machine-parse migration
- Create `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh` (bash, matches the
  plugin's script convention; no new test framework — use the existing `bun test` harness):
  - Parse the `<!-- roadmap-state:begin -->…<!-- roadmap-state:end -->` region only.
  - Fetch milestones **open AND closed** (`gh api '…/milestones?state=all&per_page=100'`) + issues.
  - Emit verdicts `STALE_STATUS` / `MISSING_ISSUE` / `EMPTY_MILESTONE` (reuse the cron's vocabulary verbatim).
  - **Guards (spec-flow):** refuse a count write when the milestone is 404/renamed OR resolves `0/0`
    over a nonzero file value (S1); allowlist milestone members absent from roadmap rows instead of
    false-flagging them (S5); phase-row→milestone resolution via an explicit map, not title-guess (S2).
- One-time migration of `knowledge-base/product/roadmap.md`: insert the bounded region around a
  clean count-only sub-table; leave all prose/non-count rows (`0 of 5`, Beta users) outside it.

### Phase 1 — `product-roadmap validate` sub-command
- Extend `plugins/soleur/skills/product-roadmap/SKILL.md` with a `validate` sub-command (the
  `community`/`growth`/`seo-aeo` sub-command pattern).
- **Mode matrix (spec-flow S-matrix):**
  | mode | counts | status-enum | phase-complete |
  |---|---|---|---|
  | dry-run (default) | report | report | report |
  | `--apply` interactive | auto-write (bounded region) | **gate** (AskUserQuestion) | **gate** |
  | `--apply` headless/cron | auto-write | report + file issue | report + file issue |
- **Write guards:** bounded region must exist & be uniquely paired — refuse (non-zero exit) on 0/>1/unpaired markers, never write outside it (S3). Re-read counts immediately before a gated write; **abort/re-prompt if the re-read ≠ the value shown in the dry-run** (TOCTOU, S4). `--apply` never writes status-enum or phase-complete (those gate/report only).

### Phase 2 — Consolidate brainstorm Phase 0.25
- Replace brainstorm Phase 0.25's ad-hoc inline milestone-count reconciliation with a call to
  `roadmap-reconcile.sh` (dry-run report mode) so the freshness check and `validate` share one parser.

### Phase 3 — `product-roadmap next` sub-command (advisory, read-only)
- Reports current phase (first non-Complete row) + exit-criteria status + the single next action.
- **Classification (spec-flow S6):** codeable vs operator-action by **label** (codeable = has a
  `domain/engineering`/`type` work label and no operator-action marker; non-codeable = recruitment/
  research/ops). Deterministic tie-break (lowest issue number). Explicit "no actionable next item"
  output — never empty/silent. Codeable → emit a paste-ready `/soleur:go #N` (scrub closed `#N` per
  go.md sharp edge). **Zero writes; never invokes one-shot.**

### Phase 4 — ADR + governance
- **ADR-070** (`/soleur:architecture create`): roadmap.md machine-parse contract + bounded region,
  single-writer boundary (`validate --apply` is the sole mechanical-count writer; the workshop calls
  the shared module), phase-row→milestone map, non-1:1 reconciliation rule, and the cron-adoption
  sequencing note (status: adopting until the cron follow-up lands).
- Governance: extend product-roadmap's `description:` minimally (≤ measured headroom; verify
  `bun test plugins/soleur/test/components.test.ts`); `## Changelog` entry; README component counts;
  `semver:minor`. CPO sign-off (threshold = single-user incident).

## Files to Create
- `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh`
- `plugins/soleur/test/.../roadmap-reconcile.test.ts` (path per the runner's discovery globs)
- `knowledge-base/engineering/architecture/decisions/ADR-070-roadmap-machine-parse-contract-and-single-writer-boundary.md`

## Files to Edit
- `plugins/soleur/skills/product-roadmap/SKILL.md` — add `validate` + `next` sub-commands; extend `description:` (budget-gated)
- `knowledge-base/product/roadmap.md` — insert bounded `roadmap-state` region (one-time migration)
- `plugins/soleur/skills/brainstorm/SKILL.md` — Phase 0.25 calls the shared module
- `plugins/soleur/README.md` + `plugins/soleur/.claude-plugin/plugin.json` — component counts/desc (per release-docs)

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** `product-roadmap validate` (dry-run) on current `roadmap.md` reports count drift without any write (golden-file unchanged).
- **AC2 (S1).** `--apply` refuses count writes when a milestone is 404/renamed or resolves `0/0` over a nonzero file value; emits `EMPTY_MILESTONE` instead. Test: rename a milestone fixture → no write.
- **AC3 (S3).** First run inserts paired `roadmap-state` markers deterministically around count rows only; 0/>1/unpaired markers → hard refuse (non-zero exit, no write). Non-count rows (`0 of 5`, Beta users, prose) provably untouched (golden-file diff).
- **AC4 (S4).** Gated `--apply` aborts/re-prompts if the pre-write re-read ≠ the dry-run-reported value.
- **AC5 (S5).** Milestone members absent from roadmap rows are allowlisted (not flagged); only true zero-issue milestones emit `EMPTY_MILESTONE`.
- **AC6 (S2).** ADR-070 ships the explicit phase-row→milestone map; phase-complete is defined on customer-facing rows, not raw milestone open-count.
- **AC7 (S6).** `next` defines the label-based codeable signal, deterministic tie-break, and an explicit "no actionable next item" output (never empty). Codeable item → valid `/soleur:go #N` line; zero file writes.
- **AC8.** Brainstorm Phase 0.25 calls `roadmap-reconcile.sh` (grep shows the inline reconciliation replaced).
- **AC9.** `bun test plugins/soleur/test/components.test.ts` passes (description word budget); `## Changelog` + README counts updated.

### Post-merge (operator)
- *(none — no infra; the existing Inngest cron is unchanged this PR. Cron adoption is the follow-up below.)*

## Domain Review

**Domains relevant:** Product, Engineering (carried forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)
**Status:** reviewed (carry-forward). Shared parse/write module is mandatory; `validate --apply` is sole count-writer; anchor on Current-State region; dry-run default + gated phase-complete; ADR for the contract. Premise correction (cron exists) folded in.

### Product/UX Gate
**Tier:** none — no UI surface. Files are SKILL.md / bash script / ADR / markdown. ux-design-lead N/A.

## User-Brand Impact
- **If this lands broken, the user experiences:** `product-roadmap validate --apply` silently corrupts roadmap status/counts (e.g. stamps a phase complete off a 404'd milestone), so the founder steers off a falsified source of truth.
- **If this leaks/misfires, the user's workflow is exposed via:** the bounded-region auto-writer overwriting real counts with `0/0`.
- **Brand-survival threshold:** single-user incident. Mitigations are first-class: dry-run default, counts-only auto-fix, bounded region, S1/S3/S4 guards, gated status/phase-complete. CPO sign-off required; `user-impact-reviewer` runs at PR review.

## Observability
```yaml
liveness_signal:   { what: "validate is operator-invoked (on-demand) + brainstorm Phase 0.25", cadence: on-demand, alert_target: "n/a (no server surface this PR)", configured_in: "SKILL.md" }
error_reporting:   { destination: "operator session stdout (non-zero exit, explicit verdict)", fail_loud: true }
failure_modes:
  - { mode: "milestone 404/rename", detection: "reconcile.sh guard", alert_route: "non-zero exit + EMPTY_MILESTONE verdict to stdout" }
  - { mode: "unpaired/duplicate region markers", detection: "marker-count guard", alert_route: "hard refuse, non-zero exit" }
  - { mode: "TOCTOU re-read mismatch", detection: "pre-write compare", alert_route: "abort/re-prompt" }
logs:              { where: "operator terminal / brainstorm session transcript", retention: "session" }
discoverability_test: { command: "bash plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh --dry-run", expected_output: "verdict report; exit 0 when clean (NO ssh)" }
```

## Architecture Decision (ADR/C4)
### ADR
Create **ADR-070** — roadmap.md machine-parse contract (bounded `roadmap-state` region), single-writer boundary, phase-row→milestone map, non-1:1 reconciliation rule, cron-adoption sequencing (status: adopting). Interaction with **ADR-054** (cron-roadmap-review is a permanent `safeCommitAndPr` exemption): this PR does NOT rewire the cron; ADR-070 records the adoption as a sequenced follow-up so the exemption rationale is revisited deliberately, not silently.
### C4 views
**No C4 impact.** Enumerated against all three `.c4` files: Founder actor (modeled, `model.c4:8`); GitHub system (modeled `:196`, edges `engine -> github` `:236` / `claude -> github` `:259`); Inngest cron layer (modeled `:155`). `roadmap.md` is a knowledge-base artifact, not a runtime container — not a C4 element. No new external actor/system/data-store or access relationship; nothing to render.

## Infrastructure (IaC)
None. No new server, secret, vendor, or persistent process. FR7's GHA cron was dropped (the Inngest cron already exists). Uses existing `gh` auth in the operator/cron context.

## Open Code-Review Overlap
None (checked `gh issue list --label code-review` against the planned file set at plan time — re-verify at work Phase 0).

## Follow-ups (tracked issues to file at work time)
- **Cron adoption:** point `cron-roadmap-review.ts`'s embedded prompt at `/soleur:product-roadmap validate` (delete the 48-line verbatim prompt + its anti-paraphrase test), re-evaluating the ADR-054 `safeCommitAndPr` exemption. Deferred because it touches a live Tier-1 brand-survival cron — separate, carefully-reviewed PR. Re-eval criteria: `validate` skill shipped + soaked one weekly cycle on-demand.

## Risks & Sharp Edges
- The roadmap.md `Current State` count strings are embedded in prose; the migration MUST isolate a clean count-only region — a greedy `\d+` parser corrupts sibling rows (spec-flow S3).
- `--apply` write guards (S1/S3/S4) are load-bearing at single-user threshold; deepen-plan data-integrity review recommended before `/work`.
- Extending product-roadmap's `description:` risks the ~1800-word cap — measure headroom before authoring (`cq-skill-description-budget-headroom`).
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — filled above.

## Test Strategy
`bun test` (existing harness — confirm via `package.json` scripts.test; no new framework). Golden-file fixtures for roadmap.md regions (synthesized, not copied from prod). Tests must remove non-determinism: assert against `roadmap-reconcile.sh` direct invocation with mocked `gh` output, not via an LLM prompt path.
