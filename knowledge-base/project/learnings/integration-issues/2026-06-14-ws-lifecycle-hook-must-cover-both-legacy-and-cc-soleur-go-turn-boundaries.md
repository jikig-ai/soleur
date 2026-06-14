# A new WS turn-boundary lifecycle hook must be wired into BOTH the legacy fan-out path AND the cc-soleur-go dispatch path

## Problem

The stream-since-disconnect replay buffer (#5273) needed a per-turn lifecycle hook (`streamReplayBuffer.resetTurn(conversationId)` at turn start, plus an `activeTurnConversations` binding so the `sendToClient` write-hook can key frames that carry no wire `conversationId`). Implementation wired `resetTurn` into exactly one site — `sendUserMessage` (`agent-runner.ts`), the legacy multi-leader fan-out path — and relied on `registerSession` (also legacy-only) to populate the binding.

But the conversation flow has **two** turn-boundary entry points:
- **Legacy fan-out:** `chat` handler → `sendUserMessage` → `dispatchToLeaders` → per-leader `startAgentSession`/`registerSession`.
- **cc-soleur-go:** `chat` handler → `dispatchSoleurGoForConversation` → `dispatchSoleurGo`, which `break`s **before** the `sendUserMessage` call and **never** calls `registerSession`.

Per #3270, cc-soleur-go is the dominant (effectively only) production path. So the feature was wired for the path that barely runs and silently broken for the one that does:
1. **No `resetTurn`** → a long cc conversation accumulates frames across turns up to the ring/byte cap → false `buffer-overflow` Sentry pages + cross-turn frame mixing.
2. **No active-turn binding** → during the disconnect grace window `sessions.delete(userId)` has run, so the write-hook's fallback chain (`frame.conversationId ?? getActiveTurnConversation(userId) ?? session?.conversationId`) resolves to `undefined` and **silently drops every gap-emitted frame** — the feature produces an empty replay for exactly its target scenario.

Green CI (35 feature tests + full 9856-test suite) and a passing tsc hid it completely: every test exercised the legacy/buffer paths; none drove the cc dispatch path.

## Solution

Wire the lifecycle hook into the cc turn boundary symmetrically: at the top of `dispatchSoleurGoForConversation`, call `streamReplayBuffer.resetTurn(conversationId)` + `setActiveTurnConversation(userId, conversationId)`, and clear the binding in a `finally` around the `dispatchSoleurGo` await (a mid-turn disconnect keeps the binding alive because the `finally` hasn't run while the turn is in flight). Added a registry `setActiveTurnConversation`/`clearActiveTurnConversation` pair for paths that don't register an `AgentSession`. Added a write-hook routing test proving a `conversationId`-less frame is buffered under the binding when `sessions` has no entry (the grace-gap case).

## Key Insight

When a feature adds a server→client lifecycle hook at a "turn boundary" in `ws-handler`/`agent-runner`, there are **two** boundaries, not one — the legacy fan-out (`sendUserMessage`) and cc-soleur-go (`dispatchSoleurGoForConversation`). Any hook (turn reset, per-turn binding, telemetry, cost gate) must be wired into both, and cc-soleur-go additionally does NOT go through `registerSession`, so any state normally populated there (here: the userId→conversationId binding) must be set explicitly on the cc path. Mechanical check at work time: `grep -n "resetTurn\|registerSession\|<your new hook>" server/*.ts` and confirm a call exists on BOTH the `sendUserMessage` lineage AND the `dispatchSoleurGoForConversation` lineage. This is a specific case of the "feature-wiring composition bug" class — correct in isolation on path A, correct in isolation on path B's buffer module, but the composition leaves path B (the dominant one) unwired.

Multi-agent review caught it: `architecture-strategist` (traced the cc `break`-before-`sendUserMessage`) and `test-design-reviewer` (noticed zero cc-path test coverage and the gap-window drop) independently converged. Plan-time and work-time both missed it because the plan reasoned about "the turn boundary" as singular.

## Session Errors

1. **`replace_all "vi_fn()" → "vi.fn()"` clobbered a helper declaration** (`function vi_fn()` → invalid `function vi.fn()`). Recovery: deleted the leftover helper. **Prevention:** scope `replace_all` to a substring that cannot appear in a declaration context; prefer removing a temporary helper before mass-renaming its call sites.
2. **Edit with too-narrow `old_string` duplicated a test body.** Matching only the `it(...)` opener and supplying a full replacement appended a second copy, merging the original body into the next test. Recovery: removed the trailing duplicate, re-verified brace balance with `grep -n '^});'`. **Prevention:** when inserting a new `describe`/`it` near an existing one, anchor the Edit on the existing test's CLOSING `});` (append after it), not its opening line.
3. **`{@link StreamReplaySeq}` JSDoc referenced an undefined symbol.** Recovery: replaced with a self-contained comment. **Prevention:** don't `{@link}` a symbol you haven't defined; use prose for cross-cutting field semantics.
4. **Doubled worktree path in a Read** (`feat-one-shot-jikig-ai/soleur/.worktrees/...`). Recovery: corrected to the absolute worktree path. One-off; **Prevention:** copy the verified worktree root from `pwd` rather than retyping.

None of the editing one-offs warrant a hook (they self-corrected within the same edit cycle and are generic tool-use slips, not workflow-rule violations).
