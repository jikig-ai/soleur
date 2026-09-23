---
plan: knowledge-base/project/plans/archive/20260923-144327-2026-09-22-fix-ship-phase2-branch-scoped-learning-probe-plan.md
issue: 8470
pr: 8567
lane: cross-domain
---

# Tasks — ship Phase 2 branch-scoped learning probe (Ref #8470)

Derived from the plan above. PR body uses `Ref #8470`, never a closing keyword.
Export `TMPDIR=/var/tmp` for local runs. Never `git stash`.

## Phase 1 — Setup / RED

- [ ] 1.1 Re-measure `wc -c plugins/soleur/skills/ship/SKILL.md` and `python3 scripts/lint-skill-body-budget.py --base origin/main` (baseline: 262718 B, OK).
- [ ] 1.2 Create `plugins/soleur/test/ship-learning-probe.test.ts` (plan §B): fence-aware section extraction, exactly-one-fence (`/^\s*(`{3,}|~{3,})/`, count == 2) with the explanatory message, fenced `--(since|after|until|before)` ban, behaviour rows 1-11 with a local bare `origin` (`init -b main`, `remote add`, push `HEAD:refs/heads/main`), all git through `gitFixture`/`gitFixtureEnv`; run the block with `bash --noprofile --norc -c` and `BASH_ENV`/`ENV`/`SHELLOPTS`/`BASHOPTS` deleted.
- [ ] 1.3 Run the suite against the CURRENT SKILL.md → RED (record output for the PR body).

## Phase 2 — Core implementation / GREEN

- [ ] 2.1 Rewrite `## Phase 2: Capture Learnings` in `plugins/soleur/skills/ship/SKILL.md` per plan §A (new opening paragraph + three-arm fetch-gated probe block + `present`/`absent` lead-ins; delete the `learnings/**/*FEATURE*` Glob line; unchanged spans byte-for-byte; keep three `skill: soleur:compound` calls), and the two §A.2 one-line edits (Headless Mode Detection bullet; Important Rules line). AC4b.
- [ ] 2.2 Suite GREEN; `bun test plugins/soleur/test/workflow-fidelity.test.ts` GREEN.
- [ ] 2.3 Amend ADR-229 per plan §C (Status line; one `**[Amended 2026-09-22 (#8470): …]**` inline amendment with the `--first-parent --reverse | head -1` SINCE key and the Skip trigger change; one Verification bullet).

## Phase 3 — Testing / verification

- [ ] 3.1 Mutation battery (plan Guard Contract): mutations 2-9 each RED, H1 RED, H2 GREEN — edit the tracked SKILL.md / suite, run, restore with `git checkout -- <file>`. Record a table for the PR body.
- [ ] 3.2 `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash plugins/soleur/test/fixture-env-adoption.test.sh`, `python3 scripts/lint-skill-body-budget.py --base origin/main` green; `skill-body-budget.json` unchanged.
- [ ] 3.3 AC3 awk/grep prints 0; AC9 checks (no `SOLEUR_RULE_APPLIED` in the plugins diff, no `rule-metrics.json` in the diff).

## Phase 4 — Ship

- [ ] 4.1 PR title/body: `Ref #8470`; AC8 grep prints 0. Keep time-gated follow-through vocabulary out of the body; if the ship Phase 5.5 enrollment gate fires, use the override citing ADR-229's Alternatives row.

## Phase 5 — Post-merge (pipeline agent)

- [ ] 5.1 Confirm #8470 is still OPEN.
- [ ] 5.2 Post the plan §D comment on #8470 (mergedAt, six-week date via jq, SINCE value, Skip check).
