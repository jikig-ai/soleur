---
title: "Ad-hoc verification evidence is as perishable as uncommitted code"
category: engineering
module: one-shot pipeline / review / test harnesses
date: 2026-07-15
related_issues: [6485]
related_pr: 6485
related_learnings:
  - knowledge-base/project/learnings/2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md
  - knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md
  - knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md
  - knowledge-base/project/learnings/2026-06-02-resumed-uncommitted-work-may-be-partial-against-the-plan.md
tags: [mutation-testing, non-vacuity, crash-recovery, evidence, guards, commit-discipline]
description: "A guard's value claim is only worth its evidence. Evidence held in session context — a mutation matrix, a RED run, a spot-check — dies with the session exactly like uncommitted code, and leaves behind a comment asserting a property nobody can re-check."
type: best-practices
---

# Ad-hoc verification evidence is as perishable as uncommitted code

## Problem

Two losses in one session, both the same shape.

**1. A concurrent agent wiped an uncommitted fix.** While a mutating agent was live, a fix sat uncommitted in the working tree; the other agent ran `git checkout --` and it was gone. Known class — see [concurrent-cleanup-merged-wipes-active-worktree](2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md).

**2. A laptop crash destroyed a mutation matrix — and only the evidence, not the code.** The `/one-shot` review step was mid-VERIFY on `check_sequence_ddl_is_allowlist_bound`, proving the guard goes RED under mutations labelled M3 and M6. The subagent's code changes were committed 66s before the crash, so nothing on disk was lost. But the matrix itself — which mutations, why those, what they proved — existed only in the dead parent's context. Nothing on disk recorded it.

The second loss is the interesting one, because it *looks* like nothing was lost. The tree was clean, the tests were green, the guard was in place. What was actually missing was the answer to "does this guard fail on the catastrophe it claims to catch?" — and no artifact could answer it.

On resume, `M3` and `M6` were recoverable only by luck: the guard has exactly two detection arms (`relkind='S'`, `pg_sequences`) and two allowlist escapes (`relname=`, `pg_get_serial_sequence`), so "the two unbound-sweep catastrophes, one per arm" was re-derivable from the guard's own source. Had the matrix been less symmetric, it would have been gone.

The codebase already had three comments claiming `mutation-proven 2026-07-15` (`inngest-rls.test.sh` ~116, ~142, ~182) with no committed harness behind them. Same failure, already shipped: a durable claim backed by evidence that evaporated.

## Solution

Commit the harness, gate it in CI ([`inngest-rls-mutation.test.sh`](../../../apps/web-platform/infra/inngest-rls/inngest-rls-mutation.test.sh), wired into `infra-validation.yml`):

```
BASE  guard=GREEN  unmutated 0002 (bound by tc.relname = t)
M3    guard=RED    relkind='S' loop, allowlist binding REMOVED
M6    guard=RED    pg_sequences loop, allowlist binding REMOVED
M6b   guard=GREEN  pg_sequences loop, binding INTACT   (false-positive check)
M3b   guard=GREEN  binding via pg_get_serial_sequence  (alt escape hatch)
```

Three properties made it worth committing rather than re-running ad hoc:

- **Both halves are load-bearing.** M3/M6 prove the guard *can* fail; M3b/M6b prove it doesn't fire on everything. RED-only evidence cannot distinguish a real guard from `return 1`. Verified by neutering the guard to always-GREEN: the harness fails on exactly M3/M6 and exits 1 — it detects the vacuity it claims to disprove.
- **It cannot damage the thing it tests.** Mutations apply to a sandbox mirroring the four levels `inngest-rls.test.sh` resolves `REPO_ROOT` through (`$DIR/../../../..`), never to the tracked SQL. The scratchpad version mutated `0002` in place and restored via `git checkout --` — fine for one operator-supervised run, wrong to commit, and the same verb that wiped the fix in loss #1.
- **The gate re-runs when the guard changes.** `apps/*/infra/**` already covers both the harness and the guard it attests, so editing the guard re-triggers the attestation. A gate that doesn't fire on edits to its own subject is decoration.

## Key Insight

**A guard's value claim is only worth its evidence, and evidence in context is uncommitted.** "Commit fixes immediately when a mutating agent is live" generalises past code: the mutation matrix, the RED run, the spot-check that justified a comment — all of it is uncommitted work until it's an artifact, and all of it dies to the same crash, `git checkout --`, or compaction.

The tell is a comment asserting a property that nothing re-checks: `mutation-proven`, `verified non-vacuous`, `confirmed RED`. Each is a claim whose evidence was thrown away at the moment it was written — prose where a test should be. Worse than absent, because it reads as protection and discourages the next reader from checking.

Ask of any guard-shaped comment: *if this were false, what would fail?* If the answer is "nothing", the sentence is decoration. Prefer a committed harness that fails, and delete the adjective.

## Prevention

- When a mutation/RED verification justifies a guard, **commit it as a harness in the same PR** — do not leave it in scratchpad, and do not summarise it in a comment. This applies with force in `/one-shot`, where the parent's context is the only thing holding the result between the review step and the report.
- Any new `mutation-proven` / `verified` claim needs a runnable artifact in the same commit, or it should not be written.
- CI-run harnesses must mutate a **sandbox copy**, never the tracked file. In-place-mutate-and-`git checkout --`-restore is unsafe to commit: an interrupted run leaves the artifact mutated for every later step in the job.
- Check the path filter actually covers both the harness **and** its subject.

## Session Errors

- **Laptop crash (18:26:44Z) killed `/one-shot` Step 4 mid-VERIFY.** Recovery: the apply-findings subagent had committed 66s earlier, so code survived; re-ran both suites at HEAD (46/0, 48/0) and rebuilt the matrix. **Prevention:** this learning — the harness is now committed and CI-gated, so the same crash costs nothing.
- **M3/M6 labels unrecoverable from disk.** Recovery: re-derived from the guard's two detection arms. **Prevention:** as above.
- **A concurrent agent wiped an uncommitted fix via `git checkout --`.** Recovery: re-applied and committed immediately. **Prevention:** commit before spawning or running anything that mutates the tree.
- **`session-state.md` recorded only the Plan phase**; implement and review were never written back, so the resume brief had to carry state the artifact should have held. **Prevention:** write back each phase as it closes, not at the end.
- **8 review commits sat unpushed at resume**, so PR #6485's green CI attested a stale SHA (`f2e361405`) while reviewers would have read stale state (`rf-before-spawning-review-agents-push-the`). **Prevention:** push before any review-adjacent step.
- **`gh issue create` denied for a missing `--milestone`** while filing #6501. Recovery: listed milestones, refiled with `Post-MVP / Later`. **Prevention:** already hook-enforced; the hook worked as designed. One-off.
- **A relative `cd` in a Bash call failed** (`cd: apps/web-platform/infra/inngest-rls: No such file or directory`) after the shell CWD reset between calls. Recovery: used worktree-absolute paths. **Prevention:** already covered by existing path rules. One-off.
