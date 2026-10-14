# Learning: one "selected only by self-inclusion" claim hid three edge provenances across four suites

## Problem

#9564 said four heavy mutation batteries (13.6 min of the registration-only bounded selection) "reach the runner only through the self-inclusion of every declared edge set, not because they test the runner", and proposed a per-suite declared runner-SUT set to tell the two apart.

## Solution

Reading each suite's actual edge on `origin/main` gave three different answers across the four suites, so no single mechanism fits:

- `registry-gate-mutation-battery`, `cf-tunnel-liveness-gate-mutations`: the runner edge comes from `PR_GATE_MACHINERY_PATHS` (ADR-262), deliberate arming, not accidental self-inclusion.
- `orphan-process-reaper-mutations`: a genuine read. Its sandbox symlinks `scripts/test-all.sh` (`scripts/orphan-process-reaper-mutation.test.sh:79`) and the driven suite reads the runner's registration lines (`scripts/orphan-process-reaper.test.sh:1394`, AC33/AC34).
- `registry-delivery-change-mutation-battery`: the hand-committed declared array lists `scripts/test-all.sh` only because the suite's header comment names it. The entry is stale, with no read behind it. There is no generator.

Outcome: keep #9564 deferred, correct the issue (comment on #9564), restate its trigger as a measurement.

## Key Insight

A claim that N items are in a set "only because of a blanket rule" is N claims about provenance. Before designing a marker to separate the two classes, classify each member by where its edge actually comes from (declared arming, real read, comment artifact). Here the classification dissolved the case for the new concept. The closure-leaf rule (ADR-242 decision 18) means a text mention cannot derive the edge, so for these four suites the edges are declared and each can be judged by reading its declaration and its suite.

A second lesson came from the review of this very write-up: a "cheaper alternative" recorded in a deferral spec has to be walked through every arm that arms the thing it narrows before it is called cheaper. The first draft said "skip the `PR_GATE_MACHINERY_PATHS` runner arm for the two PR-gated batteries". The array is spread into five arrays (six suites, four of which must stay), and registration PRs also edit the shard-leg manifests, which are two more arms. The cheap piece is a ~49 s hand edit; the rest is a new concept of the same cost the doc charged against the marker.

## Session Errors

1. **Local `main` was 393 commits behind `origin/main`, so the first ADR-242 grep on `main` returned nothing.** Recovery: `git fetch origin main`, re-read from `origin/main`. Prevention: already covered by the brainstorm skill's bare-root/stale-ref warnings; use `origin/main` for every probe after a fetch. One-off.
2. **The session-start gate's `.mcp.json` restore (`git show main:.mcp.json > … && mv`) overwrote a tracked, uncommitted local edit.** Recovery: copied it to the scratchpad first. Prevention: the gate's comment assumes the file is untracked; guard the restore when `.mcp.json` is tracked and dirty. Recurring, filed as #9622.
3. **I recorded `registry-gate-mutation-battery`'s 491 s as "unverified" in four places (brainstorm, this learning, the #9564 comment, the PR body) after searching only the light manifest.** The row is in `scripts/suite-durations-heavy.tsv:9` (`measured`). Recovery: three of four review seats re-derived it; the docs now cite the heavy manifest. Prevention: absence in one file is not absence; list every manifest (`ls scripts/suite-durations*.tsv`) before calling a figure unverified. One-off, but the claim propagated to a public issue comment before review caught it.
4. **I carried the CTO's "exactly one registration-only runner PR since #9552" into the brainstorm as fact.** `git log 2cfef66506..origin/main -- scripts/test-all.sh scripts/lib/test-affected-paths.sh` is empty: zero. Prevention: re-derive a subagent's count before it bounds a decision. One-off.
5. **The first "cheaper alternative" overclaimed (two PR-gated batteries; "the generator" to change).** Five arrays and six suites share the arming, and there is no generator. Caught by the panel's quality and security seats. Prevention: see Key Insight. One-off.
6. **A turn ended on first-person commitment language and the stop hook blocked it.** Recovery: ended with an explicit BLOCKED stop while background agents ran. One-off.
7. **The hook-enforced review gate blocked `gh pr merge` after I had accepted "skip review" from the operator.** Recovery: asked again, ran the real review. Prevention: when a merge hook enforces review evidence, offer the real review up front instead of a skip option the hook will not honour. One-off.

## Tags
category: workflow-patterns
module: test-gate (scripts/test-all.sh, scripts/lib/test-affected-paths.sh)
