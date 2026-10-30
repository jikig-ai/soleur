# Learning: extending a queue-armed refusal to every writer needs one predicate, one opt-in, and an owner for every state

## Problem

The merge-queue refusal (ADR-270) guarded only the standalone `sync-pr-behind.sh` loop. `--step` and the pre-merge hook still pushed `origin/main` into an armed BEHIND PR, which restarts every required check and can dequeue it; the always-injected AGENTS rule still said "BEHIND->resync main" with no exception (#9869, #9868).

## Solution

- One predicate (`queue_wait_eval`) serves the standalone loop, a flagless `--step`, and a new read-only `--queue-wait` mode that the hook calls. The hook re-implements nothing.
- The Phase 7 fences opt out with `--fence` because they own expiry; a flagless `--step` refuses with its own exit code (14). Exit 11 is the old fences' uncounted no-op arm and would have livelocked an old pasted fence silently; 14 reaches its `*)` arm and stops loudly.
- The hook skips only after its own `not_queued OPEN armed` read, accepts the verdict only as exactly one line with rc 0, pins its read timeout inside a 20 s wrapper, and falls through to the sync with a named note on any untrusted answer.

## Key Insight

Treating UNKNOWN like BEHIND in the predicate removed the only writer for an armed UNKNOWN PR: the fence's wait, expiry and sync arms key on `OPEN BEHIND`, and the standalone loop exits `not_behind` first. The bound for that state is the poll's `MAX_POLL_MIN`, not an expiry. When a guard widens the set of states it waits on, enumerate the writer that owns each added state before documenting a bound; the ADR residual had claimed the expiry fallback covered it (architecture seat, P2).

## Session Errors

1. **Implementation agent died on an API error mid-phase** - Recovery: `SendMessage` resumed it with context intact. Prevention: resume, never respawn, a dead agent (already in the review skill).
2. **Weekly API limit killed two review seats (performance, test design)** - Recovery: applied the other eight seats' findings and emitted a degraded `Reviewed-Coverage: degraded 8/10` trailer naming the missing seats. Prevention: none; a quota is not a workflow defect. The trailer is what keeps the gap visible downstream.
3. **Planner's `decision-challenges.md` failed the ruling gate** (class `user-challenge`, rulings not shaped `Ruled by CTO agent, <date>: ...`) - Recovery: rewrote the rows. Prevention: the gate already catches it before `work`.
4. **`gh issue close --comment-file` does not exist** - the comment posted, the close did not, and a blind retry duplicated the comment on four issues. Recovery: closed with `gh issue close --reason`. Prevention: run `gh <cmd> --help` before using a flag from memory (already in the review skill's "verify prescribed CLI flags").
5. **A review fix contradicted an assertion that pinned the old behaviour** (hook passed `PR_QUEUE_TIMEOUT` through; the fix pins it to 5) - Recovery: updated T-Q22b to assert the override is ignored. Prevention: grep the suites for the symbol before changing a pinned default.

## Tags
category: logic-errors
module: merge-queue
