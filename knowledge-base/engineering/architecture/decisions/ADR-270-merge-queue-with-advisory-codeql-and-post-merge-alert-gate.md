---
title: Merge queue with advisory CodeQL and a post-merge alert gate
status: accepted
date: 2026-10-03
supersedes: ADR-032 (the 2026-07-01 "keep CodeQL required, no queue" decision and the 2026-09-14 capacity rejection, in part)
issue: 9454
related: [4856, 5840, 5780, 5800, 5811, 8149, 8450]
related_adrs: [ADR-032, ADR-033, ADR-216]
tags: [github, ruleset, merge-queue, codeql, terraform, ci]
brand_survival_threshold: aggregate pattern
---

# ADR-269: Merge queue with advisory CodeQL and a post-merge alert gate

## Status

**Adopting — 2026-10-03 (#9454).** Flips to `accepted` when the post-apply
canary in "Canary measurements" below passes. The merge of the PR that carries
this ADR is the apply of `infra/github` (`apply-github-infra.yml`), so the
canary runs after the decision is live; the decision is recorded `adopting`, not
`accepted`, until it passes.

It supersedes, in part, two rulings recorded in
[ADR-032](./ADR-032-github-branch-protection-as-iac.md): the 2026-07-01
decision "queue stays OFF; CodeQL stays a blocking required check" and the
2026-09-14 amendment's capacity rejection of the queue (re-adoption trigger (b)
below is the operator exercising it). ADR-032 stays `accepted` for everything
else (the ruleset-as-IaC contract, the required-check inventory, the DR script).
ADR-032 carries a pointer amendment to this ADR; its dated bodies are not edited.

## Context

Direct merge under `strict_required_status_checks_policy` makes every advance of
`main` force a `gh pr update-branch` plus a full CI cycle per queued PR. CI wall
clock on PRs (`gh run list --workflow ci.yml --event pull_request`, re-measured
2026-10-04, n=102) is p50 17.4 min, p90 24.4 min, max 32.8 min (CI on `main` pushes is
a separate sample: p50 17.6 min). So with about ten auto-merge-armed
PRs the same BEHIND loop repeats (`2026-06-02-auto-merge-livelock-fast-moving-main.md`).
`/ship`'s BEHIND auto-sync is a mitigation, not a fix: each sync is a new head
and a new full cycle.

