---
feature: feat-roadmap-program-layer
lane: cross-domain
brand_survival_threshold: low
plan: knowledge-base/project/plans/2026-06-30-feat-roadmap-program-layer-plan.md
---

# Tasks: Roadmap Program Layer (report-only)

Read-only feature (deepen-plan dropped the write path). No migration, no ADR, no CPO sign-off.

## Phase 0 — Shared read-only reconcile module
- [ ] 0.1 RED tests for `roadmap-reconcile.sh`: drift-report shape; verdict emission
      (STALE_STATUS/MISSING_ISSUE/EMPTY_MILESTONE); phase-row→milestone map (row-label ≠ milestone-title);
      non-row-member allowlist; **zero file writes** (git-clean post-run). Mock `gh` output; no LLM in assert path.
- [ ] 0.2 Implement `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh` to GREEN:
      best-effort parse of `roadmap.md` Current State; fetch milestones `state=all`; emit verdicts; exit 0 clean / non-zero on drift. Writes nothing.
- [ ] 0.3 Inline phase-row→milestone map + non-1:1 allowlist (S2/S5).

## Phase 1 — `product-roadmap validate` sub-command (report-only)
- [ ] 1.1 Add `validate` sub-command to `product-roadmap/SKILL.md` (community/growth pattern) = thin CLI over the module. No `--apply`, no write path.
- [ ] 1.2 Drift report ends with the cron-trigger remediation pointer (`/soleur:trigger-cron cron/roadmap-review.manual-trigger`).

## Phase 2 — Consolidate brainstorm Phase 0.25
- [ ] 2.1 Replace brainstorm Phase 0.25's inline reconciliation with a `roadmap-reconcile.sh` call.
- [ ] 2.2 Grep-verify the inline milestone-count logic is removed.

## Phase 3 — `product-roadmap next` sub-command (advisory, read-only)
- [ ] 3.1 Add `next` sub-command: current phase (first non-Complete row) + exit-criteria + next action.
- [ ] 3.2 Label-based codeable classification; deterministic tie-break (lowest issue #); explicit "no actionable next item"; codeable → paste-ready `/soleur:go #N` (scrub closed #N). Zero writes.
- [ ] 3.3 Tests for each branch (empty / tie / codeable / non-codeable); assert zero writes; never invokes one-shot.

## Phase 4 — Governance (lite)
- [ ] 4.1 Extend `product-roadmap` `description:` minimally; verify `bun test plugins/soleur/test/components.test.ts` (word budget).
- [ ] 4.2 `## Changelog`; update README + plugin.json counts; `semver:minor`.

## Exit gate
- [ ] All ACs green; full test suite passes; zero-file-writes assertion holds. (No ADR, no CPO sign-off — threshold low.)
