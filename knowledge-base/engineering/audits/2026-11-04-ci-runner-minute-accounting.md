# CI runner-minute accounting — 2026-11-04

Issue #12030 (hosted-runner starvation dequeued green PRs from the merge queue). This audit answers the issue's open investigation list: the concurrency cap, runner-minutes per workflow, and a ruling on every demand lever. The 120-minute queue timeout stopgap is already live on main (`infra/github/ruleset-ci-required.tf`, `check_response_timeout_minutes = 120`, ADR-270 addendum 2026-11-03).

Result in one sentence: **no safe demand-trim code lever is left in `ci.yml`, `tenant-integration.yml` or `infra-validation.yml` beyond the shipped ADR-276 stages S2 and S3; the residual risk is runner supply (delivered concurrency), tracked as operator decisions in #12090.**

## 1. Concurrency cap (verified)

Source: <https://docs.github.com/en/actions/reference/limits>, fetched 2026-11-04. Total concurrent jobs, standard GitHub-hosted runners: Free 20, Pro 40, Team 60, Enterprise 500. Larger runners: 1,000 on Team, a separate pool billed per minute. The org reads `plan.name=team`:

```bash
gh api orgs/jikig-ai --jq '{plan: .plan.name, seats: .plan.seats}'
```

ADR-276 Context already recorded the same Team = 60 figure on 2026-10-07; only the issue text and the ADR-270 addendum still said "not verified".

## 2. The cap was not the limiter; delivered concurrency was

90 half-hourly `scheduled-actions-queue-health` samples (2026-11-02T23:30Z to 2026-11-04T17:30Z; `scripts/actions-queue-health.sh` output in the `[ci/actions-queue-health]` issue history): 88 HEALTHY, 1 SATURATED (2026-11-04T00:30Z, 38 queued, 31 in flight), 1 UNDER_ASSIGNED (2026-11-03T22:52Z, 100 queued, 26 in flight against a cap of 60, median live queued age 998 s). Only 5 of 90 samples had 55 or more jobs in flight and none reached 60; 20 of 90 had a median live queued age of 300 s or more. The issue's own snapshot (60 running, 222 queued at 2026-11-03T21:32Z) sat exactly at the cap, but the two deep-queue episodes show 26 and 31 jobs in flight, so the scheduler delivered well under the entitlement. That is a supply-side problem; demand trimming cannot fix it.

## 3. Runner-minutes per workflow

Reproduce any row with `scripts/ci-demand-census.sh --start <ISO> --end <ISO> --summary` (at most 12 hours per census; windows are start-inclusive, end-exclusive) or the named `gh api` query.

### 3.1 Quiet-window census

Window 2026-11-04T10:00Z to 16:00Z: 2,290.8 runner job-minutes, 344 runs. Note the window overlaps busy hours 10 to 15 UTC, so it is a Wednesday-midday sample, not an overnight trough.

| Workflow and event | Job-minutes | Runs |
|---|---|---|
| `ci.yml` merge_group | 1,121.7 | 3 (105 jobs) |
| `main-health-monitor.yml` | 376.8 | 1 |
| `ci.yml` pull_request | 283.0 | 1 |
| `scheduled-supabase-watchdog.yml` | 169.8 | 71 |
| `tenant-integration.yml` push | 48.5 | |
| `ci.yml` push | 40.3 | |
| CodeQL | 40.2 | |

### 3.2 Peak window

Window 2026-11-03T19:00Z to 22:00Z (the evening peak of the 2026-11-03 starvation episode), censused in two 90-minute halves because a single pull aborted earlier on a persistent HTTP 502; both halves completed (exit 0, 0 runs not completed), so these figures are census-grade, not sampled. Total 10,739.9 runner job-minutes (5,546.1 + 5,193.8) over 1,269 runs (506 + 763). Reproduce:

```bash
bash scripts/ci-demand-census.sh --start 2026-11-03T19:00:00Z --end 2026-11-03T20:30:00Z --summary
bash scripts/ci-demand-census.sh --start 2026-11-03T20:30:00Z --end 2026-11-03T22:00:00Z --summary
# sum the BY_WORKFLOW rows of the two outputs by (workflow, event); do not add rounded per-run figures
```