The first merge-queue adoption (#5800) deadlocked in about 14 minutes and was
reverted (#5811): the required `CodeQL` context (GHAS, integration id 57789)
cannot post on a `merge_group` ref, upstream `github/codeql-action#1537` (open,
last updated 2026-05-22, probed again 2026-10-03). ADR-032's 2026-07-01
amendment recorded the binary choice and picked "CodeQL required, no queue"; the
2026-09-14 amendment added a capacity objection (three full runs per merged PR on
the Free plan) and the 2026-09-22 amendment recorded that objection dissolved
(Free 20 to Team 60 concurrent jobs, with the qualification that 60 is an
entitlement, not a guarantee). What remained was reopener (b), "a deliberate
decision to make CodeQL advisory". The operator has taken it: the merge-train
tax is the top CD bottleneck.

Four facts the decision rests on, measured on 2026-10-03:

1. Two rulesets gate `main`, not one. CI Required (14145388, 23 contexts at
   integration id 15368 once CodeQL is removed) and CLA Required (13304872,
   `cla-check` and `cla-evidence`). The CLA contexts run only on
   `pull_request_target` / `issue_comment` and have no `merge_group` producer; the
   workflows that covered them were deleted in #5842 after the revert. A queue
   without a replacement would deadlock exactly as #5800 did.
2. "Advisory" removes more than interaction-only coverage. Today the required
   `CodeQL` check blocks a PR whose own head carries a new critical/high alert;
   after this change nothing blocks it pre-merge.
3. Removing the `CodeQL` `required_check` trips the destroy-guard in
   `apply-github-infra.yml` (a nested `required_check` shrink); the merge needs a
   line that is exactly `[ack-destroy]`, and `workflow_dispatch` cannot carry it.
   The live apply plan (not a committed fixture) is the authority that exactly ONE
   `required_check` (`CodeQL`) is removed.
4. Ship's BEHIND auto-sync is queue-unaware: a push to a queued PR dequeues it.

## Considered Options

- **A. Queue on, CodeQL advisory, post-merge alert gate (chosen).** Keeps the
  strict policy's intent by construction (each candidate is built against the
  projected post-merge state), removes the per-PR resync loop, keeps the
  `pull_request` CodeQL scan, and turns the pushed commit's CodeQL result into a
  loud, deduplicated signal within minutes. Cost: pre-merge blocking on a PR's
  own CodeQL finding is lost.
- **B. Advanced CodeQL setup plus a `merge_group` status shim.** Rejected by the
  operator, and ADR-032 already recorded that advanced setup does not fix #1537
  (the analysis runs on `merge_group`; the code-scanning status context still
  never posts). Re-owns the #5800 bug class and a self-owned shim on the queue's
  highest-concurrency path.
- **C. Bot pseudo-queue (cron: oldest armed PR, update-branch, wait green, merge).**
  Rejected by the operator: strictly serial, no speculation, a merge-driving
  orchestrator.
- **D. Drop `strict_required_status_checks_policy`.** Rejected by the operator:
  independent-green PRs with semantic conflicts would land with no integrated-state
  CI.
- **E. Required PR-head alert gate (a required Actions job that waits for the PR's
  CodeQL analyses and fails on a new critical/high alert on `refs/pull/N/merge`,
  passing through on `merge_group` by the entry-gate premise).** Not adopted
  (operator chose advisory); it would keep PR-head blocking with no shim on
  CodeQL's own status. Persisted as a User-Challenge in
  `knowledge-base/project/specs/archive/20261004-150011-feat-one-shot-9454-merge-queue-advisory-codeql/decision-challenges.md`
  and not scheduled.

## Decision

Adopt option A, as declarative IaC in `infra/github/ruleset-ci-required.tf`:

1. Add a `merge_queue` rule to the CI Required ruleset (provider
   `integrations/github` 6.12.1 supports the nested block; all seven attributes
   are optional with provider defaults 60/5/5/1/5, and the root sets all seven
   explicitly).
2. Remove the `CodeQL` `required_check` (and its row in
   `scripts/ci-required-ruleset-canonical-required-status-checks.json`, the
   DR restore skeleton in `scripts/create-ci-required-ruleset.sh`, and the audit
   tests). The `pull_request` CodeQL scan stays; the variable
   `codeql_integration_id` stays in `variables.tf` for the re-tighten recipe.
3. Restore the CLA synthetic (`merge-queue-cla-synthetics.yml`, hardened to fail
   closed against the PR head's real `cla-check` / `cla-evidence`, see "CLA
   synthetic trust model") and the stall probe (`merge-queue-stall-check.yml`).
4. Add `codeql-main-alert-gate.yml` (`on: push` to `main`): a post-merge,
   page-and-continue gate, not a required check and not a dependency of the
   release or deploy chain.
5. Make the merge tooling queue-aware. The one queue read (GraphQL
   `isInMergeQueue`, `mergeQueueEntry`, `state`, `autoMergeRequest`) lives in
   `sync-pr-behind.sh` and is reachable as `sync-pr-behind.sh <pr>
   --queue-state` (no push, no worktree needed; its one write is consuming the
   seen-queued marker when it prints `dequeued`); the hook and `monitor-pr-checks.sh` use that copy, so there is no
   second query to drift (the Phase 7 fences run a frozen snapshot of the script, so a
   sibling helper file would not exist there).
   - `sync-pr-behind.sh` skips a queued PR: `--step` exits 11 with `kind=queued
     rc=11` (the ship and merge-pr fences' uncounted `sync_noop` arm; the standalone
     loop exits 0); nothing is merged or pushed either way. The read is retried once; a
     read that still fails is `kind=gh`, exit 4, never "not queued".
   - Dequeue detection costs no fence bytes. A PR is reported as dequeued when it reads
     not queued and OPEN and EITHER a removal event is current (a GraphQL
     `REMOVED_FROM_MERGE_QUEUE_EVENT` timeline item newer than the auto-merge enable and
     than the head commit date) OR the per-worktree marker says it was seen queued earlier
     (the script touches a marker file in the git dir whenever `--step` reads the PR as queued).
     A dequeue reached through the marker alone is reported once: `--step` (exit 13) and
     `--queue-state` (the `dequeued` print) each consume the marker, so a PR fixed and
     re-armed is not reported again; a removal-event dequeue needs no marker and stops
     matching once the re-arm is newer than the event.
     Auto-merge state is no longer consulted (what GitHub does to it after a failed
     `merge_group` run is unmeasured). The read is repeated once after a short nap before
     reporting, so the queue's own merge landing (not queued, OPEN, about to read MERGED)
     is never reported. The verdict is `kind=dequeued rc=13` (recovery inline,
     `ship/references/merge-queue-dequeue.md`), exit 13, which the fences' existing `*)`
     arm turns into "Stopping the poll". It is reachable from every `mergeStateStatus`:
     both Phase 7 fences (ship, merge-pr) run `--queue-state` on every 5th OPEN tick as well
     as on a BEHIND tick, and the timeout line prints `Queue: <state>`. MERGED/CLOSED are
     not dequeues. Known behaviours, accepted: a PR that is armed and has left the queue is
     reported as dequeued and the poll stops (it may re-enqueue itself, the agent
     re-checks); a human push that dequeues a PR also stops the poll until the PR is
     re-enqueued; the one-re-enqueue cap in the recovery text is prose only (no counter
     exists). `MAX_POLL_MIN` moved 60 to 90 in both fences: a healthy queue merge is the
     PR's own CI (p50 17.4 on PR runs, max 32.8 min) plus a `merge_group` run (the push-run
     proxy: p50 17.6 on `main` pushes, max 50.8 min, n=99) plus queue wait; the two worst
     cases alone sum past the old 60. STILL UNMEASURED (canary 3): the `mergeStateStatus` a
     queued PR shows, and the removal-event payload (`reason`, timestamp ordering against
     the re-arm and the head commit) on a real ejection. The detection rule does not depend
     on the first; the "current event" test depends on the second.
   - Amendment 2026-10-07 (#9710): the Phase 7 fences do not sync an armed PR that reads
     BEHIND when `main` has a `merge_queue` rule. Before this the queued-skip
     covered only a PR already IN the queue, and an armed PR spends its whole CI cycle
     before enqueue, which is where the sync loop restarted CI on every `main` merge.
     Queue mode (`QUEUE_RULE=1`, read once from `gh api repos/{owner}/{repo}/rules/branches/main`
     by `.type == "merge_queue"`, never by position, and only with a non-empty required-check set;
     the fence reads `main`'s rules, as its required-check read does) applies only to a BEHIND
     reading GitHub itself reported (not one the DIRTY block derived), with auto-merge armed (read
     per tick) and auto-sync usable. It waits for GitHub to enqueue the PR (measured, see the canary
     addendum: GitHub enqueues an armed PR whose head is behind `main` on its own under the strict
     policy, so no explicit enqueue and no ruleset change), reports the enqueue once
     (`[ship.phase7.queued]`, at the first 5th-tick read that finds the PR queued; that reading also
     restarts the idle count, so while each 5th-tick read answers queued the PR does not expire), and is bounded: more than 5
     CONSECUTIVE wait ticks (the 6th) with no pending REQUIRED check latches back to today's sync for
     the rest of that poll (`[ship.phase7.queue_wait_expired]`), and that sync's `--step` still skips
     a queued PR through its own queue gate and stops on an unreadable queue read; `MAX_POLL_MIN` still
     caps a PR whose required checks never settle or whose state keeps flapping (any tick that is not
     a wait tick restarts the idle count). Every unreadable answer falls toward today's sync: a failed
     rules read or an empty required-check set leaves queue mode off for the poll, a failed armed read
     ends the wait for that tick, and a failed checks read counts as idle. A repo with no `merge_queue`
     rule runs today's code unchanged. `sync-pr-behind.sh` and the `pre-merge-rebase.sh` hook are not
     changed (the hook runs once per `gh pr merge`, not per poll tick). Accepted residuals: (1) some
     required contexts post a PASS on `merge_group` without re-running their suites
     (`tenant-integration-required` and `vendor-pin-required`; see each workflow's `merge_group`
     comment), so in queue mode their only real run is the PR-time one against the PR-time base,
     where the sync used to re-run the PR-event versions on a fresher base; (2) a wait tick makes no
     `--step` call, so the seen-queued marker is not written during the wait, and a dequeue is found
     only by a current removal event, on the next 5th-tick read.
   - The `pre-merge-rebase.sh` hook reads the same state and skips its origin/main
     merge-and-push for an already queued PR. It resolves the PR from the bare number,
     the number plus flags in any order, `#N`, `-R/--repo` forms and a `cd <wt> &&` or
     `export GH_REPO=..;` prefix. It parses the helper's STDOUT only (its stderr is never
     read as a verdict); a failed, timed-out or unparseable read falls back to today's
     sync and carries one warning in `additionalContext` (which the agent sees) as well as
     on stderr (which it does not on an exit-0 hook); it is never a block and never read
     as queued. Known limitation, pinned by a test row: flag-before-number
     (`gh pr merge --squash <N>`) and a URL operand are NOT resolved and still reach the
     sync.
   - `monitor-pr-checks.sh` reads the queue on BEHIND, BLOCKED, auto-merge-off and every
     `--heartbeat-every`th tick, through the shared `--queue-state` read, which is
     tri-state (queued / not queued / unknown). A queued PR keeps being watched; an
     unknown read changes nothing and, after a queued sighting, holds the previous
     verdict. `LEFT THE MERGE QUEUE UNMERGED` (rc 1) needs a positive not-queued read of
     an OPEN PR from a measured poll plus a `dequeued` verdict or a queued sighting
     followed by auto-merge off. `--repo` must be `OWNER/REPO` (else exit 3).
   - `drain-prs` §4 describes the active queue and the dequeue arm; `drain-prs` and
     `merge-pr` refuse to arm a cross-repository PR or a PR touching `.github/**`
     without explicit operator confirmation (the control for the fork residual below):
     `gh pr view <N> --json isCrossRepository` plus the paginated pulls files API
     (`gh api repos/{owner}/{repo}/pulls/<N>/files --paginate`); `gh pr view --json files`
     stops at 100 files, so a large PR could hide a workflow edit.

### Parameters

| Param | Value | Why |
| --- | --- | --- |
| `merge_method` | `SQUASH` | Matches `gh pr merge --squash`; the repo's `squash_merge_commit_message` is `COMMIT_MESSAGES`. |
| `grouping_strategy` | `ALLGREEN` | Safe default; with `max_entries_to_merge = 1` every group is one PR. |
| `max_entries_to_merge` | `1` | One PR per merged group keeps CLA verification exact (the PR number is in `head_ref`) and avoids batch-failure bisection. |
| `min_entries_to_merge` | `1` | Merge a green candidate immediately. |
| `min_entries_to_merge_wait_minutes` | `0` | The provider default (5) would add five minutes to every merge. |
| `max_entries_to_build` | `2` | Speculation (the point of the queue) with bounded runner contention: each entry runs all 25 contexts, so three parallel builds is about 3x the jobs. Raise to 3 only after the canary shows contention is not binding. |
| `check_response_timeout_minutes` | `60` | Must exceed the slowest required check on `merge_group` including runner start spread: PR wall-clock max 32.8 min plus ADR-032's 2026-09-14 measurement of a 28-minute (1708 s) maximum start spread on a drained group puts spread plus critical path near 43 min. The earlier value (15) was sized on an 8-minute critical path; an under-set value dequeues a green PR and re-creates the starvation. The stall probe threshold is 45 minutes, below this, so a stuck entry can be reported before the queue ejects it silently (best-effort: see "Stall probe"). |

The values equal the `.tf`, the DR skeleton and the `infra/github/README.md`
table; the parity gate in `tests/scripts/test-audit-ruleset-bypass.sh` (successor
of T-mq-1) compares all seven and fails if `CodeQL` is a required check while a
`merge_queue` rule exists.

### Alert-gate semantics (post-merge, page-and-continue)

The gate runs after the merge commit is on `main`, so it cannot block. It turns
the run red, files a deduplicated issue and never auto-reverts. "New" means "no
bot-authored open tracking issue exists for the alert" (`sec: CodeQL alert #N`,
the same title and `type/security` label the daily `codeql-to-issues.yml` cron
uses, so the two never double-file); a `created_at` watermark was rejected
because a queued PR scanned before the previous main push would sit below it.
Phase 1 waits on the `Analyze (*)` check-runs (not an analysis count: `ruby` has a
check-run and no analysis); phase 2 additionally waits for THIS commit's analyses
to be ingested, on its own poll budget (the production defaults are pinned by a test
that runs the script with nothing overridden). The whole gate runs under a
wall-clock deadline of 30 minutes (`DEADLINE_SECONDS` 1800), checked between calls:
before every poll of phases 1 and 2 (a pause that would not fit is never taken) and,
in phase 3, after the alerts read and before every tracking-issue create (a hit there
degrades with `deadline-exceeded`, so a late phase 2 can degrade rather than file
trackers late; the daily cron is the cover). Phases 1 to 3 are therefore bounded as a
sequence of calls, which is the designed margin below the job's 40-minute
`timeout-minutes` kill, not a guarantee: the call in flight at a check runs to its own
`timeout 60`, the degraded upsert is up to two more such calls, and a read started just
before the deadline adds one (about 34 minutes at the default); a runner stall or a hung
local tool is outside any in-script bound, and a job kill never reaches the script's
`degrade`. The four numeric knobs (`POLL_INTERVAL`, `MAX_POLLS`, `SETTLE_POLLS`,
`DEADLINE_SECONDS`) are decimal-validated digits (`08` is eight, never octal). The
`code-scanning/analyses` endpoint ignores `sha=` when `ref=` is
set (measured: 8,926 analyses over 90 pages, about 30 s), so the history is never
paginated: one newest-first page (`per_page=100`, `ref=refs/heads/main`) is read per
poll and filtered in `jq` on `.commit_sha`, and the gate needs at least one analysis
for the commit and a count unchanged across two polls. It then reads open
critical/high alerts on `refs/heads/main`, files data-minimised issues (alert
number, validated rule id, severity, a URL built from the number; never alert text),
upserts one `codeql-gate-degraded` issue on any degraded exit (deadline exceeded,
cap hit, zero check-runs, API error; labels `meta/machinery` per ADR-216 because it is
a finding about the gate's own machinery, `type/security` because the dedupe read is
scoped to it, `priority/p2-medium`, and `action-required`, which is what makes it a
page: the operator digest harvests `action-required` and keeps `meta/machinery` only
alongside it) and fails closed on any `gh` error. A degraded exit reads no alerts for
that push; the daily cron is the cover. The red run is the
push-time signal; the labelled issue is the durable page, because a push made by the
merge queue has no human actor to notify. To accept a risk, DISMISS the alert in
code scanning: closing the tracking issue accepts nothing, the alert stays open and
the next push files a new issue (a closed tracker with an open alert re-files; the
action-required SLA cron can auto-close an inactive tracker, which re-files the same
way). The gate cannot see a commit pushed with `GITHUB_TOKEN` (such a push does not
fire `push` workflows); queue merges are not token pushes, and canary 6 checks it.

### Stall probe (best-effort)

`merge-queue-stall-check.yml` files `merge-queue stall: PR #N` (labels
`merge-queue-stall` and `action-required`, with agent-runnable `gh api graphql` and
`gh run list --event merge_group` commands in the body) for a queue entry pending
past 45 minutes, below the 60-minute timeout. It ages only entries at
`position <= max_entries_to_build` (2), because an entry deeper in a healthy drain
waits its turn and can pass 45 minutes from `enqueuedAt` without being stalled
(`position` being 1-based is assumed, not yet observed on a live entry; if it is
0-based the filter admits one extra entry, a false positive, not a miss). Detection
latency is the threshold plus the schedule delivery delay, and GitHub `schedule:`
delivery on this repository is degraded: the sibling `*/15` workflow
`scheduled-inngest-health.yml` measured a median gap of about 275 min (n=59 fires,
max about 479) and `scheduled-actions-queue-health.yml` (`*/30`) gaps of 2.7 to 6 h.
Against the 15-minute window between threshold and timeout the probe will often miss a
stuck entry, so no issue is not proof of a healthy queue; it is best-effort. A filed
issue is a SUSPECTED stall that needs verification, not a confirmed one: the age counts
from `enqueuedAt`, so an entry promoted to position 1 or 2 after waiting behind others,
or a healthy slow build near the roughly 50-minute `merge_group` CI maximum (n=99), can
pass 45 minutes without being stalled. The position filter reduces those false positives
and does not remove them. The title ends `(suspected, verify first)` and the body leads
with the agent-runnable triage (live queue read, the entry's `merge_group` runs: an
in-progress run is a healthy build, no run is a real stall). The fix is an Inngest
`workflow_dispatch` cron, `cron-merge-queue-stall-dispatch` (landed with #9482
follow-up (a); ADR-033's 2026-06-02 scope note: trigger on Inngest, execution in the
ephemeral runner). The workflow's `schedule:` is now the fallback, and the function
header is the authority for the timing story; a canary row measures the `schedule` gap.
The probe is blind to a disabled queue by design (the drift cron owns that).

## CLA synthetic trust model

`cla-check` and `cla-evidence` cannot run on `merge_group`, and the CLA Required
ruleset applies to the queue's temp ref. They stay required: the restored
`merge-queue-cla-synthetics.yml` posts both names on `merge_group.head_sha` only
after `scripts/merge-queue-cla-verify.sh` has verified, for the PR named in
`merge_group.head_ref`, that the real `cla-check` and `cla-evidence` check-runs
(app `github-actions`, integration id 15368, `--paginate`) are `success` on the
PR's head, taking the latest run per name by check-run id, not `started_at` (an old
red followed by a newer green passes; the reverse fails; a queued re-run has a null
`started_at` and must not be masked by an older success, the way
`admin-merge-ready.sh` already resolves it). Any miss, a red, or a `gh` error fails
the job, and a failed verify posts BOTH `cla-check` and `cla-evidence` on the
candidate with `conclusion=failure` and the reason in the title (the reason is passed
through a step output and env, never `${{ }}` in a `run:`), so the entry is expected to
be dequeued at once and to show in `gh run list --event merge_group` (expected, not
measured: a red-CLA PR is not canaried, so confirm it the first time one occurs);
without that the entry would pend until `check_response_timeout_minutes`. The synthetic never posts success
without a green verify. Hardening: `head_ref` is routed through an
environment variable and must match
`^refs/heads/gh-readonly-queue/main/pr-[0-9]+-[0-9a-f]{40}$`;
`merge_group.base_ref` must be `refs/heads/main`; the verification logic runs from
a checkout of the repository's default branch tip with `persist-credentials: false`,
never the candidate, so no PR-controlled code runs with a `checks: write` token
under the 15368 identity. Auth is `GITHUB_TOKEN` (the ruleset matches integration id
15368).

