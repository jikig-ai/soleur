# Learning: a corpus ratchet that reads `git ls-files` ran green before my new files were tracked

## Problem

While building a notify-only follow-through probe (`scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh` and its suite, #11207), I ran the repo's whole-corpus ratchets (`fixture-relative-assert`, `fixture-dir-operand-assert`, `guard-vacuity-floor`) before the first commit. All three reported green. After the commit, the review's pattern seat ran the same ratchet and found a P1: three `[[ "$today" > "$BRIDGE" ]]` date comparisons in the new probe were read as redirects, adding three unproven-absolute sites to the baseline.

The first run was a false green. These ratchets enumerate the corpus with `git ls-files`, and a file that is neither staged nor committed is not in that list, so the scan never saw the files I was checking.

## Solution

- Run every corpus-scanning ratchet after `git add` of the new files, never before. For `lint-*` scripts that take explicit file paths this does not matter; for the three above it does.
- Compare dates as epoch integers (`[ "$a_e" -gt "$b_e" ]`), never with `[[ a > b ]]` / `[[ a < b ]]`. A bare `<` or `>` reads as a redirect to the repo's fixture scanners.

## Key Insight

A check that derives its population from the index answers a question about the index. "Green" on an untracked file means "not scanned". Before trusting a ratchet's pass on new files, state what enumerates its corpus and whether your files are in it.

The review itself found a second class worth keeping: a notify-only decision ladder must be total over the states its inputs can reach. Review found five holes in a seven-row ladder that the plan-time review and the author's mutation battery both missed: a done line for the second act without the first, a stuck prerequisite that silenced the deadline warning, text that went stale after the last date, an anchor that accepted a typo as a real time, and a malformed done line reported in only one of three asks. The fixes were to order the deadline row ahead of the prerequisite rows, to treat inconsistent records as "cannot establish" rather than as a quiet state, and to name a malformed anchor in every ask that waits for it.

## Session Errors

- **Ran corpus ratchets before staging the new files (false green).** Recovery: re-ran after `git add`; fixed three redirect-shaped comparisons. **Prevention:** work-skill Common Pitfalls bullet added in this PR.
- **`gh issue create` denied by the milestone/filing-exit hook, taking its heredoc with it.** Recovery: re-ran with the body written first. **Prevention:** already documented in the work skill; no change.
- **Python batch edit aborted on a count assertion after the first file was already written (twice), leaving the suite half-edited.** Recovery: re-ran the suite to see the divergence, re-applied with corrected counts. **Prevention:** already documented (a failed batch looks like a landed one); the suite run is what exposed it.
- **Affected-test gate queued behind other sessions' runs and ended `rc=6` (budget deferred).** Recovery: ran the specific suites and ratchets directly and recorded CI as the authoritative gate. **Prevention:** environmental, none.
- **A test needle passed in the forbidden slot, and a lowercase `hetzner` hygiene token that could never match.** Recovery: caught by the suite and the test-design seat. **Prevention:** none beyond the existing known-negative self-test.

## Tags
category: workflow-patterns
module: followthroughs, review
