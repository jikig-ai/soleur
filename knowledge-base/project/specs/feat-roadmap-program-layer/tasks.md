---
feature: feat-roadmap-program-layer
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-30-feat-roadmap-program-layer-plan.md
---

# Tasks: Roadmap Program Layer

Sequencing: **validate-first** (Phases 0–2), then `next` (Phase 3), then ADR/governance (Phase 4).
Brand-survival threshold = single-user incident → the write-safety guards (S1/S3/S4) are load-bearing.

## Phase 0 — Shared parse/reconcile module + roadmap.md migration

- [ ] 0.1 Write failing tests first (RED) for `roadmap-reconcile.sh`: dry-run report shape; verdict
      emission (STALE_STATUS/MISSING_ISSUE/EMPTY_MILESTONE); milestone-404/rename guard; `0/0`-over-
      nonzero refusal; non-row-member allowlist. Mock `gh` output (no live API, no LLM in assert path).
- [ ] 0.2 Implement `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh` to GREEN:
      parse only the `<!-- roadmap-state:begin/end -->` region; fetch milestones `state=all`; emit verdicts.
- [ ] 0.3 Phase-row→milestone resolution via an explicit map (not title-guess); non-1:1 handling (S2/S5).
- [ ] 0.4 One-time migration: insert the bounded `roadmap-state` region into `knowledge-base/product/roadmap.md`
      around a clean count-only sub-table; leave prose/non-count rows outside it. Golden-file diff proves
      sibling rows untouched.

## Phase 1 — `product-roadmap validate` sub-command

- [ ] 1.1 Add `validate` sub-command to `product-roadmap/SKILL.md` (community/growth sub-command pattern).
- [ ] 1.2 Implement the mode matrix: dry-run (default) report-only; `--apply` interactive (auto-write
      counts, gate status/phase-complete via AskUserQuestion); `--apply` headless/cron (auto-write counts,
      report+file-issue for status/phase).
- [ ] 1.3 Write guards: refuse on 0/>1/unpaired region markers (non-zero exit, no write) (S3);
      TOCTOU re-read-before-write equals dry-run value or abort/re-prompt (S4); never write status-enum
      or phase-complete under `--apply` (S1).
- [ ] 1.4 Tests for the full 2×3 mode×field matrix + guard refusals (golden-file).

## Phase 2 — Consolidate brainstorm Phase 0.25

- [ ] 2.1 Replace brainstorm Phase 0.25's inline reconciliation with a `roadmap-reconcile.sh --dry-run` call.
- [ ] 2.2 Verify via grep that the inline milestone-count logic is removed (AC8).

## Phase 3 — `product-roadmap next` sub-command (advisory, read-only)

- [ ] 3.1 Add `next` sub-command: report current phase (first non-Complete row) + exit-criteria + next action.
- [ ] 3.2 Codeable-vs-operator-action classification by label; deterministic tie-break (lowest issue #);
      explicit "no actionable next item" output; codeable → paste-ready `/soleur:go #N` (scrub closed #N) (S6).
- [ ] 3.3 Assert zero file writes; never invokes one-shot. Tests for each branch incl. empty/tie/non-codeable.

## Phase 4 — ADR + governance

- [ ] 4.1 `/soleur:architecture create` → **ADR-070**: machine-parse contract, bounded region, single-writer
      boundary, phase→milestone map, non-1:1 rule, cron-adoption sequencing (status: adopting), ADR-054 interaction.
- [ ] 4.2 Confirm no C4 change (enumeration cited in plan); no `.c4` edits.
- [ ] 4.3 Extend `product-roadmap` `description:` minimally; verify `bun test plugins/soleur/test/components.test.ts`
      (word budget). Add `## Changelog`; update README + plugin.json counts; `semver:minor`.
- [ ] 4.4 File the **cron-adoption follow-up** issue (point `cron-roadmap-review.ts` at the skill; re-eval ADR-054).

## Exit gate
- [ ] All ACs (AC1–AC9) green; full test suite passes; CPO sign-off recorded; user-impact-reviewer at PR review.