There is deliberately no "PR head is a parent of the candidate" check. With
`merge_method = SQUASH` the queue candidate is a single-parent squash commit whose
parent is the previous candidate (measured on the first adoption: candidate
`6f0e5d87a9` for `pr-5798` had one parent and PR #5798's head was not a parent), so
such a check can never pass and would deadlock the queue; and a push to a queued PR
dequeues it, so the head cannot change between the real checks and the candidate.
A wiring suite (`merge-queue-cla-workflow-wiring.test.sh`) parses the workflow YAML
and asserts the step order, no `continue-on-error` or `|| true` on the verify, the
default-branch checkout ref, the env routing and that the posted names equal the CLA
canonical names; the verify script's own suite drives the real `gh` shape (pagination
with `filter=all`, ref-aware PR-head reads).

Residual, accepted: the workflow definition itself comes from the candidate
commit like every other `merge_group` workflow, and entry to the queue requires a
write-access actor (the same trust that already lets a same-repo PR run its own
workflows with a token). This applies to EVERY `merge_group` job, not only the CLA
synthetic, and `merge_group` runs carry repository secrets, so a fork PR a
maintainer enqueues runs its own workflow edits in a secrets-bearing context (a
reach the pre-queue `pull_request` run of a fork never had; the repository carries
`DOPPLER_TOKEN`, `SENTRY_IAC_AUTH_TOKEN` and `ANTHROPIC_API_KEY` among its secrets).
Controls, none a hard gate: `drain-prs` and `merge-pr` refuse to arm a
cross-repository PR or a PR touching `.github/**` without explicit operator
confirmation (an agent-side guard, `gh pr view --json isCrossRepository` plus the
paginated pulls files API, because `gh pr view --json files` stops at 100 files; a human
can still enqueue one), and CODEOWNERS:
`.github/CODEOWNERS` has the umbrella row `/.github/workflows/` and, added in this
PR, explicit rows for the gate, the CLA verify, the probe, `sync-pr-behind.sh` and the
pre-merge hook, plus the gate's own suite, its wiring suite and the gate fixture
directories. The other suites (`merge-queue-cla-verify.test.sh`,
`merge-queue-cla-workflow-wiring.test.sh`, `merge-queue-stall-check.test.sh`,
`required-checks-merge-group-coverage.test.sh`, `sync-pr-behind.test.sh`,
`pre-merge-rebase.test.sh`, and Guard 2 in `tests/scripts/test-audit-ruleset-bypass.sh`)
have no explicit row. A CODEOWNERS row adds no enforced review: the CI Required ruleset
does not require code-owner review, so today it is review discipline, not a gate;
enforcing it is the real fix and is out of scope here. Related residual: the post-merge gate script and
workflow are loaded from the pushed commit, so the detector is editable by the change
it judges (a PR could neuter the gate and land a critical sink in one commit; the
old required `CodeQL` check, bound to GHAS, could not be edited from a PR). The
only barrier is review of that diff. The
entry-gate premise cited in the workflow header is GitHub's "Managing a merge
queue": a PR can be added to the queue only after passing all required branch
protection checks. The 2026-08-17 CLO ruling on `cla-evidence` is unaffected:
`cla-evidence` stays required, satisfied on `merge_group` by a verified synthetic
(see the one-line determination appended to that ruling).

