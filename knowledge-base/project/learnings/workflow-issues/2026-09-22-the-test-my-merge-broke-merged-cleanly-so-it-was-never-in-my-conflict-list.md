---
title: "The test my merge broke merged cleanly, so it was never in my conflict list"
date: 2026-09-22
category: workflow-issues
tags: [ship, merge, sync-pr-behind, test-stub, consumer-sweep, lefthook, ci-cancellation]
pr: 8474
module: Development Workflow
synced_to: [ship]
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

The local hooks did not cover the gap either. lefthook's `bun-test` full gate carries `skip: merge`
(`lefthook.yml`, pinned by `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh`; ADR-183: no
local run is the merge gate). The `plugin-component-test` hook does run on a merge that stages a
plugin `.md` file, but it runs `bun test plugins/soleur/test/`, which collects `.ts` suites and never
a `.sh` one.

And under the BEHIND livelock that followed, CI was not a working net: each sync push cancelled the
in-flight shard, so the red stayed unobserved across four heads. The livelock side is recorded in
[the livelock learning's §Recurrence](../2026-06-02-auto-merge-livelock-fast-moving-main.md).

## Key insight

**After a sibling merge, the conflict list is the wrong work-list.** A sibling PR can add a new
consumer of a script your branch changes, and that file merges cleanly. The work-list is every suite
that references the script on the merged tree, derived the way `plugins/soleur/skills/work/SKILL.md`
already prescribes for a refused gate ("derive the list from CONSUMERS, not memory"). For
`sync-pr-behind` that is six suites: `plugins/soleur/scripts/sync-pr-behind.test.sh`,
`plugins/soleur/test/sync-pr-behind.test.sh`, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`,
`plugins/soleur/test/harness.test.ts`, `plugins/soleur/test/pr-merge-poll.test.ts` and
`plugins/soleur/test/workflow-fidelity.test.ts`. The agent ran the two conflicted-file `.sh` suites,
the `plugin-component-test` hook most likely ran the three `.ts` ones, and the one suite nothing ran
was the one that broke.

The strict stub did its job: it refused the unexpected query, which is the only reason the contract
change surfaced at all. The fix taught it the new query instead of loosening it.

## Prevention

After changing a script, or after merging `main` into a branch that changed one, run every suite
that references it before pushing, using the work skill's consumer derivation. This is the
merge-time case of the sweep class in
`knowledge-base/project/learnings/2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files.md`,
and the ship-time twin of the plan rule in `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
("enumerate its consumers as everything that EXECUTES these bytes", #8028). Ship's Phase 6.5
hand-resolution steps, its Phase 7 DIRTY exit and merge-pr §3.4 now point at it.

**What that pointer does not cover.** A clean, automatic BEHIND sync can pull in a sibling's new
consumer the same way, with no hand resolution, and no step re-tests after it. That path still relies
on CI. It is an accepted risk, not tracked separately.

## Session Errors

1. **Read a same-basename suite as "the" suite.** Two files are named `sync-pr-behind.test.sh`.
   **Prevention:** name test files by full path in every report.

Errors from the session that wrote this learning (PR #8537):

2. **Two claims inherited from the #8474 session's closing summary were wrong** — "an admin-merge
   broke the loop" (queued auto-merge fired) and "a 60 to 70 minute CI cycle" (the runs that finished
   took 36 and 31 minutes). Both went into the brief as premises; planning caught the first, review
   the second. **Prevention:** already a rule in `plugins/soleur/skills/work/SKILL.md` ("A RESUME
   BRIEF's 'measured' facts … are preconditions, not findings"); apply it when WRITING a brief from a
   summary, not only when reading one — re-derive each number from the check-run API first.
3. **Over-corrected while fixing #2:** wrote "`main` moved every 30 to 40 minutes"; the merge
   intervals ranged from 14 to 124 minutes. Caught on read-back. **Prevention:** state only the
   measured quantity, not a paraphrase of its cadence.
4. **Planning flagged by the observability gate** because `ship/SKILL.md` is a plugin surface.
   **Prevention:** already enforced by deepen-plan Phase 4.7.
5. **A fix commit cited as if on `main`.** `e9c6ee9a4` lives only on the squashed PR branch.
   **Prevention:** check `git merge-base --is-ancestor <sha> origin/main` before citing a SHA.
6. **An acceptance check missed on spelling** (`skip: - merge` in prose, `skip: merge` in the AC).
   **Prevention:** run the AC's literal command, as `work/SKILL.md` already requires.
7. **One red suite from contention** (`redact-a11y-snapshot`, 69/0 re-run alone). **Prevention:**
   already covered by the contention banners and the re-run-in-isolation rule.
8. **Session started outside any repository** (`/home/jean`), so the readiness probe reported
   not-ready while the repo existed at a different path. **Prevention:** start sessions from the repo
   or a worktree.
9. **Transcript searches returned nothing** at first: a plain regex over JSON-escaped text, and the
   ugrep shim rejecting `xargs`-built arguments. **Prevention:** extract text with `jq` first, and use
   `/usr/bin/grep` when piping through `xargs`.

## Related

- #8474's own compound learning (review findings, not these post-merge events):
  `knowledge-base/project/learnings/2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md`.
