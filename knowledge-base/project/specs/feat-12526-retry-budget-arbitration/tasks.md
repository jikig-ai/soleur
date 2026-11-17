# Tasks: retry-budget ruling

## Phase 1: Setup

- [ ] 1.1 Re-measure `plugins/soleur/skills/one-shot/SKILL.md` with `wc -c` before editing it, and confirm the `one-shot` ceiling in `plugins/soleur/test/skill-body-budget.json` is still 52000.
- [ ] 1.2 Write `plugins/soleur/scripts/retry-budget-ruling.test.sh` first. Cover identity, `ruling_spawn: used`, empty history, the one-LF delimiter, the 64-byte stop, the fixed ledger fields, and the plain fail line.

## Phase 2: Core Implementation

- [ ] 2.1 Add `plugins/soleur/scripts/retry-budget-ruling.sh`: `--probe`, the predicate order, the ledger section, and the stdout contract in Phase 1 of the plan.
- [ ] 2.2 Add `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md` with the parent procedure in Phase 3 of the plan.
- [ ] 2.3 Teach `plugins/soleur/hooks/stop-hook.sh` the exact grant line, `retry_budget_consumed: 1`, and the current-session sweep exception in Phase 2 of the plan. Extend `plugins/soleur/test/ralph-loop.test.sh` beside the existing no-block cases.
- [ ] 2.4 Edit the two child-marker halts in `plugins/soleur/skills/one-shot/SKILL.md` so each ends with a leading space, then `Read references/retry-budget-ruling.md`, then a period In that same edit, delete the second `dispose of it` in the prose-Ref bullet, including the space before those words, and delete the token-discipline parenthetical `moved verbatim; byte-ceiling extraction`, including the space before the parenthesis. Keep that Read target. Leave step 0d and the `description:` line. When the re-measure is still 51968 bytes, the file ends at 51992.
- [ ] 2.5 Amend ADR-268 Consequences and the two `model.c4` descriptions in Phase 4 of the plan.

## Phase 3: Testing

- [ ] 3.1 Run `plugins/soleur/scripts/retry-budget-ruling.test.sh` and `plugins/soleur/test/ralph-loop.test.sh`.
- [ ] 3.2 Run `scripts/lint-skill-body-budget.py --base origin/main` and `plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 3.3 Confirm `scripts/test-all.sh` and `apps/web-platform/server/git-lock-marker-telemetry.ts` are not in the diff.
