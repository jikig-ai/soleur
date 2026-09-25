---
title: "Tasks: scope the skill-security-scan calibration in the plugin-markdown pre-commit hook"
plan: knowledge-base/project/plans/2026-09-25-perf-precommit-plugin-md-scoped-calibration-plan.md
branch: feat-one-shot-precommit-plugin-md-affected
lane: cross-domain
---

# Tasks

## 1. Setup

- [ ] 1.1 Create `knowledge-base/project/specs/feat-one-shot-precommit-plugin-md-affected/measurements.md`
  with the plan's baselines (176 s run, 127.9 s file, 116.5 s calibration test, 215/517 affected arm)
  and `wc -c plugins/soleur/skills/ship/SKILL.md` (271 033 B of a 274 000 B ceiling).
- [ ] 1.2 `git grep -n SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE` returns nothing (name is free).

## 2. Core implementation

- [ ] 2.1 Edit `plugins/soleur/test/skill-security-scan.test.ts` calibration `describe`: compute
  `scoped`/`skills` at collection (CI never scoped; unset → full; match repo-relative path), one log
  line `scoped|full <k>/<N>`, HIGH-RISK `skipIf(scoped && skills.length === 0)`, REVIEW
  `skipIf(scoped)`, names unchanged, header comment item 3 updated.
- [ ] 2.2 Edit `lefthook.yml` `plugin-component-test` `run:` to the plan's Phase 2.1 string (unset
  first), add 3–5 comment lines above the retained #7833 block. Nothing else changes.
- [ ] 2.3 Edit `plugins/soleur/skills/ship/SKILL.md` Phase 7 merge step 4 sentence (~65 s) — net byte
  delta ≤ 0; record before/after `wc -c`.

## 3. Testing (targeted — no full battery, no `test-all.sh --affected`)

- [ ] 3.1 Plan Phase 3.1 (one SKILL.md → `scoped 1/<N>`, green, < 20 s).
- [ ] 3.2 Plan Phase 3.2 (two SKILL.md → `scoped 2/<N>`).
- [ ] 3.3 Plan Phase 3.3 (agent `.md` → `scoped 0/<N>`, 2 skips).
- [ ] 3.4 Plan Phase 3.4 (`CI=1` + scope → collection log `full <N>/<N>`).
- [ ] 3.5 Mutation spot-checks M1–M5 by hand against rows 3.1–3.4; log RED observations in `measurements.md`.
- [ ] 3.6 `bash plugins/soleur/test/hook-git-env-coverage.test.sh` → `run_lines=32 runners=3`.
- [ ] 3.7 `bash plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` → 5/5.
- [ ] 3.8 AC8 census grep (plans/specs excluded) lists only `lefthook.yml` and the test file.
- [ ] 3.9 `npx markdownlint-cli2` on changed markdown before each commit.
- [ ] 3.10 Dogfood commit staging `ship/SKILL.md` with hooks live; record hook seconds, load average and
  the `scoped 1/<N>` line; confirm HEAD moved.
- [ ] 3.11 Push; required checks (incl. `test-bun`, `skill-security-scan-corpus`) green by name on the
  exact head SHA.
