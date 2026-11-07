---
title: A destroy ack that lives in one merge commit needs a written recovery path, and two sentences I added were unmeasured
date: 2026-11-06
category: workflow-issues
tags: [terraform, ack-destroy, concurrency, review, claims, scratch-sandbox]
issue: 12189
---

# Learning: a one-merge destroy ack needs a recovery line, and my added prose was unmeasured

## Problem

PR #12268 retires the egress-gw canary alert pair (Ref #12189). The two bare `-target` lines stay in
`apply-web-platform-infra.yml` for one apply, both addresses sit in the census `INTENDED_DESTROYS`, and the destroy is
authorized by a standalone `[ack-destroy]` line in one commit. Everything was green (suites, ratchets, three scratch
mutants, shellcheck), and an eight-seat panel still found real gaps in what I had *written*:

- Nothing said what happens if the run carrying the ack never applies. The apply workflow keeps one running and one
  pending run per concurrency group; a newer arrival replaces a pending run, a superseded run has no ack and fails the
  destroy guard closed, and because the bare targets stay every later infra-path merge then fails the same way.
- My first fix said a newer run "supersedes" the merge's run. That is true only while the run is pending, and
  `apply-deploy-pipeline-fix.yml` shares the same group (`terraform-apply-web-platform-host`), so "infra-path merge"
  understated who can displace it.
- The ADR cited a probe read at 20:28Z that was never recorded on the tracker; the recorded reading was 21:59Z.

## Solution

- Runbook retirement record: merge when no apply run is in progress or queued; the way out is #12270 (remove the targets
  and entries together) or a standalone ack on the next merge used only with the owner's go-ahead and only after the
  run's destroy list shows exactly the two canary addresses; do not start #12270 until the log shows `2 destroyed`.
- Cite the recorded tracker comment, not a reading that exists only in a session.
- Read the concurrency block of **every** workflow that can apply the root before describing displacement.

## Key Insight

A guard whose authorization is a property of ONE commit is a single point of failure for the pipeline it gates once the
unauthorized state (here: bare targets with pending destroys) persists after that commit. Write the recovery path where
the operator will look, scoped (owner go-ahead plus an address check) so the recovery is not itself a blanket ack.
Separately, every causal or universal sentence a fix adds is a new claim: the panel falsified three of mine with one
`grep` each.

## Session Errors

1. **The affected gate run was killed by SIGTERM (exit 143, `failed-before-budget`) mid-run.** Recovery: read the rc as
   unresolved, re-ran the one real red (`git-data-replication` F21) in isolation (68/68), and ran the diff-relevant
   suites directly. **Prevention:** none beyond the existing rule that a reaped run is not a verdict.
2. **Scratch mutation sandboxes built with `git archive` were not git repos**, so suites that derive their corpus from
   `git ls-files` failed (ceiling parsed 0 blocks, census `FAIL SETUP`). Recovery: rebuilt as `git clone --shared`.
   **Prevention:** already documented in the review skill (a subtree sandbox reddens the control); clone, do not archive.
3. **A planner's "skipped" row failed the technical-ruling gate** (class `technical` requires a CTO ruling).
   Recovery: reclassified `taste`. **Prevention:** a planner skip is a process note, not a technical ruling.
4. **My runbook wording said a newer run "supersedes" the merge's run** (pending-only; shared concurrency group).
   Recovery: rewrote after the security seat's check. **Prevention:** read the concurrency block of every workflow
   that can apply the root before describing displacement.
5. **I cited an unrecorded probe read in the ADR and a "0 destroyed" plan sentence true only for the latest main
   apply.** Recovery: cited the recorded 21:59Z comment; the plan sentence is left as a P3. **Prevention:** cite a
   tracker comment or run log for every measured figure a durable document carries.
6. **Harness frictions:** a foreground `sleep` was blocked, a backgrounded `mkdir && (...)` raced the next command,
   and `rm -rf $S/$m` was refused by the safety check. **Prevention:** poll with an until-loop, background whole
   commands only after their setup, and use literal absolute paths or `${VAR:?}` for removals.

## Tags

category: workflow-issues
module: terraform apply pipeline, review
