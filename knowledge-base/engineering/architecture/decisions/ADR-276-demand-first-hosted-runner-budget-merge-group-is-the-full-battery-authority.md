---
title: "Hosted-runner demand is cut before supply is raised; merge_group (and the push-main deploy arm) stay the full-battery authority"
status: proposed
date: 2026-10-07
issue: 9721
related_adrs: [ADR-032, ADR-181, ADR-183, ADR-216, ADR-217, ADR-242, ADR-262, ADR-270]
tags: [ci, github-actions, runners, merge-queue, cost]
brand_survival_threshold: aggregate pattern
---

# ADR-276: Hosted-runner demand is cut before supply is raised; merge_group (and the push-main deploy arm) stay the full-battery authority

## Status

**Proposed, 2026-10-07 (#9721).** On acceptance the guardrail decisions (1, 2, 3, 6, 7 and 8) become
`adopting`. Decisions 4 and 5 are the proposed shape of stages 3 and 4. Every stage, stage 2 included,
takes effect only when its own PR appends a dated `## Amendment` to this ADR (Decision 3(g)), so
finishing one stage cannot activate an unrun one. The file `status:` stays within `proposed`,
`adopting` and `accepted`; per-stage state lives only in the table below. Nothing in this ADR
provisions infrastructure.

### Stage status

Append-only: a change is a dated line added under the table (`- 2026-MM-DD S3 amended`, `- ... S3
active`), never an edit of an earlier row. `active` means the stage's dark-launch exit criterion passed.

| Stage | Lever | Tracking issue | State |
|---|---|---|---|
| S1 | Census script and secret-scan smoke path gate | #9727 | not started |
| S2 | Push-run dedupe | #9512 | not started |
| S3 | Draft PRs run the light set | #9728 | not started |
| S4 | PR runs select the affected suites | #9729 | not started |
| S5 | Re-measure, then CodeQL, Code Quality and supply decision | #9730 | not started |

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
| Minutes of the window at 55+ concurrent | 77 of 349 (22%); at the 60-job cap itself a re-run found 2 of 360 (0.6%) |
| `CI` workflow, by event | pull_request 3,094 (31 runs, 99.8 per run), merge_group 1,183 (8 runs, 147.9), push main 1,018 (7 runs, 145.4) |
| `test-scripts` share of a CI run | 64% of a PR run, 63% of a merge_group run |
| Draft-state PR events | 1,814 of 4,218 PR-event job-minutes (43%); 1,319 of them in `CI` |
| Dynamic CodeQL-family runs | 601 job-minutes, 521 of them on PR heads; two different features (code scanning, advisory per ADR-270, and GitHub Code Quality), split in the plan |
| Cancelled jobs that held a runner | 304 job-minutes (4%) |

The saturation is bursty rather than constant (mean 21 against a cap of 60), so queue wait is a
peak-demand problem, and a merged PR pays the full battery three times: on the PR head (~100),
in the merge_group candidate (~148) and again on the push to `main` (~145).

Existing mechanisms this ADR must not duplicate: ADR-216 and `cancel-superseded-pr-runs.yml` already
collapse superseded PR heads (only 4% of runner minutes are lost to cancellation); ADR-262 already
path-gates five self-test mutation batteries on pull_request; issue #8683 (BEHIND-sync pushes) is a
separate lever and is out of scope here.

**What changed since ADR-262.** ADR-262 was written when "No merge queue is enforced" (its R1). It
rejected two alternatives: "adopting the affected classifier wholesale on CI" (blast radius, ~500
suites) and "job-level path filters on the heavy legs" (a skipped job in a required chain puts
unreported-versus-skipped semantics into the required context); its admission rule (Decision 4) also
says behavioural suites over product code do not qualify. Decision 5 knowingly reverses the first
rejection and the admission rule, and Decision 4 reverses the second (a job-level `if:` on the heavy
families). The justification is ADR-270: the merge queue is now enforced, so the candidate run is the
enforced gate and a reduced PR run no longer has to be the last line of defence. ADR-262's stale R1
premise gets a pointer amendment in stage 4's PR.

## Considered Options

Letters here are local to this ADR. The lever-5 memo labels its supply options S-A (Hetzner
ephemeral), S-B (larger runners), S-C (Enterprise) and S-D (demand levers only); Option A below spans
S-A to S-C and the chosen Option C corresponds to S-D.

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
  reduction has a kill-switch (with the non-switchable parts named in Decision 4). Cons: failures
  surface later (at ready, or in the queue), so each stage must carry a measured escape rate. **Chosen.**
- **D. Do nothing and wait.** Rejected: the measured PR-state waste (43% of PR-event minutes in
  draft) is paid every day.

## Decision

1. **Demand first, supply second.** No supply change is adopted until the demand stages below have
   been re-measured. Supply options are recorded in the lever-5 memo and decided in a separate ADR.
2. **The authority invariant, with named residuals.** On the queue path, reductions hold: the
   `merge_group` run executes the full battery against the candidate tree (the candidate's own
   `ci.yml` and runner, so the authority is only as strong as that tree). The push-to-`main` run keeps
   producing the success conclusion the deploy arm's `workflow_run` trust ladder needs; it may be
   elided only per SHA, keyed on a green `merge_group` run for that exact head SHA (#9512), never by
   static removal. This narrows ADR-217 ("the verdict never crosses as a value"): an attestation job
   that reads a `merge_group` conclusion and lets the push run conclude `success` manufactures a push
   verdict from another run's value. Before choosing, S2's plan must compare that design with keying
   the deploy `workflow_run` arm on the `merge_group` run for that head SHA and dropping the push run
   (no run then asserts a success it did not earn), and must append an amendment to ADR-217 if the
   attestation design wins.

   **Named residual, owner S4's plan with the repository admins: the admin-merge route.** It is the
   only route that skips the queue (`gh pr merge --admin` or "merge without waiting" by an
   OrganizationAdmin or a repository Admin-role actor; the ruleset bypass mode is `pull_request`, so a
   PR is still required and direct pushes are closed). `admin-merge-ready.sh` is an agent-side
   convention, not a hook or a ruleset rule; any admin token merges without it. A reduction does not
   hold on this route until `admin-merge-ready.sh` demands a full-battery marker at the head before
   treating an affected-set `test` success as green (S4 entry gate, Decision 5). The detective control
   for bypass actors is `scripts/ci-required-ruleset-canonical-bypass-actors.json` and the
   `cron-ruleset-bypass-audit` cron. Two more limits on "authority": several required contexts are not
   re-run at `merge_group` (the CLA contexts are verified synthetics, `rename-guard` and
   `allowlist-diff` post a pass without re-running, the vendor-pin and tenant rows trust the PR run),
   and bot PRs receive a synthetic PR-level `test`, so `merge_group` is their only real run.
3. **PR-level reductions are allowed only when ALL hold:** (a) no required context is renamed,
   removed or left pending: a gated job still reports, and any aggregator that reads
   `needs.*.result` and tolerates a skip names each skip reason it tolerates (one per stage, each with
   its own guard contract) rather than tolerating `skipped` generally, and every consumer of that
   context (`battery-owed.sh`, the deploy `workflow_run` arm, `post-merge-monitor.yml`) is checked so a
   reduced result is never read as a full one; (b) the decision fails closed to the full battery when
   the draft state, the diff or the selection is undeterminable; (c) a repository variable is a
   kill-switch whose accepted value is exactly `on` (unset, empty, `ON`, `on` with surrounding whitespace or any other string
   means full CI; the comparison is made in the step shell because the Actions `==` operator ignores
   case); (d) the stage dark-launches behind a kill-switch plus a stage-specific proof (a canary,
   an experiment or a replay) and has a named exit criterion; (e) the stage reports the minutes it
   removed (with a numeric target) and the escape rate it caused, measured by the committed census
   (Decision 7); (f) a context whose `merge_group` arm trusts the PR run (`rename-guard`,
   `allowlist-diff`, the vendor-pin and tenant rows) is not weakened on a draft: those jobs live in
   other workflows and are left unchanged; (g) the stage's own PR appends a dated `## Amendment` to
   this ADR naming the stage, its kill-switch, its exit criterion and its census link before any
   switch is flipped; (h) ADR-270 is `accepted` before any stage moves a check from the PR run to the
   queue (stages 3 and 4), because those raise the cost of a queue failure.
4. **Draft PRs run the light set (stage 3).** `ci.yml` adds `ready_for_review` to its `pull_request`
   types (the full list `opened, synchronize, reopened, ready_for_review`). While the live draft state
   of the PR (read from the API at run time, never only from the event payload, which a re-run reuses)
   is draft and the kill-switch is on, the heavy test families do not run; marking the PR ready runs
   the full set on the same head. Net saving is about 600 job-minutes per 6h window at the plan's
   inputs (sensitivity 180 to 730 in the plan, formula there) and the break-even is about 2.2 to 3 draft
   pushes per draft PR against a measured mean of 2.6, so it is marginal. Numeric entry gate: the
   measured distribution of draft pushes per PR, with the cheaper policy (no draft push before a local
   `--affected` run passes) applied first; stage 3 proceeds only if the post-policy mean is at least 3,
   and its exit adds a net criterion and a stop rule (plan, S3 row).
   - **Option R is the decision:** the draft `test` aggregator concludes red ("full battery owed at
     ready"), so a PR cannot be enqueued until the ready run replaces the row and no consumer can read
     a light result as green. It fails toward stall (safe). The red row stays on the head for the whole
     ready run (the aggregator is created only after the shards end, 25 to 30 minutes), so for a
     non-draft head with a red `test` and the newest `CI` `pull_request` run still in progress, the
     consumers (`monitor-pr-checks.sh`, ship Phase 7 `required_failed`, `drain-prs` triage, `gh pr
     checks` readers, `admin-merge-ready.sh --wait`) must resolve the verdict from the newest non-draft
     run at HEAD, never from the check row. A PR for which no ready run is ever created (wrong token,
     dropped event) stalls with `test` red; stage 3 adds an owner-visible signal for it, because the
     ADR-270 stall probe watches queue entries only.
   - **Option T is REJECTED** (a success marker plus a tolerance arm). The ruleset cannot enforce a
     marker; a marker made a required context would land in `scripts/required-checks.txt` and
     `bot-pr-with-synthetic-checks` and `SYNTHETIC_CHECK_NAMES` in `_cron-safe-commit.ts` would post it
     green for every bot PR, fabricating the signal it exists to carry; and it fails open on the
     admin route.
   - **Dark-launch cost.** The `ready_for_review` entry in `types` is not gated by the variable: while
     the variable is unset every drafted-then-readied PR gets one extra full run (about 95 to 137
     job-minutes), so the dark phase raises demand and "variable unset" is not a full rollback. Gating
     the ready-triggered run at job level is allowed only if the S3 same-name rollup gate shows the
     required names stay stable. The non-switchable parts (the `types` entry, the ship Phase 6 wait,
     the `admin-merge-ready.sh` and `battery-owed.sh` changes) are listed under the S3 Rollback.
5. **PR runs may select affected suites; merge_group may not (stage 4).** The `--affected` selection
   already shipped by ADR-242 and `--print-selection` (#9307) is computed once per run, not per shard
   leg, and PR runs decline unselected suites inside the runner, the same call-site opt-in ADR-262
   uses, each decline a counted verdict (ADR-181). `merge_group`, `push`, `workflow_dispatch`,
   `schedule`, an undeterminable diff and a runner edit keep the full battery. Stage 4's PR will amend
   ADR-262 (the PR arm grows from five batteries to the affected set) and ADR-183 by an appended
   amendment section, adding `amends:` to its frontmatter and `amended_by:` to the targets. ADR-183
   gets a pointer amendment only: its decision (the full local battery at ship) is unchanged, its
   context premise (CI's required `test` blocks merge on the full battery) changes. Entry gates:
   `admin-merge-ready.sh` demands a full-battery marker at the head (Decision 2), and the "runner
   changed means full battery" detector and the affected-selection index are evaluated from a trusted
   base-ref copy, never the PR's own tree (otherwise a PR can edit the index and shrink its own gate on
   both arms at once); the registration-only carve-out stays out of PR mode.
6. **Per-push fan-out is trimmed only where no required context moves**, or where the context is
   named and its owner agrees. Security posture changes need a CLO/CTO decision of their own: CodeQL
   code scanning (query suite or event scope, advisory per ADR-270) and GitHub Code Quality are
   different features with different switches, and ADR-270 covers only the first.
7. **The measurement protocol is part of the decision.** Job-minutes are counted from the jobs API,
   **runner-bound jobs only**, per workflow and event, with `gh api --paginate` writing to a file and
   `jq -s` aggregating afterwards (never `--paginate` with `--jq` aggregates). A committed census
   script is the single authority for every before/after number, and a stage is not "done" until its
   post-merge census is attached to the stage's own tracking issue (the Stage status table).
8. **Supply gate** (a subset of the lever-5 memo's seven conditions, all of which are binding; the
   memo is authoritative). A self-hosted runner path requires, at minimum: ephemeral JIT registration
   through a dedicated minimal GitHub App, a runner group restricted to this repository and an
   explicit workflow list, routing derived from each workflow's triggers (never fork,
   `pull_request_target`, `issues` or comment-driven workflows), secret-free jobs on post-gate but
   unreviewed refs first (`merge_group`, `push`), a Terraform root of its own with an R2 backend, and a
   repository-variable fallback to `ubuntu-latest`. Larger runners are used only as a flippable,
   spend-capped hybrid.

## Consequences

- A heavy failure on a draft is found at ready time rather than at the draft push, and a failure the
  affected set missed is found in the merge queue (a ~148 job-minute candidate run plus a re-queue).
  The break-even escape rate for stage 4 is roughly the saved minutes per PR run divided by that
  cost (and a queue failure also ejects the entries behind it), about 12 to 16 percent; the stage's exit
  criterion is far below it. Stage 3's break-even is Decision 4's.
- The required `test` aggregator gains a draft arm. Under Option R it concludes red, so the requirement
  is a mutation row proving a draft `test` can never read as success; a named tolerance arm exists
  only under the rejected Option T. The Guard Contract in the plan carries the matrix.
- Each kill-switch is a repository variable flipped with `gh variable set` (see Principle Alignment)
  and carries a removal trigger (30 days with zero escapes) so it does not harden into a permanent
  fork; removing it also ends the one-switch rollback for that arm, which is deliberate.
- `ship`'s `battery-owed.sh` reads a required context as satisfied when its newest completed row is
  `success`; under Option R a draft `test` is red, so it returns OWED, and stage 3 still carries a
  mutation row for it.

## Cost Impacts

None for stages 1 to 4 (standard runners are free for a public repository; the saving is queue time,
not dollars). Lever 5 options carry costs recorded in the memo (larger runners are metered; Hetzner
server prices come from `knowledge-base/operations/expenses.md`; Enterprise is unquoted). No expense
row is added by this ADR.

## NFR Impacts

None.

## Principle Alignment

AP-001 (Terraform-only): accepted carve-out. The kill-switch repository variable is set with
`gh variable set` and is not Terraform-managed (no `github_actions_variable` resource exists in
`infra/github`; `WATCHDOG_ARMED` and `GIT_DATA_ROOT_STATE_MIGRATED` are the precedents). That is
acceptable because the unset state is the safe one (full CI), the accepted value is exactly `on`, and
each variable has a 30-day removal trigger. Only a future runner root and its runner group are
Terraform; this ADR provisions nothing. ADR-032 holds: no required-context name changes. No other
principle deviation.
