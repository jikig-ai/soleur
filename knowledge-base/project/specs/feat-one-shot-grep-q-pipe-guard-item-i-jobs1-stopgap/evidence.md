# Evidence: Item I (JOBS=1 stopgap, #7432, tracker #9217)

Raw run data stays under `/var/tmp/item-i-*` and is not committed. Commands: `measure/run-all.sh` (figures) and
`measure/extract-monitor-facts.sh <run_id> <job_id>` (per-run width, size, breakdown, RED set), with the
`main-health-outcomes` check-run annotation as the verdict (never the run or job conclusion, which
`continue-on-error: true` pins to success).

## Figures (re-run 2026-10-16 and 2026-10-18, `CONTROLS OK` both times)

Command: `ITEM_I_DIR=/var/tmp/item-i-work bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/measure/run-all.sh`

- M1 (300 monitor runs on main): infra step 171 ok, 81 killed at the 60-minute ceiling, 17 RED without a timeout, 31 no verdict;
  81 of the 269 steps that could deliver a verdict (30%) delivered none. Tests step killed at its ceiling in 129 of 300 (cause #9410, separate).
- M2: `deploy-script-tests` legs at `-P 4` on push to main since 2026-09-25: 688 executions, 609 success, 75 failure, 4 cancelled.
- M3: 88 suite REDs; isolated single-push suite-events 23 over 169 runs (0.136 per run, an upper bound that includes one-commit regressions).
- M4: 15 paired same-sha comparisons, 3 informative, 0 RED at `-P 4` and clean at `-P 1`, 0 the other way.

## Dispatch gate (all `dry_run=true`, infra step at `-P 4`, 179 suites, no ceiling kill, no `[KILLED]`, 0 unaccounted)

| run | head sha | infra | elapsed | breakdown | RED | note |
|---|---|---|---|---|---|---|
| 38942396026 | 4bed166006 | failure | 1890 s | 178/179 | `web-host-provisioner-parity-mutation.test.sh` rc=124, 361 s | cold shape (the diff touched no infra path), so the timeout is not a warm-state artifact |
| 38942417986 | 4bed166006 | failure | 1866 s | 178/179 | same suite rc=124, 360 s | same |
| 38965464152 | e466270ed9 | success | 1433 s | 179/179 | none | launched under a conditional ruling that did not apply; no gate credit |
| 39086879796 | ca32a51740 | success | 1881 s | 179/179 | none | RE-GATE A, cold shape |
| 39086881468 | ca32a51740 | success | 1666 s | 179/179 | none | RE-GATE B, cold shape |

The tests step hit its own 110-minute ceiling in all five runs (#9410), so the infra step always ran after it on the same runner;
no nested `Running N registered infra suite(s)` line precedes the infra step in any run. The two dispatches of each pair were
serialised by the workflow's `main-health-monitor-dry-run` concurrency group, not run concurrently.

Pre-dispatch check (CTO constraint): `git diff --name-only origin/main...HEAD` matched no `apps/` path and not
`apply-web-platform-infra.yml` (count 0) at sha ca32a51740, recorded in `/var/tmp/item-i-work/predispatch.txt`.
Commits made after the re-gate dispatches are knowledge-base only (this file, decision rows, task ticks); the workflow, the guard
and the probe are byte-identical to the dispatched sha.

## The one RED and its fix

`web-host-provisioner-parity-mutation.test.sh` (143 rows, serial) ran 171 s alone on 4 pinned cores
(`taskset -c 0-3`, `/var/tmp/item-i-work/taskset-evidence.txt`) and 401 s beside three other heavy suites running concurrently
(`workspaces-luks-provision`, `workspaces-boot-unlock`, `infra-config-repush-mutation`). It carried no `_SUITE_BOUNDS` entry
(360 s default). The bound landed separately as PR #10478 (540 s = 1.35x the 401 s worst case; the ci-deploy entry is the precedent).
Separate PR because an edit under `apps/web-platform/infra/` puts that path in the branch diff, which makes the monitor's tests
step run the nested infra runner and warm the standalone infra step; a dispatch from such a branch would not measure the cold
shape the scheduled monitor has on main.

## Not done

The stale clause "(that is why JOBS: 1 is pinned on both steps, not one)" in the `apps/web-platform/infra/run-registered-suites.sh`
comment is left as is (the tests-step pin it describes still exists, so it is half true).
