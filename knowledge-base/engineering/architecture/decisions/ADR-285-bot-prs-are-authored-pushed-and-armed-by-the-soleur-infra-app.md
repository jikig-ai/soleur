---
title: The weekly weakness-digest PR is authored, pushed and armed by the soleur-infra App, not by the workflow token
status: adopting
date: 2026-10-11
supersedes: none
issue: 9454
related: [9454, 9262, 9321]
related_adrs: [ADR-139, ADR-232, ADR-241, ADR-270, ADR-276]
tags: [ci, merge-queue, github-app, bot-pr, credentials]
brand_survival_threshold: none
---

# ADR-285: The weekly weakness-digest PR is authored, pushed and armed by the soleur-infra App, not by the workflow token

## Status

**Adopting — 2026-10-11 (#9454, item 4).** It becomes `accepted` when the first real run that produces a PR has been
measured (post-merge criteria in the plan, recorded as facts on #9454). Until then the claim below is an inference from
two controls and one confounded observation, not a proven rule. The ordinal is provisional: 285 was free on `origin/main`
and on every remote ref on 2026-10-11; `soleur:ship` re-derives it.

This record does not touch ADR-270 (the merge-queue adoption, still `adopting`) and is not canary evidence for it.

## Context

`weakness-miner.yml` opened its digest PR through `.github/actions/bot-pr-with-synthetic-checks` with
`gh-token: ${{ github.token }}`, so the PR author, the branch pusher and the actor that armed auto-merge were all
`github-actions[bot]`. Before the merge queue that only meant "no real CI; synthetic check-runs cover the rulesets", and
digest PRs merged about a minute after creation.

With the queue (ADR-270), PR 10013 on 2026-10-11 showed a different outcome:

- its 7 `pull_request` runs (head `a55ddac168`, a bot commit) were created held (`action_required`, 0 jobs) and started only
  after they were approved;
- its first queue entry, armed by `github-actions[bot]`, received **zero** `merge_group` runs in about 61 minutes while
  other entries in the same window received 7 each, and the queue removed it (`removed_from_merge_queue`, 13:12:19Z);
- its second entry was armed by a human at 17:51Z and queued at 18:11Z, on a **different head**: a human pushed commit
  `3bee7c4974` (a review-trailer commit) at 17:50Z, whose 7 `pull_request` runs were fresh and never held, and the entry
  received 7 `merge_group` runs and merged.

Controls: PR 10027 (`soleur-infra` App: branch pushed, PR created, auto-merge armed and queue entry all as the App) and
PR 9982 (`soleur-ai` App) both got real `pull_request` runs and real `merge_group` runs.

**What the data does not separate.** The second entry changed four things at once: the enqueuer, the approved state of
the PR's runs, the head commit and the pusher, while the author stayed `github-actions[bot]`. So "the author is the
cause" is not established; "the enqueuer, the head's pusher, the run approval state and the author move together" is.
A hypothesis worth recording, unmeasured: GitHub does not start workflows for events caused by the workflow token, which
would make the actor of the push and of the enqueue the load-bearing variables. The post-merge verification therefore
reads `triggering_actor` on the new runs, and treats a human-pushed head as not evaluable. The repo has no setting that distinguishes bot actors:
`fork-pr-contributor-approval` is `first_time_contributors` and the private-repo fork setting is refused (HTTP 422) on a
public repository, so no setting is a verified lever.

## Decision

1. `weakness-miner.yml` authors, pushes and arms its digest PR as the `soleur-infra` App: the same author, pusher,
   committer and enqueuer as Control A (PR 10027). Residual differences are not removed and are named so a failed first
   run is read against them: the branch prefix (`ci/`, not `soleur/inngest-pin-`), the content class (one docs file),
   the trigger (a `schedule` run here, `workflow_dispatch` only for the pin bump), and the synthetic check-runs the composite still posts beside the real runs. The App token is minted in the job that opens the PR, through
   `.github/actions/mint-infra-app-token` (narrow source `soleur-infra-app`, installation `166065653`, scoped to
   `contents:write` and `pull_requests:write` on `soleur`), and reaches the composite as the new `pr-token` input.
2. The workflow token keeps exactly one job: posting the synthetic check-runs, because the rulesets match check-runs from
   integration 15368 (ADR-139). The composite's earned-green blocks, its single-path allowlist and its off-main refusal
   are unchanged.
3. The credential job runs no content-producing step. The workflow is three jobs: `mine` (no environment, no secret; runs
   the miner and uploads one file), `open-pr` (`infra-privileged`, main only; fresh checkout, the artifact, the mint, the
   composite) and `notify` (the failure email). A miner step sharing a job with the credential could poison
   `$GITHUB_ENV`, `$GITHUB_PATH`, git config or the workspace scripts the mint later executes, and
   `persist-credentials: false` does not close that.
4. The composite is fail-closed on identity: it refuses an empty, non-bearer or workflow-token `pr-token` before any
   no-change exit, holds both tokens in unexported variables, has no step-level `GH_TOKEN`, and routes every PR write
   through `gh_app` and the check-run posts through `gh_gate`, so a bare `gh` call fails instead of silently authoring as
   the workflow token. The push carries the App token as a per-command `http.https://github.com/.extraheader`.
5. A static guard in `tests/scripts/test-weakness-miner.sh` evaluates every caller of the composite (derived, floor of
   one) and the composite itself, with a mutation battery. Its regex rules are diagnostics that name which property moved: shell has more
   spellings than any list, and two review rounds each found a fresh bypass. The closure is a sha256 pin of the
   composite's run body, env, shell, inputs and defaults and of the `open-pr` job, so any edit to either must re-pin in
   the same PR, where a reviewer sees it. ADR-241's census row G7f counts four callers.

## Exposure, stated plainly

The minted token is scoped (one repository, two permissions, one hour). The credential behind the mint is not: the
Doppler read token reads the App's private key, and the App's grant includes `administration:write` and `secrets:write`.
Scoping is a property of the mint composite's exact-grant check, not of the credential. This is the exposure the other
composite callers already carry (ADR-241 D11); it is not a new class, but this change adds a third holder of the narrow
read token (the fourth caller of the composite), on a weekly schedule. The minted token is not revoked after the PR is armed;
it expires in an hour, like the pin-bump caller's. The three-job split exists to keep content-producing steps out of that holder.

## Alternatives considered

- **Approve the held runs with the workflow token** (`POST /actions/runs/{id}/approve`). Rejected: it is not known to
  produce `merge_group` runs for a workflow-token entry, a workflow approving its own runs defeats the control, and the
  endpoint is documented for fork-contributor runs.
- **Loosen the fork-PR approval policy.** Rejected: it is keyed on contributor status, not on bots, and loosening it on a
  public repository widens the surface for every outside PR to fix one bot.
- **A personal access token.** Rejected by ADR-232 and `hr-github-app-auth-not-pat`.
- **Keep the push on the checkout credential and only move the PR writes.** Rejected: it differs from Control A in one
  unmeasured variable, and `infra-privileged` is main-only, so there is no pre-merge exercise path; a wrong guess costs a week.
- **Drop the synthetic check-runs now that real CI runs.** Deferred, not decided: it touches the fabricated-green chain
  (ADR-139) and needs its own decision (tracked).

## Consequences

- One real `pull_request` CI run per week on the digest PR. It is a full run, not a short-circuited one: only the e2e job
  skips its heavy steps for a `knowledge-base/**` diff, so budget a few runner-hours a week. The synthetic checks remain and
  are redundant; how the ruleset evaluates a real failure beside a synthetic success is unmeasured. The real `cla.yml` and
  `cla-evidence.yml` runs fire for this PR class for the first time.
- Known gap: nothing watches the digest PR after the workflow run goes green. A real check that fails or hangs leaves the PR
  open and never queued, `merge-queue-stall-check.yml` only sees queue entries, and the next Sunday's PR would then be
  stacked on the same file. Tracked with the other follow-ups in #10068 (stale open digest PR: watch or supersede).
- `scripts/audit-bot-codeql-coverage.sh` filtered `--author app/github-actions` and would have stopped sampling new digest
  PRs; it now samples both `app/github-actions` and the `ci/` branches of `app/soleur-infra`, with a test row.
- Revisit trigger: if a lower-grant App for digest-class PRs is created, this caller moves to it.

## Verification

The static guard and the census run in the required `test` aggregate. The measurement is post-merge and is carried by
#9454 item 4: on the first run that produces a PR, the `app-token` notice
(`gh run view <run-id> --log | grep -F 'app=soleur-infra installation=166065653'`; the granted set also lists
`metadata:read`), the PR author `app/soleur-infra`, zero `action_required` runs, a successful CI run, an
`added_to_merge_queue` event by `soleur-infra[bot]` followed by `merge_group` runs on `gh-readonly-queue/main/pr-<N>-*`, and
the PR merged. Read the entry's `merge_group` runs directly instead of waiting for the stall issue, whose 45-minute threshold
can fire on a healthy slow build. A run that prints "No changes to commit" is not evaluable, and neither is a PR whose head
a human pushed. If the runs are still held although the push, the PR and the auto-merge all ran as the App, this record's
premise is wrong and it is reopened rather than patched. Recovery on a same-day re-run: the composite stops with the delete
command for the leftover branch; otherwise the next scheduled run takes a new date-suffixed branch.
