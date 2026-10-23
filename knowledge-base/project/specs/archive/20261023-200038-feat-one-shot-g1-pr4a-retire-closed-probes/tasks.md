# Tasks: retire the followthrough probes whose tracker issues are closed (G1 PR-4a)

Plan: `knowledge-base/project/plans/2026-10-23-chore-retire-closed-followthrough-probes-g1-pr4a-plan.md`
Branch: feat-one-shot-g1-pr4a-retire-closed-probes. Draft PR #10937 (NOT armed; operator confirms). Epic #9294, ADR-241 D10, task 5.2.

HARD BOUNDARY: no edit to ci-deploy.sh, the webhook secret, `.github/workflows/git-data-cutover.yml`, track.sh, the Tier-B
loader, the bridge, `apps/web-platform/infra/cat-deploy-state.sh`, `inngest-soak-6178.*`, `sdk-bash-smoke-verdict-10548.*`. If a
step would need one of them, stop and report.

## Phase 0 - Preconditions

- 0.1 `git fetch origin main && git rebase origin/main`
- 0.2 Re-check trackers with `gh issue view`: #5875, #7220, #7296, #2640, #5863 closed; #6178, #10548 open. Stop and re-scope on any change.
- 0.3 Re-census: `git grep -n -i -E 'canary-promotion|infra-config-activation|infra-config-fatal-channel|workspace-isolation-verdict' -- . ':!knowledge-base/project'` and compare to the plan's Footprint tables.
- 0.4 Dump the bearer-sweep row labels from one full pre-edit run (about 5 minutes, background job, output to a scratch file) for the Phase 3 label diff.

## Phase 1 - RED first

- 1.1 Delete the five files: `scripts/followthroughs/canary-promotion-5875.sh`, `infra-config-activation-7220.sh`, `infra-config-activation-7220.test.sh`, `infra-config-fatal-channel-7220.sh`, `workspace-isolation-verdict-2640.sh`
- 1.2 Run the cheap locally-runnable guards: trio census, grep-q-pipe-guard, fixture-relative-assert, scripts-shard-manifest, lint-orphan-test-suites (not the bearer-sweep; the affected-audit baseline is CI-only)
- 1.3 Each must go red for the reason the plan's Footprint names. Investigate any guard that stayed green.

## Phase 2 - Registries

- 2.1 `tests/scripts/trio-baseline.tsv`: delete the 12 rows of the four deleted probes; keep the 6178 / 10548 / sweeper / github-app-key-status.sh rows
- 2.2 `scripts/test-all.sh`: delete the #7220 comment block and the `run_suite "scripts/infra-config-activation-7220"` line
- 2.2b `scripts/test-all.sh`: reword the following suite's comment that says it sits next to "the probe directly above"
- 2.3 `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` and their `.n` copies: `python3 scripts/regenerate-shard-manifest.py --incremental --write` (header change expected; confirm the only other diff is the one row per file)
- 2.4 `scripts/ci-pr-affected-audit.baseline.tsv`: delete the `scripts/infra-config-activation-7220` row
- 2.5 `plugins/soleur/test/fixture-relative-assert.baseline.txt`: delete the single activation `.test.sh` row by hand; leave the header prose
- 2.6 `.claude/hooks/grep-q-pipe-guard.test.sh`: delete the activation `.test.sh | python3` exempt row (the `PJ_TRIPLES` re-pin waits for Phase 3)

## Phase 3 - Bearer-sweep suite

- 3.1 `tests/scripts/test-argv-bearer-sweep.sh`: drop the four `HMAC_MANIFEST` rows (the 6178 row opens the string) and its header comment, the three `HM5_FILES` paths, the probe paths in the `hm_hmacflag` pathspec, and sweep every stale "four probes" / "four HMAC" / "four followthrough" / `hmx_refused` heading comment
- 3.1b BEFORE deleting `probe_rows_hmac`: add one parity-block E4 row (100,000-byte class-clean `CF_ACCESS_CLIENT_SECRET`, `SHIM_MODE=noread`, pipefail, against `check-deploy-script-parity.sh`; rc 0, a recorded call, no broken-pipe text) and add `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh` to `HM5_FILES` (CTO F7)
- 3.2 After `git grep -n 'probe_rows_hmac\|dynamic)\|hmx_sandbox'` shows no other caller: delete `probe_rows_hmac`, the `dynamic)` arm, `hmx_sandbox()` and the three fixture bodies (`canary_pass.json`, `workspace_isolation_pass.json`, `fatal_frame.json`); keep the `case` default, `hmac-cf`, `hmx_refused`, `hm5_mut`, `PYBAD`, `BIGTOK`, `SHIM_MUTATE`, `bk_calls`
- 3.3 Run once to green; diff row labels against the 0.4 dump as a multiset with counts normalized (removed = each deleted probe's rows, its hm5_audit and mutation rows and its delegated row; removed minus added = 880 minus the new floor); confirm `S4_GUARD_FLOOR` by `git grep -l '_bearer_ok() {'` before/after differing by exactly the four paths; repeat the label diff against `origin/main` after the final rebase; set `EXPECTED_TESTS` and `S4_GUARD_FLOOR` from that last green run (expected `S4_GUARD_FLOOR` 72), append this PR's delta to each ledger comment naming #10937
- 3.4 Re-pin `PJ_TRIPLES` (expected 287) with the documented recompute command and compare the before/after triple lists; re-run `grep-q-pipe-guard`
- 3.5 `scripts/guard-vacuity-floor.test.sh`: run; change `MIN_FIRING_SUITES` only if red

## Phase 4 - Comment pointers (wording: "retired by G1 PR-4a (#10937); history in git")

- 4.1 `.github/workflows/scheduled-followthrough-sweeper.yml` env comment only (name #6178 and #10548 as the declarers; the three env lines stay)
- 4.2 `.github/workflows/canary-status.yml` (three comments incl. the "only reads this after #5889's earliest window" line; no dollar sign, backtick or `${{` in the replacement; run the S3 rows of the bearer-sweep after the edit)
- 4.3 `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, `workspace-isolation-canary-probe.md` (keep the promotion criteria as prose: consecutive_pass >= 5 over >= 3 days; headings and anchors unchanged; expect an infra-validation run)
- 4.4 `plugins/soleur/test/preflight-discoverability-test.test.ts` (one code comment)

## Phase 5 - Verify and hand off

- 5.1 Trio census and bearer-sweep green; `test-infra-privileged-tier-census.sh` and `lint-orphan-test-suites.sh` green
- 5.2 `git diff --name-only origin/main...HEAD` checked against the HARD BOUNDARY list
- 5.3 PR body: first line "Deletes four retired followthrough probes and their guard rows; comment-only workflow edits; no production, Terraform or deploy-pipeline effect."; `Ref #9294`, no closing keyword; names the fifth probe already deleted by #10546, the retained #10548 probe, the `cat-deploy-state.sh` comment follow-up; states the PR is not armed
- 5.4 `ship`: file two follow-up issues - the `cat-deploy-state.sh` and untouchable-probe comment pointers, and the `deferred-scope-out` issue for the thinned HMAC coverage rows (milestone Post-MVP / Later, closes with PR-4 / task 5.3); comment on #9294 with the merged PR only after merge; the PR body notes that the `workspace_isolation` deploy-state field is now written but unread
