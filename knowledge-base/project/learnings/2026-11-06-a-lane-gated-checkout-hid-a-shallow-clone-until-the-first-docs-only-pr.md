# Learning: a checkout gated on a lane output hid its shallow-clone defect until the first PR on that lane

## Problem

PR #12245 (docs only) went red: the `oracle-index-check` leg of ci.yml failed rows f, k, k2, k3 and k3b of
`scripts/test-all-affected.test.sh`, each printing `MODE=full (degraded: undecidable-diff)`. The suite passed locally,
passed on every other recent PR, and passed twice more when I re-ran it. The cause was not in the diff.

The oracle-only lane (#12166) checks out with `actions/checkout`'s default depth 1, so `origin/main` is not a ref. The
real `git diff --name-only origin/main...HEAD` inside `scripts/test-all.sh` fails, the detection flag stays 0 and the
runner degrades. The sandboxed rows inject only the diff NAMES (`SANDBOX_DIFF_NAMES`), not the detection flag, so they
inherit the failure. The checkout step is gated on `oracle_only == 'true'`, so on every other PR it is skipped and the
job is a no-op: the defect could not show until the first oracle-only PR ran the manifest for real.

## Solution

`fetch-depth: 0` on that checkout (PR #12262), plus a pin row asserting one checkout, depth 0, gated on `oracle_only`,
and first in the job. Reproduced first in a `git clone --depth 1` of the branch: the same five rows failed, and the
same tree passed in a full clone, which is what separated "the diff" from "the checkout".

## Key Insight

A step gated on a lane output has a population of one until a PR lands in that lane, so "green on recent PRs" is
evidence about the OTHER lane. Before debugging code, reproduce in an environment shaped like the failing runner (here:
depth 1, no `origin/main`); a local re-run in a full clone answers a different question. The one local failure I saw
under contention was a distraction that cost a diagnosis round.

## Session Errors

1. **Debugged the rows before reproducing the runner shape.** Read `run_arm` and row k, and re-ran the suite locally
   under `CI=1`, for several rounds; a single contention flake read as a lead. **Prevention:** when a suite passes
   locally and fails in CI, first rebuild the runner's checkout (`git clone --depth 1 file://…`, no `origin/main`) and
   run the suite there; reasoning about the code comes second.
2. **Cited the wrong precedent in the new comment.** It said `ci-oracle-lane.sh` "documents the same contract for its
   own checkout"; that script runs in `oracle-selection` and for a different reason (merge-ref parents). Three review
   seats flagged it. **Prevention:** for any "same as X" claim in a comment, open X and read why it holds.
3. **Test label collision.** The new assertion reused `G4 row5`, already taken by a reordered-list assertion.
   **Prevention:** `grep -n 'row5'` the file before naming a row.
4. **The pin covered the depth and not the gate.** Flipping the checkout's `if:` to `== 'false'`, or moving the
   checkout after the manifest step, left the suite green. **Prevention:** for a pin on a workflow step, mutate each
   attribute the property depends on (`if:`, order, depth), not only the one the fix added.
5. **Repo-wide `grep -rln` over the primary checkout and `.worktrees/` hung** and was moved to the background.
   **Prevention:** use `git grep` inside the worktree.

## Tags

category: ci
module: ci-oracle-lane, test-all-affected
