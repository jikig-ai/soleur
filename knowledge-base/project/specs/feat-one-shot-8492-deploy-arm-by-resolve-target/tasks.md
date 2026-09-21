# Tasks: select the deploy arm by what resolve-target deploys (#8492)

Plan: `knowledge-base/project/plans/2026-09-21-fix-deploy-arm-selection-by-resolve-target-plan.md`
(deepened 2026-09-21 — the plan's §Proposed Solution is the contract; these tasks index it).

## Phase 1: Setup

- [ ] 1.1 Record baselines: `wc -c plugins/soleur/skills/{ship,postmerge}/SKILL.md` and
      `python3 scripts/lint-skill-body-budget.py --base origin/main`.
- [ ] 1.2 Read `plugins/soleur/test/lib/git-fixture-env.sh`, the `gh` stub and counting pattern in
      `plugins/soleur/test/issue-flow-measure.test.sh`, and `web-platform-release.yml`
      `resolve-target` (`:207-575`), `deploy` `if:` (`:1076-1084`) and the lock groups
      (`:868-870`, `:1115-1117`).

## Phase 2: Test first (RED)

- [ ] 2.1 Create `plugins/soleur/test/deploy-arm.test.sh`: per-scenario `file://` origin + clone
      (A → M → D on `main`, X unrelated), `git_fixture_env` in the parent shell, `DEPLOY_ARM_NOW` /
      `DEPLOY_ARM_SLEEP=0` pinned, timestamps rendered with `jq todate`.
- [ ] 2.2 `gh` stub: argv log; logs only with `--allow-escape-sequences`; page 2 only with
      `--paginate`; runs the script's own `--jq` with real `jq -r`; 404 = JSON body on stdout + rc 1;
      window handler can push `L` to origin (S8); rc 64 on unknown endpoints. `curl` stub for
      `served`. Fixture JSON pretty-printed, no `url` fields; any line spelling
      `workflows/…web-platform-release…/runs` carries `event=workflow_run` (Guard 8).
- [ ] 2.3 Scenarios S1-S31 (plan §Test Scenarios): rc + exactly one stdout line + full expected line.
- [ ] 2.4 Static rows (plan §Proposed Solution 5), each asserting the file exists and is non-empty,
      regexes self-tested first.
- [ ] 2.5 Counting: `cases` counter, `pass`/`fail` self-test, `passes + fails == cases`, floor.
      Run: suite is RED.

## Phase 3: Core implementation (GREEN)

- [ ] 3.1 Create `plugins/soleur/scripts/deploy-arm.sh` (executable, `set -Eeuo pipefail`, ERR trap →
      one stdout error line + rc 2, scope guard → `not_applicable`).
  - [ ] 3.1.1 `find`: CI run lookup → candidates (first guess + paginated window, sorted after
        listing, cap 30) → fetch default branch after listing → per-candidate status gate,
        temp-file log read with 3 attempts, `depth=1 origin` then `resolving deploy target for`,
        3-min grace → ancestry → `DEPLOY` derivation → verdict rules 0-4 → `run_attempt == 1` fast
        path; stderr line per candidate.
  - [ ] 3.1.2 `find --wait [MIN]`: 60 s cadence × `DEPLOY_ARM_SLEEP`, default cap 120 min.
  - [ ] 3.1.3 `contains`: input checks before network; non-fatal fetch; ancestry.
  - [ ] 3.1.4 `served [URL]`: curl `app.soleur.ai/health` (3 attempts), parse `.build_sha`, call
        `contains`, append ` BUILD_SHA=<sha|->`.
- [ ] 3.2 `shellcheck plugins/soleur/scripts/deploy-arm.sh`; suite GREEN.
- [ ] 3.3 Create `plugins/soleur/test/deploy-arm-mutations.sh` (Guard 1 rows 1-10, Guard 2 rows 1-4,
      H3); run it; all KILLED except H3 as described.
- [ ] 3.4 Edit `plugins/soleur/skills/postmerge/SKILL.md`: Phase 2 failure-branch sentence; Phase 3
      `find --wait` + `served` table; gate regex `:283` adds `deploy-arm`; Phase 3.7 rewrite per plan
      §Proposed Solution 2 (no `$()`; literal `ARM=` digits; `DEPLOY` replaces `DEPLOY_JOB_STATE`;
      match-type interpretation).
- [ ] 3.5 Edit `plugins/soleur/skills/ship/SKILL.md` with the measured replacements (plan §Proposed
      Solution 3, net −212 B).
- [ ] 3.6 Add the ADR-217 dated addendum via `soleur:architecture` (plan §Proposed Solution 4).

## Phase 4: Verification

- [ ] 4.1 `python3 scripts/lint-skill-body-budget.py --base origin/main` → OK; both files no larger
      than baseline. If postmerge is over, move the #8391/#8297 narratives to
      `postmerge/references/deploy-status-debugging.md`.
- [ ] 4.2 `bash plugins/soleur/test/deploy-arm.test.sh`;
      `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh`;
      `bash plugins/soleur/test/c4-count-parity.test.sh`;
      `bun test plugins/soleur/test/workflow-fidelity.test.ts`.
- [ ] 4.3 `env -i PATH=/usr/bin:/bin HOME=/tmp bash plugins/soleur/scripts/deploy-arm.sh contains 0000000000000000000000000000000000000000 dev`
      → `UNRESOLVED`.
- [ ] 4.4 Live smoke (read-only): `find 71e7585eae756389b815f12b490062db4347be04` and `served` on
      the same SHA; record output and the mutation-driver output in the PR body.
- [ ] 4.5 Confirm the diff excludes `worktree-manager.sh` and `web-platform-release.yml`.
