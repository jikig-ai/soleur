---
title: Tasks — Mandatory UX Wireframes + Stale-Claim Hardening
feature: feat-mandatory-ux-wireframes
date: 2026-06-02
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-feat-mandatory-ux-wireframes-stale-claim-hardening-plan.md
related_issues: [4819, 4817]
---

# Tasks: Mandatory UX Wireframes + Stale-Claim Hardening

Derived from the finalized (post-5-agent-review) plan. NEVER CODE during planning — this is the
/work checklist.

## Phase 0 — Preconditions (no commits)

- [ ] 0.1 `cd` into worktree; confirm branch `feat-mandatory-ux-wireframes`; do not read bare repo.
- [ ] 0.2 Re-measure `B_ALWAYS` = `wc -c AGENTS.md + AGENTS.core.md`; run `python3 scripts/lint-agents-rule-budget.py` (baseline 22458).
- [ ] 0.3 Empirical headless authoring: `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto`, then a trivial `batch_design`+`save` → non-zero `.pen`. Surface failure; does NOT block Phases 1-5.
- [ ] 0.4 Confirm `PENCIL_CLI_KEY` present: `doppler secrets --project soleur --config dev --only-names | grep -i pencil` (names only).

## Phase 1 — Feature B: merged hard rule + premise cross-ref + budget trim

- [ ] 1.1 Trim `hr-observability-layer-citation` body tail (~250 B) in `AGENTS.core.md` (layer enumeration duplicated at `observability-coverage-reviewer.md:15-17`). Leave SSH + GDPR rules untouched.
- [ ] 1.2 Add `[id: hr-verify-repo-capability-claim-before-assert]` body to `AGENTS.core.md` + `→ core` pointer in `AGENTS.md` `## Hard Rules`. Semantic trigger; covers own-output AND subagent-prompt premises; hedge words = examples. Verify slug regex + not retired + ≤600 B.
- [ ] 1.3 Re-run `lint-agents-rule-budget.py` → `B_ALWAYS < 23000` (target ≤ ~22800). Trim more from observability tail if needed.
- [ ] 1.4 FR9 one-line cross-ref to the new rule at brainstorm `SKILL.md:235` and plan `SKILL.md:101` (Phase 0.6). Do not restate verify-or-ask logic.

## Phase 2 — Feature A: close skip outcomes (brainstorm + plan + work)

- [ ] 2.1 brainstorm `SKILL.md:404-421`: keep `:406` trigger; replace `:419`/`:421` skips with auto-install-then-block; remove `Phase 3.55: skipped` echoes; cite term-list.
- [ ] 2.2 plan `SKILL.md` Phase 2.5: add mechanical UI-surface override at TOP of Step 1 → force Product-relevant + tier=BLOCKING when Files match term-list/glob superset (fixes the Product-NONE-sweep silent state).
- [ ] 2.3 plan `:302`: exclude `ux-design-lead` from the skippable specialist set for UI features.
- [ ] 2.4 plan `:321`: remove self-stop → `Skipped specialists` branch; auto-install + re-invoke; hard-block on genuine failure; one-shot path = sole producer (generate `.pen`).
- [ ] 2.5 plan `:324` step 7: remove "Skip with acknowledgment" for ux-design-lead; reconcile with `:321` (no contradictory offer).
- [ ] 2.6 plan `:358-359` Heading Contract: ux-design-lead never in `Skipped specialists:` for UI; verifier asserts `.pen` on disk (non-empty, under `knowledge-base/product/design/{domain}/`, in spec FRs).
- [ ] 2.7 work `SKILL.md:104` Check-9: widen glob to term-list superset (`.njk/.html/.vue/.svelte/.astro` + email templates); add arm: UI plan with NO `### Product/UX Gate` subsection → FAIL.

## Phase 3 — Shared UI-surface term-list

- [ ] 3.1 Create `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` (SoT).
- [ ] 3.2 Cite it from all four layers: brainstorm 3.55, plan 2.5, deepen-plan 4.9, work Check-9.

## Phase 4 — deepen-plan 4.9 halt + constitution / wg-* promotion

- [ ] 4.1 deepen-plan: add `### 4.9. UI-Wireframe Artifact Halt` AFTER the existing 4.8 (`:445`), mirroring 4.6/4.7 (grep `.pen` ref → HALT + `emit_incident wg-ui-feature-requires-pen-wireframe applied`).
- [ ] 4.2 Add `wg-ui-feature-requires-pen-wireframe` body to `AGENTS.docs.md` + `→ docs-only` pointer in `AGENTS.md` `## Workflow Gates`; `[skill-enforced: brainstorm 3.55 + plan 2.5 + deepen-plan 4.9]`.
- [ ] 4.3 Annotate `constitution.md:177` as promoted (`→ wg-ui-feature-requires-pen-wireframe`); keep retired `ex-wg-...` text immutable.

## Phase 5 — Tests (RED-first) + learning

- [ ] 5.1 RED: create `plugins/soleur/test/mandatory-wireframes-hardening.test.ts` (skip-clause removal, rule-id presence, single 4.8 + new 4.9). Confirm fails on current state.
- [ ] 5.2 GREEN via Phases 1-4.
- [ ] 5.3 Run `python3 scripts/lint-rule-ids.py` (exit 0) + `python3 scripts/lint-agents-rule-budget.py` (exit 0, `B_ALWAYS < 23000`).
- [ ] 5.4 Learning file `knowledge-base/project/learnings/bug-fixes/<topic>.md` (author dates at write-time); link the two related learnings.
- [ ] 5.5 `cd <worktree> && bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts` + `components.test.ts` green (run inside worktree).

## Acceptance Criteria (gate before PR-ready)

AC1-AC7 from the plan. Key: no reachable skip outcome for UI features; mechanical override + Check-9
backstop close the silent-state holes; merged hard rule has a semantic trigger; budget passes;
4.8 + 4.9 both present (one each); learning exists; tests green.
