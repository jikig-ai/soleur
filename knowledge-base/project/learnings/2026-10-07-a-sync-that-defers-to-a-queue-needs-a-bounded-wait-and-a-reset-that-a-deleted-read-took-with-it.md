# Learning: a "wait for the queue" branch needs a bounded wait, and a deleted read can take its reset with it

## Problem

Phase 7 synced every `OPEN BEHIND` PR, restarting ~20 min of CI each time, on a repo whose `main` already has a
merge queue (#9710, PR #9697 livelock). The fix is a queue mode that waits instead of syncing. Three defects
recurred while building it, all in the "wait" branch rather than the detection:

1. A wait with no upper bound fails open into a PR that is never merged. The wait needs a consecutive-idle
   counter that expires back to today's sync.
2. A review round deleted a redundant queue-state read to shrink the fence. That read was also the only place a
   queued PR reset the idle counter, so a queued PR falsely expired. Fixed by resetting on the every-5th-tick
   `--queue-state` sighting.
3. Wording in eight harness/mirror files said "until any poll exit" before it was true of the fence; the
   exception clauses had to name the exact exits (`queue_wait_expired`, a push line, MERGED, a dequeue).

## Solution

Detect the queue from `rules/branches/<base>` by `.type == "merge_queue"` (never positionally), require armed
auto-merge, and require a non-empty required-check set. Every unreadable answer falls toward the old sync.
Mutation-tested: 26 rows (M1-M19, H1-H4, control), each RED against a green 973/0 control.

## Key Insight

When a branch exists to NOT do the old thing, enumerate what the old thing's surrounding code also did (here a
read that doubled as a counter reset) before deleting "redundant" code, and bound every wait with a fall-back
to the previous behaviour. Evidence for the open question came from the pinned PR's own timeline: GitHub does
enqueue an armed BEHIND PR under `strict_required_status_checks_policy = true`.

## Session Errors

1. **`rm -f $R/*` denied** — Recovery: `mktemp -d`, no rm. **Prevention:** never rm a variable path; use fresh temp dirs.
2. **`pgrep -f` blocked by hook** — Recovery: poll rc files. **Prevention:** wait on an rc file, not the process table.
3. **Two python edit scripts aborted on wrapped-line anchors** — Recovery: fixed anchors, reran. **Prevention:** anchor on content that survives line wrapping.
4. **Ship vs mirror `auto-sync 1 pushed` / `1/6 pushed` spelling difference** surfaced by first RED run — Recovery: `1(/6)?`. **Prevention:** diff the two fences' literal output strings before pinning.
5. **Review regression: deleting the crossing read broke the idle reset** — Recovery: reset on the 5th-tick sighting. **Prevention:** see Key Insight.
6. **Mutation battery copied the live tree per row** — Recovery: snapshot once. **Prevention:** battery rows run from an immutable snapshot.
7. **Battery run stopped after M14 and its `done` marker was written anyway** — Recovery: reran M15-M19/H1-H4 from a fresh snapshot. **Prevention:** count result rows against the row list before accepting a `done` marker.
8. **Trial edit to `AGENTS.rules.md:65` (hard rule)** — Recovery: reverted; needs human review. **Prevention:** hard-rule edits are an operator gate, not a drive-by.

9. **The idle count read only the required checks present, so the not-yet-created `test` aggregate looked idle and the wait expired mid-CI on this PR's own poll.** Recovery: an absent required context counts as pending while anything runs (Q12, Q12b). **Prevention:** a fence fixture mock that lists only the required names present cannot show absence; model the real set (aggregate absent while shards run) and run the new fence on its own PR before trusting it.
10. **Extracting SKILL.md prose into a reference moved a CWD-relative command into a new file and the plugin-root anchoring ratchet counted a new site; separately `lint-skill-body-budget` needed 7.5 KB cut.** Recovery: pointer instead of the command; three blocks extracted. **Prevention:** run `lint-skill-body-budget.py --base <merge-base>` and the repo-wide ratchets before pushing a SKILL.md edit (file-selected suites cannot see them).

## Tags

category: workflow-patterns
module: ship
