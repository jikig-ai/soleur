# Learning: a green push run is not Guard 1 evidence, and a config probe's regex must meet the shapes the real file can take

## Problem

Resuming the sole-copy LUKS epic (#9927), I reported "main CI is green, including the Guard 1 leg" from the last four `ci.yml` runs on main. Those were push runs, which skip the sharded `test-scripts` legs by design; only merge-queue and dispatch runs exercise Guard 1, and #12213 (`ci/main-broken`) was open. The CTO corrected it when asked to rule on the owner decisions.

Separately, the notify-only revisit probe (`scripts/followthroughs/arm-token-revisit-12229.sh`) passed its first suite and a six-mutant battery while five realistic reformattings of the real workflow line (inline, quoted, tab-separated, bash array, `-target` and its name on continued lines) exited 2 "targets gone" with the token still in config.

## Solution

- State a CI claim only with the run kind and the leg it covers. For Guard 1, read merge-queue or dispatch runs on a SHA, never the push-run list.
- Give a config probe a name boundary written as a denylist (`[^[:alnum:]_-]|$`), drop comment lines before joining shell continuations (a comment line ending in a backslash otherwise swallows the next code line), and run the probe once against the real tree in the suite.
- A suite for a probe needs: a decoy that must NOT match (`..._v2`), one fixture per realistic spelling, a control that proves `expect()` can reject on exit code AND on wording, a control that proves the mutant grader grades an unmutated copy as surviving, and exact assertion/case/mutant floors.

## Key Insight

A "green" read answers a question about the set it was handed. A probe that exits 2 when it cannot see the thing is a silent failure that reads as "done", so its fixtures must come from the real file, and its safe direction (notify) must be the one every ambiguity falls to.

## Session Errors

1. **Overstated CI status to the owner** (push-run greens read as Guard 1 evidence). Recovery: CTO consult named it; corrected in the same turn. **Prevention:** name run kind and leg with every CI claim (existing rule in the review skill: the check-set answers about the set you handed it).
2. **Backticked command inside a double-quoted `echo` executed** (`git grep` ran during a test). Recovery: removed the backticks; `grep -c '`'` is now 0 in the probe. **Prevention:** no backticks in any double-quoted string a script emits; check with `grep -c '`' <script>` after editing.
3. **Scripted multi-edit failed on quote-splice patterns and half-applied.** Recovery: re-read the file, edited by line number, verified with counts. **Prevention:** assert each anchor with `count == 1` and print the changed line back (already in the work skill).
4. **Mutation did not land** (two boundary mutants reported "0 sites"). Recovery: printed the exact line, mutated with the exact bytes. **Prevention:** assert the mutated construct changed (work skill: a mutation that does not land reports the baseline).
5. **`rc=$?` after a pipe read `cut`'s status.** Recovery: re-ran without the pipe. **Prevention:** capture `cmd; rc=$?` with nothing between.
6. **Local affected-test gate queued behind sibling sessions (position 3 of a 2-hour queue).** Recovery: relied on CI's required `test` and ran the diff's own suites. **Prevention:** a contended-or-no-edge fallback in the workflow, tracked separately so the owner stops being asked.

## Tags
category: workflow
module: sole-copy-luks-epic, followthroughs, review
