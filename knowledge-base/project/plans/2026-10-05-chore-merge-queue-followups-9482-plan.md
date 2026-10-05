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

## Scope Check

Ask mapping (every ask maps to a deliverable; nothing is `inferred`: the one inferred item, a follow-through probe, was cut at plan review):

| Ask | Deliverable | Provenance |
|-----|-------------|------------|
| Item 1: observe next weakness-miner PR | Phase 1.1 pull and record (or "pending" with the re-run command) | ask |
| Item 2: sync-push count | Phase 1.2 | ask |
| Item 3: (b), (c), (d) | Phase 1.3 verdicts; one tracking issue for (c) | ask |
| Item 3: do not act on the three operator decisions | Explicit non-goal; the verdict comment restates "defaults stand" | ask |
| Item 4: route the monitor | Phase 2 | ask |
| Heartbeat decision (from #9493 body) | Phase 1.4 | ask (#9493) |
| ADR stays `adopting` | Non-goal; ADR gets only dated evidence lines | ask |

Split assessment: one PR is right. The only code is a one-label Terraform routing move and its one-value reference-file
edit; everything else is data pulls recorded on the issue plus a short ADR evidence record.

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
to the comment instead of restating it.

**1.1 Item 1: weakness-miner PR through the queue.**

- `gh pr list --state merged --search "weakness-miner in:title" --limit 30 --json number,title,mergedAt,headRefName`, then
  keep `headRefName` starting `ci/weakness-digest-` and `mergedAt` strictly after the adoption merge time, which is read
  live (`gh pr view 9455 --json mergedAt`), never hard-coded.
- For each kept PR, the queue timeline in one GraphQL read (`timelineItems` of `AUTO_MERGE_ENABLED_EVENT`,
  `ADDED_TO_MERGE_QUEUE_EVENT`, `REMOVED_FROM_MERGE_QUEUE_EVENT` with `reason`, `MERGED_EVENT`): enqueue to merge in
  minutes; the `merge_group` CI run (`gh api "repos/{o}/{r}/actions/runs?event=merge_group"` filtered on
  `head_branch` starting `gh-readonly-queue/main/pr-<N>-`); and any `merge-queue-stall` issue whose title
  starts `merge-queue stall: PR #<N> pending` (the stall workflow's own anchor, so PR 9 does not match PR 94; all states).
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
Compare the after-mean with follow-up (d)'s 1.3 threshold.

**1.3 Item 3: follow-up triage. Verdict per follow-up, each quoted against its own trigger.**

| Follow-up | Trigger (from #9482) | Evidence at plan time | Actionable without an operator decision? | This PR |
|-----------|----------------------|-----------------------|------------------------------------------|---------|
| (a) | landed | merged in #9491 | n/a | none |
| (b) `codeql-to-issues.yml` fails closed | first `codeql-gate-degraded` issue, or the ADR flip to `accepted` | 0 such issues; gate 15/15 green; ADR still `adopting` | Yes, when its trigger fires | NOT done: trigger not fired. Verdict "not fired" recorded. |
| (c) skip duplicate push-to-main CI run | canary records push SHA == `merge_group.head_sha` | 12/12 pairs match (fired) | Yes, but it is a deploy-chain redesign (the push run is what the `workflow_run` trust ladder and `post-merge-monitor.yml` read) | NOT done here: file a new tracking issue (`deferred-automation`, `Ref #9482`) carrying the 12/12 evidence, the one-line constraint "must still emit the CI completion event the deploy waits on", the value at stake (one duplicate `ci.yml` run, p50 17.6 min of runner time, per queue merge; quote the actual per-day count from `gh run list`), and a re-evaluation trigger (when the deploy chain is next touched, or runner-minute cost becomes binding). The consumer list is the future plan's job (it goes stale). Milestone from `knowledge-base/product/roadmap.md`. |
| (d) hook skips pre-enqueue sync under the queue rule | sync pushes per merged PR at or above 1.3 | 0.83 to 1.00 on the pilot (below) | Yes, when its trigger fires | NOT done: trigger not fired on the frozen number. If the frozen after-mean is at or above 1.3, STOP and file it as its own plan; do not implement inline. |

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
2026-09-24): no executor-side heartbeat unless max latency or a gap exceeds 15 minutes. Also check whether a red
`merge-queue-stall-check.yml` run (a broken token, a failed `gh` call) alerts anywhere today; if not, record that as an
accepted gap alongside the latency gap. Record in the combined #9482 comment and on #9493.

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

### Phase 4: ship and post-merge verification

PR body: `Ref #9482` and `Ref #9493`. Avoid any prose that pairs a closing keyword with an issue number (the squash parser
reads prose). After merge:

1. `apply-sentry-infra.yml` run for the merge commit is green; the apply plan was one in-place update of
   `sentry_alert.cron_monitor_failure` (no destroy).
2. Read the live route back: the `cron-monitor-failure` workflow's `detectorIds` includes `2359391`
   (command in the Sentry README, extended with `| index("2359391")`).
3. File the (c) tracking issue and the one-line pointer comments (#9454, #9493).
4. Comment the heartbeat decision and the apply read-back on #9493, then close #9493 by hand (`gh issue close 9493`
   with the evidence). Post the combined measurement comment and final summary on #9482 (pending items: item 4 awaits the 2026-10-11 fire, the three
   operator decisions, (b), (d), and the new (c) issue).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` (move one label from the unrouted map into `monitor_ids`)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (comment only)
- `apps/web-platform/infra/sentry/alert-reference.json` (one id appended, derived locally; CI gate is the proof)
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (short dated evidence block only)

Glob check: each path exists on `origin/main`. `cron-merge-queue-stall-dispatch.ts` is deliberately NOT edited: its header
already says the heartbeat decision is "tracked by the routing follow-up issue", which stays true.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9482-merge-queue-followups/tasks.md` (derived from this plan)

New GitHub issue (not a file): the (c) tracking issue, filed at ship.

## Open Code-Review Overlap

Queried the open `code-review` issues against every planned path: no issue names any path above. Disposition: none.

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
- [ ] Item 2 block: frozen definition, both windows, n, totals, means (after-window excludes #9455), the bias direction, the exact commands, and the comparison to 1.3.
- [ ] Item 3 block: a verdict row each for (b), (c), (d) quoting the trigger and evidence, plus "operator decisions 1 to 3: defaults stand, not acted on".
- [ ] Heartbeat block: n, window, median and max job-start latency, longest gap between starts and count of gaps over 15 minutes, whether a red stall-check run alerts anywhere, and the default-no decision with its revisit trigger. Posted in the combined #9482 comment and on #9493.

### Post-merge (operator-free, agent-run)

- [ ] `apply-sentry-infra.yml` run on the merge commit succeeded; plan was one in-place update, zero destroy.
- [ ] Live read shows the `cron-monitor-failure` workflow `detectorIds` includes `2359391`.
- [ ] The (c) tracking issue exists (`deferred-automation`, evidence, value at stake, trigger, roadmap milestone, `Ref #9482`).
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
    detection: missed check-in on the monitor (Sentry issue plus, after this change, email)
    alert_route: sentry_alert.cron_monitor_failure email
  - mode: dispatch POST fails
    detection: reportSilentFallback Sentry issue plus an error-status check-in
    alert_route: Sentry issue; email via the same alert once the monitor fails a check-in
  - mode: dispatched run delayed on the runner pool (not detected today)
    detection: measured job-start latency in Phase 1.4 (a recorded accepted gap, not a new alert)
    alert_route: none by design (accepted gap, decision recorded on #9493)
  - mode: weakness-miner PR stalls or bypasses the queue
    detection: the existing merge-queue-stall issue (best-effort probe) and the item 1 re-run on #9482
    alert_route: stall issue is action-required
logs:
  where: GitHub Actions run logs for apply-sentry-infra.yml; Sentry cron monitor history
  retention: GitHub run retention (90 days default) and Sentry issue retention
discoverability_test:
  command: grep -c 'sentry_cron_monitor.scheduled_merge_queue_stall_dispatch.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: 1
```

The discoverability command prints `0` on the tree today (the label is only in the unrouted map; run at plan time) and `1` once Phase 2 lands, so it
proves the change rather than the status quo. Check 10 runs it at ship against the final tree.

Affected-surface note (2.9.2): the dispatcher runs on the Inngest host (a surface the operator cannot inspect directly).
The in-surface probe already exists: the dispatcher itself posts the check-in and raises `reportSilentFallback`, so the
signal is emitted from the surface, not inferred from the host. This plan adds routing for that signal, no new probe.

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
