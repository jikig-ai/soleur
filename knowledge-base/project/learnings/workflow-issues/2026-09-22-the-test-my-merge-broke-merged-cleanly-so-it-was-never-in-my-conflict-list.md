---
title: "The test my merge broke merged cleanly, so it was never in my conflict list"
date: 2026-09-22
category: workflow-issues
tags: [ship, merge, sync-pr-behind, test-stub, consumer-sweep, lefthook, ci-cancellation]
pr: 8474
issues: [8500]
module: plugins/soleur/skills/ship
---

# The test my merge broke merged cleanly, so it was never in my conflict list

## Problem

PR #8474 (merged 2026-09-21T23:48:20Z as `97633e8e`) changed `plugins/soleur/scripts/sync-pr-behind.sh`
to check that the branch it syncs is the PR's own head branch (`kind=wrong_branch`, exit 12). That
check needs one extra `gh` query for the PR's `headRefName`.

A sibling PR, #8384 (ADR-235), landed on `main` while #8474 was waiting to merge. It added a new
suite, `plugins/soleur/scripts/sync-pr-behind.test.sh`, whose `gh` stand-in refuses any query it does
not expect: it prints `STUB-MISS: unexpected gh invocation` and exits 64. When #8474 merged `main`
in, that suite broke on the new `headRefName` query. The break reached CI and was not seen for
3 h 46 min.

## What happened

| When (UTC, 2026-09-21) | Head | Event |
|---|---|---|
| 19:10:00 | `3b1e46aa9` | Hand-resolved merge with #8488 (`rule-metrics.json`, `plan-sharp-edges.md`). |
| 19:24:08 | `7c8a60222` | Hand-resolved merge with #8384 (`sync-pr-behind.sh`, `ship/SKILL.md`, the Phase 7 fixture, `INDEX.md`, `kb-tags.txt`). The new `plugins/soleur/scripts/sync-pr-behind.test.sh` merged cleanly. The agent re-ran the Phase 7 fixture (392/0) and its own `plugins/soleur/test/sync-pr-behind.test.sh` (29/0), both green. |
| 19:52:47 | `7c8a60222` | `test-scripts (3/3)` **cancelled**: a BEHIND sync pushed a new head. |
| 21:20:02 | `5d65dad50` | Hand-resolved merge with #8484 (`plan-sharp-edges.md` append). |
| 21:22 to 22:35 | `922808ff6`, `5d65dad50`, `94b940efb` | `test-scripts (3/3)` **cancelled** on each head. |
| 23:10:37 | `1e198ac00` | First run to finish: `test-scripts (3/3)` concludes **failure** on the #8384 suite. |
| after 23:10 | `e9c6ee9a4` (on the PR branch, squashed into `97633e8e`) | Fix: the stub answers the `headRefName` query with the fixture's branch, and the query is not counted in `GH_CALLS`. |

## Root cause

The re-test after the hand-resolved merge was scoped to the **conflicted** files. The broken suite
was not conflicted: it was new on `main` and merged cleanly, so it was never in the list the agent
worked from. It also shares its basename with the branch's own `plugins/soleur/test/sync-pr-behind.test.sh`,
which did run and passed, so "the sync-pr-behind test is green" read as true.

Nothing local caught it either. lefthook's `bun-test` full gate carries `skip: merge` (`lefthook.yml`,
pinned by `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh`; ADR-183: no local run is the merge
gate). On a merge commit, CI is the first thing that runs the suites, unless the agent runs them.

And under the BEHIND livelock that followed, CI was not a working net: each sync push cancelled the
in-flight shard, so the red stayed unobserved across four heads. The livelock side is recorded in
[the livelock learning's §Recurrence](../2026-06-02-auto-merge-livelock-fast-moving-main.md).

## Key insight

**After a sibling merge, the conflict list is the wrong work-list.** A sibling PR can add a new
consumer of a script your branch changes, and that file merges cleanly. The consumer set is what
references the script, found on the merged tree:

```bash
git grep -l '<script-basename>' -- '*.test.*' '*test*.sh'
```

For `sync-pr-behind` that lists six suites: `plugins/soleur/scripts/sync-pr-behind.test.sh`,
`plugins/soleur/test/sync-pr-behind.test.sh`, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`,
`plugins/soleur/test/harness.test.ts`, `plugins/soleur/test/pr-merge-poll.test.ts` and
`plugins/soleur/test/workflow-fidelity.test.ts`. Two of the six were run.

**The strict stub was right; the merge was wrong.** #8384's stub refuses what it does not expect,
and that is the only reason the new `headRefName` query was visible at all. A permissive stub would
have answered it and hidden the contract change, the failure recorded in
`knowledge-base/project/learnings/2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md`
and `knowledge-base/project/learnings/2026-09-19-the-one-defect-lived-in-the-only-code-path-with-no-test-and-my-stub-answered-every-question.md`.
The fix taught the stub the new query and kept it out of the call count, so the suite's call-count
assertions kept their meaning.

## Prevention

After changing a script, or after merging `main` into a branch that changed one, grep for every
test that references the script and run all of them before pushing. This is the merge-time case of
the sweep class in `2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files.md`, and
the ship-time twin of the plan rule in `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
("enumerate its consumers as everything that EXECUTES these bytes", #8028). Ship Phase 7's DIRTY
exit now carries it as the "re-test by consumer, not by conflict" bullet.

**What that bullet does not cover.** A clean, automatic BEHIND sync can pull in a sibling's new
consumer the same way, with no hand resolution, and no step re-tests after it. The bullet sits on
the hand-resolved path only; the automatic path still relies on CI.

## Session Errors

1. **Re-tested the conflicted files, not the script's consumers.** Recovery: `e9c6ee9a4`, one more
   CI cycle. **Prevention:** the Phase 7 bullet above.
2. **Read a same-basename suite as "the" suite.** Two files are named `sync-pr-behind.test.sh`.
   **Prevention:** name test files by full path in every report.

## Related

- Livelock recurrence: `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md` §Recurrence: PR #8474.
- #8474's own compound learning (review findings, not these post-merge events):
  `knowledge-base/project/learnings/2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md`.
- Issue #8500 (open): the separate #8458 admin-merge with an absent required check.
