# Learning: one "selected only by self-inclusion" claim hid four different edge provenances

## Problem

#9564 said four heavy mutation batteries (13.6 min of the registration-only bounded selection) "reach the runner only through the self-inclusion of every declared edge set, not because they test the runner", and proposed a per-suite declared runner-SUT set to tell the two apart.

## Solution

Reading each suite's actual edge on `origin/main` gave four different answers, so no single mechanism fits:

- `registry-gate-mutation-battery`, `cf-tunnel-liveness-gate-mutations`: the runner edge comes from `PR_GATE_MACHINERY_PATHS` (ADR-262), deliberate arming, not accidental self-inclusion.
- `orphan-process-reaper-mutations`: a genuine read; its sandbox symlinks `scripts/test-all.sh`.
- `registry-delivery-change-mutation-battery`: the declared array lists `scripts/test-all.sh` only because the suite's header comment names it, a generator artifact.

Outcome: keep #9564 deferred, correct the issue (comment on #9564), replace its trigger with a measured wait.

## Key Insight

A claim that N items are in a set "only because of a blanket rule" is N claims about provenance. Before designing a marker to separate the two classes, classify each member by where its edge actually comes from (declared arming, real read, derived, comment artifact). Here the classification dissolved the case for the new concept: two members were intentional, one was a real SUT, and one is fixed by a generator tweak. Also check the declared-vs-derived split first: `scripts/test-all.sh` is a closure leaf, so every such edge is declared.

## Session Errors

1. **Local `main` was 393 commits behind `origin/main`, so the first ADR-242 grep on `main` returned nothing.** Recovery: `git fetch origin main`, re-read from `origin/main`. Prevention: already covered by the brainstorm skill's bare-root/stale-ref warnings; use `origin/main` for every probe after a fetch. One-off.
2. **The session-start gate's `.mcp.json` restore (`git show main:.mcp.json > … && mv`) overwrote a tracked, uncommitted local edit.** Recovery: copied it to the scratchpad first. Prevention: the gate's comment assumes the file is untracked; guard the restore when `.mcp.json` is tracked and dirty. Recurring, filed as #9622.
3. **`registry-gate-mutation-battery`'s 491 s has no row in `scripts/suite-durations.tsv`.** Recovery: recorded as unverified in the brainstorm. Prevention: re-check against manifest weights before any build. One-off.
4. **A turn ended on first-person commitment language and the stop hook blocked it.** Recovery: ended with an explicit BLOCKED stop while background agents ran. One-off.

## Tags
category: workflow-patterns
module: test-gate (scripts/test-all.sh, scripts/lib/test-affected-paths.sh)
