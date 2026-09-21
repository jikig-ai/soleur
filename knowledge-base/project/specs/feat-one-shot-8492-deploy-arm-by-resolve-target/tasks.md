# Tasks: select the deploy arm by what resolve-target deploys (#8492)

Plan: `knowledge-base/project/plans/2026-09-21-fix-deploy-arm-selection-by-resolve-target-plan.md`

## Phase 1: Setup

- [ ] 1.1 Record baselines: `wc -c` of `plugins/soleur/skills/{ship,postmerge}/SKILL.md` and
      `python3 scripts/lint-skill-body-budget.py --base origin/main`.
- [ ] 1.2 Read `plugins/soleur/test/lib/git-fixture-env.sh` and the `gh` stub in
      `plugins/soleur/test/issue-flow-measure.test.sh:101-128`.

## Phase 2: Test first (RED)

- [ ] 2.1 Create `plugins/soleur/test/deploy-arm.test.sh`: `file://` origin fixture (A → M → D on
      `main`, X unrelated, L pushed after the clone), `git_fixture_env` in the parent shell, and a
      fake `gh` that serves logs only with `--allow-escape-sequences`. Stub patterns naming
      `workflows/web-platform-release.yml/runs` carry `event=workflow_run` on the same line (Guard 8).
- [ ] 2.2 Scenarios S1-S18 (plan §Test Scenarios), each asserting rc AND stdout.
- [ ] 2.3 Static rows: both SKILL.md reference `deploy-arm.sh`; no `head_sha=[^&" ]*&event=workflow_run`;
      no ``expected `build_sha` `` / `build_sha == merge sha`; postmerge has `=~ ^[0-9]+$`;
      resolve-target checkout `ref:` pinned.
- [ ] 2.4 Final `passed == expected` non-vacuity check. Run: suite is RED.

## Phase 3: Core implementation (GREEN)

- [ ] 3.1 Create `plugins/soleur/scripts/deploy-arm.sh` (executable): `find` and `contains`
      subcommands, `ERR` trap → rc 2, dependency checks, stdout one line.
  - [ ] 3.1.1 `find`: ci.yml push-run lookup (status, created_at, run_attempt) → candidates (first
        guess + paginated window, sorted after listing, cap 30) → `git fetch origin main` → per
        candidate status gate, temp-file log read, `depth=1 origin` then `resolving deploy target
        for`, 3-min grace → classify → verdict rules 1-4 → `run_attempt == 1` fast path.
  - [ ] 3.1.2 `contains`: fetch main; CONTAINS / NOT_CONTAINED / UNRESOLVED.
- [ ] 3.2 `shellcheck plugins/soleur/scripts/deploy-arm.sh`; suite GREEN.
- [ ] 3.3 Edit `plugins/soleur/skills/postmerge/SKILL.md`: Phase 3 `contains` rule; Phase 3.7 rule
      sentence, copy-able block with numeric run-id check, REASON table (Monitor, 60 s, 45-min cap),
      deletions listed in plan §Proposed Solution 2. Move #8391/#8297 narrative to
      `references/deploy-status-debugging.md` only if the budget requires it.
- [ ] 3.4 Edit `plugins/soleur/skills/ship/SKILL.md` with the four measured replacements (plan
      §Proposed Solution 3).

## Phase 4: Verification

- [ ] 4.1 `python3 scripts/lint-skill-body-budget.py --base origin/main` → OK; both files no larger
      than baseline.
- [ ] 4.2 `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh`;
      `bun test plugins/soleur/test/workflow-fidelity.test.ts`; `bash plugins/soleur/test/deploy-arm.test.sh`.
- [ ] 4.3 Hand mutations: Guard 1 rows 1, 2, 5 and Guard 2 row 1 each turn the suite red; record in
      the PR body.
- [ ] 4.4 Live smoke (read-only): `find 71e7585eae756389b815f12b490062db4347be04` and `contains`
      against `app.soleur.ai/health`; record output in the PR body.
- [ ] 4.5 Confirm the diff excludes `worktree-manager.sh` and `web-platform-release.yml`.
