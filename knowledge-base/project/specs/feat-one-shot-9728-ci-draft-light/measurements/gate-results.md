# Entry gate results for S3 (#9728), recorded 2026-10-09

Probe: two throwaway draft PRs (a scratch branch that deletes the PR-triggered workflows and adds one probe workflow,
`zz-s3-probe`, whose job `test` reproduces the production topology: the draft push concludes red, the `ready_for_review`
run is slow and then green). Both PRs were closed unmerged and their branches deleted (verified: no open PR, no remote
branch left). Raw reads are in `gate-probe-snapshots/`.

## Gate 1 - required-status rollup with two same-name rows: CLEARED

Question: with a red `test` row from the draft run and a newer `test` row from the `ready_for_review` run on the SAME SHA,
does the older red row keep blocking after the newer one is green?

To make the ruleset's own evaluation observable (not just `gh`'s view), the probe also posted every OTHER required context
from github-actions (a matrix job named with each context, integration 15368), so a green `test` could make the PR
mergeable. A first attempt had a quoting bug in my probe step (three contexts red) and a second ran while the branch was
behind `main` (`BEHIND`); the third, clean cycle is the one recorded here (`gate1c-*`).

| Read point | `test` rows on the SHA | `mergeStateStatus` | `gh pr checks --required` `test` bucket |
|---|---|---|---|
| B3 just after `gh pr ready`, ready run in flight | old red only | BLOCKED | fail |
| C3 ready run's `test` row pending (queued) | old red + newer pending | BLOCKED | pending |
| D3 ready run's `test` row green | old red + newer green | **CLEAN** (MERGEABLE, repeated 3 reads) | pass |

Decision: the newest `test` row per name decides. Red blocks while a newer row is pending (so a draft's red cannot
admit the PR), and clears the moment the newer row is green (so Option R is usable, no tolerance arm needed). The
GraphQL `statusCheckRollup.state` still reads FAILURE while the older red row is listed (first cycle, `gate1-D-rollup.txt`),
so any reader built on the rollup's aggregate state misreads a decided PR: that is exactly the class `ci-head-verdict.sh`
(Phase 7) exists for.

Sub-scenarios not probed live, with reasons: (i) a failed-job re-run of the pre-ready run while the ready run is in flight:
the per-ref concurrency group (cancel-in-progress on `pull_request`) makes this a cancel-the-in-flight-run action; the plan
already classifies it as NOT a recovery, so nothing depends on probing it. (ii) a bot-posted same-name synthetic `test`:
synthetics are posted by the same integration (15368) as the real row, so the same newest-row rule applies; no new fact.
(iii) arming auto-merge on the throwaway: the probe PR became CLEAN and MERGEABLE once the required set was satisfied, so
arming it could have enqueued and merged a PR that deletes 21 workflows. It was never armed and was closed at once;
the arm-then-register hazard is covered by gate 4's wait step instead.

## Gate 2 - `gh pr ready` token identity: CLEARED

