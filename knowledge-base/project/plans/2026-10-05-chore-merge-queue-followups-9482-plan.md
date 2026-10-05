---
title: "chore: merge-queue follow-ups for #9482 (canary measurements, follow-up triage, stall-dispatch monitor routing)"
date: 2026-10-05
slug: merge-queue-followups-9482
branch: feat-one-shot-9482-merge-queue-followups
issue: 9482
type: chore
lane: cross-domain
priority: p2-medium
brand_survival_threshold: none
---

# chore: merge-queue follow-ups for #9482

## Overview

Continue the ADR-270 merge-queue adoption (status stays `adopting`) after follow-up (a), the Inngest
dispatch cron for the stall probe, shipped in #9491. Four work items, in the order the brief gave them,
split by what they produce:

| # | Item | Deliverable class | Output |
|---|------|-------------------|--------|
| 1 | ADR item 4: next `weakness-miner.yml` PR through the queue | Measure and comment; if no post-adoption PR exists yet, record "pending, next fire 2026-10-11T06:00Z" with the re-run command | One combined #9482 comment block; short ADR-270 canary record |
| 2 | Sync-push count per merged PR | Measure and comment | Same combined #9482 comment; ADR-270 canary row 9 |
| 3 | Follow-ups (b), (c), (d) | Triage against each follow-up's own stated trigger | One verdict per follow-up in the combined #9482 comment; one new tracking issue for (c); no code for (b) and (d) |
| 4 | #9493: route the `scheduled-merge-queue-stall-dispatch` monitor, decide the executor heartbeat | Code (Terraform) plus measure and comment | `.tf` + `alert-reference.json` PR; heartbeat decision in the combined comment and on #9493 |

Everything lands in the draft PR #9511 (branch `feat-one-shot-9482-merge-queue-followups`). The PR body
says `Ref #9482` and `Ref #9493`; neither is closed by merge (see Sharp Edges for why #9493 is closed by
hand after the apply is read back).

## Enhancement Summary

**Deepened on:** 2026-10-05. **Agents:** observability-coverage-reviewer, architecture-strategist, plus live verification
(cited PRs/issues, labels, rule ids, the discoverability command, the Sentry read-back command, the stall-title anchor).

Key improvements: (1) item 2's threshold reconciled with ADR-270's break-even (a before-minus-after delta of about 1.3,
which the pilot puts at the margin) and (d) downgraded to "not yet robustly measurable"; (2) (c)'s evidence gets a
denominator and the real deploy-chain constraint (`workflow_run` arm needs a push-event `CI` success; any change keyed
per SHA); (3) a red `merge-queue-stall-check.yml` run alerts nobody, recorded as an accepted gap with a tracked follow-up so
#9493 is not closed on quiet-window data; (4) Observability layer citations added; (5) the Scope Check rewritten to the
canonical schema; (6) the existing canary-log runbook (#9485) is indexed.

New considerations: the ADR heading says `# ADR-269` while the file is ADR-270 (pre-existing, not touched here); the
Network-Outage gate keyword `timeout` in this plan means the merge-queue check timeout, not a connectivity symptom, so that
gate does not apply.

## Research Insights

### Premise Validation (Phase 0.6)

Checked by command, today (2026-10-05, UTC):

- #9482 is OPEN. Its follow-up list is (a) landed, (b) fail-closed `codeql-to-issues.yml`, (c) skip the
  duplicate push-to-main CI run, (d) skip the hook's pre-enqueue sync. Each has its own re-evaluation trigger
  (quoted in Phase 1.3 below). The three operator decisions are the issue's "Decisions" 1 to 3 (deploy hold,
  brand-survival threshold, `actions`-language alerts), distinct from (b)/(c)/(d). (b)/(c)/(d) are NOT operator
  decisions; they are trigger-gated engineering follow-ups.
- #9493 is OPEN (`deferred-automation`, p3). Its body has TWO asks: route the monitor, and decide from measured
  data whether an executor-side heartbeat step is worth adding.
- #9455 (queue adoption) merged 2026-10-04T14:47:24Z. #9491 (follow-up a) merged 2026-10-05T08:34:05Z.
- **Item 1 premise is partly stale.** The last merged weakness-miner PR (#9479) merged 2026-10-04T11:51:51Z, which is
  2 h 55 min BEFORE the queue went live, and its timeline has no queue events (direct merge). No weakness-miner
  PR has merged since. The next scheduled fire is Sunday 2026-10-11T06:00Z (`cron: '0 6 * * 0'`). So the ADR item 4
  observation cannot be completed today; the correct outcome now is "pending, next fire dated, re-run command recorded".
- **The brief's runner-latency claim is weaker than stated.** "`run_started_at == created_at`" is true for every
  `workflow_dispatch` run by construction and says nothing about runner-pool wait. Runner wait shows up on the JOB:
  `jobs[0].started_at - run.created_at`. Measured on the three dispatched runs so far (09:10, 09:20, 09:30 UTC):
  4 s, 4 s, 4 s (n=3, quiet pool). The heartbeat decision must use the job-level number over a window that includes
  a busy period (Phase 1.4).
- Cited paths all exist on `origin/main`: `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`,
  `cron-monitors.tf`, `alert-reference.json`, `.github/workflows/weakness-miner.yml`,
  `.claude/hooks/pre-merge-rebase.sh`, `plugins/soleur/scripts/sync-pr-behind.sh`,
  `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`.
- ADR-corpus check for the mechanisms named: ADR-270 is the owner. Its Considered Options reject a bot pseudo-queue, a
  dropped strict policy and an advanced-CodeQL shim; none of this plan's mechanisms (measurements, a monitor route,
  a probe) is in a rejected-alternatives table. ADR-031 (Sentry as IaC) owns the two-PR rule; ADR-033 owns the
  Inngest-trigger/runner-execute shape.
