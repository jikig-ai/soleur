---
title: "Hosted-runner demand is cut before supply is raised; merge_group (and the push-main deploy arm) stay the full-battery authority"
status: proposed
date: 2026-10-07
issue: 9721
related_adrs: [ADR-181, ADR-183, ADR-216, ADR-217, ADR-242, ADR-262, ADR-270]
tags: [ci, github-actions, runners, merge-queue, cost]
brand_survival_threshold: aggregate pattern
---

# ADR-276: Hosted-runner demand is cut before supply is raised; merge_group (and the push-main deploy arm) stay the full-battery authority

## Status

**Proposed — 2026-10-07 (#9721).** This ADR decides nothing until the plan review panel and the
operator accept it. Each stage it names ships as its own PR, and a stage that changes a required
check, the ruleset, or a deploy gate flips this ADR (or the ADR it amends) to `active` only after
that stage's dark-launch exit criteria pass. Nothing in this ADR provisions infrastructure.

## Context

Hosted-runner supply is saturated and per-push CI demand is the driver. GitHub documents the
standard hosted-runner cap as 60 concurrent jobs on the Team plan (500 on Enterprise); larger runners
have a separate pool (1000 on Team) and are billed per minute, including on public repositories where
standard runners are free (docs.github.com `actions/reference/limits` and
`billing/reference/actions-runner-pricing`, fetched 2026-10-07). The org is on Team, with zero
self-hosted runners.

Measured 2026-10-07, window 13:04Z to 19:04Z, jobs API, **runner-bound jobs only** (a job with
`runner_id == 0` was cancelled in the queue and consumed no runner time; counting it as running
inflated an earlier pass by 26%):

| Quantity | Value |
|---|---|
| Runner job-minutes in the window | 7,456 |
| Mean / p90 / peak concurrent jobs | 21.4 / 57 / 60 (the cap) |
| Minutes of the window at 55+ concurrent | 77 of 349 (22%) |
| `CI` workflow, by event | pull_request 3,094 (31 runs, 99.8 per run), merge_group 1,183 (8 runs, 147.9), push main 1,018 (7 runs, 145.4) |
| `test-scripts` share of a CI run | 64% of a PR run, 63% of a merge_group run |
| Draft-state PR events | 1,814 of 4,218 PR-event job-minutes (43%); 1,319 of them in `CI` |
| CodeQL default setup (advisory, ADR-270) | 601 job-minutes, 521 of them on PR heads |
| Cancelled jobs that held a runner | 304 job-minutes (4%) |

The saturation is bursty rather than constant (mean 21 against a cap of 60), so queue wait is a
peak-demand problem, and a merged PR pays the full battery three times: on the PR head (~100),
in the merge_group candidate (~148) and again on the push to `main` (~145).

Existing mechanisms this ADR must not duplicate: ADR-216 and `cancel-superseded-pr-runs.yml` already
collapse superseded PR heads (only 4% of runner minutes are lost to cancellation); ADR-262 already
path-gates five self-test mutation batteries on pull_request; issue #8683 (BEHIND-sync pushes) is a
separate lever and is out of scope here.

## Considered Options

- **A. Raise supply first** (ephemeral Hetzner runners, larger runners, or a plan upgrade). Pros:
  attacks queue wait directly. Cons: self-hosted runners on a public repo are the highest-risk
  option available (code execution on owned hardware, agent-authored PRs); larger runners move a
  free resource to a metered one; Enterprise price is unknown. Rejected as the *first* move; kept as
  a gated follow-on. See `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/lever5-runner-supply-memo.md`.
- **B. Cut demand at the merge-gate authority** (drop the merge_group battery, or the push-main run,
  wholesale). Pros: largest raw saving. Cons: the merge queue is the only point at which the
  *candidate* tree is tested, and the deploy arm keys on a push-event CI run. Rejected: the authority
  stays; only *duplicates of an already-passed identical tree* are removable, per SHA (#9512).
- **C. Cut demand upstream of the authority, behind kill-switches, fail-closed** (draft-PR light
  checks, affected-only PR runs, trimmed per-push fan-out). Pros: no authority is removed; every
  reduction is reversible by one variable. Cons: failures surface later (at ready, or in the queue),
  so each stage must carry a measured escape rate. **Chosen.**
- **D. Do nothing and wait.** Rejected: the measured PR-state waste (43% of PR-event minutes in
  draft) is paid every day.

## Decision

1. **Demand first, supply second.** No supply change is adopted until the demand stages below have
   been re-measured. Supply options are recorded in the lever-5 memo and decided in a separate ADR.
2. **The authority invariant.** The `merge_group` run executes the full battery against the candidate
   tree and keeps every required context in `scripts/required-checks.txt`. The push-to-`main` run
   keeps producing the success conclusion the deploy arm's `workflow_run` trust ladder needs; it may
   be elided only per SHA, keyed on a green `merge_group` run for that exact head SHA (#9512), never
   by static removal.
3. **PR-level reductions are allowed only when ALL hold:** (a) no required context is renamed,
   removed or left pending: a gated job still reports, and any aggregator that reads
   `needs.*.result` names each skip reason it tolerates (one per stage, each with its own guard
   contract) rather than tolerating `skipped` generally, and every consumer of that context
   (`battery-owed.sh`, the deploy `workflow_run` arm, `post-merge-monitor.yml`) is checked so a reduced
   result is never read as a full one; (b) the decision fails closed to the full battery when the draft state, the diff or
   the selection is undeterminable; (c) a repository variable is a kill-switch whose unset value
   means full CI; (d) the stage dark-launches (observe or shadow before it removes anything) and has
   a named exit criterion; (e) the stage reports the minutes it removed and the escape rate it
   caused, measured by the committed census (Decision 7); (f) a context whose `merge_group` arm
   trusts the PR run (`rename-guard`, `allowlist-diff`, the vendor-pin and tenant rows) is not
   weakened on a draft: those jobs live in other workflows and are left unchanged.
4. **Draft PRs run the light set.** `ci.yml` adds `ready_for_review` to its `pull_request` types.
   While `github.event.pull_request.draft` is true and the kill-switch is on, the heavy test families
   do not run; marking the PR ready runs the full set on the same head, so a PR makes one full run
   per ready head rather than one per draft push. A PR that makes fewer than two draft pushes loses
   by design (the break-even is stated in the plan).
5. **PR runs may select affected suites; merge_group may not.** The `--affected` selection already
   shipped by ADR-242 and `--print-selection` (#9307) is computed once per run, not per shard leg,
   and PR runs decline unselected suites inside the runner, the same call-site opt-in ADR-262 uses.
   `merge_group`, `push`, `workflow_dispatch`, `schedule`, an undeterminable diff and a runner edit
   keep the full battery. This amends ADR-262 (extends the PR arm from five batteries to the
   affected set) and ADR-183 (the CI backstop for a PR is the affected set; the full battery moves to
   the queue).
6. **Per-push fan-out is trimmed only where no required context moves**, or where the context is
   named and its owner agrees. Security posture changes (CodeQL query suite or event scope) need a
   CLO/CTO decision of their own.
7. **The measurement protocol is part of the decision.** Job-minutes are counted from the jobs API,
   **runner-bound jobs only**, per workflow and event, with `gh api --paginate` writing to a file and
   `jq -s` aggregating afterwards (never `--paginate` with `--jq` aggregates). A committed census
   script is the single authority for every before/after number, and a stage is not "done" until its
   post-merge census is attached to its tracking issue.
8. **Supply gate.** A self-hosted runner path requires, at minimum: ephemeral JIT registration through
   a dedicated minimal GitHub App, a runner group restricted to this repository and an explicit
   workflow list, no fork or `pull_request_target` routing, secret-free jobs on trusted refs first
   (`merge_group`, `push`), a Terraform root of its own with an R2 backend, and a repository-variable
   fallback to `ubuntu-latest`. Larger runners are used only as a flippable, spend-capped hybrid.

## Consequences

- A heavy failure on a draft is found at ready time rather than at the draft push, and a failure the
  affected set missed is found in the merge queue (a ~148 job-minute candidate run plus a re-queue).
  The break-even escape rate for stage 4 is roughly the saved minutes per PR run divided by that
  cost (and a queue failure also ejects the entries behind it), about 12 to 16 percent; the stage's exit
  criterion is far below it. Stage 3 saves only above about three draft pushes per PR on the measured
  window, so the cheaper alternative (no draft push before a local `--affected` run passes) is checked
  first.
- The required `test` aggregator gains a named, mutation-guarded skip arm. That is the one place a
  false green could be introduced, so it carries a Guard Contract in the plan.
- Each kill-switch is a repository variable flipped with `gh variable set` (no `github_actions_variable`
  resource exists in `infra/github`, so it is not Terraform-managed) and carries a removal trigger (30
  days with zero escapes) so it does not harden into a permanent fork.
- `ship`'s `battery-owed.sh` reads a required context as satisfied when its newest completed row is
  `success`, which would read a light draft `test` as the full battery and skip the local gate; stage 3
  must make the light result distinguishable before it is enabled.

## Cost Impacts

None for stages 1 to 4 (standard runners are free for a public repository; the saving is queue time,
not dollars). Lever 5 options carry costs recorded in the memo (larger runners are metered; Hetzner
server prices come from `knowledge-base/operations/expenses.md`; Enterprise is unquoted). No expense
row is added by this ADR.

## NFR Impacts

None.

## Principle Alignment

AP-001 (Terraform-only): Aligned. The kill-switch variable and any future runner root go through
Terraform; this ADR provisions nothing. No other principle deviation.