## Consequences

### Positive

- The per-PR BEHIND resync loop and its repeated full CI cycles go away; a green
  PR waits on one candidate build, not on every main advance.
- The strict policy's up-to-date guarantee is satisfied by construction, with no
  routine `--admin` merge.
- A new critical/high CodeQL alert on `main` is surfaced within minutes of the
  push without standing-backlog noise (three open alerts today, all `medium`).
- Rollback is one Terraform diff and does not depend on the queue draining.

### Negative and accepted residuals

- **Pre-merge CodeQL blocking is lost.** A PR whose own head carries a new
  critical/high alert can now merge. The gate pages about 9 to 11 minutes after the
  push (measured on n=1, `origin/main` b77bee3707: `Analyze (javascript-typescript)`
  ran 21:47:17Z to 21:56:16Z and 21:57:57Z, plus ingestion; the `Analyze` check-runs
  alone finish p50 5.1, max 6.6 min after the commit, n=23). The deploy is triggered
  by `workflow_run` of CI success on the main push and completes 12.9 to 41.1 min after
  the merge (median about 19, n=12; CI on main pushes p50 17.6, p90 24.8, n=40), so the
  page usually leads the deploy start, but NOTHING in the deploy chain waits for it
  (deliberate: no `needs:`/`workflow_run:` on the gate), so a flagged commit can
  deploy unattended and a `workflow_dispatch` deploy skips CI entirely. An
  `actions`-language critical/high finding (code injection in an `issue_comment` or
  `pull_request_target` workflow) is live on `main` the moment it merges, on a public
  repository with secrets, for the whole gate window. Those two vectors, the deploy
  hold and the threshold are User-Challenges 1 to 3 in `decision-challenges.md`;
  none is applied. Brand-survival threshold stays `aggregate pattern` as the operator
  declared it; the user-impact review argues for `single-user incident` with CPO
  sign-off (Challenge 2), pending the operator's go-ahead. The daily
  `codeql-to-issues.yml` cron stays as the backstop (up to 24 hours if the gate never
  fires; it swallows API errors with `|| true` today, Follow-up (b)).
