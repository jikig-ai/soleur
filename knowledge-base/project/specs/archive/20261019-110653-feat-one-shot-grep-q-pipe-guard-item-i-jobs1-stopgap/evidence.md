# Evidence: Item I (JOBS=1 stopgap, #7432, tracker #9217)

The verdict is always the `main-health-outcomes` check-run annotation, never the run or job conclusion (`continue-on-error: true`
pins those to success). Raw data was pulled to `/var/tmp/item-i-*` during the work phase and is not committed; the review cut the
measurement scripts (evidence-only, nothing runs them after merge). To re-derive a figure, list runs with
`gh run list --workflow main-health-monitor.yml --branch main --limit 300 --json databaseId,status,conclusion,createdAt,event`,
read each run's `health-check` job annotations (`gh api repos/jikig-ai/soleur/check-runs/<job id>/annotations`), and read job
logs with `gh api --allow-escape-sequences repos/jikig-ai/soleur/actions/jobs/<job id>/logs` (the flag is required on gh 2.102).
A re-pull today will not reproduce the figures below exactly: older runs leave the 300-run window.

## Figures (one pull, 2026-10-16 20:10Z, controls passed)

- M1 (300 monitor runs on main): infra step 171 ok, 81 killed at the 60-minute ceiling, 17 RED without a timeout, 31 no verdict
  (22 cancelled, 7 predating the annotation, 1 in progress, 1 unclassified). A ceiling kill does report a verdict
  (`infra=failure`, no `infra_elapsed_s`): the sample is censored, not silent. 81 of the 269 steps that could deliver a verdict
  (30%) were killed (a recount by another definition gives 271 verdict-bearing runs; the 81 is the same). Tests step killed at
  its ceiling in 129 of 300 at this pull (cause #9410, separate).
- M2: `deploy-script-tests` legs at `-P 4` on push to main since 2026-09-25: 688 executions, 609 success, 75 failure, 4 cancelled.
- M3: 84 suite REDs (23 isolated single-push suite-events, 61 chained) over 169 runs; isolated events 0.136 per run, an upper
  bound that includes one-commit regressions and 3 events of the tag-drift suite the probe allowlists (without them 0.118).
- M4: 15 paired same-sha comparisons, 3 informative, 0 RED at `-P 4` and clean at `-P 1`, 0 the other way. This cannot rule a
  parallel-only RED out; the soak is the instrument.

## Dispatch gate (all `dry_run=true`, infra step at `-P 4`, 179 suites)

| run | head sha | infra | elapsed | breakdown | RED | note |
|---|---|---|---|---|---|---|
| 38942396026 | 4bed166006 | failure | 1890 s | 178/179 | `web-host-provisioner-parity-mutation.test.sh` rc=124, 361 s | cold shape (the diff touched no infra path), so the timeout is not a warm-state artifact |
| 38942417986 | 4bed166006 | failure | 1866 s | 178/179 | same suite rc=124, 360 s | same |
| 38965464152 | e466270ed9 | success | 1433 s | 179/179 | none | launched under a conditional ruling that did not apply; no gate credit |
| 39086879796 | ca32a51740 | success | 1881 s | 179/179 | none | RE-GATE A, cold shape |
| 39086881468 | ca32a51740 | success | 1666 s | 179/179 | none | RE-GATE B, cold shape |

Runner: all five ran on `ubuntu-latest`, which resolved to the `ubuntu-24.04` image 20261012.334.1 (read from run 39086879796's
log). The monitor is now pinned to `ubuntu-24.04` (the `ubuntu-latest` label moves to a newer image on 2026-10-19, inside the
soak); the pin is a semantic no-op against these runs. The tests step hit its own 110-minute ceiling in all five runs (#9410), so
the infra step always ran after it on the same runner. The job log of run 39086879796 carries exactly one
`Running 179 registered infra suite(s) with -P 4` line, at the infra step, so no nested infra runner ran in the tests step.
Each pair was serialised by the workflow's `main-health-monitor-dry-run` concurrency group.

Pre-dispatch check (CTO constraint): `git diff --name-only origin/main...HEAD` matched no `apps/` path and not
`apply-web-platform-infra.yml` at sha ca32a51740. After that sha the review round changed the workflow by comments and one
`runs-on: ubuntu-24.04` pin (a CTO-ruled bounded exception, no re-dispatch: it resolves to the image the five dispatches ran on),
and rewrote the guard and the probe, neither of which is on the dispatched path.

### What the two green re-gates do and do not show

They are two samples from a weekend-heavy span (Fri 2026-10-16 17:49Z to Sun 2026-10-18 05:47Z, which includes a US Friday
afternoon; no weekday-peak sample; parity-mutation has only 3 uncensored durations: 240, 424, 481 s). Slowness is a shared
run-level factor (total suite-seconds ranged 4474 to 6242 across the five runs). Each suite's longest reconstructed duration
over its bound (the maxima come from different runs):

| suite | longest / bound | ratio |
|---|---|---|
| web-host-provisioner-parity-mutation | 481 / 540 | 0.89 |
| cloud-init-inngest-zot-pull-mutation | 475 / 540 | 0.88 |
| infra-config-repush-mutation | 468 / 540 | 0.87 |
| workspaces-boot-unlock | 766 / 900 | 0.85 |
| run-registered-suites.test.sh (360 s default) | 281 / 360 | 0.78 |
| ci-deploy | 410 / 540 | 0.76 |

The step wall (1666 to 1881 s against 3600 s) has 1.9 to 2.2x headroom; the per-suite bounds are the tight constraint at `-P 4`.
That is why the bounds are widened in a separate PR (#10486: parity, repush and zot-pull 540 to 720, boot-unlock 900 to 1200,
a new 540 entry for `run-registered-suites.test.sh`; about 1.5x of the observed maximum, 1.9x for the new entry; a judgement
and not a measured ceiling). It MUST merge before the soak starts: until it does, the soak runs on the bounds above and each
bound-kill counts as a strike. The soak, not these two runs, is the instrument for headroom.

## The one RED and its fix

`web-host-provisioner-parity-mutation.test.sh` (143 rows, serial) ran 171 s alone on 4 pinned cores
(`taskset -c 0-3`) and 401 s beside three other heavy suites running concurrently (`workspaces-luks-provision`,
`workspaces-boot-unlock`, `infra-config-repush-mutation`) — one contended sample; the siblings took 360, 482 and over 560 s. It
carried no `_SUITE_BOUNDS` entry (360 s default). PR #10478 added 540 s; the re-gate then observed 481 s (1.12x), which PR #10486
widens. Both are separate PRs because an edit under `apps/web-platform/infra/` puts that path in the branch diff, which makes the
monitor's tests step run the nested infra runner and warm the standalone infra step; a dispatch from such a branch would not
measure the cold shape the scheduled monitor has on main.
