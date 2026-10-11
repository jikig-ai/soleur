# Tasks: argv-bearer sweep S5 (#9597, Ref #7797)

Plan: `knowledge-base/project/plans/2026-10-11-fix-argv-bearer-sweep-s5-apply-workflow-and-registry-cloud-init-plan.md`

Three commits. C3 (the registry file) is last so the carve-out is dropping a trailing commit.

## 1. Phase 0: gates, measure, RED

- 1.1 Re-measure on `origin/main`: Rule E census (expect 4 files / 11 sites), file sizes, latest `apply-web-platform-infra` and `infra-validation` runs; record the failing suite names.
- 1.2 Registry readiness without SSH: read the header of `scripts/registry-replace-preflight.sh`; run only a read-only mode; read the pull-tier state; else record "could not read".
- 1.3 Read the three `.c4` files; run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 1.4 Replay the five real workflow curl argument lists through `_bc_tail_ok`; read the posture step and name the consumer of `unknown-*`; confirm each job's checkout with `lint-workflow-local-action-checkout.py`.
- 1.5 Registry measurement: draft the helper and the four-copy fallback, render with `registry-userdata-budget.sh`, decide helper vs fallback (D5) and any budget raise (D6); run the Better Stack drift guard and its mutation suite (D7); `bash -n` on rendered scripts.
- 1.6 Run the suites in the plan's transport-grep list on the unchanged tree; record pass counts.
- 1.7 Write the RED rows first (Guard 1 and Guard 2, the S5 battery stage, baseline and ceiling expectations parametrized on the registry commit); confirm they fail for the right reasons.
- 1.8 Live credential shapes, booleans only, never printed: `BETTERSTACK_LOGS_TOKEN`, `BETTERSTACK_API_TOKEN`, `HCLOUD_TOKEN`. A registry-token mismatch is a stop.
- 1.9 Read `scripts/followthroughs/bearer-curl-s4-first-runs-9905.sh` for its run-log scan scope.

## 2. C1: workflow sites

- 2.1 Convert lines 2272, 2506, 3293 (library form, marker visible, `STATUS` arm unchanged).
- 2.2 Convert lines 2641 and 2648 per D3 (pre-guard only if 1.4 shows it is needed).
- 2.3 Battery rows for the workflow sites; `--write-baseline-e`; remove the ceiling row for the apply file.
- 2.4 `wc -c` below 490,000; size, target-parity and heartbeat-reconcile suites green.

## 3. C2: documentation that does not depend on the registry commit

- 3.1 `#9756` owner comment in the header of the baseline and of the ceiling table.
- 3.2 One-time lint docstring and ceiling-header correction.
- 3.3 ADR-280 S5 addendum (about ten lines, no registry paragraph).

## 4. C3: the registry file (last; the carve-out unit)

- 4.1 Template change: helper via `write_files`, four call sites, once-per-run shipper guard, per-command stdin redirect in the boot block.
- 4.2 Sibling suites edited only where measured red.
- 4.3 Battery registry rows (Guard 1 rows 1 and 2 and the census; Guard 2 rows 2, 3, 4, 7 and the rendered-output rows).
- 4.4 Budget constant and comment block only if measured over; ADR-185 amendment then.
- 4.5 Remove the registry baseline and ceiling rows; add the ADR-280 registry paragraph.

## 5. Verify and stop

- 5.1 Gates by their own invocation: `--changed --base origin/main` for Rule E and the infra no-human-steps lint; local rename-guard run; merge-base diff checks.
- 5.2 Dry-run the carve-out in a scratch worktree (`git revert --no-commit` of C3, then the baseline, lint and battery gates); record it.
- 5.3 Three-tier review. Stop and give the operator explicit notice (D4). No merge and no armed auto-merge before approval.

## 6. After approval and merge

- 6.1 `gh pr merge --squash --auto`; poll with Monitor.
- 6.2 `bash plugins/soleur/scripts/deploy-arm.sh find --wait <FULL 40-hex sha>`, then `served` from a detached `origin/main` worktree.
- 6.3 Read the dispatcher verdict and the dispatched run, new-host rows, the heartbeat step and its log, the push apply by step, the `infra-validation` suite names, the release arm.
- 6.4 Comment the delivery verdict on #9597 and the dispatch-only jobs on #9905; file the owning issue if delivery is not confirmed.