- Monitor precondition for item 4 verified live (read-only, Doppler `prd`): detector `2359391`,
  name `scheduled-merge-queue-stall-dispatch`, type `monitor_check_in_failure`, `enabled: true`. The first apply
  has happened, so PR 2 of the two-PR rule can reference it.

### Pilot measurements already taken (inputs to the work phase, NOT the deliverable)

These came from throwaway `gh` pulls during planning. The work phase re-runs them with a frozen definition and
records the final numbers; they are here so the plan's triage verdicts are grounded.

**Sync merges per merged human PR** (definition: a commit on the PR whose second parent is an ancestor of
`origin/main`, i.e. a main-into-branch merge by the hook, the ship/merge-pr fence, `gh pr update-branch`, or by hand;
bot PRs excluded):

| Window | n | main-into-branch merges | mean per PR | PRs with at least 1 |
|--------|---|-------------------------|-------------|---------------------|
| Before the queue (human PRs merged 2026-09-28 to 2026-10-04T14:47Z, most recent 40) | 40 | 85 | 2.13 | 33 |
| After the queue (human PRs merged since 2026-10-04T14:47:24Z, includes #9455 itself) | 13 | 13 | 1.00 | not recorded |
| After the queue, excluding #9455 (its own syncs happened before the queue existed) | 12 | 10 | 0.83 | not recorded |

Follow-up (d)'s trigger is "at or above 1.3": NOT met on this pilot (0.83 to 1.00 against 1.3), though n=12 to 13 is
small. This count is commits, not pushes (two merges can share a push), so it is an upper bound on pushes; and it
counts every main-into-branch merge, so it upper-bounds the hook's own share. Both biases push toward "above
threshold", so a below-threshold result is the robust direction.

**Follow-up (c) premise** ("push SHA == `merge_group.head_sha`"): 12 of 12 `ci.yml` runs on `push` to `main` since
adoption have a head SHA that equals the head SHA of a successful `merge_group` CI run (for example `ac16f98227`,
`1ad302c07d`, `46b5460ebe`). The trigger IS met. Three further `merge_group` CI runs exist for candidates that failed
or were rebuilt (#9478 at 16:27Z, #9492 at 18:30Z, and #9488 built twice), which is the queue working as designed.

**Follow-up (b)'s triggers**: zero issues labelled `codeql-gate-degraded` (all states); `codeql-main-alert-gate.yml` has
15 of 15 recent runs `success`; ADR-270 has not flipped to `accepted`. NOT met. The `|| true` swallow on the alerts read
is still present at `.github/workflows/codeql-to-issues.yml:31`.

**Bot PRs already through the queue (adjacent evidence, not item 4):** `soleur-ai[bot]` PRs #9503 (enqueue 07:23:39Z,
merge 07:38:06Z, 14.5 min) and #9507 (enqueue 08:19:52Z, merge 08:52:28Z, 32.6 min, behind #9491) flowed
`AutoMergeEnabled -> AddedToMergeQueue -> Merged` with a `merge_group` CI run each. These are App-token PRs; item 4
is specifically the `GITHUB_TOKEN`-armed `weakness-miner.yml` path (the `bot-pr-with-synthetic-checks` composite
arms `gh pr merge --squash --auto` with `github.token`), so they do not satisfy item 4.

### Property List (Phase 0.6b)

- P1. ADR-270 item 4's status is backed by recorded evidence for a post-adoption weakness-miner PR (enqueue to merge
  timeline, `merge_group` run, any stall-check issue), or says "pending" with the next fire date.
- P2. The sync-push count per merged PR is a recorded number with a stated definition, window and n, for before and
  after the queue, so follow-up (d)'s trigger is judged from data.
- P3. Each of (b), (c), (d) carries an explicit trigger verdict (fired or not fired, with the evidence) on #9482, and
  none is actioned before its trigger fires. The three operator decisions are untouched.