- **Insider dismissal is not covered.** The gate reads only open alerts, so an actor
  who dismisses a critical/high alert is not detected (the same trust that can
  `--admin` merge). A dismissal-evasion check was designed and removed as
  unreachable beyond that trust.
- **The detector is editable by the change it judges** (see the CLA trust model: the
  gate script and workflow load from the pushed commit; CODEOWNERS rows exist but
  code-owner review is not enforced by the ruleset).
- **Fork PRs reach secrets on `merge_group` once enqueued.** Control: agents refuse
  to arm a cross-repository PR or one touching `.github/**` (`drain-prs`,
  `merge-pr`); a human enqueue is not stopped. 0 of the last 200 PRs were
  cross-repository (security review), so the likelihood today is low.
- **Gate coverage bounds.** A closed tracker with an open alert re-files on the next
  push; `GITHUB_TOKEN` pushes do not fire push workflows, so the gate cannot see one.
- **Bot PRs have no `pull_request` CodeQL scan** (their diffs are limited to
  `weakness-digest.md` and `rule-metrics.json` by `ALLOWED_PATHS`), so the
  post-merge gate is their only CodeQL coverage.
- **Pass-through gates trust a pre-queue run.** `rename-guard`, `allowlist-diff`
  and waiver discipline pass through on `merge_group` on the entry-gate premise;
  for bot PRs and bypass actors that earlier run is itself synthetic. Those actors
  can already merge directly, so this adds no new reach.
- **Bot-PR gates are now earned, not fabricated.** `test`, `e2e`, `grok-fidelity`,
  `credential-path-guard`, `rule-body-lint`, `marketplace-manifest-guard` and the
  content gates run for real on `merge_group` for bot PRs (two reach the network:
  the Grok CLI install and an `mcr` image pull). A flake ejects the PR. The
  coverage guard proves the trigger and the job `if:`, not that the job body
  succeeds on `merge_group`; the first canary enqueue is the empirical test.
- **The workflow definition on `merge_group` comes from the candidate commit**
  (see the CLA trust model above).
- **Dequeue by sync.** A push to a queued PR dequeues it. `sync-pr-behind.sh` now
  skips queued PRs, but an older checkout's copy has no queued-skip and would
  dequeue; the queued-skip lands on `main` in the same PR so sessions pick it up on
  their next plugin sync. The `pre-merge-rebase.sh` hook skips its origin/main
  merge-and-push for an already-queued PR when it resolves the PR from the command
  (bare number and the forms in Decision 5; flag-before-number and a URL operand are
  not resolved and still sync); for a PR that is not yet queued on a
  queue-enabled repo it still syncs (a push before the enqueue is a new head and a
  full CI cycle, the per-PR tax the queue exists to remove; measured in canary 9,
  skip designed in Follow-up (d)), and a failed queue read falls back to that sync
  with a warning (stderr and `additionalContext`). Dequeue detection (removal event or
  marker, every 5th OPEN tick plus the BEHIND tick) is in Decision 5, with its known
  behaviours.
- **Flake ejection.** 11% of `ci.yml` runs on `main` fail post-merge on content that
  was green on the PR (11 of 99: 5 e2e flakes, 5 `test-scripts` leg failures, 2
  whole-run failures; performance review). Today that has no consequence for the
  merge; in the queue each one is a pre-merge ejection (no auto-retry), the
  speculative entry behind it rebuilds, and the ejected PR pays at least one more full
  cycle (p50 17.6 min on a `main`-push run) plus a re-enqueue. This is the cost "a flake ejects the PR"
  accepts; fixing the e2e flake first is the cheapest mitigation; canary 3/5 record
  the candidate failure rate.
- **Runner capacity and cost per merged PR.** A queue costs three full CI runs per
  merged PR (`pull_request`, `merge_group`, `push`; the `push` run is a rerun of a
  tree the `merge_group` run just built, Follow-up (c)). `ci.yml` is 34 to 36 jobs
  and 111 to 155 billed minutes per run (median about 120); the repository is public,
  so standard-runner minutes cost $0 and the real currency is concurrent-job slots
  (60 is an entitlement, not a guarantee) and wall-clock. `max_entries_to_build`
  stays 2 until measured. Break-even against the removed BEHIND resyncs is about 1.3
  removed resyncs per merged PR; the net is unmeasured (canary 9 counts sync pushes).
- **Ship's post-merge wait grows.** `soleur:ship`'s all-workflows-on-the-merge-sha check now also waits for the
  alert-gate run (about 10 to 12 minutes measured, 30-minute wall-clock deadline), and a red gate run is the intended page, not a deploy failure. No workflow
  `needs:` or `workflow_run:` keys on the gate, so it never blocks the release or deploy chain. `ship/SKILL.md` has
  too little byte headroom for a prose exemption, so this is recorded here instead.

