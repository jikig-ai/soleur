# Learning: Re-arming an idle watchdog on the SDK `tool_progress` heartbeat is DoS-safe only because the absolute turn cap is untouched — and fixing the server watchdog *increases observability* of a pre-existing client-side timeout

## Problem

The Soleur Concierge conversation died mid-answer with "Agent stopped responding after: Reading file" while the agent was visibly still working (the debug stream kept running `cat` commands). Root cause: the server-side per-block idle watchdog (`state.runaway`, 90s `DEFAULT_WALL_CLOCK_TRIGGER_MS` in `apps/web-platform/server/soleur-go-runner.ts`) fires `runner_runaway` during a *single legitimate long tool execution* — a large `Read` or a slow Anthropic round-trip that produces no assistant block and no `tool_use_result` for >90s. The watchdog mistook "one slow tool" for "agent went idle."

## Solution

Re-arm `state.runaway` on the SDK's mid-tool forward-progress heartbeat (`SDKToolProgressMessage`, `type: "tool_progress"`), which already flows into the runner's `consumeStream` loop via `includePartialMessages: true` but was dropped at the dispatch switch's "ignored at V1" branch. The fix is a ~3-line branch calling `armRunaway(state)` guarded by `!state.closed && !state.awaitingUser`, mirroring the existing `tool_use_result` reset in `handleUserMessage`. The sibling runner `agent-runner.ts:1901` already consumes the same message.

## Key Insights

1. **Heartbeat-reset is DoS-safe ONLY because the absolute turn cap is a separate, untouched timer.** A reviewer's first instinct is "can a malicious/looping tool emit `tool_progress` forever to keep the session alive?" The answer is no — but *only* because `state.turnHardCap` (10-min `DEFAULT_MAX_TURN_DURATION_MS`) is anchored on `firstToolUseAt` and is NOT re-armed by the heartbeat. The load-bearing design rule: **a forward-progress signal may reset the per-block idle window but must NEVER touch the absolute turn ceiling.** Verify this explicitly whenever you add a new reset trigger — the safety proof lives entirely in "which timer does the new branch touch."

2. **Hung-tool detection is preserved, not relaxed — and this is the merge-blocking invariant.** A genuinely hung tool emits NO `tool_progress`, so it still trips the 90s idle window. The danger of "just raise the 90s constant" (the rejected Path B) is that it dissolves hung-tool detection into the 10-min cap, converting a premature-death bug into a hang-forever bug (strictly worse UX). The RED test that pins this (single `tool_use` then SDK silence >90s STILL fires `idle_window`) must be non-vacuous and treated as merge-blocking.

3. **Fixing an upstream watchdog can INCREASE the observability of a pre-existing downstream timeout.** On the cc surface, the client-side `STUCK_TIMEOUT_MS` (45s) is not heartbeat-fed (cc-dispatcher does not forward `tool_progress` to the client). A >90s tool drives the client bubble to a *terminal error state* at the second client timeout. Before this PR, the server often tore the stream down first (premature `runner_runaway`), *masking* the client path. By keeping the stream alive, the server fix makes the client-side terminal-error path **more reachable**. This is "newly exposed by fixing an upstream bug," not "a regression introduced by the fix" — it stays a `pre-existing-unrelated` follow-up (filed #5214), but its user-reachability goes UP, so don't let the follow-up rot. When you fix a timer/guard that previously short-circuited a flow, ask: "what downstream failure path did this short-circuit used to hide?"

4. **A "pure re-arm" handler that reads no message fields needs no runtime shape-guard — but say so in a comment.** The sibling `agent-runner.ts` validates `tool_use_id`/`tool_name`/`elapsed_time_seconds` because it keys a debounce map and forwards to the client. The soleur-go re-arm reads nothing off the message, so replicating that guard would be cargo-cult. Document the asymmetry inline so a future field-read doesn't silently inherit an unvalidated SDK shape.

## Session Errors

1. **Edit-before-Read after a subagent read the file.** The orchestrator delegated implementation to a subagent (which read + edited the files), then tried to `Edit` ADR-022 directly for a review fix — the Edit tool rejected it with "File has not been read yet" because subagent reads do not populate the parent's read-state. **Recovery:** `Read` each edit-site file in the orchestrator context first, then re-apply. **Prevention:** already tool-enforced (Edit fails hard and the fix is a single Read); one-off, no workflow change needed. When an orchestrator resumes editing files a subagent touched, batch a `Read` of every edit site before the first `Edit`.

## Tags
category: best-practices
module: apps/web-platform/server (soleur-go-runner, agent-runner)
related: ADR-022-sdk-as-router.md; #5214 (client cc-surface tool_progress forwarding follow-up); PR #5208
