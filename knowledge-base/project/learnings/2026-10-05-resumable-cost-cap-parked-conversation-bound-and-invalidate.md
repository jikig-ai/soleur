# A parked conversation needs a bounded release AND a cache-invalidation sweep — the raise flow lives or dies on two invisible contracts

## Problem

feat-cc-cap-raise-resume (#9565) made the Concierge per-conversation cost cap
resumable: cap breach emits an `ask_user` interactive prompt and parks the
live SDK Query (`awaitingUser`) instead of `emitWorkflowEnded`→`closeQuery`.
Two review-seat findings showed the naive version of this was broken:

1. **The park had no net.** `PendingPromptRegistry.reap()` deletes expired
   records with no callback, so an unanswered cap prompt left `awaitingUser`
   set forever — `reapIdle` skips such queries by design (the comment at the
   site explicitly credits `REVIEW_GATE_TIMEOUT_MS` for making the *other*
   park bounded). Any new pause-state needs its own absolute upper bound or
   it silently becomes a permanent Query+subprocess+lease leak.
2. **A new session-cache field silently leaked across conversations.**
   `ClientSession.costCapUsd` was seeded on the chat-case cache miss but never
   invalidated — `abortActiveSession`, `resume_session`, `close_conversation`
   each clear `routing`/`contextPath`/`sessionId` under an "invalidate
   together" contract the new field was invisible to. A raise on conversation
   A then applied to a freshly materialized conversation B for the whole
   Query lifetime.
3. **"Invalid response" was a dead end.** The response path clears park
   state then validates; a non-tier or stale-tier answer returned `false`
   with the record already consumed — the conversation sat parked with no
   timer and no answerable prompt. Validation-failure paths must leave the
   conversation in a *recoverable* state, not merely an honest one.

## Solution

- Bound every park: `CAP_PROMPT_PARK_MS` timer (registry TTL + grace) that
  consumes the prompt record, releases `awaitingUser`, drops the parked
  message, and emits honest copy. On expiry the conversation rejoins
  normal idle reaping — same shape `REVIEW_GATE_TIMEOUT_MS` gives the
  review-gate park.
- Every new `ClientSession` cache field MUST be added to every
  invalidate-together site AND seeded at materialization — grep the
  sibling `routing = undefined` sites when adding a cache field.
- On invalid raise response, re-emit a fresh prompt (the consumed record
  is unanswerable anyway) — the user's parked message survives and the
  conversation stays recoverable.
- Whitelist validate raise tiers server-side (`capRaiseTiersFor(cap)`)
  rather than accepting any `Raise to $N` — a crafted response could
  otherwise permanently and *persistently* disable the guardrail.
- Sentinel records (`cost-cap:` toolUseId) MUST be routed before
  `deliverToolResult` — there is no real SDK `tool_use`, so a `tool_result`
  would corrupt the stream.

## Key Insight

A "pause" state is a resource lifecycle: whoever sets `awaitingUser`
(or any skip-the-reaper flag) owns its release, and the registry/timer
that motivated it does not call back. Similarly, a session-scoped cache
is only as safe as its invalidation sites — adding the field is half
the work; the other half is finding every `X = undefined` sibling.

## Session Errors

1. Background review seats (`subagent_explore`) intermittently failed with
   "Tool was rejected" — environmental; foreground retry also failed once.
   **Prevention:** spawn fewer, broader seats; tolerate partial panels by
   folding failed lenses into the surviving seats' briefs.
2. `git rebase --continue` hung on the editor — the worktree shell has no
   interactive EDITOR. **Prevention:** `GIT_EDITOR=true git rebase --continue`
   in non-interactive runs.
3. The spec's claim that `cost_ceiling` was terminal was refuted by research
   (it emits a non-terminal `error` frame; the kill is `closeQuery`).
   **Prevention:** verify status-taxonomy claims against the wire-handler
   switch, not the name.
4. Two test assertions used wrong harness facts (`reapIdle` ordering vs.
   park timer; `query.streamInput` vs `inputQueue.push`).
   **Prevention:** read the fixture's push path before asserting on it.
5. `git stash list` inside a compound command was hook-blocked (correct —
   worktrees forbid stash). **Prevention:** don't probe stash in worktrees;
   use `git rev-parse --verify refs/stash` per Phase-0.5 convention.

## Tags

soleur-go-runner, cost-cap, interactive-prompt, pending-prompt-registry,
session-cache-invalidation, park-lifecycle, managed-vs-byok, feat-cc-cap-raise-resume
