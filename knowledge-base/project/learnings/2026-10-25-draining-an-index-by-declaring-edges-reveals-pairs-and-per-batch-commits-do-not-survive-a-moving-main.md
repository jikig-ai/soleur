# Learning: draining the affected-index baseline by declaring edges (S4 PR4)

## Problem

PR4 (#10860, PR #10945) had to shrink the shrink-only baseline `scripts/ci-pr-affected-audit.baseline.tsv` by declaring an exact-file edge in `scripts/lib/test-affected-paths.sh` for every code-extension (suite, path) pair where the suite really reads or executes the path. Three things made it harder than counting pairs:

1. Declaring an edge makes the audit READ the declared file, and every path that file names becomes a new pair for that suite. The first report of one chain revealed 135 new pairs (cap 60), another 358.
2. Main moved four times during the work and sibling PRs edited the same index and baseline, so the three per-batch commits all conflicted at the last rebase.
3. The first full affected gate (4.7 h) failed two suites that the edges themselves caused.

## Solution

- Classify by reading the deciding line (class a execute/source, b open content, c existence, d data row with quoted loop), not by grepping for the name. 239 pairs declared, 547 mentions left for PR5, 160 real reads with no edge yet.
- Apply the CTO stop line: when a declaration reveals more than the cap, hold the edge back (its pairs stay baselined) instead of absorbing the revealed pairs. 117 edges held back, tracked in #10959.
- Regenerate the baseline only with `ratchet --print-baseline` from a snapshot, never by hand, starting from `git checkout origin/main -- <baseline>` after each rebase.
- When per-batch commits conflict, rebuild the same edges from the saved edge lists on current main and commit once, and record the deviation in the decision log (row 16).
- Keep the decision table (`pairs-decisions.tsv`) as the evidence: one row per pair, deciding `file:line`, and a second section for held-back and whole-tree reads.

## Key Insight

A drain is not monotone: the oracle the baseline is measured against changes when you declare an edge, so the work needs a fixpoint loop and a stop line decided up front. And a branch that edits the same shared file as its siblings should keep its edge lists as data, not as commits, because the commits will not survive the rebase but the data will.

## Session Errors

1. **PR-body Write failed ("modified since read")** — Recovery: re-read, then re-wrote the whole body. Prevention: always Read a scratch file immediately before overwriting it, or write the body to a fresh filename.
2. **Classification agents ended without writing output (group 4 finished by hand)** — Recovery: classified 12 pairs myself. Prevention: brief reading agents to append rows incrementally and to verify the output file exists before finishing.
3. **Hook blocked `$VAR` paths in `git commit` and `gh issue create --body-file`** — Recovery: literal absolute paths. Prevention: write literal absolute paths in commands from the start.
4. **Per-batch commits all conflicted on the last rebase** — Recovery: rebuilt the edges from the saved edge lists and committed once (decision-log row 16, ruling 15i not met as written). Prevention: keep edge lists as data files and treat batch commits as disposable when sibling PRs edit the same index.
5. **Two suites failed in the first full gate because of this PR's edges** (`test-affected-kb-consumers`, `inngest-probe-row`) — Recovery: fixed, and held back the inngest edge. Prevention: run the two repo-global consumers of the index (`scripts/test-affected-kb-consumers.test.sh`, `scripts/lib/inngest-probe-row.test.sh`) after every edge batch, not only the ratchet.
6. **The review verifier found three wrong cites and a false extension list in my own new comments** — Recovery: fixed in `a9b6377420`. Prevention: cite by content anchor and re-derive any list of extensions from the tree before writing it into a comment.
7. **The worktree directory disappeared mid-session** — Recovery: pushed branch was intact; `git worktree add` rebuilt it at `d96be3c8d7`. Prevention: push before any long detached wait so nothing lives only in the worktree.
8. **The gate summary counted 8 non-passing suites but printed 4 `[FAIL]` lines** — Recovery: none; could not identify the other 4 from the log, so the gate was reported as not clean. Prevention: not isolated (suite names with spaces defeat simple log greps); read `suite-timings.tsv` against result lines when it recurs.
9. **The audit reported 1651 pairs where the ratchet reported 1642** — Cause: main already carries `scripts/ci-pr-affected-audit.accept.tsv` with 9 rows from sibling PRs, which the audit run without that file does not apply. Prevention: always run the audit with main's accept file when comparing to the ratchet.
10. **Monitors expired every 30 minutes with no event** — Recovery: re-armed. Prevention: expect the 30-minute expiry on long gates and re-arm, or poll the rc file once per wake.
11. **`gh issue create` was refused without `meta/machinery` label or User-Impact lines** — Recovery: added the label. Prevention: pass the label on first call.

## Tags
category: workflow-issues
module: ci-pr-affected
