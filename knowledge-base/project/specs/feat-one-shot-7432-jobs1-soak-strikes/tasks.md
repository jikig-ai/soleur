# Tasks — chore: disposition the two JOBS=1 soak strikes (#7432, #10654)

Plan: `knowledge-base/project/plans/2026-10-20-chore-jobs1-soak-strike-disposition-plan.md`

## Phase 0 — ruling check
- [ ] Read `decision-challenges.md` fork row; if still `pending`, spawn `soleur:engineering:cto` with the packaged evidence before touching the probe

## Phase 1 — `_SUITE_BOUNDS` entry (either arm)
- [ ] Add `"apps/web-platform/infra/git-data-wipe-assert.test.sh=720"` to `_SUITE_BOUNDS` in `apps/web-platform/infra/run-registered-suites.sh` with a comment citing #10654, #10523's growth, the two bound-kill run ids, and the 162 s serial measurement (dev host, faster-than-CI caveat)

## Phase 2 — Arm A only (fork rules reproducing-in-intent)
- [ ] Set `JUDGED_REPRODUCING_RUNS="39378082716 39446197504"` in `scripts/followthroughs/jobs1-stopgap-7432.sh` + one-line comment citing H4/ATTRIBUTION/#10654
- [ ] Re-anchor the four `mutate` needles in `scripts/followthroughs/jobs1-stopgap-7432.test.sh` (R4b3 ~L261, R4q ~L290, K12 ~L423, K22 ~L445) in the same commit; re-run the suite green
- [ ] Re-run the probe with `SOLEUR_FT_EARLIEST=2026-10-19T18:00:00Z` + live `GH_TOKEN`: expect exit 2 NOT YET (never 5 unless a new run struck — record, don't mask)

## Phase 3 — issue comment on #7432
- [ ] `gh issue comment 7432`: soak 4/12 counted (2 clean, 2 struck) + 1 in flight, strike disposition, grep -q re-evaluation measurement, standing re-evaluate triggers

## Phase 4 — ship
- [ ] PR body: `Ref #7432` + `Closes #10654`, measurement, dispositions, ruling line
- [ ] `python3 scripts/lint-guard-contract.py` on the plan; `npx markdownlint-cli2` on plan + tasks

## Phase 5b — Arm B only (fork rules letter-stands non-reproducing)
- [ ] Restore infra-step `JOBS` pin in `.github/workflows/main-health-monitor.yml` + flip guard (12b) in `plugins/soleur/test/main-health-monitor-workflow.test.sh`; note on #9217
