# Tasks: move harness model pins to this week's releases (Phase A)

Plan: `knowledge-base/project/plans/2026-09-23-feat-upgrade-harness-models-plan.md`

This pipeline executes **Phase A only**. Phase B (Opus 5.5) is date-gated to on or after
2026-09-25T15:44:39Z and is tracked by #7773.

## Phase 1: Setup and verification

- [ ] 1.1 Re-run `grok models` and confirm it lists `grok-4.7` (default), `grok-4.7-build-fast`, `grok-4.6` and `grok-4.5`. Record the output for the PR body.
- [ ] 1.2 Confirm the 7 workflow fences still carry `standard: 'grok-4.6', strong: 'grok-4.6', advisor: 'grok-4.6'` (one each).

## Phase 2: Tests first (RED)

- [ ] 2.1 Edit `plugins/soleur/test/harness-model-map.test.ts`:
  - [ ] 2.1.1 Rename the grok fixture test to `grok fixture map uses live CLI spawn slugs` (no version).
  - [ ] 2.1.2 Expect standard/strong/advisor `grok-4.7` and cheap `grok-4.5`. Keep `.not.toBe("grok-build-0.1")`.
  - [ ] 2.1.3 Rewrite the "only non-default slug" comment to the cached-input rationale.
  - [ ] 2.1.4 `resolveAdvisorTier("grok")` / `resolveAdvisorFallback("grok")` / `TIER_MAPS.grok.standard` → `grok-4.7`.
- [ ] 2.2 `bun test plugins/soleur/test/harness-model-map.test.ts` must fail (RED).

## Phase 3: Core implementation (GREEN)

- [ ] 3.1 `plugins/soleur/lib/harness-model-map.ts`:
  - set `TIER_MAPS.grok` standard/strong/advisor to `grok-4.7` (cheap stays `grok-4.5`);
  - shorten the provenance comment to a pointer at the ADR-110 addendum plus a one-line cheap rationale.
- [ ] 3.2 Make the exact-string triple swap in the 7 workflow fences (review, plan-review, deepen-plan, resolve-parallel, resolve-todo-parallel, resolve-pr-parallel, drain-labeled-backlog).
- [ ] 3.3 Re-run `bun test plugins/soleur/test/harness-model-map.test.ts` and check it passes (GREEN).
- [ ] 3.4 `plugins/soleur/AGENTS.md:180`: rewrite the grok-4.6 mention tier-generically.
- [ ] 3.5 ADR-110:
  - update the fixture table (grok-4.7), the line-35 heading and the line-39 cheap note;
  - update the "Do not pin grok-build-0.1 … 1.0.29" line to 1.0.40;
  - append `## Addendum — 2026-09-23 (Grok 4.7 launch)` with the live output, the docs.x.ai prices, the cached-input cheap rationale and the server-fetched catalog note.
- [ ] 3.6 `plugins/soleur/skills/model-launch-review/SKILL.md` (body only):
  - add row 6 (Grok tier-map freshness, agent-run, with the one-clause cheap fallback);
  - rename to "7 items";
  - change "Items 2–5" to "Items 2–6";
  - change "all 5 checks" to "items 1–5 scripted; row 6 agent-run";
  - add the Codex no-pin sentence and the xAI trigger under "When to invoke".

## Phase 4: Verification

- [ ] 4.1 `bun test plugins/soleur/test/harness-model-map.test.ts plugins/soleur/test/workflow-model-pins.test.ts plugins/soleur/test/components.test.ts` exits 0.
- [ ] 4.2 `git grep -l 'grok-4\.6' -- plugins/soleur` prints nothing, or only `plugins/soleur/lib/harness-model-map.ts`.
- [ ] 4.3 `git grep -nE -e 'gpt-[0-9]' -e 'codex-mini' -- apps/web-platform/server .codex plugins/soleur/codex` prints nothing.
- [ ] 4.4 The SKILL.md `description:` line is unchanged vs `origin/main`.
- [ ] 4.5 `git diff --name-only origin/main...HEAD` lists nothing under `apps/` or `scripts/dogfood/`.
- [ ] 4.6 `grep -c advisor...grok-4.7 plugins/soleur/lib/harness-model-map.ts` prints `1`.

## Phase 5: Issue hygiene

- [ ] 5.1 Retitle #7773 to the Phase B title (Opus 5.5 CLI bump + AUDIT_MODEL swap, not before 2026-09-25T15:44Z). Add a comment that links the plan's `### Phase B` section.
- [ ] 5.2 The PR body carries `Ref #7773`. It also records the Codex no-pin finding and the live `grok models` output.
