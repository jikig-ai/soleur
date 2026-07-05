---
title: "Serialize the same physical op across DIFFERENT GitHub Actions workflows with a shared job-level concurrency group"
date: 2026-07-05
category: best-practices
tags: [github-actions, concurrency, ci, deploy, serialization, drift-guard]
issues: ["#6060"]
pr: "#6066"
---

# Cross-pipeline serialization via a shared job-level `concurrency` group

## Problem

The same physical prod mutation — a **web-1 container swap** (`docker stop` → `docker
run`) — was triggered from FOUR different GitHub Actions jobs across THREE workflows
(release `deploy`, `web_2_recreate`, `warm_standby`, pipeline-fix `apply`; all POST
`command: deploy web-platform` to `/hooks/deploy`). Three of them shared a
workflow-level `terraform-apply-web-platform-host` group, but the frequent
push-release `deploy` was in a disjoint group. So a release landing inside an operator
dispatch's in-flight window issued its own concurrent swap on the sole live origin —
verified harm: a `lock_contention` RED release (the release's Verify step has no
`exit_code=1` case → falls to `*)` → exit 1) + a possible web-1 tag-downgrade, plus a
transient single-probe 521.

## Solution

Give all N triggering jobs an **identical job-level** `concurrency` block with a stable
literal name:

```yaml
concurrency:
  group: web-1-swap
  cancel-in-progress: false
```

GitHub's scheduler then guarantees at most one of them runs at a time — an **atomic
mutex** (no check-then-act TOCTOU), **bidirectional** (order-independent), and
**queue-not-fail** (a superseded push release queues then deploys, or is
latest-wins-cancelled by a newer SHA — never hard-failed/stranded ahead of prod). Zero
custom polling script, zero new API permission.

## Key Insights

1. **Job-level and workflow-level `concurrency` COEXIST** (independent scopes, per the
   GitHub workflow-syntax reference). Adding a job-level `web-1-swap` group to a job that
   already sits in a workflow-level `terraform-apply-web-platform-host` group does NOT
   drop it from the workflow-level serializer — both apply. This is what lets you add a
   cross-pipeline mutex without disturbing an existing state-lock serializer.
2. **Load-bearing lock-hold-duration invariant.** The mutex only serializes the *actual*
   op because every member POSTs then **polls to a terminal state** — the GHA job (and
   thus the group) is held across the multi-minute detached on-host work, not just the
   202 POST. A future edit making any member fire-and-forget would release the mutex in
   seconds while the op ran on, silently restoring the overlap while a drift-guard stays
   green. Record the invariant in the ADR + a Sharp Edge.
3. **`cancel-in-progress: false` is load-bearing, not cosmetic.** `true` could kill an
   in-progress swap mid-`docker run` (widening the outage window) or a mid-apply
   `terraform apply` (state-corruption risk).
4. **A replicated group literal across N jobs needs an allow-list drift-guard** — assert
   each NAMED member carries the group + a total-count `== N` (allow-list length, NOT
   `head -1`, NOT `>= N`), so a dropped member (< N) OR an accidentally-enrolled/renamed
   job (≠ N) both fail loud. A deliberate future member is then a visible allow-list edit.
   (Extends the `head -1` un-guard lesson,
   `2026-07-05-extracted-specialized-shared-script-not-clean-swap-and-parity-blind-spots.md`.)
5. **Deadlock check for a shared inner mutex:** verify the group has ≤2 live contenders
   and at least one always makes progress (holds only the inner lock, needs nothing
   else). Here sites 2/3/4 are mutually serialized by the outer workflow-level group, and
   the release holds only `web-1-swap` → no hold-and-wait cycle.
6. **Operator-op priority-inversion (accepted):** GitHub keeps at most ONE pending run
   per group and the newest arrival wins the pending slot — so a routine push can cancel
   a *pending* operator recovery dispatch queued behind an in-flight release. Fails safe;
   engage the merge-freeze before an operator recovery dispatch and re-dispatch if
   preempted.

## Session Errors

1. **`git checkout <file>` during a RED-proof mutation wiped a not-yet-committed edit.**
   The plan's Phase 4.2 RED-proof ("divert one member's group literal, confirm the guard
   FAILs, revert") was run against a workflow whose legitimate concurrency-block edit was
   NOT yet committed. `git checkout <file>` restores to HEAD → it wiped BOTH the
   deliberate mutation AND the real edit; the guard then showed 3 failures after the
   "revert." **Recovery:** re-applied the edit, re-ran GREEN (13/13). **Prevention:**
   commit the GREEN edits BEFORE running any `git checkout`-based mutation-revert, OR
   mutate a copy in a throwaway dir (`cp` to `/tmp`, point the test at it) so the undo
   never touches the working tree. Same root cause as the `review/SKILL.md` Sharp Edge
   "Mutation-verify restores via `git checkout -- <file>` silently wipe UNCOMMITTED
   sibling edits" — but it fired in the **/work Phase 4.2** RED-proof, not a /review pass.
2. **A batch of 5 sibling infra tests hit the 2-min Bash timeout** (ci-deploy.test.sh is
   a ~heavy 106-assertion suite). One-off; resolved by running the heavy suite separately
   with a 300s timeout. **Prevention:** run known-heavy `.test.sh` suites individually,
   not in a serial batch under the default 120s tool timeout.
