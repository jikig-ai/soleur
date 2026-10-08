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

**Proposed, 2026-10-07 (#9721).** The file `status:` moves `proposed` to `adopting` when the CTO
approves this ADR in a review comment on a PR that edits the line, and no stage PR that changes CI
behaviour (S2, S3, S4; S1 exempt below) may merge while it reads `proposed`. On that edit the guardrail decisions (1, 2,
3, 6, 7 and 8) become `adopting`; Decisions 4 and 5 stay the proposed shape of stages 3 and 4. It moves
`adopting` to `accepted` when S5 closes with a post-merge census for S2 and S3, or with each closed by
its entry gate or stop rule. Every stage that changes CI behaviour (S2, S3, S4) takes effect only when
its own PR appends a dated `## Amendment` to this ADR (Decision 3(g)), so finishing one stage cannot
activate an unrun one. S1 is exempt from 3(c), (d) and (g): its smoke gate is a PR-only, non-required
job that runs unconditionally off `pull_request` and fails open, it moves no required context or merge
authority, and its rollback is a revert (a variable would add a switch to guard 1.8% of minutes); S1's
census script changes no CI behaviour and S5 is decision-only, so neither appends an amendment. Nothing
in this ADR provisions infrastructure.

> **Superseded 2026-10-08 (S1, #9727):** two clauses above no longer describe S1. The smoke gate does not run
> "unconditionally off `pull_request`": `smoke-relevance` runs on every pull request, and `smoke-tests` is now
> path-conditional (it skips only when the pull request event is not cancelled, the gate job succeeded and its output
> is exactly `false`; on any other event it still does not run). The exemption from 3(c), (d) and (g) rests instead
> on: a non-required context, a fail-open gate, rollback by revert, and a saving bounded at about 134 job-minutes per
> 6 h (1.8% of the 7,456 job-minute baseline in the Context, 1.5% of the 9,045 the committed census reports for the
> same window). And "neither appends an amendment" was a floor, not a ban: S1 appends the amendment at the end of this
> file. S1 is therefore merged, not done, until the census evidence named in the amendment is attached. The original
> sentences are kept above unedited.

### Stage status

Append-only: a change is a dated line added under the table (`- 2026-MM-DD S3 amended`, `- ... S3
live`), never an edit of an earlier row, so the current state of a stage is the last dated line that
names it (the column below is the initial state only). `live` means the stage's dark-launch exit
criterion passed (ADR file statuses use `active`, so the stage word differs on purpose).

| Stage | Lever | Tracking issue | Initial state |
|---|---|---|---|
| S1 | Census script and secret-scan smoke path gate | #9727 | not started |
| S2 | Push-run dedupe | #9512 | not started |
| S3 | Draft PRs run the light set | #9728 | not started |
| S4 | PR runs select the affected suites | #9729 | not started |
| S5 | Re-measure, then CodeQL, Code Quality and supply decision | #9730 | not started |

- 2026-10-08 S1 amended (#9727; see `## Amendment 2026-10-08 (S1, #9727)` below)

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
| Minutes of the window at 55+ concurrent | First pass 77 of 349 sampled minutes (22%); the re-run uses all 360: 82 of 360 (22.8%) at 55 or more, 45 of 360 (12.5%) at 58 or more, 2 of 360 (0.6%) at the 60-job cap itself |
| `CI` workflow, by event | pull_request 3,094 (31 runs, 99.8 per run), merge_group 1,183 (8 runs, 147.9), push main 1,018 (7 runs, 145.4) |
| `test-scripts` share of a CI run | 64% of a PR run, 63% of a merge_group run |
| Draft-state PR events | 1,814 of 4,218 PR-event job-minutes (43%); 1,319 of them in `CI` |
| Dynamic CodeQL-family runs | 601 job-minutes, 521 of them on PR heads (first pass); the re-run measured 613 and 533 on PR heads, split 294 code scanning (advisory per ADR-270) + 239 GitHub Code Quality, two different features (plan) |
| Cancelled jobs that held a runner | 304 job-minutes (4%) |

The 60-job cap is account-wide: the org's private repositories share the pool and are not visible to
this public-repository analysis, so the measured peak understates total demand on the pool.

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
   been re-measured: S2 and S3 each have a post-merge census, or are closed by their entry gate or
   stop rule. Supply options are recorded in the lever-5 memo and decided in a separate ADR.
2. **The authority invariant, with named residuals.** On the queue path, reductions hold: the
   `merge_group` run executes the full battery against the candidate tree (the candidate's own
   `ci.yml` and runner, so the authority is only as strong as that tree). The push-to-`main` run keeps
   producing the success conclusion the deploy arm's `workflow_run` trust ladder needs; it may be
   elided only per SHA, keyed on a green `merge_group` run for that exact head SHA (#9512), never by
   static removal. Both S2 designs change ADR-217, so S2's PR appends an ADR-217 amendment whichever
   wins. An attestation job that reads a `merge_group` conclusion and lets the push run conclude
   `success` manufactures a push verdict from another run's value, against ADR-217's "the verdict never
   crosses as a value". Keying the deploy `workflow_run` arm on the `merge_group` run for that head SHA
   and dropping the push run (no run then asserts a success it did not earn) changes the trigger that
   ADR-217 Decision 2 establishes. S2's plan compares the two before choosing; S2's stop rule: stop and close the stage if the
   keyed-attestation design cannot keep the deploy gate's verdict per SHA.

   **Named residual, owner S4's plan with the repository admins: the admin-merge route.** It is the
   only route that skips the queue (`gh pr merge --admin` or "merge without waiting" by an
   OrganizationAdmin or a repository Admin-role actor; the ruleset bypass mode is `pull_request`, so a
   PR is still required and direct pushes are closed). `admin-merge-ready.sh` is an agent-side
   convention, not a hook or a ruleset rule; any admin token merges without it. The full-battery
   marker (S4 entry gate, Decision 5) is a completed `CI` run on the head SHA that ran the full
   battery and concluded `success`. A full-mode and an affected-mode PR run share head SHA, event and conclusion, so
   S4 adds a `run-name` suffix `[full]` to `ci.yml` that only full-battery runs carry (readable as
   `display_title`); affected-mode PR runs never do. The producer exists: a `workflow_dispatch` of
   `ci.yml` (ADR-262's force-full lever) and any full-mode PR run, so after a rollback (variable unset,
   full PR runs) the marker is still emitted and the admin route does not stall. S4 teaches
   `admin-merge-ready.sh` to read it from the runs API on head SHA, event, display_title and run
   conclusion (a completed run with conclusion `success` whose display_title ends in `[full]`, or event
   `workflow_dispatch` with the full input), not by check name, because any `checks: write` token can post a check run under any name (KNOWN LIMIT
   (b) in the script). The marker stops accidents by agents, not an adversary. The residual is reduced,
   not closed: a human or other-token `--admin` merge, and a bypass actor editing the ruleset, still
   land an affected-only-green PR. S4 therefore also needs an admin-side control decided with the
   repository admins before it starts (Decision 5 entry gates), and the residual is counted in the
   escape metric. The detective control for bypass actors is `scripts/ci-required-ruleset-canonical-bypass-actors.json` and the
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
   the full set on the same head. Net saving at steady state (every draft PR is eventually readied, r = 7
   in the window) is about 180 job-minutes per 6h window on first-pass inputs and about 895 on the
   re-measure inputs (formula and table in the plan); the in-window transient (3 to 4 readied PRs,
   591 to 1,277) is not the steady state. The break-even is about 2.2 draft pushes per draft PR on
   first-pass inputs (about 1.1 on the re-measure inputs) against a measured pre-policy mean of 2.6,
   so it is marginal. Numeric entry gate: the pre-policy and the post-policy mean pushes per draft PR
   are measured separately, with the cheaper policy (no draft push before a local `--affected` run
   passes) applied first; stage 3 proceeds only if the post-policy mean is at least 2.75 (the 2.2
   first-pass break-even plus a 25% margin). The gate may legitimately fail, because that policy
   exists to lower draft pushes; S3 then closes by its own stop rule (the same 2.75), and its exit adds
   a net criterion (plan, S3 row).
   - **Option R is the decision:** the draft `test` aggregator concludes red ("full battery owed at
     ready"), so a PR cannot be enqueued until the ready run replaces the row and no consumer can read
     a light result as green. It fails toward stall (safe). The red row stays on the head for the whole
     ready run (the aggregator is created only after the shards end: up to about 38 minutes, since the 12
     successful PR `CI` runs in the window took 14 to 38, median about 28, and failed runs up to 51), so for a
     non-draft head with a red `test` and the newest `CI` `pull_request` run still in progress, the
     consumers (`monitor-pr-checks.sh`, ship Phase 7 `required_failed`, `drain-prs` triage, `gh pr
     checks` readers, `admin-merge-ready.sh --wait`) must resolve the verdict from the newest non-draft
     run at HEAD, never from the check row. A PR whose ready run is never created (wrong token,
     dropped event) or ran light because the live draft read lagged stalls with `test` red; stage 3
     adds an owner-visible signal keyed on a non-draft head whose newest `test` is draft-mode red for
     more than N minutes (N above the observed maximum (about 38 min success, 51 min failed), fixed in S3's plan), not only on a
     missing ready run, because the ADR-270 stall probe watches queue entries only.
   - **Option T is REJECTED** (a success marker plus a tolerance arm). The ruleset cannot enforce a
     marker; a marker made a required context would land in `scripts/required-checks.txt`, from which the
     composite action `bot-pr-with-synthetic-checks` derives its names and would post it green for
     every bot PR, fabricating the signal it exists to carry (the `SYNTHETIC_CHECK_NAMES` list in
     `_cron-safe-commit.ts` is hard-coded and needs a manual add); and it fails open on the admin
     route.
   - **Dark-launch cost.** The `ready_for_review` entry in `types` is not gated by the variable: while
     the variable is unset every drafted-then-readied PR gets up to one extra full run (about 95 to 137
     job-minutes; the skip arm below may avoid it), so the dark phase raises demand and "variable unset" is not a full rollback. The
     ready-triggered run must NOT be gated on the kill-switch variable: a variable flipped between the
     draft push and the ready transition would skip the ready run or post a skipped or tolerated row
     newer than the red one, and a skipped required check posts green (the #8450 pattern). The only
     allowed form is that the ready run runs the full battery unless the head's own draft run
     concluded a full-mode `test` success, read from the API (a failed or undeterminable read runs
     full); any skip arm concludes explicitly, never `skipped`, and Guard 1 carries a mutation row for
     it. The non-switchable parts (the `types` entry, the ship Phase 6 wait,
     the `admin-merge-ready.sh` and `battery-owed.sh` changes) are listed under the S3 Rollback.
5. **PR runs may select affected suites; merge_group may not (stage 4).** The `--affected` selection
   already shipped by ADR-242 and `--print-selection` (#9307) is computed once per run, not per shard
   leg, and PR runs decline unselected suites inside the runner, the same call-site opt-in ADR-262
   uses, each decline a counted verdict (ADR-181). `merge_group`, `push`, `workflow_dispatch`,
   `schedule`, an undeterminable diff and a runner edit keep the full battery. Stage 4's PR appends pointer
   amendments to ADR-262 (recording that its R1 premise and its admission rule are reversed for the PR
   arm, which grows from five batteries to the affected set) and to ADR-183, adding `amends:` to its
   frontmatter and `amended_by:` to the targets. ADR-183's amendment is a pointer only: its decision (the full local battery at ship) is unchanged, its
   context premise (CI's required `test` blocks merge on the full battery) changes. Entry gates:
   `admin-merge-ready.sh` demands the full-battery marker of Decision 2; an admin-side control is
   decided with the repository admins (narrowing the bypass actors of the CI Required ruleset, or a
   detective post-merge probe that flags any bypass merge whose head lacks the marker); and the "runner
   changed means full battery" detector and the affected-selection index are evaluated from a trusted
   base-ref copy, never the PR's own tree (otherwise a PR can edit the index and shrink its own gate on
   both arms at once); the registration-only carve-out stays out of PR mode. Minutes target (Decision 3(e)): PR `CI`
   job-minutes per run down at least 20% (about 20 of 99.8), at a replay escape rate under 2%.
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

## Amendment 2026-10-08 (S1, #9727)

Status stays `proposed`. This amendment is non-activating: it records what stage 1 delivered, supersedes two Status clauses (see the dated note under Status) and activates no other stage.

- **Delivered.** S1 added `scripts/ci-demand-census.sh` (the measurement authority Decision 7 names) and a path gate for the secret-scan `smoke-tests` matrix: a new fail-open `smoke-relevance` job lists the pull request's files through the API, and the ten smoke cases run only when the PR touches a file they exercise, or when the changed-file list cannot be fully determined. Both are additive. No required context, merge authority or non-`pull_request` behaviour moved.
- **Dropped, with the residual named.** The weekly smoke arm the issue allowed for was dropped, because no document claims weekly smoke coverage: every "weekly" in the secret-scanning runbook means the gitleaks scan, which the smoke job never fed. No schedule arm and no kill-switch variable were added; the rollback is a revert. The accepted residual: the smoke matrix was also, in effect, a canary for runner-image and tool drift (it ran on every PR); it now runs on PRs that touch a subject path, so that drift surfaces at the next such PR rather than within hours. S5 (#9730) re-measures and decides whether a `schedule` arm is worth its cost.
- **Decision 3(e).** The numeric target: the secret-scan smoke-related minutes per pull-request run (the `smoke` stem plus the `smoke-relevance` stem) fall by at least 80% against the baseline window, where `smoke` was 134.4 job-minutes over 33 runs that ran it and 2.92 job-minutes per completed secret-scan PR run (46 runs). That is a target of at most 0.584 job-minutes per run. Every run pays the gate (about 0.09 job-minutes, measured on the comparable `pr-quality-guards.yml` detect job) and a run that executes the matrix costs about 4.07, so the target holds while the share of runs that touch a subject path stays at or under about 12% ((0.584 - 0.09) / 4.07). Measure over at least 48 hours or 100 pull-request runs and report the run-weighted hit share next to the skip share. An escape rate is not directly observable (a skipped case has no verdict), so none is reported; the skip share and the hit share stand in for it, and nothing in the required set depends on either. The census skip share is a lower bound for gate skips (a run holding a cancelled job counts its skipped stem as queue-cancelled) and may include skips caused by an upstream job failing.
- **How to measure.** From a developer shell with `gh auth` (the script refuses live mode in CI; fixture mode runs anywhere): `end=$(date -u -d '-1 hour' +%Y-%m-%dT%H:00:00Z); start=$(date -u -d '-7 hours' +%Y-%m-%dT%H:00:00Z); bash scripts/ci-demand-census.sh --start "$start" --end "$end" --summary > /var/tmp/ci-census.txt`. `--end` is exclusive, the window is fetched in one-hour sub-windows (the runs listing is capped at 1,000 results), a single window is at most 12 hours, a 6 h window takes about 15 minutes (an estimate), and a self-check failure exits 3 with no total. Add `--workflow secret-scan.yml` to cost one workflow only (the call the stage evidence uses). A longer period is covered by consecutive non-overlapping windows: sum `TOTAL_JOB_SECONDS` and the `runs_*` columns across them and recompute per-run minutes from the totals (the printed minute rows are rounded independently and are not additive).
- **How to roll back.** Revert the pull request, or by hand: restore the original condition on `smoke-tests` (`if: github.event_name == 'pull_request'`), delete its `needs: smoke-relevance`, delete the `smoke-relevance` job and restore the secret-scan row of `scripts/pr-fanout-ledger.txt` to 6 jobs. Deleting only the `if:` line is not a rollback: with no `if:` the job's implicit `success()` condition applies, so on a pull request the matrix would run even when the gate answers `false` (the saving is lost) and would be skipped whenever the gate fails or is skipped (inverting fail-open).
- **Evidence ownership.** The baseline census is attached to #9727 before merge (the committed census reports 9,045.1 job-minutes for the parent plan's 2026-10-07 13:04-19:04Z window against the 8,414 of the parent plan's re-measure, +7.5%; it is not reconciled to the digit and moves in the direction the documented lower-bound behaviour predicts). The post-merge census (`--workflow secret-scan.yml`, a closed window after merge) and the first no-subject-path pull request that shows `smoke-relevance` green and the `smoke (...)` row skipped are collected by S2 (#9512) as its first step, and the `S1 live` line is appended by the S2 amendment (or by a docs commit if S2 does not follow). `Closes #9727` closes the issue at merge, before that evidence exists; this is a deviation from Decision 7's reading of "done", recorded here: S1 is merged, not done, until that evidence is attached.
- **Test cost, counted against the saving.** The two suites S1 adds (`scripts/ci-demand-census.test.sh`, `scripts/secret-scan-smoke-gate.test.sh`) run in the full battery on every CI run and measured about 30 s and 20 s on a loaded 16-core machine (about 15 s each when idle; a 4-vCPU hosted runner will be slower). At the baseline window's 54 CI runs per 6 h that is roughly 30 to 45 job-minutes per 6 h, up to about a third of the 118 net job-minutes the gate saves. The saving stays positive, and S4 (affected-only PR suites) removes this cost from pull-request runs; S5 re-measures it with the census (`test-scripts` stem).
- **Required rollup.** A job-level skipped matrix job posts one check named `smoke (${{ matrix.case }})`, not ten, so promoting any `smoke (*)` context to required (the deferred rollup recorded under ADR-032) needs an always-run aggregator that treats that skipped row as success by name (Decision 3(a)); until then `skipped` is never read as green by anything in the required set.
- **Corrections.** Decision 5 cites `--print-selection` as #9307; the merged pull request is #9306 (#9307 is the open issue). The census `STEM` rows carry `runs_ran`, `runs_skipped` and `runs_runnerless`; a queue-cancelled or superseded run is counted in `runs_runnerless`, not `runs_skipped`.
