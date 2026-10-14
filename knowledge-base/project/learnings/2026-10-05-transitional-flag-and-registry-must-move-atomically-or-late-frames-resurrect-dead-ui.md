# Learning: a transitional flag and its registry must move atomically, or late frames resurrect dead UI

## Problem

The #9514 review panel (three independent seats) found the same defect shape in the Concierge chat
state machine: `enter_stopping` swept transitional bubbles to an `interrupted` marker **but left
their leaders registered in `activeStreams`**. The cc path's `abort_turn` is a documented no-op, so
frames legitimately race in behind a user abort — and every one of them resolved through the
registered-idx path, which re-entered a transitional state while the stale `interrupted` flag still
rendered "Interrupted". The user saw a box claiming **Working + Interrupted simultaneously** for the
rest of the turn. A second, symmetric defect: the rebind scan walked backward across
`role: "user"` messages, so the NEXT turn's first frame could resume a dead bubble positioned *above*
the question that prompted it — an ordering inversion.

## Solution

Three moves, each atomic where it matters (PR #9514, commit dc2a0b8):

1. **Sweep to a stronger state, and clear the registry in the same reducer action.** `enter_stopping`
   marks bubbles `stopped` (a non-rebindable variant of `interrupted`) *and* clears `activeStreams`
   — the finders skip `stopped`, and with no registration the late frames take the fresh-append path
   instead of the idx path. Either half alone leaves a reachable contradiction.
2. **User messages are turn boundaries.** `findInterruptedBubble`,
   `findRecoverableErrorBubble`, and `foldNarrationIntoTrail` all `break` on `role === "user"` — a
   rebind can never reach across a question into a prior turn's corpse.
3. **Belt on the idx paths.** Every idx-resolved transitional write emits `interrupted: false`
   anyway, so a hypothetical future arm that re-registers a swept bubble can't preserve the flag.

## Key Insight

A sweep that changes presentation state without changing *admissibility* is a half-fix: the
registered-idx path is the resurrection vector, and it bypasses the interrupted-finder entirely.
Audit both the state you write AND every lookup path that can reach the write — the bug lives in
their product, not in either alone. Corollary the panel surfaced: a backwards scan for "the newest X"
is a turn-scoped query — without an explicit boundary token (`role: "user"`), it silently becomes a
session-scoped query the moment a user message exists between the scan origin and the target.

## Session errors → fixes worth keeping

- `gh issue create --body-file` needs a **literal absolute path inside a dir the hook can read**
  (not /tmp, not `$(pwd)`, not a file created in the same exec call — the hook reads it
  pre-execution). Write the file first, then file.
- `User-Impact:` values must contain a word from `.claude/hooks/lib/user-surface-taxonomy.txt`
  (`page`/`component`/`route`/`command`…), not just a route literal like `/chat`.
- `Fix-Size: N lines / M files` inside the ≤100 lines / ≤4 files inline threshold is **refused** —
  the gate's honest answer is "fix it inline".
- A spread of a fold-helper that writes `toolLabel: undefined` must come **before** the new
  `toolLabel: event.label` assignment, not after — two of us (agent + review seat) had to name it.
- `exec timeout` parameters kill long-running gates; a repo-wide `--affected` run needs hours, not
  the default.
