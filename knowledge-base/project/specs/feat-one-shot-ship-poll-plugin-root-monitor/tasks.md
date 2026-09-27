---
title: "Tasks: fix(ship): Phase 7 poll loses the plugin root when its fence is run from disk under Monitor"
plan: knowledge-base/project/plans/2026-09-27-fix-ship-phase7-poll-plugin-root-under-monitor-plan.md
branch: feat-one-shot-ship-poll-plugin-root-monitor
lane: cross-domain
---

# Tasks

## 1. Setup

- [ ] 1.1 Record the baseline. `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` should print `392 pass, 0 fail`.
- [ ] 1.2 Record `wc -c plugins/soleur/skills/ship/SKILL.md` (should be 271034; the ceiling is 274000).

## 2. RED: fixture rows (`plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`)

- [ ] 2.1 Add one prose-pin row for each file, `ship/SKILL.md` and `merge-pr/SKILL.md`. Each is a `grep -qF` for the fragment `` the root for this session is `${CLAUDE_PLUGIN_ROOT}` ``.
- [ ] 2.2 Build `SUBST_BLOCK` and `SUBST_MIRROR` by replacing the token with `$PLUGIN_COPY`, the way the loader does.
  - [ ] 2.2.1 Use a literal replacement only: no `sed` or `perl` whose replacement text contains `$`.
  - [ ] 2.2.2 Register both files in `_TMP_OWNED`.
  - [ ] 2.2.3 Assert that the replacement landed: the token count after is 0, and the path count is at least 1.
- [ ] 2.3 Add row `17b-delivered-decoy`, modelled on scenario 9.
  - [ ] 2.3.1 Set `SCEN_ROOT="$EVIL_ROOT"`.
  - [ ] 2.3.2 Run it on both blocks, using the fifth argument of `run_scenario`.
  - [ ] 2.3.3 Expect the per-block success line: `auto-sync 1 pushed` for the ship block and `auto-sync 1/6 pushed` for the mirror.
  - [ ] 2.3.4 Forbid `[ship.phase7.precondition]` and `does not name soleur`.
- [ ] 2.4 Run the suite. The prose pins should be RED and 17b GREEN, because the existing binding is already correct. Note this in the PR body.

## 3. GREEN: skill prose (the fences stay byte-identical)

- [ ] 3.1 In `ship/SKILL.md` Phase 7, add the "plugin root is fixed only in delivered text" notice. It goes after the `**Claude — Monitor tool loop**` line and before the fence. Use the exact text from the plan's Phase 2.
- [ ] 3.2 In `merge-pr/SKILL.md` §5.2, append the pointer sentence to the `**Mirror invariant:**` paragraph.
- [ ] 3.3 Check the new text against the W1/W1b/W2/W3 constraints. Do not spell out a checkout path. Keep the net ship growth at or below 800 bytes.

## 4. Verify

- [ ] 4.1 Rerun the fixture suite: all green. Raise `MIN_VERDICTS` to the new total, and update the scenario list in the header comment.
- [ ] 4.2 Run the Guard Contract mutations M1–M5 and H1, all expected RED, and H2, expected GREEN. Revert each with `git checkout -- <file>`, never `git stash`. Put the results table in the PR body.
- [ ] 4.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
- [ ] 4.4 `python3 scripts/lint-skill-body-budget.py --base origin/main`
- [ ] 4.5 `bash scripts/plugin-root-anchor-debt.sh` should print `anchor-debt-files=0`.
- [ ] 4.6 `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/components.test.ts`
- [ ] 4.7 Confirm that both extracted fences are byte-identical to `origin/main`.
- [ ] 4.8 Run `npx markdownlint-cli2` on both edited SKILL.md files.

## 5. Ship notes

- [ ] 5.1 If the rename-guard false alarm (#9028) fires, rebuild the branch as one linear commit on `origin/main` with an identical tree. Never apply the override label.
- [ ] 5.2 Keep to one PR. The guardrails.sh filing-gate matcher is a separate follow-up.