## Rollback and re-tighten recipes

**Rollback (kill switch), one Terraform diff.** Revert exactly these hunks in one
PR (the apply workflow enacts it on merge):

- `infra/github/ruleset-ci-required.tf`: remove the `merge_queue` block and re-add
  the `CodeQL` `required_check` with `integration_id = var.codeql_integration_id`.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json`: re-add the
  `CodeQL` row.
- `scripts/create-ci-required-ruleset.sh`: restore the skeleton (no queue rule,
  `CodeQL` required).
- `infra/github/README.md`: remove the params table (Guard 2's queue-off check requires
  NO table row naming a queue param) and update the merge-queue status text.
- The Guard 2 and `T-rsc` test expectations in `tests/scripts/test-audit-ruleset-bypass.sh`,
  and the queue-on pristine inputs of the real-tree rows of that suite and of
  `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` (see below).

Queue-off state: the ENGINES treat "no source carries a `merge_queue` rule" as the
legitimate rolled-back state. The merge-group coverage probe prints
`merge-group-coverage=SKIPPED (no merge_queue rule: producers not required)` and Guard 2
reports "queue off" and passes, so re-adding `CodeQL` does not make the probe or Guard 2
themselves fail. SKIPPED means the queue is off; an accidental deletion of the
`merge_queue` block alone also reads SKIPPED, which is covered by Guard 2 (a
half-removed state, queue in some sources only or `CodeQL` required beside a live queue,
is RED) and by the drift cron. The SUITES that run in CI do not follow the engines: the
real-tree rows of the coverage suite (its `build_pristine` copies the live queue-ON `.tf`
and every mutation row expects an OK line) and of Guard 2 (`T-mq-1.m1..m13` mutate the
real queue-on files and assert an exact count; `T-rsc` expects no `CodeQL` row) build
their pristine from the live tree. A queue-removing rollback PR therefore still reds those
two suites, even though the probe and Guard 2 print SKIPPED / queue-off. The rollback is
consequently an `--admin` merge (already the stated path below), and its hunks must also
edit the suites' queue-on pristine inputs and remove the README params table, in
addition to the files above. Making those pristines self-contained is the cleaner fix and is not done here.

Adding a required check and dropping the queue block are both `0 destroy`; include
`[ack-destroy]` anyway (harmless). If the queue is stalled, merge the rollback with
`gh pr merge --admin` (admin bypass is retained; `plugins/soleur/scripts/admin-merge-ready.sh`
is the readiness gate). If both the queue and the admin bypass fail, PUT the queue-less payload to the
EXISTING ruleset id: build the payload with the DR script's jq (skeleton plus the
canonical bypass actors and required checks), drop the `merge_queue` rule from its
`.rules`, and run `gh api -X PUT repos/jikig-ai/soleur/rulesets/14145388 --input
<payload>`. Do not delete the live ruleset first: that leaves `main` with no
required checks until a POST lands and changes the ruleset id and Terraform state.
The script has no code for this path: the PUT is prose, not rehearsed, and a PUT
REPLACES the whole ruleset object, so a payload missing `bypass_actors` or `conditions`
clears them (and the admin bypass the rollback depends on goes with it); keep name,
target, enforcement, `conditions`, `bypass_actors` and all rules but `merge_queue`.
The 2026-06-30 kill-switch ran in about four minutes, but as a direct `terraform
apply`, so it rehearses neither the admin merge nor the PUT. The apply workflow's
verify step prints the required-check count and asserts neither it nor the
`merge_queue` count (pre-existing), so a silently no-op'd apply is caught only by
the canary. After a rollback, reopen #9454 and #4856 and add the observed cause to the
PIR directory.

**Re-tighten (when upstream resolves `codeql-action#1537`).**
`codeql-1537-revisit-watch.yml` pings #5840 on upstream close. First verify on a
real queue entry that CodeQL posts a status context on `merge_group`; only then
re-add the `CodeQL` `required_check` with `integration_id = var.codeql_integration_id`
to the `.tf`, the canonical JSON and the DR skeleton, and flip Guard 2's
CodeQL-absent invariant deliberately in the same PR. The queue and a working
`merge_group` CodeQL status then coexist. One Terraform diff; the post-merge gate
can be retired or kept as defence in depth.

## Raise checklist (`max_entries_to_merge` above 1)

