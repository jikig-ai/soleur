# Learning: a new "for-all-members" drift guard turns main RED when a sibling PR adds a set member — rebase immediately before ship

## Problem

PR #5280 (issue #5279) added a drift-guard assertion to
`apps/web-platform/infra/cron-egress-firewall.test.sh` of the shape **"every
command in the `server.tf` post-apply assertion block MUST carry an
`ASSERT-FAILED: <name>` sentinel"** (a for-all-members invariant over a set).

While the branch was open, two sibling PRs landed on `main` touching the **same**
assertion block:
- **#5281** added a NEW bare assertion (`nft list set … | grep -qE '[,[:space:]](20|4)[.]'` — the GitHub `/meta` api-pool CIDR check).
- **#5285** split `systemctl enable --now cron-egress-firewall.service` into `enable` + `restart` (the Type=oneshot inert-fix).

Neither sibling carried a sentinel (they predate this PR's guard). Git merges
them as non-conflicting **additions** to the array. So at merge time, `main`
would have carried the new bare assertion AND this PR's guard that forbids bare
assertions → **the test goes RED on `main`**, not on the PR branch. Every
local run on the feature branch was green (the branch never saw the sibling
lines), so the failure was invisible until the code-quality review agent
re-derived the diff against fresh `origin/main`.

## Root cause

A for-all-members drift guard couples the test's pass/fail to the **current
membership of the set on `main`**, not just to the branch's diff. The standard
branch-vs-main divergence check (work Phase 0.5 check #6) is only a WARN for
non-AGENTS files, and the set-membership coupling is invisible to a diff that
only looks at the branch's own changes. The egress-firewall assertion block is
a high-churn surface (4 PRs in one week all editing it), which made a
concurrent set-addition near-certain.

## Solution

1. **Rebase onto `origin/main` immediately before ship whenever the PR
   introduces (or tightens) a for-all-members invariant over a code surface
   that other PRs edit.** After rebasing, instrument every member the sibling
   PRs added so the invariant holds on the merged tree.
2. Re-run the guard against the **rebased** tree, not the pre-rebase branch.
3. The review-time catch that saved this: an agent prompted to re-derive the
   diff against fresh `origin/main` ("branch is N commits behind; main's new X
   will land sentinel-less") — keep that check in the review spawn prompt for
   any PR adding an all-members guard.

## Key Insight

A drift guard that asserts a property over **all members of a set** is only as
green as the set's membership on `main` at merge time. A sibling PR adding a
member is not a merge *conflict* — it is a silent post-merge RED. The cheapest
gate is **rebase-before-ship + re-run the guard on the rebased tree**; the
backstop is a review agent that re-derives the diff against fresh `origin/main`.
This is the all-members analogue of the "rebase before applying AGENTS.md plan
edits" rule, generalized from a high-collision *file* to a high-collision
*set within a file*.

Secondary insight (infra diagnosis under no-SSH): when an infra apply fails
**blind** (terraform suppresses inline `remote-exec` stdout) and live-host
diagnosis is not autonomously available, ship the **self-reporting
observability layer first** (`ASSERT-FAILED: <name>` sentinels + a journalctl
tail on the loader-running line). The next apply self-names the fault in the
Actions log with zero SSH — converting a blind multi-PR chase (the #5247
precedent) into a single named-culprit fix — without relaxing any containment
invariant.

## Session Errors

1. **Stale branch base — sibling set-addition would have turned main RED.**
   Recovery: `git rebase origin/main`, resolve the same-block conflict keeping
   #5281/#5285's lines, instrument the new `firewall-restart` / `cidr-set-api-pool`
   lines, re-run the guard (149/0). Prevention: rebase-before-ship for any
   all-members drift guard; keep the review "re-derive diff vs fresh origin/main"
   prompt.
2. **Drift-guard authored with strippable members + no runbook parity.**
   The first cut of the guard let `chmod-scripts`/`daemon-reload` sentinels be
   stripped silently (floor slack + a command-detection regex that missed setup
   lines), and the runbook table could desync from the code names. Recovery:
   widen the no-bare-command regex to every command verb; add a runbook↔code
   name-parity assertion. Prevention: when authoring an all-members guard, make
   the per-member check (not the count floor) the load-bearing gate, and pin any
   companion doc table with a parity assertion.
3. *(forwarded, planning phase)* `iac-plan-write-guard.sh` blocked plan-write
   attempts containing literal `ssh root@<host>` / `systemctl enable --now`.
   Recovery: rephrase diagnostic commands abstractly in plan prose. Prevention:
   reference on-host commands by file:line in plans rather than quoting the
   literal command.
4. *(forwarded)* Non-blocking Dependabot advisory on push — one-off, no action.

## Tags
category: best-practices
module: infra / drift-guards / one-shot-pipeline