| Workflow and event | Runs | Job-minutes | Share |
|---|---|---|---|
| `ci.yml` pull_request | 92 | 5,312.7 | 49.5% |
| `ci.yml` merge_group | 3 | 1,252.2 | 11.7% |
| `pr-quality-guards.yml` pull_request | 92 | 792.9 | 7.4% |
| CodeQL (dynamic) | 86 | 725.9 | 6.8% |
| `secret-scan.yml` pull_request | 93 | 627.2 | 5.8% |
| `infra-validation.yml` pull_request | 22 | 501.5 | 4.7% |
| `tenant-integration.yml` pull_request | 83 | 310.5 | 2.9% |
| `vendor-pin-verify.yml` pull_request | 83 | 214.6 | 2.0% |
| `apply-sentry-infra.yml` pull_request | 83 | 173.8 | 1.6% |
| `cla-evidence.yml` pull_request_target | 85 | 150.7 | 1.4% |

`ci.yml` is 61.2% of the peak minutes and `infra-validation.yml` 4.7%; no workflow outside `ci.yml` and `infra-validation.yml` is above 15% (the next is `pr-quality-guards.yml` at 7.4%). `main-health-monitor.yml` does not fall in this window (its `0 */6 * * *` slots are 00, 06, 12 and 18 UTC). Cancelled share: from the raw job rows of the same census data, 45% of the `ci.yml` pull_request job-minutes belong to cancelled jobs (4,095 of 9,094 job-minutes by job conclusion). That ratio is not census-grade: the raw job rows sum to more minutes than the census (which excludes runnerless and skipped rows), so quote the ratio, not the absolute. It is well above the plan's 20% contradiction threshold, so the quiet-window shares hold at peak and nothing here reopens the lever rulings.

### 3.3 Per-run cost (sampled; not census-grade)

