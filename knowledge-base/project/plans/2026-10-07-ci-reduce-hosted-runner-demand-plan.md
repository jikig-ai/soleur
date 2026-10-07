---
title: "ci: reduce hosted-runner demand (draft-PR light checks, affected-only PR gate, fan-out trim)"
date: 2026-10-07
slug: ci-reduce-hosted-runner-demand
branch: feat-one-shot-ci-hosted-runner-demand
issue: 9721
closes: 9721
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# ci: reduce hosted-runner demand (draft-PR light checks, affected-only PR gate, fan-out trim)

## Enhancement Summary

**Deepened on:** 2026-10-07. **Agents used:** repo-research-analyst, learnings-researcher, CTO (lever 5 and devex), DHH, Kieran, code-simplicity (plan review); architecture-strategist and spec-flow-analyzer (deepen pass).

1. Measurement corrected: runner-bound job-minutes are 7,456 (an unfiltered pass said 9,392); cancelled jobs that held a runner are only 4%.
2. Stage 1 left this PR; the ranking now states net or gross per lever; S2 push-main dedupe (up to 1,018) leads.
3. New S3 risks found by the deepen pass: the agent `--admin` merge path bypasses the queue, the arm-after-ready window, and an all-skipped run concludes `skipped` (so S2 must keep a real job). Option R (red draft `test`) is the preferred design.
4. ADR-276 gains a staged-acceptance rule so one stage cannot activate the others.

## Overview

