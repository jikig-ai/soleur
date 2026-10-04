---
title: Merge queue with advisory CodeQL and a post-merge alert gate
status: adopting
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
clock on PRs (60 green runs, `gh run list --workflow ci.yml --event pull_request`)
is p50 17.7 min, p90 25.9 min, max 32.8 min, so with about ten auto-merge-armed
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
  `knowledge-base/project/specs/feat-one-shot-9454-merge-queue-advisory-codeql/decision-challenges.md`
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
5. Make the merge tooling queue-aware: `sync-pr-behind.sh` skips a PR that is in
   the queue (`--step` exits 11 for it, `kind=queued rc=11`, the ship and merge-pr
   fences' uncounted `sync_noop` arm; the standalone loop exits 0; nothing is merged
   or pushed either way; a failed queue read is `kind=gh`, exit 4, never "not
   queued"); the `pre-merge-rebase.sh` hook reads the same queue state and skips its
   origin/main merge-and-push for an already queued PR, with a failed or unparseable
   read falling back to today's sync (never a block, never read as queued);
   `drain-prs` §4 describes the active queue and the dequeue arm.

### Parameters

| Param | Value | Why |
| --- | --- | --- |
| `merge_method` | `SQUASH` | Matches `gh pr merge --squash`; the repo's `squash_merge_commit_message` is `COMMIT_MESSAGES`. |
| `grouping_strategy` | `ALLGREEN` | Safe default; with `max_entries_to_merge = 1` every group is one PR. |
| `max_entries_to_merge` | `1` | One PR per merged group keeps CLA verification exact (the PR number is in `head_ref`) and avoids batch-failure bisection. |
| `min_entries_to_merge` | `1` | Merge a green candidate immediately. |
| `min_entries_to_merge_wait_minutes` | `0` | The provider default (5) would add five minutes to every merge. |
| `max_entries_to_build` | `2` | Speculation (the point of the queue) with bounded runner contention: each entry runs all 25 contexts, so three parallel builds is about 3x the jobs. Raise to 3 only after the canary shows contention is not binding. |
| `check_response_timeout_minutes` | `60` | Must exceed the slowest required check on `merge_group` including runner start spread: PR wall-clock max 32.8 min plus ADR-032's 2026-09-14 measurement of a 28-minute (1708 s) maximum start spread on a drained group puts spread plus critical path near 43 min. The earlier value (15) was sized on an 8-minute critical path; an under-set value dequeues a green PR and re-creates the starvation. The stall probe threshold is 45 minutes, below this, so a stuck entry is reported before the queue ejects it silently. |

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
to be ingested. The `code-scanning/analyses` endpoint ignores `sha=` when `ref=` is
set (measured: 8,926 analyses over 90 pages, about 30 s), so the history is never
paginated: one newest-first page (`per_page=100`, `ref=refs/heads/main`) is read per
poll and filtered in `jq` on `.commit_sha`, and the gate needs at least one analysis
for the commit and a count unchanged across two polls. It then reads open
critical/high alerts on `refs/heads/main`, files data-minimised issues (alert
number, validated rule id, severity, a URL built from the number; never alert text),
upserts one `codeql-gate-degraded` issue on any degraded exit (cap hit, zero
check-runs, API error; labels `meta/machinery` per ADR-216 because it is a finding
about the gate's own machinery, `type/security` because the dedupe read is scoped
to it, `priority/p2-medium`) and fails closed on any `gh` error. The red run is the
push-time signal; the labelled issue is the durable page, because a push made by the
merge queue has no human actor to notify. To accept a risk, DISMISS the alert in
code scanning: closing the tracking issue accepts nothing, the alert stays open and
the next push files a new issue.

## CLA synthetic trust model

`cla-check` and `cla-evidence` cannot run on `merge_group`, and the CLA Required
ruleset applies to the queue's temp ref. They stay required: the restored
`merge-queue-cla-synthetics.yml` posts both names on `merge_group.head_sha` only
after `scripts/merge-queue-cla-verify.sh` has verified, for the PR named in
`merge_group.head_ref`, that the real `cla-check` and `cla-evidence` check-runs
(app `github-actions`, integration id 15368, `--paginate`) are `success` on the
PR's head, taking the latest run per name (an old red followed by a newer green
passes; the reverse fails, as the ruleset itself resolves them). Any miss, a red,
or a `gh` error fails the job, so the queue entry fails visibly instead of
passing a CLA gate that did not run. Hardening: `head_ref` is routed through an
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