- `ci.yml` merge_group run: about 375 job-minutes; `test-scripts` (8 legs, about 34 min each) is 269 of it, `test-webplat` 37, `test-scripts-heavy` 29, `shard-totality-mutations` 13. With `max_entries_to_build = 2` two such candidates can build at once.
- `ci.yml` pull_request run, 81 sampled runs: success 330.5 job-minutes (26 runs, median 344, about 40 jobs), failure 159.4 (20 runs), cancelled 105.1 mean and 6.2 median (35 runs). About 258 PR runs a day, 57% cancelled (396 of 698 PR runs, 2026-11-01 to 2026-11-04). Estimated CI PR demand about 43,000 job-minutes a day, of which cancelled runs about 15,000 (about 35%).
- Number bases: the daily estimate re-weights the sample by the observed mix (258 x 0.57 x 105 = about 15,400 cancelled; the other 111 runs x about 255 = about 28,300; total about 43,700). The cancelled-run lifetime sample (60 runs, 4,884 job-minutes, mean 81) is a different draw from the 35-run cancelled mean of 105. A green sample is not the all-runs basis ADR-276 used on 2026-10-07 (about 100 job-minutes per PR run); the cause of the 330 versus 100 difference is **not measured** and is handed to epic #11556.
- `main-health-monitor.yml`: 376.8 job-minutes per run, 16 jobs, 4 runs a day (`0 */6 * * *`), about 1,500 job-minutes a day (about 3%).
- `infra-validation.yml` pull_request run: success 55.6 job-minutes (`deploy-script-tests` 4 legs 41.9, `deploy-script-tests-fixed` 9.2), failure 53.9, cancelled 17.4 mean; about 73 PR runs a day, 41% cancelled.
- `tenant-integration.yml` pull_request run: success 2.2 job-minutes, cancelled 0.5 (a cheap `detect-changes` job gates the heavy suite).
- `infra-validation.yml` `deploy-script-tests` leg time, re-measured over the 10 most recent green pull_request runs (40 legs; reproduce with `gh run list --workflow infra-validation.yml --event pull_request --status success -L 10`, then each run's jobs filtered to `deploy-script-tests (N/4)`, `completed_at - started_at`): minimum 5.9 min, median 10.1, p95 13.4, worst 14.0 min. The workflow comment still records the 6.7-minute figure it was set against; the 15-minute ceiling is now about 1.07x the worst leg. The p95 is above the plan's 12-minute raise-to-20 trigger, so the raise is tracked in #12091.

### 3.4 Cancelled pull_request run lifetime

60 cancelled `ci.yml` PR runs, 4,884 job-minutes: runs ending within 5 minutes hold 2% of the cancelled minutes, within 20 minutes 6%, within 40 minutes 26%, so 74% of the cancelled waste sits in runs that lived longer than 40 minutes. A start-delay (settle or debounce) gate would therefore save almost nothing.

### 3.5 Hour-of-day load

`ci.yml` pull_request runs weighted 1 plus merge_group runs weighted 3 (a rough cost proxy: about 375 versus about 150 job-minutes), UTC hours, from the newest runs. Reproduce: `gh run list --workflow ci.yml -L <N> --json createdAt,event`, then sum the weights by `createdAt[11:13]`.

| Window | Hourly weighted load, h0 to h23 |
|---|---|
| Newest 2,600 runs (2026-10-27T12:48Z to 2026-11-04T18:31Z) | 87, 51, 49, 36, 28, 37, 50, 71, 179, 275, 161, 146, 115, 149, 180, 127, 139, 244, 170, 139, 184, 155, 186, 78 |
| Newest 700 runs (about 2.7 days) | 32, 25, 32, 17, 16, 20, 39, 34, 37, 38, 29, 15, 19, 25, 27, 20, 29, 77, 35, 31, 65, 56, 93, 35 |

Three-hour overlap load by cron offset `0` to `5` (the current `main-health-monitor` slot is offset 0, `0 */6 * * *`): 2,600-run window 1424, 1595, 1699, 1612, 1441, 1337; 700-run window 401, 407, 459, 445, 439, 387. Offset 5 (05/11/17/23 UTC) is the lowest in both windows, by 6.1% and 3.5%: too small to justify a six-file cron change plus a Sentry Terraform apply, so no cron change ships.

## 4. Lever rulings

Rulings by the CTO agent, 2026-11-04 (rows in `knowledge-base/project/specs/feat-one-shot-12030-ci-runner-starvation/decision-challenges.md`).

| Lever | Ruling | Measured reason |
|---|---|---|
| 1a `main-health-monitor` cadence or tree-identity skip | No change | The hour-of-day gain is 3.5% to 6.1% (section 3.5); a tree-identity skip adds new proof logic to the Sentry check-in contract of the un-gated backstop (ADR-181, ADR-262). |
| 1b Late-cancel waste (settle or debounce gate) | No change | 74% of cancelled minutes sit in runs that lived over 40 minutes (section 3.4). |
| 1c `infra-validation.yml` triggers or draft skip | No change; comment re-measure only | Every `paths:` entry guards a named drift suite (#10032, #10065, #10138, #10445); there is no `ready_for_review` trigger, so a draft skip would leave no run at ready. The leg-time comment is re-measured; the ceiling raise is #12091. |
| 1d `ci.yml` shard count K | No change | K trades about 60 s of per-leg overhead against wall clock; fewer legs lengthen the `merge_group` critical path toward the 120-minute timeout; the manifest and shard-totality tests pin K. |
| 1e `tenant-integration.yml` | No change | 2.2 job-minutes per PR run (section 3.3). |
| S4 affected-only PR runs (#9729) | Out of scope | Operator-gated; NO-GO on index completeness (ADR-276 amendment 2026-10-16, #10448). |
| `max_entries_to_build` (currently 2) | Not evaluated here | A queue-throughput trade owned by ADR-270 (raise checklist); lowering it lengthens every merge. Candidate cost measured: about 375 job-minutes per `merge_group` run. |
| Suite minutes (`test-scripts` suites 12% to 190% over committed prices; `scripts/suite-durations.tsv` stale) | Out of scope | Owned by epic #11556 Lever A (2026-11-03 top-15 report); the PR-run-cost finding is handed over there. |
| 5-minute `scheduled-supabase-watchdog` dispatch (71 runs, 169.8 job-minutes per 6 h, about 7% of the quiet window) | Out of scope | Cron fleet, not one of the three named workflows; each cadence protects a named detection window. Recorded here only. |
| Supply: larger runners; GitHub support ticket on under-assignment | Operator decision | Spend and vendor contact; tracked in #12090 with the 2026-11-03T22:52Z sample. |

## 5. Follow-ups

- #12090 (`deferred-scope-out`): larger hosted runners for the `test` aggregator and tail gate jobs, and a GitHub support ticket about under-assignment. Re-evaluate when an UNDER_ASSIGNED verdict or a `checks_timed_out` removal recurs after the 2026-11-03 raise.
- #12091: raise `deploy-script-tests` `timeout-minutes` 15 to 20; its trigger (p95 over 12 minutes) is already met.
- Epic #11556: PR-run-cost finding handed over (comment posted 2026-11-04).
