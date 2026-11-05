# Tasks: invert the egress-gateway probe-silence alert metric (Ref #12180)

Plan: `knowledge-base/project/plans/2026-11-05-fix-egress-gw-probe-silent-invert-metric-plan.md`

## Phase 1: Tests first

- 1.1 Rewrite the G2 block of `apps/web-platform/test/infra/egress-gw-alert.test.sh` to the new canon; add the G2b canary block and its mutation rows (Guard 1 matrix, 13 rows); confirm RED against the unchanged `.tf`.
- 1.2 Write `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` (PATH-shimmed `curl`/`gh`, synthesized fixtures, Guard 2 matrix); confirm RED with the probe absent.

## Phase 2: Production change

- 2.1 Edit `apps/web-platform/infra/betterstack-logs-alerts.tf`: new SQL local, silent alert operator/value/`incident_cause`/comments, canary local (after the fail local), canary exploration and alert, flip-silent comment refresh.
- 2.2 Add the two canary `-target` lines to `.github/workflows/apply-web-platform-infra.yml`; check `wc -c` is at most 490000.
- 2.3 Re-prove the final SQL read-only (healthy 0, web-2 only 1, canary identifier 2); counts only in the PR body.
- 2.4 Read the live Logs alert count read-only (names and counts only); record in the ADR amendment.

## Phase 3: Dependent exact counts

- 3.1 `logs-alert-query-period-ceiling.test.sh`: `EXPECT_BLOCKS` 18 to 19; re-derive `MIN_PASSES`.
- 3.2 `betterstack-send-failed-alert-mutation.test.sh`: `count == 18` to `19` and the comment list.
- 3.3 Run `apps/web-platform/infra/betterstack-alert-structure.test.sh`; edit only on red.
- 3.4 Re-derive `PRESENCE_ROWS` and `MUT_ROWS` in `egress-gw-alert.test.sh` at both write sites each.
- 3.5 Reword the header comment (lines 35-37) of `inngest-cutover-flip-silent-alert.test.sh`; leave pinned strings alone.

## Phase 4: Probe, registration, docs

- 4.1 Write `scripts/followthroughs/egress-gw-probe-silent-12180.sh` (verdict table in the plan; `RETIREMENT:` header line); register like the 8097 probe (`scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/lint-betterstack-emitter-read.sh`).
- 4.2 Reword the comment above the egress step in `.github/workflows/infra-validation.yml`; keep the step name.
- 4.3 Update `cron-egress-blocked.md` (section `soleur-egress-gw-probe-silent-prd`) and `betterstack-log-query.md` (egress bullet; flip-silent stuck-at-0 sentence); label the zero-fill mechanism an inference.
- 4.4 Append the ADR-218 amendment (inverted absence-alert rule, canary, decision rule, residuals, alert count).
- 4.5 At ship: add the `follow-through` label and column-0 directive to the tracker issue; dry-run the sweeper.

## Phase 5: Verify

- 5.1 Run the suites listed in the plan's Phase 5, `c4-count-parity.test.sh`, `workflow-file-size.test.ts`, `lint-guard-contract.py`, then the affected-tests runner.
- 5.2 PR body: `Ref #12180` only, inference disclosure, proof counts, expected plan counts, `## Changelog`.

## Post-merge (probe-verified)

- Apply completion plus 25 minutes: `soleur:postmerge` runs the probe once and reads `canary=`; `canary=absent` means build the poller (file the issue at once) and keep the production alert armed.
- Once `canary=fired`, the follow-up PR (tracker #12189) deletes the canary (RETIREMENT list in the probe header); incident 1047829421 must resolve on its own and stay clear for 4 hours (sweeper probe, earliest at apply completion plus 4h30).