Residual, accepted: the workflow definition itself comes from the candidate
commit like every other `merge_group` workflow, and entry to the queue requires a
write-access actor (the same trust that already lets a same-repo PR run its own
workflows with a token). This applies to EVERY `merge_group` job, not only the CLA
synthetic, and `merge_group` runs carry repository secrets, so a fork PR a
maintainer enqueues runs its own workflow edits in a secrets-bearing context. The
named control is CODEOWNERS on `.github/workflows/**`: `.github/CODEOWNERS` exists
and its umbrella row `/.github/workflows/` names the owner, but code-owner review is
NOT enforced by the CI Required ruleset, so today it is review discipline, not a
gate; enforcing it is the real fix and is out of scope here. The
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
  critical/high alert can now merge; the post-merge gate pages about 9 to 11 minutes
  after the push (measured on `origin/main` b77bee3707: `Analyze
  (javascript-typescript)` ran 21:47:17Z to 21:56:16Z and 21:57:57Z, plus
  ingestion), and the production deploy follows the push by a comparable window, so
  a critical finding can reach prod before the page. That is an accepted residual,
  not a hidden one. Brand-survival threshold is `aggregate pattern`, not
  `single-user incident`: the exposure needs a critical/high finding that the
  pre-merge scan reports but nothing now blocks, the gate pages within about ten
  minutes, and revert is a single diff. The daily `codeql-to-issues.yml` cron
  stays as the backstop (up to 24 hours if the gate never fires).
- **Insider dismissal is not covered.** The gate reads only open alerts, so an actor
  who dismisses a critical/high alert is not detected (the same trust that can
  `--admin` merge). A dismissal-evasion check was designed and removed as
  unreachable beyond that trust.
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
  their next plugin sync. The `pre-merge-rebase.sh` hook now skips its origin/main
  merge-and-push for an already-queued PR; for a PR that is not yet queued on a
  queue-enabled repo it still syncs (a push before the enqueue is a new head and a
  full CI cycle, the per-PR tax the queue exists to remove; measured in canary 9),
  and a failed queue read falls back to that sync.
- **Runner capacity.** A queue costs three full runs per merged PR (`pull_request`,
  `merge_group`, `push`). 60 concurrent hosted jobs is an entitlement, not a
  guarantee; `max_entries_to_build` stays 2 until measured.
- **Ship's post-merge wait grows.** `soleur:ship`'s all-workflows-on-the-merge-sha check now also waits for the
  alert-gate run (about 10 to 12 minutes measured, 25-minute cap), and a red gate run is the intended page, not a deploy failure. No workflow
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
- The Guard 2 and `T-rsc` test expectations in `tests/scripts/test-audit-ruleset-bypass.sh`.

Adding a required check and dropping the queue block are both `0 destroy`; include
`[ack-destroy]` anyway (harmless). If the queue is stalled, merge the rollback with
`gh pr merge --admin` (admin bypass is retained; `plugins/soleur/scripts/admin-merge-ready.sh`
is the readiness gate). If both the queue and the admin bypass fail, PUT the queue-less payload to the
EXISTING ruleset id: build the payload with the DR script's jq (skeleton plus the
canonical bypass actors and required checks), drop the `merge_queue` rule from its
`.rules`, and run `gh api -X PUT repos/jikig-ai/soleur/rulesets/14145388 --input
<payload>`. Do not delete the live ruleset first: that leaves `main` with no
required checks until a POST lands and changes the ruleset id and Terraform state.
The script has no code for this path. The 2026-06-30 kill-switch ran in about four minutes. After a rollback,
reopen #9454 and #4856 and add the observed cause to the PIR directory.

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
   behind-but-queued PR (the plan does not assume it; the tooling is correct either
   way), the observed candidate shape (number of parents, and whether the PR head is
   one) and which check-run names and apps land on the candidate (the CLA verify
   relies on neither parent shape nor extra names, so a surprise here is a finding).
4. Canary bot PR (next `weakness-miner.yml` PR): flows through without stalling. If a
   `GITHUB_TOKEN`-armed bot PR sits pending, the queue stays on for human PRs only if
   bot PRs fall back to the admin-merge path and a follow-up to arm bot PRs with an
   App token is filed in the same session.
5. `merge_group` CI wall-clock and runner start spread. If the slowest required check
   on a real candidate exceeds 30 minutes, raise `check_response_timeout_minutes` in
   the same Terraform root (one line); keep `max_entries_to_build` at 2 until
   contention is measured.
6. The first `codeql-main-alert-gate.yml` push run is green and its push-to-verdict
   time is recorded against the measured 9 to 11 minutes for the Analyze check-runs
   (proves the trigger fires for a queue-made push); record whether the deploy
   finishes before the gate does.
7. PRs armed before the apply (`gh pr list --state open --json number,autoMergeRequest`)
   each show a `mergeQueueEntry` within minutes or merge.
8. Inspect the queue-built squash commit: record whether the message came from the
   commits or from the PR title and body, and what happens when
   `check_response_timeout_minutes` is exceeded.
9. Confirm `pre-merge-rebase.sh` is a no-op for an enqueue of an up-to-date branch
   and skips the sync for an already-queued PR, and record the head-change and CI
   cost of its sync for a not-yet-queued behind branch.

GitHub's documentation does not settle items 1, 3, 8 and the squash-message source;
each is recorded as a measurement with a defined fallback, not as an assumption.

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
