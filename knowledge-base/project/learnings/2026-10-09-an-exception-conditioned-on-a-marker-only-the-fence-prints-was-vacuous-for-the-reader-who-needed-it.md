# Learning: an exception conditioned on a marker only the fence prints was vacuous for the reader who needed it

## Problem

PR 9839 (armed, merge queue on `main`, strict up-to-date checks) was resynced by an agent's hand-written poll loop that
treated `mergeStateStatus=BEHIND` as an error and ran `sync-pr-behind.sh` after `gh pr merge --auto` and before the
enqueue. One resync push landed 12 minutes after arming (the second merge commit named in the brief predates the arm by
17 seconds), restarting PR CI for nothing. The skill already carried a "queue mode" exception, but it was conditioned
on "once the poll has printed `[ship.phase7.queue_wait]`", a marker only the Phase 7 fence prints. A reader who wrote
their own loop never satisfied the condition, so the exception was vacuous for exactly that reader. The same
marker-conditioned sentence existed on seven more surfaces (`behindSyncInstructions`, `pollInstructions` x4, codex and
devin INSTRUCTIONS), and the standalone script had no guard at all.

## Solution

- Enforce at the point of action: `sync-pr-behind.sh` (standalone loop) answers `kind=queue_wait` (exit 0, nothing
  fetched/merged/pushed) when GitHub reports BEHIND (not DIRTY), auto-merge is armed and `main` has a `merge_queue`
  rule; an unreadable rules read while armed fails closed (`kind=gh`, exit 4) after the same retry the queue read has.
  `--step` stays the fence's unguarded call (#9869 tracks it and the pre-merge hook).
- State the exception on facts (one canonical phrase: "when `main` has a merge queue and the PR is armed (the Phase 7
  poll prints ...)") and put it before the stop-and-sync rule on every surface, with "use the Phase 7 loop; never write
  your own". A whole-plugin test bans the class (once/after/until the poll|loop|fence printed ...), with positive
  controls so the ban cannot go dead.
- No new AGENTS rule: a script can carry it. The hard-rule line that still says "BEHIND->resync main" is an operator
  gate (#9868).

## Key Insight

A prose exception gated on an observable that only one component emits protects that component's own readers, not the
reader who bypassed it. When the incident is "an agent skipped the sanctioned path", the fix cannot live in text the
sanctioned path prints: it belongs in the executable the bypassing reader still calls, and the text should be restated
on facts any reader can check.

## Session Errors

1. **The incident brief's "pushed twice in the window" was carried into the plan and the ADR addendum unmeasured.** The
   git-history seat falsified it from the PR timeline: one push after arming, one 17 s before. Recovery: ADR addendum
   and `queue-mode.md` corrected. Prevention: re-derive every count a brief supplies from the timeline/API before it
   enters an ADR (the repo already says so for plan-quoted numbers; briefs are the same class).
2. **`--help` exit-4 line wrapped, breaking the suite's `^  4 .*kind=gh` pin.** Recovery: keep `kind=gh` on the first
   line. Prevention: after editing `usage()`, run the suite's `--help` row before anything else.
3. **A sanitiser row asserted the forged tag text was absent, but sanitising keeps alphanumerics.** Recovery: assert no
   line starts with the forged tag and no ESC byte. Prevention: assert the property (no extra tag line, no control
   byte), not the absence of a substring the sanitiser deliberately preserves.
4. **My own docs tripped my new class-ban test** (queue-mode.md described the old wording using the banned phrase).
   Recovery: reworded. Prevention: this is the ban working; describe the old wording without quoting its phrase.
5. **The first mutant-anchor uniqueness check counted the anchor's first line, which also occurs in the loop.**
   Recovery: count the WHOLE anchor via `${SUT_SRC//"$old"/}` length arithmetic. Prevention: uniqueness checks use the
   exact string the replace uses.
6. **`pgrep -f` was blocked by the self-match hook.** Recovery: used `list_runs`/`kill_mine`. Prevention: already
   hook-enforced.
7. **The affected gate queued 28+ minutes (position 3) behind sibling worktrees' runs.** Recovery: killed my own two
   runs with `kill_mine`; ship Phase 4 re-runs it. Prevention: `--capacity` before launching (already documented).
8. **Stop hook flagged two closing messages that promised a next action.** Recovery: `<stop>BLOCKED:</stop>` while
   seats were still running, then did the work. Prevention: when waiting on background seats, either do independent work
   or declare the stop.
9. **A gh issue create was refused by a hook in the planning phase (forwarded).** Recovery: re-filed with the
   `meta/machinery` label. Prevention: already hook-enforced.

## Tags

category: workflow-patterns
module: plugins/soleur/ship (sync-pr-behind.sh, merge queue)