Hosted-runner supply is saturated in bursts and per-push CI demand is the driver. This plan
re-measures where the runner job-minutes go, ranks the demand levers by measured saving, and proposes
ADR-276 (status `proposed`) plus a staged, dark-launch-first rollout, one lever per PR. Supply options
(lever 5) are a separate memo reviewed by the CTO agent; nothing is provisioned. This PR is the plan
phase: it writes only plan, spec, ADR proposal and memo files. Lever 1 (BEHIND-sync pushes, #8683) is
out of scope and only referenced.

Spec note: no `spec.md` exists for this branch, so `lane:` defaults to `cross-domain` (fail-closed).

## Research Reconciliation: brief vs. codebase

| Brief claim | Reality (checked on this branch) | Plan response |
|---|---|---|
| 59 running / 289 queued, `CI` 35/194 | Reproduced only as a peak. Over the 6h window 13:04Z to 19:04Z: mean 21.4, p90 57, peak 60 concurrent; 77 of 349 minutes at 55+. Right now 14 runs in progress and 2 queued. | State saturation as bursty (22% of minutes at the cap), not constant. |
| 478 PR runs, "count JOBS not runs" | Runs overstate: 514 of 661 cancelled jobs never got a runner (`runner_id` 0) and their start-to-finish span is queue time. An unfiltered pass reported 9,392 job-minutes; runner-bound is 7,456. | Every number below is runner-bound; the census script (Stage 1) bakes the filter in. |
| "Light checks on DRAFT PRs" is untried | No workflow filters on `draft`; only `board-status-sync.yml` and `claude-code-review.yml` (disabled on GitHub's side since 2026-02-12, 0 minutes in the window) list `ready_for_review`. `ci.yml` uses default `pull_request` types, so marking ready triggers nothing today. | Lever 2 must add `ready_for_review` to `ci.yml` types, or a drafted-then-readied PR would merge-queue on light results. |
| Lever 3 is greenfield | ADR-262 already path-gates five batteries on PRs (shipped, #9323 follow-through due 2026-10-09). `--print-selection` (#9307) and ADR-242 `--affected` exist. | Lever 3 extends the ADR-262 call-site opt-in to the affected set; it does not re-do the battery gate. |
| Fan-out of ~12 workflows per push | Median 10 workflows per PR head (max 14, 54 heads). Infra Validation is already workflow-level path-gated (18 of ~54 heads trigger it); Tenant integration has a detect job. | Drop "path-gate Infra Validation" from lever 4. |
| `cancel-superseded-pr-runs.yml` handles superseded heads | Confirmed: cancelled jobs that held a runner cost 304 of 7,456 job-minutes (4%). The loss from cancellation is queue time, not minutes. | Out of scope; do not re-solve. |
| #9512 is a low-priority duplicate-run item | Push-main `CI` is 1,018 job-minutes (13.7%), the largest single removable duplicate, and gate-neutral for merging. | Rank it first by measured minutes; keep it a separate PR owned by #9512. |

## Research Insights

### Premise validation (Phase 0.6)

Checked: #9721 open and unbranched; #8683, #9323, #9512, #9307, #9410, #9497 all open; draft PR #9722
open; next free ADR is 276 (latest 275 on `origin/main`; no open PR carries an ADR above 275).
Repo is public (`gh api repos/jikig-ai/soleur --jq .visibility` returns `public`). ADR corpus grep for
the proposed mechanisms: ADR-262 already holds the PR-vs-main coverage split for batteries and ADR-270
holds the merge-queue authority and the advisory-CodeQL decision; neither rejected draft-light checks
or a push-run dedupe. Stale premise found and corrected: the earlier measurement counted runner-less
jobs as running (see Reconciliation row 2). GitHub concurrency figures verified against
docs.github.com `actions/reference/limits` on 2026-10-07: Team 60, Enterprise 500, larger runners 1000
(separate pool).

### Property List (Phase 0.6b)

1. A PR that is still a draft consumes materially fewer hosted-runner minutes per push.
2. A PR cannot enter the merge queue, or merge, without the full battery having run on the candidate.
3. A required context always reports; none is left pending on the PR head or on `merge_group`, and no consumer treats a light result as a full one.
4. Every reduction is reversible by one switch and fails closed to full CI when state is unknown.
5. Every claimed saving has a before and after job-minute figure from one committed measurement.
6. Supply changes are decided separately, after demand has been re-measured.

### Cut List

| Mechanism | Property it buys | What already covers it |
|---|---|---|
| Re-doing superseded-run cancellation | 1 | `cancel-superseded-pr-runs.yml` (ADR-216): 4% of minutes lost |
| Path-gating Infra Validation | 1 | Workflow-level `paths:` already gates it |
| Path-gating the five mutation batteries | 1 | ADR-262, shipped |
| A new "light CI" workflow file | 1 | Job-level `if:` inside `ci.yml` keeps required context names stable |
| Consolidating the ~1,300 short non-CI jobs | 1 | Saves setup overhead only and renames required contexts (parity cost exceeds benefit) |
| Provisioning runners in this PR | 6 | Memo only; ADR-276 Decision 8 |

### Measured state (re-measured 2026-10-07, window 13:04Z to 19:04Z)

Method (reproducible; Stage 1 commits it as `scripts/ci-demand-census.sh`):
`gh api --paginate "repos/jikig-ai/soleur/actions/runs?created=>=<since>&per_page=100"` to a file,
`jq -s` to flatten (955 runs), `gh api "repos/jikig-ai/soleur/actions/runs/<id>/jobs?per_page=100&filter=latest"`
for each of 745 completed runs (736 returned), then aggregate runner-bound, non-skipped jobs
(`runner_id > 0`). PR draft state at each run time was reconstructed from the issue timeline
`ready_for_review` / `convert_to_draft` events (20 PRs). Never `--paginate` with `--jq` aggregates.

| Bucket | Runner job-min | Share |
|---|---|---|
| All completed runs in window | 7,456 | 100% |
| `CI` pull_request (31 runs, 99.8 per run) | 3,094 | 41.5% |
| `CI` merge_group (8 runs, 147.9 per run) | 1,183 | 15.9% |
| `CI` push main (7 runs, 145.4 per run) | 1,018 | 13.7% |
| CodeQL default setup (dynamic, advisory) | 601 | 8.1% |
| Infra Validation (pull_request, 18 runs) | 441 | 5.9% |
| PR quality guards (pull_request) | 227 | 3.0% |
| secret-scan (pull_request; smoke matrix 134) | 203 | 2.7% |
| Tenant integration (pull_request) | 137 | 1.8% |
| Everything else | ~550 | ~7% |

`CI` job families per run (pull_request / merge_group / push): `test-scripts` 64.3 / 92.9 / 90.3,
`test-webplat` 7.9 / 11.2 / 11.6, `shard-totality-mutations` 7.3 / 9.0 / 9.3, `test-scripts-heavy`
6.3 / 17.4 / 16.8, `e2e` 3.1 / 3.6 / 4.2; the light set (everything not in those families, including
`web-platform-build`, `lint-webplat` and the cheap gates) is 8.2 / 9.3. PR-event minutes by PR state:
draft 1,814 (43%), ready 2,404; `CI` alone draft 1,319 over 18 runs on 7 PRs. Median 10 workflows per
PR head; median PR job queue wait 297 s, p90 855 s; merge_group `CI` queue wait median 329 s.

Affected selection probes (`bash scripts/test-all.sh --print-selection --paths=<p>`, durations from
`scripts/suite-durations.tsv`, 79.0 suite-minutes registered): a docs diff selects 148 of 576 suites
(27% of suite time), a web-platform UI file 163 (29%), a skill plus script 236 (36%), `ci.yml` plus
`required-checks.txt` 171 (51%). The always-on floor is 148 suites / 21.7 suite-minutes. The pre-pass
costs 86 s wall per invocation, so it must run once per run, not once per shard leg.

Two caveats on the totals. (1) 7,456 is a lower bound: the census covers completed runs only (about 210
queued or in-progress runs are excluded, the survivorship bias the queue-health learning warns about) and
9 of 745 completed runs returned no jobs. (2) Mean concurrency is 21 against a cap of 60 and the pool sits
at the cap 22% of the minutes, so demand cuts lower the mean more than they lower the peaks; S5's
re-measure should judge queue wait at peak, not only job-minutes.

### Lever ranking by measured saving (window totals; do not add the rows)

| Rank | Lever | Basis | Window saving (job-min) | Merge-gate effect | Owner |
|---|---|---|---|---|---|
| 1 | Elide the duplicate push-main run when `merge_group` already passed that SHA | gross upper bound | up to 1,018 (13.7%) | None to merging; touches the deploy `workflow_run` trust ladder | #9512 (S2) |
| 2 | Lever 2: draft PRs run the light set; full set on `ready_for_review` | net | about 600 (range 350 to 850): draft `CI` 1,319 (18 runs, 73 each) replaced by about 18 light runs of 10, less 4 ready-transition full runs at about 137 | None: `merge_group` stays full | S3 |
| 3 | Lever 3: PR runs run the affected set | gross | about 300 to 700: roughly 23 suite-minutes off a PR `test-scripts` run (51 derived from ADR-262's 28-of-39 battery saving against 79.0 registered, to about 28 selected), shrunk by the 13 job-minutes of shard overhead that do not scale with selection; about 300 after lever 2 removes draft runs | Amends ADR-262 and ADR-183; escape risk | S4 (parked) |
| 4a | Lever 4: path-gate the secret-scan smoke matrix (PR-only, non-required) | gross upper bound (assumes no PR touches the subject paths) | up to 134 (1.8%) | None | S1 |
| 4b | Lever 4: CodeQL cost | gross | up to 521 on PR heads (7.0%) of 601 | Advisory per ADR-270; a security-posture decision | S5 |

Break-even for lever 2: draft pushes in the window averaged 2.6 per draft PR (18 runs over 7 PRs) and a
draft run averaged 73 job-minutes (many were cancelled part-way), against about 137 for a full ready run.
A PR therefore saves minutes only above about 3 draft pushes (saving per draft push about 63, less one
ready run), so lever 2 is marginal on cancelled-heavy drafts and strongest where drafts finish full runs.
Cheaper alternative to check first: stop the pipeline pushing a draft before a local `--affected` run
passes, which removes draft pushes at the source with no aggregator change. Break-even for lever 3's
escape cost: a missed failure costs a ~148 job-minute candidate run plus a re-queue, and ejects the
entries queued behind it, against about 23 saved per PR run, so the escape rate must stay well below
12 to 16 percent; the stage's exit criterion is set far below that.

Not a lever here: cancelled jobs that held a runner are 304 job-minutes (4%).

### Institutional learnings applied

- A check that cannot report is indistinguishable from one that passed: every skip arm below carries a
  mutation row (`knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`).
- Path-gate detectors must fail open (run) on any failure, and gate on exit status, not on empty output
  (`knowledge-base/project/learnings/2026-09-25-path-gating-exit-status-not-emptiness.md`).
- Merge-queue adoption needs every ruleset producer to report on `merge_group`, enumerated by job
  (`knowledge-base/project/learnings/best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`); `ci.yml` header says never add an
  `event_name == 'pull_request'` gate to a required job.
- Job-level wait metrics carry survivorship bias; measure delivered concurrency (`knowledge-base/project/learnings/2026-09-22-actions-queue-under-assignment-metrics-and-monitor.md`).
- `gh api --paginate` with `--jq` aggregates truncate per page (hard rule; census writes to a file).
- Merge-queue `merge_group` trusts the PR run for `rename-guard` and `allowlist-diff`
  (`secret-scan.yml`), and likewise for the vendor-pin and tenant rows: those contexts must stay in the
  draft light set.

### Deepen-plan research (2026-10-07)

- **Measured, not assumed (S2):** in the window's jobs data a workflow run whose jobs were all skipped concluded `skipped` (8 `Post-Merge Monitor` `workflow_run` runs, 7 `Cleanup unmerged bot branches`, 7 `Dev ledger: reconcile unmerged migrations`), never `success`; GitHub's documentation separately says a skipped job reports success to a required status check. So an elided push-main `ci.yml` run would fail the deploy arm's `success` condition unless one real job survives.
- **Documentation checks (fetched 2026-10-07):** the `vars` context page does not say whether fork PRs receive repository variables, and the automatic-token page did not carry the "GITHUB_TOKEN events create no workflow runs" text; both stay S3 entry gates measured on a throwaway PR rather than cited.
- **Architecture pass:** an existing precedent, `scripts/main-push-duplicate-skip.sh`, already implements per-SHA push-run elision for five workflows (its keying was checked: two push-main `CI` SHAs each equal a `merge_group` run's `head_sha`); the agent `--admin` path is a merge route that bypasses the queue; the ADR's single `proposed` flip would activate unrun stages.
- **Spec-flow pass:** journeys above; Option R/T and the arm-after-ready wait are the smallest plan changes.
- **Gates run:** user-brand impact (present, `aggregate pattern`), observability (docs-only plan; probe command exists in this tree and returns `1 guard entry`), PAT-shape grep (no hits), encryption posture (no store or connection introduced), guard contract (`lint-guard-contract.py` green, adequacy read: assembly names the chokepoint and a consumer census, rows come from the design), scope check (one unfenced section, no `unmapped` or blocked rows), ADR ordinal (276 free).

## Open Code-Review Overlap

Open `code-review` issues touching files this plan names: #8659 (`scripts/test-all.sh`, test-helpers
EXIT trap), #7942 (`scripts/test-all.sh`, two unregistered mutation batteries), #3829
(`.github/workflows/pr-quality-guards.yml`, Sentry carve-out gate). **Acknowledge** all three: each is a
different concern and none sits on the lines the stages edit; they stay open. No overlap on `ci.yml`,
`secret-scan.yml`, `required-checks.txt` or `infra/github/ruleset-ci-required.tf`.

## Reconciliation with related trackers

| Tracker | State | Relationship |
|---|---|---|
| #8683 (BEHIND-sync pushes) | open | Lever 1, out of scope; this plan only measures its effect (S5 re-measure) |
| #9323 (battery path-gate) | open; ADR-262 shipped, soak probe due 2026-10-09 | Lever 3 builds on it; no duplicate work; its probe is the evidence base |
| #9512 (push-run dedupe) | open, p3 | Becomes S2; raise to p2 and attach the ranking; its three unknowns stay its own |
| #9307 (affected-only gate) | open umbrella; PR 1, B and C merged | Lever 3 consumes `--print-selection`; PR 2 (plugin-generic gate) stays there |
| #9410 (shard main-health-monitor tests) | open | Wall-clock item, not minutes; untouched |
| #9497 (scope gitleaks/bun rows of the shard-runtime-coverage gate) | open | Small, independent; untouched |

## Staged rollout (one lever per PR, dark-launch and non-blocking first)

Plan review verdict on Stage 1: DHH, code-simplicity, the CTO devex lens and Kieran all advised against
implementing it in this PR (it breaks the plan phase's "no workflow edit" line for a 1.5% saving, drags a
`test-scripts` suite and a ledger bump into the ADR PR, and one of its premises was false), so **this PR
ships plan, ADR-276, memo, tasks and follow-up issues only**. Stage 1 keeps its own PR.

| Stage | Lever | PR | Entry gate, dark launch and exit criterion | Rollback |
|---|---|---|---|---|
| S0 | Plan, ADR-276 (`proposed`), lever-5 memo | this PR (#9722) | n/a | revert |
| S1 | Small census script (the Measured-state method, runner-bound filter, one job-count self-check) plus, optionally, the secret-scan smoke path gate (lever 4a) | own PR | No required context or merge authority touched. The smoke job runs only on `pull_request` today (no `schedule` arm exists), so S1 either adds a weekly arm with its own test or drops the "full coverage weekly" claim; it must gate on `event_name == 'pull_request'` and run unconditionally on other events (no diff base there); adding `smoke-relevance` raises the declared job count and needs a `scripts/pr-fanout-ledger.txt` bump. Exit: census attached to #9721; smoke minutes down at least 80% on PRs that miss the subject paths | revert (non-required, PR-only job) |
| S2 | Push-run dedupe (#9512, lever 3b) | own PR | Entry gate, already answered by the census data: a run whose jobs are ALL skipped concludes `skipped`, not `success` (8 `Post-Merge Monitor` `workflow_run` runs and 7 `Cleanup unmerged bot branches` runs in the window), and the deploy arm needs `success`, so the elision must keep at least one real job (a keyed attestation job) in the push run. Reuse the precedent `scripts/main-push-duplicate-skip.sh` (used by tenant, vendor-pin, infra-validation, validate-vector-config and skill-security-scan-corpus) but not as-is: its coverage proof (latest `pull_request` run at the head succeeded) would be satisfied by a light draft run once S3 lands, so for `ci.yml` it must read the `test` job conclusion and a non-draft guard. A second named tolerance arm (keyed on a green `merge_group` run for the exact head SHA) needs its own Guard Contract in S2's plan; it is not covered by Guard 1. Dark launch behind a repository variable (unset means run), 7 days. Exit: zero SHAs elided without a green `merge_group` run | variable unset |
| S3 | Draft light checks (lever 2) | own PR | **Variable name: `CI_DRAFT_LIGHT` (value `on`).** **Entry gates, resolved on a throwaway PR before any `ci.yml` edit:** (1) how the required-status rollup treats two same-name check runs on one SHA (draft light green, then ready pending); (2) a `gh pr ready` issued with an ordinary user token versus `GITHUB_TOKEN` (the latter triggers no workflow, leaving the draft-run green on the ready head); (3) a fork PR sees or does not see the variable (fork PRs always run full regardless: compare `head.repo.full_name` with the repository, as `ci.yml` already does); (4) the arm-then-register window: ship Phase 6 runs `gh pr ready` then `gh pr merge --squash --auto` within seconds, and the head already carries green required contexts from the draft run. Then dark launch: variable default unset (merge is a no-op), canary on one draft PR (draft, ready, queue entry, merge_group), then on for 7 days. Design choice, decided by the entry gates: **Option R** (preferred): the draft aggregator concludes red with a plain message (`draft: full battery owed at ready`), so no consumer can read a light `test` as green, `battery-owed.sh` already returns OWED, `admin-merge-ready.sh` reads RED/PENDING, and no tolerance arm exists; its cost is a red `test` on drafts, so first check that `monitor-pr-checks.sh`, `drain-prs` triage and ship Phase 7 do not misread it. **Option T**: a tolerance arm plus a distinct non-required marker check-run that `battery-owed.sh` and `admin-merge-ready.sh` also require. Either way ship Phase 6 gains a step between `gh pr ready` and arming auto-merge: wait for a non-draft `CI` run on HEAD created after the ready call, fail closed (do not arm) if none appears, and the same wait goes into `drain-prs` and `merge-pr`; every `gh pr ready` caller must use a non-`GITHUB_TOKEN` identity. The variable has a removal trigger: delete it, keeping only the draft-input arm, after 30 days with zero escapes. Exit: draft `CI` minutes per draft push down at least 80%, zero queue stalls | variable unset |
| S4 | PR affected-only (lever 3) | own PR, parked | Re-decide after S2 and S3 have post-merge censuses; then the replay is the evidence: `--print-selection` over the last 300 first-parent commits against suite failures, replay escape rate under 2%, no live shadow window. The pre-pass (86 s) runs once per run, not per shard leg. The escape metric must also count agent `--admin` merges, which skip the queue: those get only the affected set, and the metric "merge_group red with a green PR run" never sees them | variable unset |
| S5 | Re-measure, then decide CodeQL cost (lever 4b) and supply (lever 5) | one decision issue, no code | Census on a 30-day window after S2 to S4; the CTO memo's measure-first list; CodeQL query suite or event scope needs CLO/CTO sign-off | n/a |

Ordering: S1 first (it makes every before/after number reproducible). S3's entry gates run in parallel
with S2's experiment, since the two touch disjoint files; if S2's all-skipped question stays open for about
a week, S3 goes first. S2 is the largest removable duplicate and gate-neutral for merging, but it is the
stage with the most unknowns (the deploy trust ladder).

## Guard Contract

Only S3's aggregator guard is a deliverable that needs a contract now. S1's smoke gate, S2's elision arm
and S4's selection each author their own contract in their own plan (S2's keyed tolerance arm in
particular is a second skip reason that Guard 1 deliberately does not cover).

### Guard 1 - Draft-light aggregator (S3, the `test` context)

**Property.** On a draft `pull_request`, confirmed live and with `CI_DRAFT_LIGHT` on, the `test` context is never success-equivalent for a head whose heavy families did not run (Option R: it concludes red; Option T: it is success only with a distinct marker that every consumer requires); on every other event or state it reflects the real results, and no consumer or merge path reads a light `test` as proof of the full battery.

**Assembly.** The chokepoint is the `test` aggregator job in `.github/workflows/ci.yml` (its `needs:` list, which today is `test-webplat`, `test-bun`, `test-scripts`, `test-scripts-heavy`, `web-platform-build`, `encryption-posture`; its `env:` result strings and its loop body, which the repo already extracts and executes over synthetic result triples). Mutation rows for "needed families" are generated from the live `needs:` list, not a remembered one; `shard-totality-mutations` and `e2e` sit outside it. Every consumer of the context must see the same truth, and the consumer list is a census, not a recollection: the ruleset required-context list (`scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`, the canonical JSON); `web-platform-release.yml`'s `workflow_run` arm; `post-merge-monitor.yml`; `plugins/soleur/skills/ship/scripts/battery-owed.sh` (newest completed `success` per name reads as satisfied); `plugins/soleur/scripts/admin-merge-ready.sh` and `plugins/soleur/test/admin-merge-ready-wiring.test.sh` (the agent `--admin` path skips the merge queue, takes the highest check-run id per name, and the `test` aggregator is created only after every shard ends, so after a ready transition the draft run's `test` is the newest row until the ready run's aggregator starts); the `gh pr checks` and `statusCheckRollup` readers (`plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/merge-pr/SKILL.md`, `plugins/soleur/scripts/monitor-pr-checks.sh`, `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`, `scripts/audit-bot-codeql-coverage.sh`); and the measurement probe `scripts/followthroughs/pr-battery-gate-saving-9323.sh`, whose baseline averages all successful `pull_request` runs and is contaminated once light runs exist. `e2e` is a required context and keeps its existing step-level gating (the #8450 pattern, a skipped required check posts green): it still runs on drafts, so lever 2 does not save its ~3 job-minutes, and it is named here so a job-level `if:` is not added to it by analogy. Event shapes: `pull_request` (draft, ready, reopened, a re-run whose payload still says draft, a fork), `merge_group`, `push`, `workflow_dispatch`.

**Mutation matrix.**

| Mutation (must go RED) | Targets |
|---|---|
| Make the aggregator treat any `skipped` result as success | the tolerance arm is too wide (Option T) |
| On `merge_group` or `push`, feed it `skipped` for `test-scripts` with draft true | draft input must be ignored off the pull_request event |
| Add a further needed family after a compliant first and leave it out of the loop | a check that stops at the first member |
| Unset `CI_DRAFT_LIGHT` | unset must mean full CI |
| Feed an empty `needs` map (0 families checked) | the guard's own dispatch must refuse 0 checked and exit non-zero |
| Resolve the draft input before it is set (empty string) or make the live read error | an unresolved or failed read must fail closed to full |
| Payload says draft true while the PR is live-ready (a re-run after ready) | a stale event payload must not skip heavy families on a ready head |
| A fork PR with `CI_DRAFT_LIGHT` on | forks must run full |
| Feed `admin-merge-ready.sh` a draft-run `test` row and no ready-run `test` row | it must return ABSENT or PENDING, not READY |
| Feed `battery-owed.sh` a light `test` row on a ready head whose full run never started or was cancelled | it must return OWED, not SKIPPABLE |
| Arm auto-merge with no non-draft `CI` run on HEAD created after `gh pr ready` | the ship step must refuse to arm |
| Add a job-level `if:` to `e2e` on draft | the required `e2e` context must keep reporting |

Harness rows: replace the extracted aggregator body with a stub that prints success (the suite must fail); must-PASS non-canonical input: a draft run with `CI_DRAFT_LIGHT` on where the light families succeed and heavy families are `skipped`, in a different order from the canonical fixture, producing the Option R or Option T verdict exactly.

**Anchor.** The aggregator compares results, not a stored value, so no stored-value anchor applies; the independent anchor for "the full battery still ran" is the `merge_group` run for queue merges, which this change does not alter. It is NOT an anchor for the agent `--admin` path (that path skips the queue, so `admin-merge-ready.sh` is the only gate and is in the assembly above) and not for the contexts the queue trusts the PR run for (`rename-guard`, `allowlist-diff`, the vendor-pin and tenant rows), which live in other workflows that S3 leaves unchanged.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-276, status `proposed`, rich shape: "Hosted-runner demand is cut before supply is raised;
merge_group (and the push-main deploy arm) stay the full-battery authority". It is a deliverable of
this plan and is written in this PR
(`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`).
It amends ADR-262 and ADR-183 only when S4 lands (those amendments are tasks of S4, not of this PR).
The ordinal is provisional: `soleur:ship`'s ordinal gate re-verifies it against `origin/main`.

### C4 views

Read in full: `model.c4`, `views.c4`, `spec.c4`. Checked and already modeled: the external system
`github` ("Source control, CI/CD..."), the human actors `founder` and `contributor`, the `github ->
doppler`, `github -> hetzner`, `github -> tunnel` and `github -> sentry` CI edges, and the hetzner
`platform.infra.hetzner` container. Hosted runners are not modeled as an element today (the word
appears only inside edge text) and the demand stages add no actor, system, data store or
access relationship, so **no C4 edit in this PR**. If lever 5 option A is ever adopted its ADR adds a
`ciRunners` container and a `github -> hetzner` runner edge with a `view include` line; that is that
ADR's deliverable. `plugins/soleur/test/c4-count-parity.test.sh` was run on this branch: "ALL TESTS
PASSED", 0 failed.

### Sequencing

ADR-276 describes the target state and carries `status: proposed`; it flips to `active` per stage as
each stage's dark-launch exit criterion passes (stated in its Status section).

## Observability

Plan-phase files are docs; the stages carry code. The observability contract the stages must meet:

```yaml
liveness_signal:
  what: weekly census report attached to the stage tracking issue, plus the S3 follow-through probe
  cadence: weekly during rollout, then monthly
  alert_target: the stage tracking issue (follow-through label) and the main-health monitor
  configured_in: scripts/ci-demand-census.sh and scripts/followthroughs/ (S3, S4)
error_reporting:
  destination: workflow run annotations and the follow-through sweeper issue comment
  fail_loud: true
failure_modes:
  - mode: draft-light job reports success while a heavy family was skipped on a non-draft head
    detection: the Guard 1 mutation suite in the test context and a canary run on a throwaway draft PR before enabling
    alert_route: red `test` context, then follow-through probe failure
  - mode: affected selection misses a failing suite
    detection: S4 replay over the last 300 first-parent commits; afterwards a merge_group red with a green PR run is counted as an escape
    alert_route: follow-through probe and main-health monitor
  - mode: census silently undercounts (paginate truncation, runner-less jobs)
    detection: the S1 census self-checks job count against the runs listing and fails on mismatch
    alert_route: red suite in test-scripts (once S1 lands)
logs:
  where: GitHub Actions run logs and the census output stored as the issue attachment
  retention: GitHub default run retention; census output kept on the issue
discoverability_test:
  command: python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md
  expected_output: 1 guard entry
```

The command exists in this PR's tree and checks the one machine-checkable deliverable of the plan phase
(the Guard Contract). The census command Stage 1 adds (`bash scripts/ci-demand-census.sh --fixture
<dir> --summary`, printing a `TOTAL_JOB_MINUTES` line) becomes the stage's own `discoverability_test`
in its tracking issue, because that script does not exist on this branch yet.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent reviewed lever 5 and the rollout framing. Recommendation order: demand
levers first (D), price-check an Enterprise quote second (C, price unknown), larger runners as a
spend-capped hybrid third (B), ephemeral Hetzner runners last and gated (A). Blocking concerns recorded
in the memo: public-repo code execution on owned hardware with agent-authored PRs, unverified Hetzner
quota and stock, an autoscaler is a new service needing observability, required contexts must never go
missing, runner image drift, and that "larger runner" may not mean more cores below 8-core. Full memo:
`knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/lever5-runner-supply-memo.md`.

No product, UX, marketing, legal, finance or sales surface is touched (no user-facing page or copy). A
CFO note applies only if lever 5 is pursued: larger runners are metered and need an expense row.

## User-Brand Impact

- **If this lands broken, the user experiences:** a regression that the reduced PR-level checks failed
  to catch reaches `main` and the deployed web app, because a gate that should have run did not; the
  merge_group authority is kept to bound this.
- **If this leaks, the user's workflow is exposed via:** no data surface; the only exposure vector is a
  future self-hosted runner executing public-repo PR code, which this plan does not build and which the
  memo gates behind explicit conditions.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the plan changes when checks run, not who can read what, and
  the full battery stays at the queue; a single-user incident needs a data or credential surface, which
  only the deferred runner-supply option has.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Plan plus ADR proposal first, NOT a big-bang change." [brief] | Staged rollout, ADR-276 | mapped |
| 2 | "Lever 1 (stop redundant BEHIND-sync pushes, tracked by issue 8683) is out of scope; reference it only." [brief] | Overview, Reconciliation table | mapped |
| 3 | "Related open trackers to reconcile (not duplicate): 9323 ... 9512 ... 9307 ... 9410, 9497." [brief] | Reconciliation with related trackers | mapped |
| 4 | "RE-MEASURE before trusting, numbers move; count JOBS not runs" [brief] | Measured state | mapped |
| 5 | "VERIFY against GitHub's current docs before citing it" [brief] | Premise validation (60, 500, 1000 verified) | mapped |
| 6 | "Do NOT re-solve that." (superseded-run cancellation) [brief] | Cut List | mapped |
| 7 | "Light checks only on DRAFT PRs; full required set on `ready_for_review` and again in merge_group." [brief] | Lever 2, S3, Guard 1 | mapped |
| 8 | "Do not run the full battery twice" [brief] | Lever 3 (S4), push dedupe (S2) | mapped |
| 9 | "Trim the ~12-workflow per-push fan-out" [brief] | Lever 4 (S1 smoke gate, S5 CodeQL decision) | mapped |
| 10 | "SUPPLY (separate decision, do not bundle)" [brief] | Lever-5 memo, S5 | mapped |
| 11 | "a staged rollout (one lever per PR, dark-launch/non-blocking first per wg-dark-launch-deploy-gates)" [brief] | Staged rollout table | mapped |
| 12 | "Stage 1 of the rollout must be defined so it is safely implementable in this PR only if the plan review panel signs off" [brief] | Staged rollout (S1 row and the verdict paragraph above it) | mapped |
| 13 | "New ADR must use the next free ADR number" [brief] | ADR-276 | mapped |
| 14 | "with follow-up issues per stage (milestone required; body needs `User-Impact:` + `Fix-Size:` lines or label meta/machinery)" [brief] | Phase 4 | mapped |
| 15 | "Do NOT touch the worktree .worktrees/feat-one-shot-merge-queue-aware-behind-sync" [brief] | Constraint: no file in that tree is read or written | mapped |
| 16 | "Do NOT write product code or edit workflows: plan-only phase" [brief] | Phases 0 to 2 write docs only | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Plan file, tasks.md | "Plan plus ADR proposal first" | asked (ask 1) |
| ADR-276 | "New ADR must use the next free ADR number" | asked (ask 13) |
| Lever-5 memo | "a short options memo for lever 5 routed through the CTO agent" | asked (ask 10) |
| Guard Contract (Guard 1) | "Required contexts must still report on the PR head" | asked (ask 7); enforcement contract for the aggregator |
| S1 census and smoke gate (deferred to its own PR) | "Trim the ~12-workflow per-push fan-out" | asked (ask 9); the census is inferred, because the first measurement pass was wrong by 26% and the ADR names one measurement authority, so it stays a small script, not a suite-heavy tool |
| S2 push-run dedupe | "9512 (skip duplicate push-to-main CI run when merge_group already passed)" | asked (ask 3) |
| Follow-up issues | "follow-up issues per stage" | asked (ask 14) |

### Split Assessment

- Subsystems touched: 2 (`knowledge-base/project`, `knowledge-base/engineering`)
- Planned files: 9 | Estimated changed lines: about 900 (prose; no code)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR for the plan phase. The line count is prose, not code, and stages S1 to S5
  are separate PRs by design.

## Implementation Phases

### Phase 0 - Plan artifacts (this PR, no workflow or product code)

1. Write this plan, `tasks.md`, ADR-276 (`proposed`) and the lever-5 memo.
2. Run `bash scripts/check-adr-ordinals.sh` and `python3 scripts/lint-guard-contract.py` on the files.
3. Commit and push with the required trailer.

### Phase 1 - Plan review

Run the plan review panel and record the verdicts in `## Plan Review Outcome`. Applied: Stage 1 is its own
PR.

### Phase 2 - Follow-up issues (filed in this plan phase)

One issue per stage S1 to S5, each with milestone "Post-MVP / Later" (same as #9721), labels `type/chore`,
`domain/engineering`, `meta/machinery`, a `User-Impact:` line naming a surface and a `Fix-Size:` line in
`N lines / M files` form, and a "Re-evaluation" line. Bodies are written to
`knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/issues/` first (the filing gate reads
tracked paths only). #9512 gets a comment (and a priority raise to p2) instead of a duplicate issue for S2.

### Phase 3 - Stages S1 to S5

Each is its own PR per the staged table; none starts in this PR.

## Files to Create

- `knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/lever5-runner-supply-memo.md`
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`
- `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/issues/*.md` (follow-up issue bodies)

## Files to Edit

None in this plan phase. Later stages edit (listed in their issues, with the fan-out ledger row where a
job is added): S1 `.github/workflows/secret-scan.yml`, `scripts/pr-fanout-ledger.txt`; S2
`.github/workflows/ci.yml`, `.github/workflows/web-platform-release.yml` only if the attestation form
needs it, `scripts/pr-fanout-ledger.txt`; S3 `.github/workflows/ci.yml`,
`plugins/soleur/skills/ship/scripts/battery-owed.sh`, the aggregator harness, `scripts/pr-fanout-ledger.txt`
if a job is added (`ci.yml` is at its declared ceiling of 24); S4 `scripts/test-all.sh`,
`scripts/lib/test-relevance-paths.sh`, ADR-262 and ADR-183 amendments.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Plan, tasks.md, ADR-276 (`status: proposed`) and the lever-5 memo exist at the paths above.
- [ ] `bash scripts/check-adr-ordinals.sh` prints "ADR ordinal + content checks passed" and no other
      ADR file claims ordinal 276 on `origin/main` at merge time.
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan (one entry with a matrix of at least
      three rows).
- [ ] Every number in the ranking table traces to the Measured-state method and states its basis (net or
      gross); the lower-bound caveat is present.
- [ ] `## Plan Review Outcome` records the panel verdicts.
- [ ] Follow-up issues exist for S1, S3, S4 and S5 with the milestone, `meta/machinery` label,
      `User-Impact:` and `Fix-Size:` lines, #9512 carries the S2 comment, and their numbers are listed in
      `## Follow-up Issues`.
- [ ] #9721 carries a comment with the ranking and a link to this plan; the PR body says `Closes #9721`.
- [ ] `git diff --name-only origin/main...HEAD` lists no file under `.github/`, `scripts/`, `apps/` or
      `plugins/` (merge-base diff, not the moving tip).

### Post-merge (operator-visible follow-through)

- [ ] S5 runs only after S2 to S4 have a post-merge census; each stage attaches its own before and after.

## Test Scenarios

Per-stage, owned by the stage's PR (this PR changes no behavior):

1. Census fixture with a runner-less cancelled job: the job contributes 0 minutes; a page-truncated
   listing fails the job-count self-check.
2. Smoke gate: a docs-only PR diff skips the matrix; a diff touching `.gitleaks.toml` runs it; a
   non-PR event runs it; a relevance job that exits 1 runs it.
3. Draft with the kill-switch on: heavy families skipped, `test` green, `battery-owed.sh` still OWED;
   the same head marked ready: full run; `merge_group`: full regardless of the variable; a re-run of a
   light job after the PR went ready does not skip.
4. S2: an all-skipped run's conclusion and the deploy arm's reaction, measured before any elision.
5. S4: replay prints selected versus actual outcome over 300 commits and never narrows a run.

## Risks and Sharp Edges

- A required context left pending is the worst failure; the `ci.yml` header forbids event gates on
  required jobs, so S3 gates heavy jobs on the draft input and edits the aggregator, never the event.
- Marking a PR ready triggers nothing today; S3 must add `ready_for_review` to `ci.yml` types, and a
  `gh pr ready` issued with `GITHUB_TOKEN` triggers no workflow at all (an S3 entry gate).
- The agent `--admin` merge path skips the queue entirely (the ruleset grants an organization-admin and a repository-role bypass), so `merge_group` is NOT the authority there; `admin-merge-ready.sh` is the only gate and it reads the highest check-run id per name. Because the `test` aggregator is created only after every shard ends, a draft run's light `test` is the newest row in the window after `gh pr ready`. Guard 1 covers it; Option R (a red draft `test`) closes the window without a tolerance arm.
- `gh pr ready` followed within seconds by `gh pr merge --squash --auto` can enqueue a PR on the draft run's greens before the ready run registers any check; ship Phase 6 must wait for a non-draft `CI` run on HEAD created after the ready call, and fail closed.
- Smaller journeys (spec-flow): `converted_to_draft` is not a trigger, so ready-draft-ready with no new push reruns full on a head that may already be green (skip when a full-mode marker exists, Option T); converting a queued PR to draft dequeues it (ship Phase 7 reads it as dequeued); a light run cancelled by the per-ref concurrency group leaves `cancelled` rows on the SHA that Phase 7 polling must ignore in favour of the newest row per name; `fix-constraints-stage-b.yml` opens drafts with `github.token`, which trigger no CI, so the human ready click is that PR's first run; `reopened` takes the live draft state; labels are inert for `ci.yml`.
- A stale green `test` from the draft light run sits on the same SHA as the pending ready run. The
  merge_group full battery bounds this for contexts it re-runs; it does not bound the contexts the queue
  trusts the PR run for (`rename-guard`, `allowlist-diff`, vendor-pin, tenant), which S3 leaves untouched.
  Which same-name check run feeds the required rollup is unmeasured and is an S3 entry gate.
- `battery-owed.sh` reads a context as `ok` when its newest completed row is `success`; a light draft
  green would make it return SKIPPABLE and skip the local gate (a wrong SKIP, the failure class its own
  comments name). S3 must make a light `test` distinguishable and carry a mutation row for it.
- A re-run reuses the original event payload, so a light job re-run after ready would still read
  `draft == true`; the draft state is confirmed live, not read only from the payload.
- Whether repository `vars` reach a fork `pull_request` run is unverified (an S3 canary item). The outcome
  is safe either way because the queue runs the full battery, so the plan does not rely on the answer.
- Adding `ready_for_review` to `ci.yml` means writing the full `types:` list
  (`opened, synchronize, reopened, ready_for_review`); naming only the new type drops the defaults.
  `scripts/pr-fanout-ledger.txt` keys a row on "no `types:` or `synchronize` in `types:`", so keeping
  `synchronize` leaves the `ci.yml` row valid; `plugins/soleur/test/pr-fanout-ledger.test.sh` is the
  check. Lifecycle members that differ: `board-status-sync.yml` already lists `ready_for_review` and is
  never replaced by a later push; `cancel-superseded-pr-runs.yml` reaps only runs on a superseded head
  SHA, so the ready run on the same head is not reaped, while `ci.yml`'s own per-ref concurrency group
  cancels the in-progress light run when the ready run starts (intended).
- The kill-switch is a repository variable set with `gh variable set` (no `github_actions_variable`
  resource exists in `infra/github`); each stage names a removal trigger so it does not become a permanent
  fork in the workflow.
- The affected pre-pass (86 s) must not run per shard leg or it consumes the saving.
- Window bias: 6 hours of one working day, completed runs only. S5 requires a 30-day census before any
  supply spend.
- A plan whose `## User-Brand Impact` section is empty, or omits the threshold, fails deepen-plan; this
  one carries all three lines.

## Plan Review Outcome

Panel: DHH, Kieran, code-simplicity (per mechanism) and the CTO agent under a devex lens. Brand-survival
threshold is `aggregate pattern`, so the three-agent baseline plus the named devex reviewer ran.

| Finding | Source | Class | Disposition |
|---|---|---|---|
| Do not implement Stage 1 in this PR (1.5% saving, breaks the docs-only line) | DHH, simplicity, CTO, Kieran | mechanical | Applied: S1 is its own PR; Guard 2 moved out of this plan |
| Stage 1 premises false: no `schedule` arm exists; ledger count would redden; non-PR events have no diff base | Kieran, simplicity | mechanical | Recorded in the S1 row and its issue |
| `battery-owed.sh` reads a light green as full (wrong SKIP) | CTO | mechanical | Applied: Guard 1 assembly and mutation row, S3 entry gate |
| Same-name rollup, `GITHUB_TOKEN` ready, stale payload, `e2e` skip, fork `vars` need entry gates | Kieran, DHH | mechanical | Applied: S3 entry gates and Guard 1 rows; the false fork claim removed |
| S2 needs a second named tolerance arm and a hard all-skipped-conclusion precondition; drop the 14-day shadow | Kieran, simplicity | mechanical | Applied in the S2 row |
| S4: replay instead of live shadow; park until S2 and S3 are measured | simplicity, DHH | mechanical | Applied in the S4 row |
| Fold CodeQL and supply into one decision issue (S5) | simplicity | mechanical | Applied |
| Arithmetic: net/gross basis, break-even about 3 draft pushes, lever 3 baseline derivation, lower-bound window | Kieran | mechanical | Applied in the ranking section |
| Kill-switch needs a removal trigger; no Terraform management of the variable | CTO, DHH | taste | Applied (30-day removal trigger; `gh variable set`) |
| Cut ADR-276, or write it only when S3 lands | DHH | user-challenge | Not applied: the brief explicitly requires the ADR proposal ("New ADR must use the next free ADR number"); recorded in `decision-challenges.md` |
| Shrink the lever-5 memo; drop the Observability block and `tasks.md` | DHH, simplicity | taste | Not applied: the memo is the asked deliverable and was CTO-reviewed; the Observability schema is a plan-skill gate; `tasks.md` is the plan skill's output |
| Check "no draft push before local `--affected` passes" before building S3 | DHH | taste | Recorded in the ranking section as the cheaper alternative to check first |

## Follow-up Issues

- S1: #9727 (census script plus optional smoke path gate), own PR
- S2: #9512 (push-run dedupe; priority raised to p2, preconditions added as a comment)
- S3: #9728 (draft light checks)
- S4: #9729 (PR affected-only, parked)
- S5: #9730 (re-measure, then decide CodeQL cost and runner supply)
