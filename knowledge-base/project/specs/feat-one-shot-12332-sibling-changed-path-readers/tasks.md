# Tasks: sibling changed-path readers (#12332)

Plan: `knowledge-base/project/plans/2026-11-07-fix-sibling-changed-path-readers-plan.md`. Rulings: `decision-challenges.md`.
CI is the gate (see `session-state.md`): run only the targeted suites by path, never the affected battery to completion.
Commit order keeps each commit green; accept rows go in the last commit. `git add` and `git commit` in separate calls.

## Phase 0: Setup

- 0.1 cd into the worktree; confirm branch `feat-one-shot-12332-sibling-changed-path-readers`, draft PR #12357.
- 0.2 `git merge-tree` against open PRs #12329 and #12168 for the files in the plan; note conflicts.
- 0.3 Re-run the census regex (plan Phase 5) over `.github/workflows`; add any `^`-anchored site not in the plan's table.

## Phase 1: Helper (RED first)

- 1.1 Create `plugins/soleur/test/changed-path-readers.test.sh` with the `helper` section: C-quote precondition rows, rename-away, gitlink, `diff.relative`, failing-git shim, `--match` exits 0/1/2, empty args exit 2, control row.
- 1.2 Create `plugins/soleur/scripts/changed-paths.sh` (plain mode, `--match` mode, usage exit 2, header comment on helper vs inline).
- 1.3 Green the helper section.

## Phase 2: Workflows

- 2.1 `steps` section: one PyYAML extraction, weakest-shell execution, `DEFAULT_ENV` map with named scenarios, template-repo `cp -a`, rows per the plan (live-defect rows, shape-preserving rows, legal-docs rename-away row, secret-scan argv rows).
- 2.2 Convert: `infra-validation.yml` `dirs` (both arms, capture-first), `ci.yml` `filter`, `apply-sentry-infra.yml`, `tenant-integration.yml`, `vendor-pin-verify.yml`, `pr-quality-guards.yml` `constraint-gates-changed` and `enforce-legal-lockstep` (separate surface read).
- 2.3 Shape-preserving: `ci.yml` `trigger-canary` / `trigger-propagation` (`--no-renames` only, keep `|| true`).
- 2.4 `secret-scan.yml`: `lint-fixture-files-pr` (two arms), `lint-fixture-files-nonpr`, `lint-fixture-content` (`xargs -0 -a`); git captured first, no `|| true` on the git line.
- 2.5 Update `infra-validation-detect.test.sh` and any suite found by `git grep -lE 'workflows/(...)\.yml' -- '*.test.sh' tests`.

## Phase 3: Non-workflow readers

- 3.1 `battery-refusal-wait.sh`: append `--ignore-submodules=none` to four reads; header sentence; argv-shim scenario per read plus one defensive fixture in `ship-battery-refusal-wait.test.sh`.
- 3.2 `scripts/test-all.sh`: append `--ignore-submodules=none` to six reads; run the four pin suites first and fix only the red pins (`staged_anchor`, `rename-sources-dropped`, the end-anchored `exit 128` shim glob, notice regex); add argv-shim scenarios to the infra-notice suite.
- 3.3 `ship-cmo-content-gate.sh` (`-z`), `ship-runbook-ssh-gate.sh` (`mapfile -d ''`, raw-name re-diff, `--literal-pathspecs`), `check-backstop-revision.sh` (`--no-renames`), each with suite rows.
- 3.4 `battery-owed.sh` header: one reason line for `INFRA_RE` (no regex change).

## Phase 4: Skill prose

- 4.1 Record the byte delta; convert preflight Step 0.1 (+ its two fallbacks), ship gdpr (shared invocation) / DPF / `.github` check via `--match`, review Change Classification (name-only line) and gdpr line.
- 4.2 `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0; trim same-paragraph prose on overshoot.

## Phase 5: Sentinel

- 5.1 `sentinel` section: workflow scan with comment stripping and continuation joining, exemption data block (3-4 rows), stale-entry check, scanned-file floor, pinned must-keep-`-z` list, header naming what is not covered.

## Phase 6: Retirement, records, registries

- 6.1 `git rm` the #12332 probe; remove the `follow-through` label from #12332 before the merge is armed.
- 6.2 One-line observation in `ship/references/queue-mode.md`.
- 6.3 Measure the suite once; add `suite-durations.tsv` (measured floor), `suite-shard-legs.tsv`, the `AFFECTED_..._PATHS` declaration in `scripts/lib/test-affected-paths.sh`; `bash scripts/lint-orphan-test-suites.sh`.
- 6.4 LAST: accept rows (12-hex anchor, `file:line`, sorted); re-derive after any later suite edit.

## Phase 7: Mutation battery (agent-run)

- 7.1 Per guard: green control, mutation-landed check, lead-unique scratchpad name; record "N killed + M controls green" for the PR body; two fix rounds plus one verification pass.

## Phase 8: Ship and post-merge

- 8.1 PR body: `Closes #12332`, `Ref #12246`, `Filed: none`, Phase 7 line, Fork 1 reason, `## Changelog`, review map, known remainder; comment the Phase 7 line on #12332; `net-issue-flow.sh`.
- 8.2 `--queue-state` before any push; no `--admin`; no ruleset change; required checks `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`.
- 8.3 After merge: `deploy-arm.sh find --wait <full-sha>`, `deploy-arm.sh served <full-sha>` = CONTAINS, `/health` on app.soleur.ai with supabase connected.
