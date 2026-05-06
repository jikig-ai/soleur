---
name: SDK tool_use_result on user-role messages is the load-bearing forward-progress signal
description: When a streaming-input SDK runner uses a per-block idle reaper, that timer must reset on the SDK's documented forward-progress discriminator — `SDKUserMessage.tool_use_result !== undefined` — not only on assistant or result messages. Detection MUST be field-shape (the SDK's discriminator), not structural inspection of `message.content`.
type: best-practice
date: 2026-05-06
pr: "#3326"
parent_pr: "#3225"
domain: engineering
tags:
  - sdk-lifecycle
  - timer-design
  - forward-progress
  - defense-pair
  - cc-soleur-go
related_learnings:
  - 2026-05-05-defense-relaxation-must-name-new-ceiling.md
  - 2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot.md
synced_to: []
---

# SDK forward-progress on user-role messages: tool_use_result is the load-bearing signal

## Problem

`apps/web-platform/server/soleur-go-runner.ts:consumeStream` had two switch arms — `msg.type === "assistant"` (which calls `recordAssistantBlock` to re-arm `state.runaway`) and `msg.type === "result"` (which clears both timers). A comment said "Other SDKMessage variants … are ignored at V1."

When the user asked Concierge to summarize a 10MB PDF (a real Manning Book), the failure flow was:

1. T+0s — model emits `assistant.content[0] = { type: "tool_use", name: "Read", input: { file_path: ".../book.pdf" } }`. `recordAssistantBlock` arms `state.runaway` for `wallClockTriggerMs = 90_000` ms.
2. T+10–30s — SDK reads the PDF natively, packages bytes as a `tool_result` content block, and emits `{ type: "user", message: { role: "user", content: [{ type: "tool_result", … }] } }`. **`consumeStream` falls through this message** — the comment "ignored at V1" was correct in V1's day but became wrong as soon as the SDK started using `user`-role messages mid-turn for forward progress.
3. T+30–90s — SDK forwards PDF bytes + prior turns to Anthropic's API. The model thinks across 200+ pages and composes a summary. Zero client-visible activity during this window.
4. T+90s — `state.runaway` fires. UI renders `Agent stopped responding after: Reading <pdf>…`.

The 90s ceiling at `soleur-go-runner.ts:126` was raised in PR #3225 based on `~75s p99` for a "PDF Read+summarize" turn. That measurement was taken on small KB-fixture PDFs, not 10MB books. The window is bounded by **Anthropic's PDF processing latency**, not by the runner.

## Solution

Add a third switch arm that detects the SDK's documented forward-progress discriminator and re-arms the per-block runaway timer **only**:

```ts
// apps/web-platform/server/soleur-go-runner.ts:1058-1062
} else if (msg.type === "user") {
  handleUserMessage(state, msg as SDKUserMessage);
}

// peer to handleAssistantMessage / handleResultMessage:
function handleUserMessage(state: ActiveQuery, msg: SDKUserMessage): void {
  if (msg.tool_use_result === undefined) return;
  if (state.closed || state.awaitingUser) return;
  armRunaway(state);
}
```

Three load-bearing properties:

1. **Detection is field-shape, not content-shape.** The SDK exposes `SDKUserMessage.tool_use_result?: unknown` as the documented discriminator. `SDKUserMessageReplay` shares the field, so the same check covers both shapes without an extra branch. Scanning `message.content` for `tool_result` blocks would also work today but is brittle to future SDK content-shape changes.

2. **Only `armRunaway` is called — `armTurnHardCap` is NOT touched.** The 10-min `DEFAULT_MAX_TURN_DURATION_MS` ceiling stays anchored on `firstToolUseAt`. PR #3225 added that ceiling explicitly as the bound on chatty-but-stalled agents; the `2026-05-05-defense-relaxation-must-name-new-ceiling.md` learning is the constraint. If a future SDK regression starts emitting fake heartbeats, the absolute ceiling still bounds the turn.

3. **`closed` and `awaitingUser` short-circuit the re-arm at the call site.** `armRunaway` itself has a defense-in-depth `if (state.awaitingUser) return` at L833, but the call-site guard is clearer for future readers and prevents spurious work even when `armRunaway`'s internal guard would suffice.

## Key Insight

**When a streaming-input SDK runner uses a per-block idle reaper, the reset signal is "the SDK's lifecycle is making forward progress," not "the assistant emitted a block."** Forward progress includes:

- Assistant blocks (text or tool_use) — already covered by `recordAssistantBlock`
- The SDK's own `user`-role tool_use_result envelopes — the SDK's documented progress signal during native tool execution + downstream model thinking
- (Future) `partial_assistant`, `tool_use_summary`, `stream_event` variants — the V2 SDK roadmap

The detection key for `tool_use_result` is **the SDK's documented discriminator field** (`SDKUserMessage.tool_use_result?: unknown`), not structural content-shape inspection. Field-shape detection survives SDK content-shape evolution.

The relaxation must preserve the absolute turn ceiling. A chatty-but-stalled agent that keeps emitting fake forward-progress signals must still be bounded by `turnHardCap` (anchored on `firstToolUseAt`, never reset by per-block activity). Without this invariant, the per-block reset becomes a DoS vector.

