---
date: 2026-07-17
issue: 6589
pr: 6582
tags: [ci, workflow, gate-design, duplication, review, self-review]
category: workflow-patterns
---

# A copy-adapted gate drifted in the exact half I didn't parity-pin — and shipped permanently red

## What happened

#6589 adds a PR-time destroy gate to `apply-sentry-infra.yml`. The `plan_pr` job
was written by copy-adapting the existing `apply` job's destroy-guard block. The
adaptation carried `resource_deletes` / `resource_creates` / `nested_deletes`,
and **dropped one line** — `destroy_count=$((resource_deletes + nested_deletes))`
— then went on to read `$destroy_count`.

Under `set -uo pipefail`, reading an unset variable aborts the step. So on every
sentry-touching PR the gate did this:

```
Plan: 0 to add, 0 to change, 2 to destroy.
line 53: destroy_count: unbound variable
##[error]Process completed with exit code 1
sentry-destroy gate FAILED closed (detect-changes=success, plan_pr=failure)
```

The plan correctly ran and found the destroys — and then the gate crashed before
evaluating them. **The gate was permanently red, by accident.** Its entire green
path — the ack detection, the squash-setting assertion, the destroyed-address
listing — had never executed once.

The bitter part: this PR's whole thesis is "don't ship a permanently-red gate"
(it rejects the plan's permanently-red design on the grounds that red-on-every-
correct-PR trains ack-blindness). I shipped exactly that, through a dropped line.

## Why my own guards didn't catch it

I *did* build a drift guard for this file — `test-destroy-guard-regex-parity.sh`
pins the `[ack-destroy]` regex across 7 sites, and I added an 8th, **because
"drift between a predictor and the thing it predicts is invisible to review."**

But I pinned the **regex**. The two jobs also share **arithmetic**, and that had
no pin. The drift landed in the unpinned half. I guarded the seam I had already
thought about and left the adjacent seam — same two files, same copy-adaptation,
same failure mode — open.

The lesson isn't "add a parity test for the arithmetic too." It is:

**When you copy-adapt a block, the whole block is a drift surface, not just the
part you already decided was risky. The fix is one copy, not two pinned copies.**

I extracted the counts + validation + the sum into `scripts/sentry-destroy-counts.sh`
that both jobs call. A parity test over two copies detects drift; one copy makes
it **unrepresentable**. Prefer removing the second copy over pinning it.

## Why it survived my own review until an agent ran it

Three things hid it from me:

1. **Local tests pass.** Every unit test of the extracted scripts
   (`sentry-squash-ack-detect.sh`, `sentry-destroy-gate-verdict.sh`) was green,
   because the ~50 lines of inline glue in `plan_pr` that *sequences* them had no
   test. I tested the parts and not the composition.
2. **The green path never ran, so nothing observed its absence.** A gate that is
   red for an unrelated reason looks, from the outside, like a gate doing its
   job.
3. **I read the code as correct because I wrote it.** `architecture-strategist`
   and `security-sentinel` both converged on line 324 independently — the
   security agent's last words before it died on an API error were "Found
   something already at line 324." A fresh reader running the thing beat three of
   my own passes.

## The generalisable rule

- **Copy-adaptation drift is not confined to the risky-looking token.** If you're
  pinning one shared literal across copies because copies drift, the copies will
  drift in the *other* shared things too. De-duplicate; don't multi-pin.
- **Test the composition, not just the extracted parts.** Extracting verdict
  logic into a tested script and leaving the glue that calls it untested moves
  the bug, it doesn't kill it. The bug lives in the seam.
- **A gate's green path must be exercised before you trust it.** "It fails closed"
  is not "it works" — a gate that fails closed *for the wrong reason* is a gate
  that has never demonstrated it can pass. Run a destroying-plan fixture through
  the whole composed gate, or run it live, before marking ready.
- **Run your own guard, don't read it.** I read line 324 three times and saw
  correct code. The bug was one variable that isn't there. `grep`, `set -u`, and
  a real execution find what re-reading cannot.

## Operational aside: a CONFLICTING PR silently stops `pull_request` workflows

While validating the fix I found the sentry gate had stopped appearing in CI
entirely — three pushes, no new run. The cause was not the workflow: the PR had
drifted 7 commits behind main into a `mergeStateStatus: DIRTY` /
`mergeable: CONFLICTING` state, and **GitHub cannot build the merge commit a
`pull_request` workflow runs on, so those workflows simply don't fire.** The
symptom (a workflow that "won't trigger") looks like a workflow bug; the cause is
mergeability. When a `pull_request`-triggered check goes missing, check
`gh pr view --json mergeable,mergeStateStatus` before touching the workflow —
merge main in, and the runs return. (This is also why the branch's newest
head-SHA had zero check-runs while an older SHA still showed its failed run.)

## Companion

The sibling learning from the same session —
`2026-07-17-a-detector-placed-before-the-cure-blocks-it.md` — is the same shape
in the Class D detector: a fail-closed gate that fires for a reason that isn't
the failure it names. Both are "the gate is red/green for the wrong reason", and
both were caught by running the thing against real state rather than reading it.