- P4. A dead dispatcher or a failed dispatch of the stall probe reaches the operator by email (the #9493 route).
- P5. Whether an executor-side heartbeat is worth adding is decided from measured job-start latency, and recorded.
- P6. (Dropped at plan review.) Automated pickup of item 4 at the next fire: see the Cut List row for the follow-through probe.

### Cut List (Phase 0.6b)

| Mechanism considered | Property | Cut because / what already covers it |
|----------------------|----------|--------------------------------------|
| Dispatch `weakness-miner.yml` by hand now to manufacture the PR | P1 sooner | Cut. It merges a bot PR to `main` (a production write the brief did not ask for) and the weekly fire is 6 days out; "observe the next" is the brief's wording. `gh workflow run weakness-miner.yml` stays available if the operator wants early closure. |
| Commit a reusable sync-count script or dashboard | P2 | Cut. One-off measurement; the exact commands go in the #9482 comment so it is reproducible. The `merge_group`/queue canary is a time-boxed adoption record, not a permanent metric. |
| Implement (b) | P3 | Cut. Trigger not fired (above). Re-evaluate at the ADR flip, which is when its own trigger says to. |
| Implement (d) | P3 | Cut. Trigger not fired on the pilot; the hook already skips the sync when the origin/main delta is file-disjoint (#9401). The work phase re-measures and only escalates if the frozen number is at or above 1.3. |
| Implement (c) in this PR | P3 | Cut from THIS PR. Trigger fired, but the change removes or neuters the `push`-to-`main` CI run that `web-platform-release.yml`'s `workflow_run` trust ladder, `post-merge-monitor.yml` and others read the jobs API of. That is a deploy-chain redesign with its own plan. Tracked as a new issue (Phase 1.3). |
| Executor-side heartbeat step in `merge-queue-stall-check.yml` | P5 | Cut unless measured p90 job-start latency exceeds 5 min (Phase 1.4). It would also put Sentry secrets into a runner that today holds none (the dispatcher header's stated posture). |
| A new alert rule or a dedicated route for this monitor | P4 | Cut. `sentry_alert.cron_monitor_failure` already routes every other cron monitor to email; moving one label is the whole change. |
| Follow-through probe + hermetic suite + 3 registry rows + tracker issue for item 4 | P6 | Cut at plan review (both review panels fired on it: DHH and simplicity said cut; Kieran found two design defects, an open-PR blind spot and a reopen-on-later-failure trap on a closed tracker; the CTO called it over-built). It was the plan's only `inferred` item. What covers P6 instead: #9482 stays open with item 4 listed as pending and the re-run command recorded in the combined comment; a stalled bot PR is already caught by the existing `merge-queue-stall` issue path. #9482 is deliberately not enrolled as a follow-through tracker for the same reason: its remaining items (b), (d), item 4 and the operator decisions are not one probe-able condition. |
| Flip ADR-270 to `accepted` | P1 | Forbidden by the brief and by the ADR (canary items 1, 3, 4, 5, 7, 8, 9, 10 are still open). |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md`:
  two-PR rule; the route lives on the alert side (`sentry_alert.monitor_ids` is the detector id).
- `knowledge-base/project/learnings/2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`:
  descriptive prose containing a closing keyword plus an issue number in a PR body auto-closes the issue. The PR body for
  this change must not contain such prose.
- `knowledge-base/project/learnings/2026-03-04-gh-jq-does-not-support-arg-flag.md`: single-stage `gh --jq` does not
  forward `--arg`; use `--json` then standalone `jq --arg`.
- `knowledge-base/project/learnings/2026-10-04-a-queue-candidate-trust-check-premised-on-an-unmeasured-commit-shape.md`:
  measure the queue's commit shape rather than assume it (applied to the sync-merge definition below).

## Research Reconciliation: brief vs codebase and live state

| Brief claim | Reality | Plan response |
|-------------|---------|---------------|
| "Observe the next weakness-miner PR flowing through the queue" | No weakness-miner PR has merged since adoption; the last one (#9479) merged before #9455. Next fire 2026-10-11T06:00Z. | Item 1 records "pending" now with the dated next fire and the re-run command (Phase 1.1). ADR stays `adopting`. |
| "dispatched runs are spaced exactly 10:00 with `run_started_at == created_at`" | True, but `run_started_at == created_at` is structural for dispatched runs and is not a runner-wait measurement. | Heartbeat decision uses job `started_at` minus run `created_at` (4 s on n=3 so far), over a window including busy periods. |
| "Measure the hook's sync-push count" | The commits API gives main-into-branch merge commits, not pushes, and cannot separate the hook from the ship fence or `gh pr update-branch` (same default merge message). | Define the metric as main-into-branch merges per merged human PR (an upper bound on pushes and on the hook's share); state the bias and its direction. |
| "(b), (c), (d): re-read the issue for their definitions" | Each has a stated trigger. (c)'s fired on measured data; (b) and (d) did not. (c)'s "must still emit the CI completion event the deploy waits on" makes it a deploy-chain change, not a one-file edit. | Verdict per follow-up on #9482; (c) gets its own issue; no code for (b)/(c)/(d) here. |
| "#9493: route the monitor" | #9493 also asks for the heartbeat decision from measured data. | Both are in this plan; #9493 is closed by hand after the apply is read back, not by the merge. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. A wrongly moved monitor label either leaves the
stall-dispatch monitor unrouted (status quo: a Sentry issue opens but no email) or, if the reference file is wrong, a red
`plan_pr`/apply on `infra/sentry` that blocks other Sentry changes until fixed. No product surface, no runtime path.

**If this leaks, the user's data is exposed via:** no vector. The change adds an operator-only email route for a liveness
monitor and records public-repo measurements (PR numbers, timestamps, counts). No user data, credentials or workspace
content is read or written. The measurements read only public PR/issue/run metadata.

**Brand-survival threshold:** none.

- threshold: none, reason: the diff touches `apps/web-platform/infra/` (a sensitive path) only to route an operator-only
  cron monitor to the existing email alert, with no user data, auth, billing or runtime behaviour involved.

## Implementation Phases

### Phase 0: work-time preflight (read-only)

1. `git fetch origin main`; confirm the queue is still on (`gh api graphql` `mergeQueue(branch:"main")` non-null) and
   the monitor is still unrouted (`grep -n scheduled_merge_queue_stall_dispatch apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
   shows it only in the unrouted map). If the branch is BEHIND, sync is the hook's job; do not push a queued PR.
2. Re-read #9482 and #9493 (state may have moved). If either is closed or the operator answered a decision, re-scope.

### Phase 1: measure and comment (no repo code)

All pulls use `gh` and, for Sentry, the read-only Doppler `prd` token (`SENTRY_IAC_AUTH_TOKEN`). Nothing is asked of the
operator. Results are posted as ONE combined comment on #9482 with four headed blocks (1.1 to 1.4), plus a pointer on #9493 and a
one-line pointer on #9454 (the ADR says canary results are recorded there); Phase 3 adds a short ADR-270 record that links
to the comment (and #9454) instead of restating it.

**1.1 Item 1: weakness-miner PR through the queue.**

- `gh pr list --state merged --search "weakness-miner in:title" --limit 30 --json number,title,mergedAt,headRefName`, then
  keep `headRefName` starting `ci/weakness-digest-` and `mergedAt` strictly after the adoption merge time, which is read
  live (`gh pr view 9455 --json mergedAt`), never hard-coded.
- For each kept PR, the queue timeline in one GraphQL read (`timelineItems` of `AUTO_MERGE_ENABLED_EVENT`,
  `ADDED_TO_MERGE_QUEUE_EVENT`, `REMOVED_FROM_MERGE_QUEUE_EVENT` with `reason`, `MERGED_EVENT`): enqueue to merge in
  minutes; the `merge_group` CI run (`gh api "repos/{o}/{r}/actions/runs?event=merge_group"` filtered on
  `head_branch` starting `gh-readonly-queue/main/pr-<N>-`); and any `merge-queue-stall` issue whose title
  starts `merge-queue stall: PR #<N> pending` (the stall workflow's own anchor, so PR 9 does not match PR 94). The workflow's own dedupe reads only open issues, so
  query `gh issue list --label merge-queue-stall --state all --limit 200 --json number,title` and prefix-match the title
  client-side with `jq` (`gh --search` cannot do starts-with). A missing stall issue is NOT proof of a clean pass: the probe
  is best-effort by ADR-270's own text.
  Also list any OPEN `ci/weakness-digest-*` PR created after the cutoff (a stuck, never-merged bot PR is the failure
  item 4 exists to catch, and a merged-only search cannot see it). Note the merge lag: recent digests merged about 5.5 h
  after the 06:00 fire (#9479 at 11:51Z, #9037 at 11:30Z), so "no merged PR" on Sunday morning is not yet a finding.
- If none exists (expected today): record "pending; last weakness-miner PR #9479 merged 2026-10-04T11:51:51Z, before the
  queue; next scheduled fire 2026-10-11T06:00Z (PR typically merges hours later); re-run: the three commands above".
  Do NOT dispatch the workflow.
- If one exists at work time: record the timeline, whether it stalled, and apply the ADR's fallback only if it did
  (bot PRs fall back to the admin-merge path and a follow-up to arm bot PRs with an App token is filed in the same
  session). A clean pass still does not flip the ADR; it satisfies item 4 only.

**1.2 Item 2: sync-merge count per merged PR.** Frozen definition: for each merged, human-authored PR, the number of PR
commits (REST `pulls/{n}/commits`, `--paginate`) with two parents whose second parent is an ancestor of `origin/main`
(`git merge-base --is-ancestor`). Windows: after = human PRs merged after the adoption merge time, excluding #9455 itself (its
syncs predate the queue); before = the 40 most recent human PRs merged before it (ADR canary 9 asks "before and after").
Report n, total and mean per window, say the bias direction (commits not pushes; hook share not separable), and post the
exact shell used. Run the procedure once at work time and take the number from that run (the pilot above used n=12 to 13).
Report the after-mean (what (d)'s trigger literally names:
"sync pushes per merged PR at or above 1.3") AND the before-minus-after delta (ADR-270 "Runner capacity" puts the queue's
break-even at about 1.3 REMOVED resyncs per merged PR, a delta; the pilot's 2.13 minus 0.83 to 1.00 is 1.13 to 1.30, at the
margin, so the break-even question is open and matters more for the `accepted` flip than (d) does). Split by merge
message as a hint only: `Merge branch 'main' into ...` with a GitHub web-flow committer is `gh pr update-branch`; the
other forms are local `git merge` (hook or ship/merge-pr fence, not separable from each other); verify the split against a
sample before asserting it. Further caveats to state: rebase-style syncs and force-pushed PRs leave no merge commit (so the
count is not strictly an upper bound), a sibling-branch merge whose second parent later reached main is a false positive,
the after window is about one day (Sunday afternoon through Monday) against 40 weekday PRs before, and PRs in flight at
cutover carry pre-queue syncs. Label the ADR row "sync merges (proxy)".

**1.3 Item 3: follow-up triage. Verdict per follow-up, each quoted against its own trigger.**

| Follow-up | Trigger (from #9482) | Evidence at plan time | Actionable without an operator decision? | This PR |
|-----------|----------------------|-----------------------|------------------------------------------|---------|
| (a) | landed | merged in #9491 | n/a | none |
| (b) `codeql-to-issues.yml` fails closed | first `codeql-gate-degraded` issue, or the ADR flip to `accepted` | 0 such issues; gate 15/15 green; ADR still `adopting` | Yes, when its trigger fires | NOT done: trigger not fired. Verdict "not fired" recorded. |
| (c) skip duplicate push-to-main CI run | canary records push SHA == `merge_group.head_sha` | 12/12 queue-merged commits have a successful `merge_group` run on the same SHA (fired; a SQUASH queue fast-forwards `main` to the candidate, so this holds by construction for queue merges) | Yes, but it is a deploy-chain redesign (the push run is what the `workflow_run` trust ladder and `post-merge-monitor.yml` read) | NOT done here: file a new tracking issue (`deferred-automation`, `Ref #9482`) carrying the 12/12 evidence, the denominator (all `main` commits since adoption, how many have a green `merge_group` run on the same SHA, and what the non-matches were: `--admin` and bypass merges and direct pushes create commits no `merge_group` run built), the constraint stated precisely (`web-platform-release.yml`'s `workflow_run` arm needs a push-event `CI` run on `main` with conclusion `success`, otherwise `resolve-target` clean-skips and the release never deploys; any change must therefore be keyed per SHA, "skip only when a green `merge_group` run exists for this exact head SHA", never a static removal of the push run; basing the trust ladder on `merge_group` is a trust-model change because `merge_group` runs use the candidate's workflow definitions; whether an all-jobs-skipped `ci.yml` run concludes `success` is unmeasured), the value at stake (one duplicate `ci.yml` run, p50 17.6 min of runner time, per queue merge; quote the actual per-day count from `gh run list`), and a re-evaluation trigger (when the deploy chain is next touched, or runner-minute cost becomes binding). The consumer list is the future plan's job (it goes stale). Milestone from `knowledge-base/product/roadmap.md`. |
| (d) hook skips pre-enqueue sync under the queue rule | sync pushes per merged PR at or above 1.3 | 0.83 to 1.00 on the pilot (below 1.3), but n=12 over about one day | Yes, when its trigger fires | NOT done. Verdict "not fired on the pilot, not yet robustly measurable": re-run when 7 days or n>=30 post-adoption PRs exist, recorded as the revisit trigger in the combined comment (#9482 stays the tracker). If a frozen after-mean is at or above 1.3, STOP and file it as its own plan; do not implement inline. |

Operator decisions 1 to 3 (deploy hold default NO, threshold `aggregate pattern`, no `.github/**` gate): the verdict
comment restates "defaults stand, not acted on". Nothing in this PR touches them.

Because (b) and (d) remain open with unfired triggers, #9482 stays the tracking issue for them (it carries
`deferred-automation` wording and the triggers); no new issue is filed for them. (c) is the only follow-up whose trigger
fired, so it alone gets a dedicated issue.

**1.4 Heartbeat decision (from #9493).** Measure on the population the budget governs: the stall-check workflow's own
jobs, not sibling workflows. Pull the dispatched runs of `merge-queue-stall-check.yml`
(`gh api "repos/{o}/{r}/actions/workflows/merge-queue-stall-check.yml/runs?per_page=100&created=>=2026-10-05T09:00:00Z"`),
and for each `GET .../runs/{id}/jobs` for `jobs[0].started_at - run.created_at`. Report n, window, median and max, plus the
longest gap between consecutive job starts and the count of gaps over 15 minutes (the 15-minute window between the
45-minute threshold and the 60-minute timeout is what a coverage gap must stay under; one slow job is retried by the next
tick, a sustained gap is what misses a stall). Say plainly that this is a default-no with a revisit trigger, not a
decision the data can flip from a quiet window (the dispatcher header cites a ~20 min p90 on a congested pool,
2026-09-24): no executor-side heartbeat unless max latency or a gap exceeds 15 minutes. Settled at plan time (checked, read-only): a red
`merge-queue-stall-check.yml` run (a GraphQL error, a token problem, a failed issue create under `set -euo pipefail`)
alerts nobody: the workflow has no `if: failure()` step, no Sentry or notify step and no secrets, nothing consumes its run
conclusion, and dispatched runs have the Inngest GitHub App as actor so GitHub's native failure email goes nowhere. The
dispatcher's green check-in means "dispatched", not "probe executed". Record that as an accepted gap in the combined
#9482 comment and on #9493, and file ONE small tracked follow-up (`deferred-automation`, `Ref #9493`) for a secretless
route, for example a dispatcher-side check of the previous dispatched run's `conclusion` through the `actions:write`
token it already holds, which would also cover the runner-wait gap; revisit trigger: a missed stall, or a start gap over
15 minutes measured under load. Record in the combined #9482 comment and on #9493.

### Phase 2: route the monitor (Terraform, two-PR rule PR 2)

Per `apps/web-platform/infra/sentry/README.md` §"Adding or removing a cron monitor":

1. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: remove the `scheduled_merge_queue_stall_dispatch` entry and its
   `#9482 follow-up (a)` comment block from `local.cron_monitor_alert_unrouted`; add
   `sentry_cron_monitor.scheduled_merge_queue_stall_dispatch.id,` to `sentry_alert.cron_monitor_failure.monitor_ids` in
   sorted order (C locale): between `scheduled_membership_health` and `scheduled_nag_4216_readiness`
   (`membership` sorts before `merge`; `merge` sorts before `nag`). Verify with the derivation command in that file's
   header.
2. `apps/web-platform/infra/sentry/cron-monitors.tf`: update the comment above the monitor (the sentence "email routing
   lands with #9493, the two-PR rule") to say it is routed (#9493).
3. `apps/web-platform/infra/sentry/alert-reference.json`: derive it locally in this phase (a PR-required generated
   artifact is a merge blocker, not a post-push follow-up). The change is one value: append `"2359391"` as the last
   element of the `cron-monitor-failure` workflow's `detectorIds` (the projection in
   `tests/scripts/lib/sentry-alert-projection.jq` sorts the array as strings; the live file is 59 entries, sorted,
   last `"2321651"`, and `"2359391"` sorts after it). Verify the edit is canonical with `jq -S` and that the array is
   still `. == sort`. The `plan_pr` `sentry-alert-reference-gate` is the proof, not the producer; only if it reds,
   take the CI artifact (`gh run download <run-id> -n sentry-alert-reference-expected-<run-id>`) and diff it against
   the local edit before copying. Any hunk beyond the one id is a finding, not noise.
4. Local gates before pushing: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`
   (verify the runner invocation in `apps/web-platform/package.json` first), `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`,
   `bash plugins/soleur/test/c4-count-parity.test.sh`. The routing change moves no count (the monitor is already
   counted), so a red parity gate here means a mis-edit.

No operator step: `apply-sentry-infra.yml` applies on merge. The apply is a non-destroy in-place update of one
`sentry_alert`; no `[ack-destroy]` is needed.

### Phase 3: record in ADR-270 (docs, status unchanged)

In `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`
under "Canary results", add a SHORT dated block (recorded 2026-10-05), 3 to 5 lines linking to the combined #9482 comment rather than restating
definitions: item 4 pending (next fire date); item 9 the sync-merge numbers; item 10 the dispatched-run spacing and
job-start latency summary; item 3 partial ("push SHA == merge_group head SHA, 12/12"). Do NOT edit the `## Status` section, the
`status:` frontmatter, or any "Follow-up" definition. The (b)/(c)/(d) verdicts live on #9482 and, for (c), its new issue.
Also add one table row each for canaries 4, 9 and 10 to `knowledge-base/engineering/operations/runbooks/merge-queue-canary-log.md`
(the per-canary index created in #9485; it records "result on #9454" for canary 1), pointing at the combined #9482 comment.

### Phase 4: ship and post-merge verification

PR body: `Ref #9482` and `Ref #9493`. Avoid any prose that pairs a closing keyword with an issue number (the squash parser
reads prose). After merge:

1. `apply-sentry-infra.yml` run for the merge commit is green; the apply plan was one in-place update of
   `sentry_alert.cron_monitor_failure` (no destroy).
2. Read the live route back: the `cron-monitor-failure` workflow's `detectorIds` includes `2359391`
   (command in the Sentry README, extended with `| index("2359391")`).
3. File the (c) tracking issue and the one-line pointer comments (#9454, #9493).
4. Comment the heartbeat decision and the apply read-back on #9493, then close #9493 by hand (`gh issue close 9493`
   with the evidence) once the executor-visibility follow-up (Phase 1.4) exists, so the unmeasured-under-load decision is
   tracked rather than closed. Post the combined measurement comment and final summary on #9482 (pending items: item 4 awaits the 2026-10-11 fire, the three
   operator decisions, (b), (d), and the new (c) issue).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` (move one label from the unrouted map into `monitor_ids`)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (comment only)
- `apps/web-platform/infra/sentry/alert-reference.json` (one id appended, derived locally; CI gate is the proof)
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (short dated evidence block only)
- `knowledge-base/engineering/operations/runbooks/merge-queue-canary-log.md` (three index rows pointing at the #9482 comment)

Glob check: each path exists on `origin/main`. `cron-merge-queue-stall-dispatch.ts` is deliberately NOT edited: its header
already says the heartbeat decision is "tracked by the routing follow-up issue", which stays true.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9482-merge-queue-followups/tasks.md` (derived from this plan)

New GitHub issues (not files), filed at ship: the (c) tracking issue and one executor-visibility follow-up for the stall check (`Ref #9493`).

## Open Code-Review Overlap

Queried the open `code-review` issues against every planned path: no issue names any path above. Disposition: none.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ADR item 4: observe the next weakness-miner.yml PR flowing through the merge queue without stalling. Check `gh pr list --search \"weakness-miner\" --state merged`, then each PR's queue timeline (enqueue -> merge) and any stall-check issue filed." [brief] | Phase 1.1 | mapped |
| 2 | "Until one clean pass, ADR-270 stays adopting. Do not flip it to adopted without that evidence." [brief] | Phase 3 (status untouched), Acceptance Criteria ADR-status check | mapped |
| 3 | "Measure the hook's sync-push count per merged PR (currently unmeasured). Pick a window of merged PRs, count the BEHIND-sync pushes each needed, and record the numbers on #9482." [brief] | Phase 1.2, Phase 3 | mapped |
| 4 | "Follow-ups (b), (c), (d) from #9482: re-read the issue body for their definitions before touching them." [brief] | Phase 1.3 | mapped |
| 5 | "Do NOT act on the three operator decisions; their defaults stand until the operator answers." [brief] | Phase 1.3 closing paragraph, Non-goals in Overview | mapped |
| 6 | "#9493: route the scheduled-merge-queue-stall-dispatch Sentry monitor (two-PR rule: the monitor was declared unrouted in cron-monitor-alerts.tf, citing #9493)." [brief] | Phase 2, Files to Edit (three Sentry files) | mapped |
| 7 | "decide, from measured data, whether an executor-side heartbeat step in `merge-queue-stall-check.yml` is worth adding" [issue #9493] | Phase 1.4 | mapped |
| 8 | "PR bodies use `Ref #9482`, never `Closes`." [brief] | Phase 4, Acceptance Criteria PR-body checks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1.1 weakness-miner pull | asks 1 and 2 | asked |
| Phase 1.2 sync-merge count | ask 3 | asked |
| Phase 1.3 follow-up verdict table | ask 4 | asked |
| Phase 1.3 tracking issue for (c) | ask 4 ("re-read the issue body for their definitions before touching them"); the wg-when-deferring rule requires a tracker for a fired, deferred follow-up | inferred — justification: (c)'s trigger fired and the change is deferred out of this PR, so the repo's deferral rule needs an issue carrying the evidence and a re-evaluation trigger |
| Phase 1.4 heartbeat measurement | ask 7 | asked |
| Phase 2 and the three Sentry files | ask 6 | asked |
| Phase 3 ADR-270 evidence block | ask 3 ("record the numbers") and ask 2 | inferred — justification: the ADR names its own canary rows (9, 10, 4) and says results are recorded; a short linked block keeps the ADR from contradicting #9482. Plan review kept it short and may cut it. |
| Canary-log index rows | ask 3 ("record the numbers") | inferred — justification: the runbook created in #9485 is the per-canary index and would otherwise omit canaries 4, 9 and 10 |
| Pointer comments on #9454 and #9493 | ask 7 and the ADR's own "recorded ... on #9454" instruction | inferred — justification: one-line pointers only, so the ADR's stated record location stays true |
| `tasks.md` | pipeline artifact for `soleur:work` | inferred — justification: the work skill executes against it |

### Split Assessment

- Subsystems touched: 2 — apps/web-platform, knowledge-base
- Planned files: 6 | Estimated changed lines: 45 (excluding the plan and tasks files)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cron-monitor-alerts.tf`: `grep -c 'sentry_cron_monitor.scheduled_merge_queue_stall_dispatch.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf` prints `1`, and the label no longer appears as a key of `cron_monitor_alert_unrouted`.
- [ ] The routing-parity vitest, `sentry-monitors-audit.test.sh` and `c4-count-parity.test.sh` pass locally; the PR's `plan_pr` and sentry-alert-reference gate are green on the first push (the file is derived locally, not fetched after a red).
- [ ] `alert-reference.json` diff against the merge base (`git diff origin/main...HEAD -- apps/web-platform/infra/sentry/alert-reference.json`) is exactly one added `detectorIds` entry (`"2359391"`) in the `cron-monitor-failure` workflow, and `jq '.. | objects | select(.name? == "cron-monitor-failure") | .detectorIds | . == sort'` still prints `true`. Any other hunk is explained or removed.
- [ ] ADR-270 `## Status` and the `status:` frontmatter still read `adopting`; the diff touches only the dated "Canary results" block (`git diff origin/main -- <adr> | grep -E '^[+-](status:|\*\*Adopting)'` is empty).
- [ ] The lint gates run with their own scope: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `npx markdownlint-cli2` on this plan and `tasks.md` pass.
- [ ] The PR body's FIRST line states the production effect of merging: the push-triggered `apply-sentry-infra.yml` (its `paths:` cover the whole `apps/web-platform/infra/sentry/` tree) applies one in-place update adding detector `2359391` to the `cron-monitor-failure` alert workflow. Merging this alone mutates production Sentry routing; the merge click is the authorization.
- [ ] The PR body contains `Ref #9482` and `Ref #9493`, and contains no closing keyword adjacent to either number (`gh pr view <n> --json body --jq .body | grep -Ein '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#9(482|493)'` prints nothing).

### Measurement deliverables (one combined comment on #9482, verified by reading it back; one-line pointers on #9493 and #9454)

- [ ] Item 1 block: either the post-adoption weakness-miner PR timelines (enqueue to merge, `merge_group` run, stall-issue check, open-PR check) or the explicit "pending, next fire 2026-10-11T06:00Z" line with the re-run commands; it states ADR-270 stays `adopting`.
- [ ] Item 2 block: frozen definition, both windows, n, totals, means (after-window excludes #9455), the before-minus-after delta against the ADR's 1.3 break-even, the caveats, the exact commands, and the comparison of the after-mean to (d)'s 1.3.
- [ ] Item 3 block: a verdict row each for (b), (c), (d) quoting the trigger and evidence, plus "operator decisions 1 to 3: defaults stand, not acted on".
- [ ] Heartbeat block: n, window, median and max job-start latency, longest gap between starts and count of gaps over 15 minutes, whether a red stall-check run alerts anywhere, and the default-no decision with its revisit trigger. Posted in the combined #9482 comment and on #9493.

### Post-merge (operator-free, agent-run)

- [ ] `apply-sentry-infra.yml` run on the merge commit succeeded; plan was one in-place update, zero destroy.
- [ ] Live read shows the `cron-monitor-failure` workflow `detectorIds` includes `2359391`.
- [ ] The (c) tracking issue exists (`deferred-automation`, evidence and denominator, the per-SHA constraint, value at stake, trigger, roadmap milestone, `Ref #9482`). The executor-visibility follow-up exists (`deferred-automation`, `Ref #9493`, revisit trigger) before #9493 is closed.
- [ ] #9493 closed by hand with the read-back and heartbeat decision; #9482 stays open.

## Observability

```yaml
liveness_signal:
  what: the scheduled-merge-queue-stall-dispatch Sentry cron monitor check-in (posted by the Inngest dispatcher every 10 minutes); after this change a missed or failed check-in emails via sentry_alert.cron_monitor_failure
  cadence: every 10 minutes (monitor margin 30 minutes, so a dead dispatcher alerts within about 40 minutes)
  alert_target: email to all active Sentry org members (action_filters email, issue_owners with ActiveMembers fallthrough), throttled to one email per monitor group per ~24 h
  configured_in: apps/web-platform/infra/sentry/cron-monitor-alerts.tf (monitor_ids) and apps/web-platform/infra/sentry/cron-monitors.tf (the monitor)
error_reporting:
  destination: Sentry (the unrouted monitor already opens a Sentry issue; the dispatcher also raises a reportSilentFallback issue on a failed dispatch POST)
  fail_loud: true; a failed dispatch is an error-status check-in, not a silent skip
failure_modes:
  - mode: dispatcher dead or Inngest outage
    detection: Sentry monitor `scheduled-merge-queue-stall-dispatch` missed check-in (inngest-heartbeat layer)
    alert_route: sentry_alert.cron_monitor_failure email, after this change
  - mode: dispatch POST fails
    detection: sentry-correlation reportSilentFallback issue from the Inngest function, plus a Sentry monitor error-status check-in
    alert_route: the Sentry monitor failure reaches email through sentry_alert.cron_monitor_failure; the silent-fallback issue is Sentry-only
  - mode: dispatched run delayed on the runner pool (not detected today)
    detection: workflow run log job timestamps, measured once in Phase 1.4 (an accepted gap, not a new alert)
    alert_route: none by design (accepted gap, decision recorded on #9493 with a revisit trigger)
  - mode: executor run red (GraphQL or gh error, issue-create failure)
    detection: workflow run log of merge-queue-stall-check.yml is the only signal
    alert_route: none (accepted gap, tracked follow-up from Phase 1.4)
  - mode: weakness-miner PR stalls or bypasses the queue
    detection: the merge-queue-stall issue filed by the workflow (workflow run log layer, best-effort) and the item 1 re-run on #9482
    alert_route: stall issue is action-required
logs:
  where: GitHub Actions run logs for apply-sentry-infra.yml; Sentry cron monitor history
  retention: GitHub run retention (90 days default) and Sentry issue retention
discoverability_test:
  command: grep -c 'sentry_cron_monitor.scheduled_merge_queue_stall_dispatch.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: 1
```

This is the Check 10 source probe (it proves the `.tf` edit); the live route read-back in Phase 4 is the post-merge probe.
The command prints `0` on the tree today (the label is only in the unrouted map; run at plan time) and `1` once Phase 2 lands, so it
proves the change rather than the status quo. Check 10 runs it at ship against the final tree.

Affected-surface note (2.9.2): the dispatcher runs on the Inngest host (a surface the operator cannot inspect directly).
The dispatcher side already emits from its own surface (check-in plus `reportSilentFallback`); this plan adds routing for
that signal. The executor runner is the blind surface (a red run alerts nobody); that gap is recorded and tracked, not
closed here.

## Infrastructure (IaC)

### Terraform changes

Existing root `apps/web-platform/infra/sentry` (provider and version pins unchanged). One attribute edit on
`sentry_alert.cron_monitor_failure` (`monitor_ids`) and one `locals` map entry removed. No new resource, no new variable,
no new secret. The Doppler/GitHub secret used by the apply (`SENTRY_IAC_AUTH_TOKEN`) is unchanged.

### Apply path

(a) cloud-init and bootstrap are not involved. The change applies through the standing `apply-sentry-infra.yml` on merge to
`main` (full-root plan then apply). Expected blast radius: one in-place update of one alert workflow, no downtime, no destroy.

### Distinctness / drift safeguards

The routing-parity guard, the `alert-reference.json` plan-vs-committed gate in `plan_pr`, the post-apply probe, and the daily
`scheduled-sentry-alert-drift.yml` cover drift. The `lifecycle.ignore_changes = [environment]` on the alert is untouched.

### Vendor-tier reality check

Sentry detector and workflow objects are already in use for 60+ monitors on this org; adding one id to an existing workflow
needs no tier change.

## Encryption Posture

Not applicable under plan Phase 2.11's skip condition: no persistent store and no new cross-component connection is
introduced. The `.tf` edit moves one detector id inside an existing Sentry alert workflow (the existing vendor HTTPS API,
unchanged), and the measurements read public GitHub metadata. Recorded here because the deepen-plan trigger matches any
`.tf` path.

## Architecture Decision (ADR/C4)

No new architectural decision. The change moves one monitor into an existing alert (ADR-031's two-PR rule) and appends dated
measurement evidence to ADR-270, whose Decision and Status are unchanged.

### ADR

None created or amended in substance. ADR-270 gets a dated evidence block only (Phase 4); its status stays `adopting` by
instruction.

### C4 views

No C4 impact. The three model files under `knowledge-base/engineering/architecture/diagrams/` (`model.c4`, `views.c4`,
`spec.c4`) are read in the work phase before this line is finalised; checked here by enumeration: external actors, none new
(operator/founder already modelled); external systems, GitHub and Sentry are already modelled and the monitor routes through
the existing Sentry edge; data stores, none; actor-to-surface access relationships, unchanged. The cardinalities embedded in
`model.c4` edge prose (monitor and function counts) do not move because the monitor and its dispatcher already exist and are
already counted; `bash plugins/soleur/test/c4-count-parity.test.sh` is the proof and is an acceptance gate.

### Sequencing

Not applicable (no decision awaiting a later slice).

## Plan Review Record

Eng panel (DHH, Kieran, code-simplicity) plus a CTO devex advisory, all headless. Applied as mechanical: cut the
follow-through probe, its suite, registry rows and tracker (the only `inferred` item; both panels fired on it); one
combined #9482 comment; short ADR block plus a pointer on #9454; simplified heartbeat rule (gaps and max, default-no);
open-PR check and the stall-title anchor added to the item 1 pull; (c) issue gets value and trigger. No taste or
user-challenge items (nothing of operator-requested scope was dropped).

## Domain Review

**Domains relevant:** engineering (infrastructure and CI tooling only)

### Engineering

**Status:** reviewed
**Assessment:** CI, merge-queue measurement and an operator-only alert route. No product, marketing, legal, finance, sales or support surface; no user-facing UI, so the Product/UX gate does not fire (no `components/`, `app/` or page file in either Files list). No regulated-data surface (no schema, auth, API route or `.sql`), no external-API processing of user data, no new distribution surface: the GDPR gate does not fire. The Encryption Posture gate does not fire (no new store or connection). CTO review was not spawned because the change is a label move plus measurements; plan-review covers engineering correctness.

## Risks and Sharp Edges

- **A wrong `alert-reference.json`.** It is a PR-required generated file, so a wrong or missing edit is a red `plan_pr`, a merge blocker. Derive the one-value edit locally; if the gate still reds, diff the CI artifact against the local edit before copying. Any hunk beyond the one id is a finding.
- **Same-PR routing reds `main`.** Not this case (the detector id exists since the first apply), but the routing-parity guard cannot check that: it compares `.tf` with `.tf` inside one commit. The live read in Phase 0 and Phase 4 is what proves the id is real.
- **Closing #9493 by merge would close it before the route is real.** The route exists only after the apply, and a keyword in the PR body would close the issue at squash time. Use `Ref`, close by hand after the read-back.
- **A closing keyword in prose.** A sentence pairing a closing keyword with #9482 or #9493 in the PR body or a commit body auto-closes the issue at squash. The acceptance grep above enforces it.
- **Small-n measurement.** The after-queue window is 12 to 13 PRs. State n; do not present a mean as a settled rate. A below-1.3 result is the robust direction given the upper-bound bias; an at-or-above result must not be actioned inline.
- **Item 4 is time-gated on a weekly cron.** Do not flip ADR-270 and do not dispatch the workflow to hurry it. A clean pass satisfies only item 4; canary items 1, 3, 5, 7, 8 and 10 remain.
- **Known flake and accepted gaps (from the brief), not bugs:** main-branch e2e nav-states failed once and passed on re-run; a 403 secondary rate limit is not retried (the next 10-minute tick is the retry); a late run on a congested runner pool is not detected by the dispatcher (Phase 1.4 measures it, it does not fix it).
- **Revert path for the whole queue change** is one Terraform diff on `infra/github/ruleset-ci-required.tf` (ADR-270 "Rollback"). Nothing in this plan alters it, and nothing here should be bundled with a rollback.
- A plan whose `## User-Brand Impact` section is empty, placeholder, or missing its threshold fails deepen-plan Phase 4.6; this one declares `none` with a scope-out reason because it touches `apps/web-platform/infra/`.

## Resume

Branch `feat-one-shot-9482-merge-queue-followups`, worktree `.worktrees/feat-one-shot-9482-merge-queue-followups`, draft PR
#9511, issue #9482 (and #9493). Plan-review applied (probe cut, measurements consolidated into one comment); `soleur:deepen-plan` next, then `soleur:work` on this file.