## Generalizable Rule

When extending an SDK message-dispatch table with a new lifecycle signal:

1. **Use the SDK's documented discriminator field** as the detection key, not heuristic structural inspection of payload content.
2. **Identify which timer category the new signal resets** (per-block? absolute? both?). Reset only the categories the signal genuinely advances.
3. **Pin the un-reset categories in tests with the production constant**, not a shrunk fixture value (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`). A separate "constant pin" test asserts the production-default value; scenario tests use shrunk fixtures for runtime.
4. **Extract the new branch as a peer handler** (`handleUserMessage`) matching existing dispatch-table convention (`handleAssistantMessage`, `handleResultMessage`). Keep `consumeStream` as a pure router. Inline branches with rationale comments make the dispatch ladder grow asymmetrically.
5. **Treat forward-progress-on-user-message as intentional pass-through** for `cq-silent-fallback-must-mirror-to-sentry` purposes. Do not Sentry-breadcrumb every reset — the analogous existing path (`recordAssistantBlock`) doesn't, and adding a Sentry call here would be precedent-contradicting per the pattern-recognition rule. The 10-min `runner_runaway` log + Sentry mirror remain the diagnostic hooks for actual stalls.

## Test Strategy

Pin all five behaviors with synthetic SDK message harness + `vi.useFakeTimers()`:

- **Scenario A (bug fix)**: tool_use → tool_use_result @ <window → text after >window does NOT trigger runaway.
- **Scenario B (defense-pair)**: tool_use_result drumbeat every <idle-window does NOT defeat the absolute turn ceiling. Loop bound MUST be derived from the cap (`Math.ceil(maxTurnDurationMs / drumBeatMs) + 1`), not a magic number.
- **Scenario B-pin (production constant)**: assert `DEFAULT_MAX_TURN_DURATION_MS === 10 * 60 * 1000` directly. Without this pin, a future drop of the production constant would silently slip through.
- **Scenario C (discriminator precision)**: `user` message WITHOUT `tool_use_result` does NOT reset.
- **Scenario D (silence still fires)**: tool_use + window + 1ms silence still triggers `runner_runaway` with `reason: "idle_window"`.
- **Scenario E (replay-path)**: `SDKUserMessageReplay` with `tool_use_result` also resets — proves the field-shape check covers both shapes.

Strengthen scenario A's negative-only assertion with positive liveness: `expect(events._ended).toHaveLength(0)` AND `expect(mockReportSilentFallback).not.toHaveBeenCalled()`. Without these, the test passes vacuously if the new branch silently short-circuits before re-arming.

## Session Errors

1. **Plan-phase: `gh pr view 3287/3253` failed** — those numbers are issues, not PRs. Recovery: `gh issue view N --json state`. **Prevention:** AGENTS.md `hr-before-asserting-github-issue-status` already mandates `gh issue view <N> --json state` for issue verification — already-enforced as a rule, no new rule needed.

2. **Bash CWD non-persistence** — first vitest invocation failed with `./node_modules/.bin/vitest: No such file or directory` because the Bash tool starts a fresh shell each call; a previous `cd` does not persist. Recovery: chained `cd /absolute/path && cmd` per AGENTS.md `cq-when-running-test-lint-budget`. **Prevention:** already-enforced rule. Discoverable via clear error.

3. **First M1 scope-out claimed wrong criterion** — claimed `architectural-pivot` for "extract shared SDK fixture harness from 5 runner test files." Co-sign correctly DISSENTed: test-helper extraction is routine DRY refactor (no design tradeoff to deliberate, no second valid approach the agent named, no codebase-wide pattern at stake). Recovery: refiled under `cross-cutting-refactor` (4 concrete unrelated test files named, ~5x diff inflation justifying deferral) → CONCUR. **Prevention:** the existing `2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot.md` learning's symmetric corollary IS this case — extending the rule "X is documentation work, not pattern-changing" to "X is routine DRY refactor, not pattern-changing." Both fail `architectural-pivot` for the same structural reason: the criterion requires the *fix itself* to change a cross-codebase pattern, and routine consolidation/documentation does not. Already-discoverable via the dissent gate working as designed; no new rule needed.

4. **`grep` from wrong CWD** — same root cause as #2 (Bash CWD non-persistence). Already-enforced.

All four errors are either already-enforced by existing rules or recovered via existing gates working correctly. No new AGENTS.md rules proposed.

## Ship Trail

- PR #3225 — raised idle window to 90s with per-block reset + 10-min ceiling (introduced the defense pair).
- PR #3253 — fixed model fabricating missing pdftotext tool.
- PR #3287/#3288 — instrumented cc-soleur-go cold-Query construction with Sentry breadcrumb.
- PR #3294 — Phase 2 artifact frame leads + gated named-tool exclusion list.
- **PR #3326 (this learning)** — added forward-progress reset on `tool_use_result`; preserved 10-min absolute ceiling; one-char `jikigai → jikig-ai` GitHub org slug fix on the failure-card link.