A multi-PR group is not reachable while `max_entries_to_merge = 1`. Before raising
it: the CLA synthetic must enumerate every PR in the group (`merge_group.head_ref`
names one PR; verification must cover each PR's real `cla-check` / `cla-evidence`),
`grouping_strategy` and the
`ALLGREEN` bisection behaviour must be re-read, `check_response_timeout_minutes`
must be re-derived against the larger group, and the Guard 1 / Guard 2 gates and
the README table must move with the `.tf`.

## Canary measurements (flip `adopting` to `accepted` when these hold)

Post-apply, agent-run, no SSH. Recorded in the PR notes and on #9454. Run in this
order.

1. **FIRST, before anything else: the admin bypass.** One `gh pr merge --admin` of a
   trivial PR merges past the queue (`bypass_actors` `RepositoryRole 5`, mode
   `pull_request`). The rollback depends on it. A failure is an IMMEDIATE rollback
   trigger: PUT the queue-less payload to the existing ruleset (see the rollback
   recipe above), and amend this ADR before the queue is left on.
2. Apply run green; live ruleset has exactly one `merge_queue` rule, `CodeQL` is no
   longer required, and the CI Required count is 23; the anonymous
   `rules/branches/main` probe lists `merge_queue`; GraphQL `mergeQueue(branch:"main")`
   is non-null; `scheduled-terraform-drift.yml` plans no changes for `infra/github`.
3. Canary human PR via `gh pr merge --squash --auto`: it enters the queue, all 25
   contexts (23 plus `cla-check` and `cla-evidence`) report on the temp ref, and it
   merges. Record enqueue-to-merge minutes, the observed `mergeStateStatus` of a
   queued PR (unmeasured; the dequeue rule no longer depends on it, the queued-skip is
   correct either way), the removal-event payload (`reason`, and its timestamp against the
   auto-merge enable and the head commit) on a real ejection if one occurs, the observed
   queue entry `state` and `position` values on a real entry (is `position` 1-based,
   which the stall filter assumes; which `state` a never-reporting head entry shows),
   the candidate squash shape recorded (number of parents, and whether the PR head is
   one; the first adoption measured one parent) and which check-run names and apps land
   on the candidate (the CLA verify relies on neither parent shape nor extra names,
   so a surprise here is a finding). Also record that the push SHA equals
   `merge_group.head_sha` (Follow-up (c)'s premise).
4. Canary bot PR (next `weakness-miner.yml` PR): flows through without stalling. If a
   `GITHUB_TOKEN`-armed bot PR sits pending, the queue stays on for human PRs only if
   bot PRs fall back to the admin-merge path and a follow-up to arm bot PRs with an
   App token is filed in the same session.
5. `merge_group` CI wall-clock and runner start spread, against the push-run proxy
   (p95 37.3, p99 44.2, max 50.8 min, n=99), whose headroom under the 60-minute
   timeout is 9 to 23 min. If the slowest required check on a real candidate exceeds
   30 minutes, raise `check_response_timeout_minutes` in the same Terraform root (one
   line); keep `max_entries_to_build` at 2 until contention is measured. Record the
   candidate failure rate against the 11% post-merge flake rate.
6. The first `codeql-main-alert-gate.yml` push run is green and its push-to-verdict
   time is recorded against the measured 9 to 11 minutes (n=1) and the Analyze
   check-runs' p50 5.1 / max 6.6 min (proves the trigger fires for a queue-made
   push); record whether the deploy finishes before the gate does, and over the first
   queue merges the gate push-to-verdict spread against CI on main pushes (p50 17.6,
   fastest 11.5 min).
7. PRs armed before the apply (`gh pr list --state open --json number,autoMergeRequest`)
   each show a `mergeQueueEntry` within minutes or merge.
8. Inspect the queue-built squash commit: record whether the message came from the
   commits or from the PR title and body, and what happens when
   `check_response_timeout_minutes` is exceeded.
9. Confirm `pre-merge-rebase.sh` is a no-op for an enqueue of an up-to-date branch
   and skips the sync for an already-queued PR, and record the head-change and CI
   cost of its sync for a not-yet-queued behind branch, as the count of hook and
   fence sync pushes per merged PR (before and after the queue).
10. Measure the `schedule`-event gap of `merge-queue-stall-check.yml`
    (`gh run list --workflow merge-queue-stall-check.yml --event schedule`) against
    the 15-minute window between the 45-minute threshold and the 60-minute timeout;
    a wider median gap makes Follow-up (a) the next change (Follow-up (a) landed; the
    dispatched-run spacing and runner-start latency are measured on #9482 after merge).

GitHub's documentation does not settle items 1, 3, 8 and the squash-message source;
each is recorded as a measurement with a defined fallback, not as an assumption.

## Canary results (recorded 2026-10-04, merge commit 814533b223)

- Item 2: the `Apply github infra (rulesets)` run for the merge commit succeeded. The live ruleset 14145388
  carries one `merge_queue` rule (SQUASH, ALLGREEN, max build 2, max merge 1, min merge 1, wait 0, timeout 60),
  23 required contexts, no `CodeQL` context, strict policy on, and both bypass actors unchanged; the plan was one
  in-place update with no destroy.
- Item 6: the first `codeql-main-alert-gate.yml` push run (run 37210557735) waited for the `Analyze (*)` check-runs
  of the pushed SHA, found 0 open critical/high candidates and returned `verdict=GREEN` 3 min 52 s after the merge
  commit landed (the job itself ran 3 min 39 s; the 9 to 11 min estimate was n=1 on a different commit).
- Items 1, 3 to 5 and 7 to 10: pending; recorded on #9454 as each canary completes.

### Addendum 2026-10-05 (#9482)

Definitions, commands and caveats are in [the #9482 measurement comment](https://github.com/jikig-ai/soleur/issues/9482#issuecomment-5992118670); the numbers below are the record.

- Item 4: pending. No `weakness-miner.yml` PR has merged since adoption (the last, #9479, merged before the queue); the next scheduled fire is 2026-10-11T06:00Z. Status stays `adopting` until one clean pass.
- Item 9: sync merges (proxy for sync pushes) per merged human PR: 2.50 before (n=40), 0.83 after (n=12, about 17 h), a delta of 1.67 against the 1.3 break-even; first reading, small after-window.
- Item 10: dispatched runs of `merge-queue-stall-check.yml` start 10.0 min apart (within 10 s) with 4 to 5 s runner start (n=5, quiet window); no executor heartbeat. A red executor run alerts nobody (tracked in #9513).
- Item 3 (partial): push SHA equals `merge_group.head_sha` for 13 of the 15 completed push runs on `main` (snapshot 2026-10-05 ~09:50Z); the other 2 are the adoption merge and the admin-bypass canary (Follow-up (c), tracked in #9512).

### Addendum 2026-10-07 (#9710): enqueue while BEHIND

Measured read-only for the queue-mode design. Question: does GitHub enqueue an armed PR whose head is behind `main` once its
checks are green, under `strict_required_status_checks_policy = true`? Answer: yes.

- PR #9697: `auto_merge_enabled` 2026-10-07T11:02:22Z; last commit dated 11:53:47Z (head `4b0bb6d78d`, merge-base
  `8b43d09caa`); `added_to_merge_queue` 12:39:57Z with no push in between. Two `main` commits landed between the
  merge-base and the enqueue, not counting the PR's own squash commit (the queue dates that commit at the enqueue
  instant, so a `--before <enqueue>` date filter run after the merge counts 3). The one queued reading taken (#9697 after
  the enqueue) was `OPEN CLEAN` with auto-merge disarmed (n=1).
- Five further PRs merged through the queue that day were enqueued with a single enqueue event while 1 to 14 `main`
  commits behind, 9 to 47 minutes after auto-merge was armed; method and table in
  `knowledge-base/project/plans/2026-10-07-fix-ship-phase-7-merge-queue-aware-behind-sync-plan.md`.
- The plan records BEHIND showing only while a check was pending; that reading is why the idle count keys on
  pending REQUIRED checks and not on `mergeStateStatus`. Not measured: the last-green-to-enqueue latency over more
  than one sample. The 5-tick grace is a chosen margin, to be re-derived from that latency.
- Dogfood finding (PR #9710's own poll, same day): the idle count keyed on pending REQUIRED checks *present in the list*, but
  the aggregate required context `test` does not exist until its shards finish, so 24 of 25 required contexts were
  complete (last at 20:45:17Z) while the shards ran and the count expired on tick 6, syncing mid-CI (push at 20:50:54Z).
  The expiry fallback did its job (a sync, today's behaviour) but defeated the wait for the whole shard window. Fixed in
  the same PR: a required context that is absent counts as pending while any check is pending, and as idle when nothing
  is (fixtures Q12, Q12b). This run therefore says nothing about enqueue latency: it expired before the required set could
  complete.

## Cost Impacts

No new vendor or subscription. A queue adds one `merge_group` run per candidate on
top of the `pull_request` and `push` runs (up to `max_entries_to_build` = 2 in
parallel), billed against the Team plan's 60 concurrent hosted jobs. No change to
`knowledge-base/operations/expenses.md`.

## NFR Impacts

None of the NFR-register rows changes tier. The register has no SAST or
merge-gating NFR; the control moved (pre-merge PR-head block to post-merge
detection) is recorded as an accepted residual above.

## Principle Alignment

- AP-001 (Terraform-only infrastructure provisioning): Aligned. The queue and the
  required-check change are declarative in `infra/github`; the DR script is kept in
  sync by Guard 2.
- AP-011 (ADRs for architecture decisions): Aligned. This ADR supersedes in part
  an earlier ADR-032 decision and records the trade.

## C4 impact

No C4 impact. The three `.c4` files under `knowledge-base/engineering/architecture/diagrams/`
were read in full (`model.c4` 891 lines, `views.c4` 113 lines, `spec.c4` 54 lines)
and `bash plugins/soleur/test/c4-count-parity.test.sh` passes 12/12.

- External actors: none new (the founder and agents already merge through GitHub).
- External systems: GitHub is already modelled (`github = system "GitHub"` and
  `engine -> github "Git operations and CI"`); CodeQL, the merge queue and rulesets
  are GitHub features, not new systems. The `github` description does not state
  "direct merge" or "CodeQL required", so no element description is falsified; the
  only "ruleset" mentions concern the soleur-marketplace repository's ruleset and
  Cloudflare rulesets, unrelated to the CI Required ruleset.
- Data stores: none (the workflows are stateless; the gate keeps no cache or artifact).
- Access relationships: unchanged.

## Amendment 2026-10-09 (accepted by operator direction)

Status moves `adopting` to `accepted` on 2026-10-09 by the operator's (founder's) direction, given in their own
words that day: "yes please accept and flip to adopting and start S3" (answering: accept ADR-270 and flip ADR-276
to adopting so S3 can start). The Status section above says the flip waits for the post-apply canary to pass; that
condition is NOT met. This amendment records that acceptance came first, so the record does not read as a passed
canary.

The canary items not yet recorded as measured at this date are items 1, 3, 4, 5, 7, 8, 9 and 10 of "Canary
measurements" (items 2 and 6 are recorded under "Canary results"; items 3, 4, 9 and 10 carry only first, partial or
pending readings in the 2026-10-05 addendum, not a completed measurement). Item 1 has a PASS recorded outside this
file, in the #9454 comment of 2026-10-04T15:46Z (#9485 admin-merged past the queue at 15:20:13Z, not strictly first as
the item requires), so it is listed here because this file's Canary results do not carry it. Item 6 is recorded as one
GREEN verdict with 0 candidates (run 37210557735); this file records no run of the post-merge alert gate going RED on
a real critical or high alert, so the compensating control for advisory CodeQL is evidenced on its green path only. Item 4 waits for the next
`weakness-miner.yml` PR; the next scheduled fire is 2026-10-11T06:00Z. Their text, verbatim from "Canary
measurements":

> 1. **FIRST, before anything else: the admin bypass.** One `gh pr merge --admin` of a
>    trivial PR merges past the queue (`bypass_actors` `RepositoryRole 5`, mode
>    `pull_request`). The rollback depends on it. A failure is an IMMEDIATE rollback
>    trigger: PUT the queue-less payload to the existing ruleset (see the rollback
>    recipe above), and amend this ADR before the queue is left on.
> 3. Canary human PR via `gh pr merge --squash --auto`: it enters the queue, all 25
>    contexts (23 plus `cla-check` and `cla-evidence`) report on the temp ref, and it
>    merges. Record enqueue-to-merge minutes, the observed `mergeStateStatus` of a
>    queued PR (unmeasured; the dequeue rule no longer depends on it, the queued-skip is
>    correct either way), the removal-event payload (`reason`, and its timestamp against the
>    auto-merge enable and the head commit) on a real ejection if one occurs, the observed
>    queue entry `state` and `position` values on a real entry (is `position` 1-based,
>    which the stall filter assumes; which `state` a never-reporting head entry shows),
>    the candidate squash shape recorded (number of parents, and whether the PR head is
>    one; the first adoption measured one parent) and which check-run names and apps land
>    on the candidate (the CLA verify relies on neither parent shape nor extra names,
>    so a surprise here is a finding). Also record that the push SHA equals
>    `merge_group.head_sha` (Follow-up (c)'s premise).
> 4. Canary bot PR (next `weakness-miner.yml` PR): flows through without stalling. If a
>    `GITHUB_TOKEN`-armed bot PR sits pending, the queue stays on for human PRs only if
>    bot PRs fall back to the admin-merge path and a follow-up to arm bot PRs with an
>    App token is filed in the same session.
> 5. `merge_group` CI wall-clock and runner start spread, against the push-run proxy
>    (p95 37.3, p99 44.2, max 50.8 min, n=99), whose headroom under the 60-minute
>    timeout is 9 to 23 min. If the slowest required check on a real candidate exceeds
>    30 minutes, raise `check_response_timeout_minutes` in the same Terraform root (one
>    line); keep `max_entries_to_build` at 2 until contention is measured. Record the
>    candidate failure rate against the 11% post-merge flake rate.
> 7. PRs armed before the apply (`gh pr list --state open --json number,autoMergeRequest`)
>    each show a `mergeQueueEntry` within minutes or merge.
> 8. Inspect the queue-built squash commit: record whether the message came from the
>    commits or from the PR title and body, and what happens when
>    `check_response_timeout_minutes` is exceeded.
> 9. Confirm `pre-merge-rebase.sh` is a no-op for an enqueue of an up-to-date branch
>    and skips the sync for an already-queued PR, and record the head-change and CI
>    cost of its sync for a not-yet-queued behind branch, as the count of hook and
>    fence sync pushes per merged PR (before and after the queue).
> 10. Measure the `schedule`-event gap of `merge-queue-stall-check.yml`
>     (`gh run list --workflow merge-queue-stall-check.yml --event schedule`) against
>     the 15-minute window between the 45-minute threshold and the 60-minute timeout;
>     a wider median gap makes Follow-up (a) the next change (Follow-up (a) landed; the
>     dispatched-run spacing and runner-start latency are measured on #9482 after merge).

Nothing above this heading is edited by this amendment except the frontmatter `status:` line. The earlier Status
sentence "Flips to `accepted` when the post-apply canary ... passes" (the lead beginning "**Adopting — 2026-10-03**"),
the heading "Canary measurements (flip `adopting` to `accepted` when these hold)" and the Item 4 sentence "Status stays
`adopting` until one clean pass" are superseded by this amendment, not rewritten.
The pending measurements keep being recorded on #9454 as each completes; a measured failure of item 1 (the admin
bypass) still triggers the rollback recipe above regardless of this status.