(a) A user-token `gh pr ready` (operator's `gh` login) created a `ready_for_review` run every time (3 samples, below).
(b) A probe step that readied its own PR with `GITHUB_TOKEN` was refused by the API:
`API call failed: GraphQL: Resource not accessible by integration (markPullRequestReadyForReview)`
(job `selfready`, PR 9894, run 37986243717): `GITHUB_TOKEN` cannot produce a ready event at all, so it cannot create the
`ready_for_review` run either. The wait step therefore only has to handle user-token callers. The caller census in the plan
stands (no `gh pr ready` in tracked code under `.github/`, `apps/`, `scripts/`).

## Gate 3 - variables on fork `pull_request` runs: ANSWERED BY DESIGN

`draft-light` requires `head.repo.full_name == repository` before it can emit `light=true`; a fork run therefore runs full
whether or not repository variables reach it. No live probe (no second GitHub identity available). Asserted in Guard 1.

## Gate 4 - arm-then-register window: CLEARED, wait step ships regardless

Server-side ready event time to the created time of the `ready_for_review` run: +3 s (20:14:26 to 20:14:29), +3 s
(20:39:18 to 20:39:21), +2 s (21:17:19 to 21:17:21): the minimum is positive, so the planned 5-second skew allowance
(accept runs created at or after the ready time minus 5 s) holds with margin. The timeline showed the new
`ReadyForReviewEvent` 1 s after `gh pr ready` returned (first sample). Hosted runners were starved during the probe: the
ready run's `test` row stayed queued for about 5 minutes and ended at 21:33 (about 16 minutes after the ready call, with the
probe's own 150 s sleep); the real aggregator takes 38 to 51 minutes of runner time. Wait timeout stays 300 s, stall
threshold N stays 75 minutes (widened, never narrowed).

## Gate 5 - `--admin` path and consumers: DEFERRED TO PHASE 7 FIXTURES; 5b ANSWERED

`admin-merge-ready.sh` refuses a PR that edits workflows (`UNTRUSTED-CI`), so its readiness logic is driven through its
stubbed fixtures in Phase 7, not live.

**5b: the Soleur GitHub App delivers `workflow_run` for this repository.** Read with an App JWT (`GET /app` and
`GET /repos/jikig-ai/soleur/installation`): app `soleur-ai`, installation 122213433, `repository_selection: all`, not
suspended, subscribed events `issues, pull_request, push, repository_advisory, secret_scanning_alert, workflow_run`.
`apps/web-platform/app/api/webhooks/github/route.ts` gates `workflow_run` on `conclusion == failure` only. Under Option R
every draft push concludes `failure` (the draft `test` aggregator is red by design), about 100% against 12.8% of draft
pushes failing today (census: 414 of 3,203), so each would reach the `engineering.ci_failed` handler. 5b is therefore a HARD
precondition of activation and of the canary (plan Phase 3 row 5b, Phase 9): a route filter that drops `workflow_run`
events whose run is a draft PR's `pull_request` run ships before the variable is set.

## Gate 6 - cheaper alternative (the census): PASS

See `draft-push-census-2026-10-09.summary.txt`: 408 draft PRs, 3,203 draft pushes, mean 7.85 distinct-SHA draft pushes per
draft PR (median 7), policy floor 6.84, both at or above 2.75; 30 of 30 slices reconcile. Informational minutes line
(not a verdict input), from `ci-yml-pr-run-minutes-2026-10-08.txt` (178 `pull_request` runs, 2026-10-08): the four gated
families cost 89.82 job-minutes a run and the rest of the run 14.26, so a light run saves about 75.6 minutes. At 7.85 draft
pushes per drafted-then-readied PR the saving is about 7.85 x 75.6 = 593 minutes against one extra full ready run
(about 104 minutes), a net of about 490 minutes per drafted-then-readied PR. `test-bun` is 1.81 minutes a run (not above 3,
so not gated) and `e2e` 3.14 (untouched).

## Erratum 2026-10-10 (review of #9885): the Gate 6 minutes line

Appended, not edited: the paragraph above is left as written.

- "a light run saves about 75.6 minutes" subtracts the light-set cost (14.26) from the gated cost (89.82), but the light set is paid in BOTH the full and the light run, so it must not be subtracted. The saving per push is the gated-family cost less the `draft-light` job, about 89.7 on the same basis. ADR-276 S3 Decision 3(e) uses the correct form (7.85 x 104.08 before against 7.85 x 14.4 plus one 104.08 ready run after).
- Denominator: the per-run figures divide minutes of all 209 runs by the 178 that had jobs. On the 209-run basis the figures are full 88.6, gated 76.5, light 12.1, break-even near 1.4 pushes and a net near 496 job-minutes per drafted-then-readied PR at 7.85 pushes. The 7.85 x 75.6 = 593 minus 104 = 490 figure above is right only by coincidence.
- "12.8% of draft pushes failing (census: 414 of 3,203)": 414 / 3,203 is 12.9%; 12.8% is the planning-pilot figure (448 of 3,501).
- No verdict changes: Gate 6 turns on pushes per PR, not minutes. The unit is job-minutes (not billing-rounded); a billed estimate puts the saving per push near 79%, recorded beside the 80% criterion in the ADR.
