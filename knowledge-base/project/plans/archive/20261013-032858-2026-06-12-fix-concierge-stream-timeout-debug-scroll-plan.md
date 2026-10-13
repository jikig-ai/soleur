---
title: "fix: Concierge stream mid-run timeout + Debug stream sticky autoscroll"
type: fix
date: 2026-06-12
branch: feat-one-shot-concierge-stream-timeout-debug-scroll
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Concierge stream mid-run timeout + Debug stream sticky autoscroll

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Root Cause, Implementation Phases, ACs, Risks (precedent-diff), Observability
**Research agents used:** SDK-realism verifier, verify-the-negative, architecture-strategist, code-simplicity-reviewer

### Key Improvements (deepen pass)

1. **Path A is now the SOLE path; Path B (raise the constant) is DELETED.** Verified against the installed SDK: `SDKToolProgressMessage` (`type: 'tool_progress'`, `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:2504-2513`) is a true mid-tool heartbeat carrying `elapsed_time_seconds`. It already flows into the runner's `consumeStream` loop because `includePartialMessages: true` is set in the shared options builder (`agent-runner-query-options.ts:156`, consumed by `realSdkQueryFactory` in `cc-dispatcher.ts:1214`), and is currently dropped at the "ignored at V1" branch (`soleur-go-runner.ts:2171`). No SDK option change is needed. Path B was an unfalsifiable magic-number raise that would have dissolved hung-tool detection into the 10-min hard cap — both reviewers flagged it for deletion.
2. **Uncited server precedent surfaced:** the sibling runner `agent-runner.ts:1901-1948` ALREADY consumes `tool_progress` and re-arms a watchdog from it. The original plan mis-cited the CLIENT reducer (`chat-state-machine.ts`); the load-bearing server precedent is `agent-runner.ts`. The fix is the symmetric ~3-line addition to `soleur-go-runner.ts`.
3. **Hung-tool detection is PRESERVED, not relaxed:** a genuinely hung tool emits NO `tool_progress`, so it still trips the 90s `idle_window`. Only a slow-but-progressing tool is spared. New AC2b pins this by name.
4. **Cadence invariant named:** the fix's correctness depends on `SDK tool_progress emit interval < DEFAULT_WALL_CLOCK_TRIGGER_MS (90s)`. The ≤5s floor is inferred from `agent-runner.ts:1864` `TOOL_PROGRESS_DEBOUNCE_MS = 5_000` (a throttle proves the SDK emits at least that often).
5. **Client 45s watchdog on the cc surface reconciled:** cc-dispatcher does NOT forward `tool_progress` to the client (verified: zero matches). The original "client is already heartbeat-fed" claim is FALSE for this surface; corrected below and a follow-up acknowledged.
6. **Debug panel design tightened:** `stickToBottom` is a `useRef` (not state); use `ul.scrollTop = ul.scrollHeight` (not `scrollIntoView` — avoids ancestor-scroll yank in a nested `overflow-y-auto`); drop the sentinel `<li>`; name the threshold constant.

### New Considerations Discovered

- ADR-022 amendment owed (records the now-THREE `state.runaway` reset triggers); the #3225 follow-up debt to land this was never closed.
- Test-enumeration grep step owed per `2026-05-05-defense-relaxation-must-name-new-ceiling.md` §Sub-Lesson 6 (`grep -rn "wallClockTriggerMs\|tool_progress\|runaway" test/`).

## Overview

Two independent defects in the Soleur Concierge conversation harness (`apps/web-platform`):

1. **The agent stops mid-run with "Agent stopped responding after: <last activity>"** while it is still legitimately working (debug stream actively shows `cat` commands reading source files). This is the server-side **idle watchdog** (`armRunaway`, 90s `DEFAULT_WALL_CLOCK_TRIGGER_MS`) firing during a legitimate long single tool execution, because that timer is re-armed ONLY by (a) a new assistant block (`recordAssistantBlock`) or (b) an SDK `tool_use_result` synthetic user message (`handleUserMessage`). A single tool call whose execution + Anthropic round-trip exceeds 90s before producing its first `tool_use_result` trips the watchdog even while the SDK is mid-execution and the harness is genuinely active.

2. **The Debug stream panel appends new entries at the bottom** with no autoscroll, forcing the operator to scroll down manually. Fix: **sticky autoscroll-to-bottom** — pin to newest as entries arrive, but do NOT yank scroll when the user has scrolled up to read history.

The workspace is incidentally named "Fix Issue 4826" (nav-rail position resume). **Issue 4826 is NOT the target of this plan** — it is a separate feature the prior agent happened to be working on. The two fixes here are scoped strictly to the Concierge conversation infrastructure.

This is a pure code change against already-provisioned surfaces (the long-lived Node WS server process and a React client component). No new infrastructure, no new secret, no new vendor, no DB migration, no regulated-data surface.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (direct one-shot plan entry). The premise was validated by reading the runner + state-machine source directly. The one place the operator's framing needed correction:

| Premise (operator) | Codebase reality | Plan response |
|---|---|---|
| "the debug stream kept moving (`cat` commands) but the stream stopped and connection dropped" | Two SEPARATE timers exist: a CLIENT 45s `STUCK_TIMEOUT_MS` (reset by `tool_use`/`tool_progress` in `chat-state-machine.ts:486,522`) and a SERVER 90s `armRunaway` idle window (`soleur-go-runner.ts:1779`). The "stopped responding" card and the `runner_runaway` workflow-end come from the SERVER timer, NOT the client one. **CORRECTION (deepen):** on the cc/`soleur-go` surface, `cc-dispatcher.ts` does NOT forward `tool_progress` WS events to the client (verified: zero matches) — so the CLIENT 45s timer is ALSO not heartbeat-fed during a long single tool on this surface (unlike the `agent-runner` surface). | Fix targets the SERVER `armRunaway` reset surface (the timer that produces `runner_runaway`). The client 45s timer is a known residual on the cc surface — see Follow-ups; it does not produce the "stopped responding" card (that is the server `runner_runaway`), so it is out of scope for THIS PR. |
| "the watchdog fires while the agent is still producing tool calls" | Partially. `armRunaway` IS re-armed on each `tool_use_result` (`soleur-go-runner.ts:2035`) and each assistant block. It fires only on a >90s gap with NEITHER signal — i.e., a single long tool execution (large `cat`, slow Anthropic round-trip) that emits no intermediate progress. The comment at `:2022-2031` explicitly names "native PDF Read + Anthropic API roundtrip on a multi-MB document" as this gap. | The plan does NOT claim the watchdog "never resets on tool activity". It targets the specific gap: tool-call **start** (`tool_use` block, already a reset via `recordAssistantBlock`) followed by >90s of silent in-tool execution before the result. The SDK emits a forward-progress signal during this window that the runner currently ignores. |
| "Ignore the Disconnected state — screenshot was late" | `connected` badge in `debug-stream-panel.tsx:116-123` is driven by `status === "connected"`; the disconnect is downstream of `runner_runaway` `clear_streams` + the client reconnect loop. | Out of scope — no change to the disconnect/reconnect affordance. The real fix prevents the premature `runner_runaway` that triggers the cascade. |

## 🎯 Goal

- The agent no longer emits "Agent stopped responding after: …" while a single tool call is legitimately executing (e.g., reading a large file or awaiting a slow model round-trip). The 90s idle window is re-armed by the SDK's mid-tool forward-progress signal, not only by block/result boundaries.
- The Debug stream panel keeps the newest entry visible by default (sticky autoscroll-to-bottom), and stops auto-scrolling the moment the operator scrolls up to read history, resuming when they scroll back to the bottom.

## User-Brand Impact

**If this lands broken, the user experiences:** a Concierge conversation that dies mid-answer with "Agent stopped responding after: Reading file" while the agent was visibly still working — the single most trust-destroying failure mode for a chat product (it looks like the product silently gave up). For the debug panel: an operator (Soleur team) who cannot watch the harness live without constant manual scrolling, slowing every debug session.

**If this leaks, the user's data / workflow is exposed via:** N/A for the timeout fix (no new data surface — the watchdog reset reads only an SDK message discriminator already handled in `handleUserMessage`). The debug panel re-redacts every body at render (`redactCommandForDisplay`, `debug-stream-panel.tsx:52`) and the autoscroll change touches only DOM scroll position — no new emit path, no change to what data reaches the client.

**Brand-survival threshold:** single-user incident — a Concierge turn that dies mid-stream is a single-user-visible incident on the product's core surface. CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs at review-time.

> CPO sign-off required at plan time before `/work` begins. Invoke CPO domain leader if not already covered by Phase 2.5, or confirm CPO has reviewed this framing.

## Root Cause Analysis

### Defect 1 — premature `runner_runaway` on long single tool execution

The runner (`apps/web-platform/server/soleur-go-runner.ts`) maintains two server-side timers per active query:

- **`state.runaway`** — the per-block idle window, 90s (`DEFAULT_WALL_CLOCK_TRIGGER_MS`, `:528`). Re-armed by `armRunaway` (`:1779`).
- **`state.turnHardCap`** — the absolute turn ceiling, 10 min (`DEFAULT_MAX_TURN_DURATION_MS`, `:534`). Armed once per turn (`armTurnHardCap`, `:1698`), deliberately NOT reset on block activity (chatty-stall defense, PR #3225).

`armRunaway` is called from exactly three places today:

1. `recordAssistantBlock` (`:1773`) — on every `text` / `tool_use` assistant block (`:1913`, `:1960`).
2. `handleUserMessage` (`:2035`) — on every SDK `tool_use_result` synthetic user message (the SDK's documented forward-progress signal during tool execution; comment `:2022-2031`).
3. The `notifyAwaitingUser(false)` resume path (`:2987`) and the partial-routing path (`:2035` region).

The gap: when the agent issues ONE tool call (a single `tool_use` block → one `armRunaway` reset) and that tool then executes for >90s before the SDK emits ANY `tool_use_result` (large-file `Read`/`cat`, a slow Anthropic round-trip on a multi-MB document, a long `Bash`), **no signal re-arms `state.runaway`**, so it fires `runner_runaway` with `reason: "idle_window"` and `lastBlockToolName` = the in-flight tool. The harness was genuinely active the whole time; the watchdog mistook "one slow tool" for "agent went idle".

**The SDK emits a finer-grained forward-progress signal during this window that the runner currently drops.** The SDK yields `SDKToolProgressMessage` (`type: 'tool_progress'`, `tool_use_id`, `tool_name`, `elapsed_time_seconds`; `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:2504-2513`) as a top-level message variant DURING a single tool's execution. It is NOT gated behind a separate opt-in beyond `includePartialMessages: true`, which is already set in the shared options builder (`agent-runner-query-options.ts:156`) that `realSdkQueryFactory` (`cc-dispatcher.ts:1214`) feeds into the runner's `consumeStream` loop. The runner's dispatch switch (`soleur-go-runner.ts:2158-2172`) currently handles only `assistant`/`result`/`user` and drops `tool_progress` at the "ignored at V1" branch (`:2171`).

**Server-side precedent already exists.** The sibling runner `agent-runner.ts:1889-1948` ALREADY consumes `SDKToolProgressMessage` (`:1901`) — it runtime-validates the shape, debounces at `TOOL_PROGRESS_DEBOUNCE_MS = 5_000` (`:1864`), and forwards a `tool_progress` WS event that resets the client watchdog. `soleur-go-runner.ts` has the symmetric blind spot: it does not re-arm `state.runaway` on the same heartbeat. **The fix is to add a `tool_progress` branch to the runner's dispatch switch that calls `armRunaway(state)`** (guarded by `!state.closed && !state.awaitingUser`), exactly as `handleUserMessage` already does for `tool_use_result` (`:2034-2035`) — touching `state.runaway` ONLY, never `state.turnHardCap`.

**Cadence invariant (load-bearing):** correctness requires `SDK tool_progress emit interval < DEFAULT_WALL_CLOCK_TRIGGER_MS (90s)`. The ≤5s emit floor is inferred from `agent-runner.ts:1864` `TOOL_PROGRESS_DEBOUNCE_MS = 5_000` — a 5s *outbound throttle* only makes sense if the SDK emits at least that often, so emissions land well inside the 90s window.

**Hung-tool detection is PRESERVED, not relaxed.** A genuinely hung tool emits NO `tool_progress` (the SDK reports elapsed time only while the subprocess is alive and progressing), so it still trips the 90s `idle_window`. Only a slow-but-*progressing* tool is spared — which is exactly the case that should NOT be killed. This is the opposite of Path B (raising the constant), which would give a hung tool up to 10 min of rope before the hard cap.

### Defect 2 — Debug stream panel has no autoscroll

`debug-stream-panel.tsx:156` renders entries oldest-at-top into a `<ul className="max-h-72 overflow-y-auto">` with **no ref and no scroll effect** (confirmed: the panel has zero `useRef`/`useEffect`/scroll logic). Entries arrive append-bottom (`chat-state-machine.ts:1044`, `messages: [...prev, debugMsg]`). The operator must scroll down to see new entries.

The chat message list already has an **unconditional** autoscroll precedent at `chat-surface.tsx:303-305` (`messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })` on `[messages]`). The debug panel needs the **sticky** variant: pin only when the user is already at the bottom.

## 🛠️ Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

0.1 Confirmed at deepen time (no re-verification needed, but re-read the cited lines at `/work` start): `SDKToolProgressMessage` (`type: 'tool_progress'`) at `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:2504-2513` is the mid-tool heartbeat; `includePartialMessages: true` is set at `agent-runner-query-options.ts:156`; the runner drops `tool_progress` at `soleur-go-runner.ts:2171`; the server precedent is `agent-runner.ts:1901`. **Read `agent-runner.ts:1889-1948` before implementing** — it is the established server-side consumer pattern to diff against.

0.2 **Test-enumeration grep (mandatory, per `2026-05-05-defense-relaxation-must-name-new-ceiling.md` §Sub-Lesson 6):** run `grep -rn "wallClockTriggerMs\|tool_progress\|runaway\|DEFAULT_WALL_CLOCK_TRIGGER_MS" apps/web-platform/test/` and audit EVERY hit — do not sample. Any test that pins the OLD "runaway only resets on block/result" semantic must be updated alongside the GREEN change, or it breaks mid-implementation.

0.3 Confirm test runner + globs (verified): vitest, happy-dom env, `test/**/*.test.ts` (node) + `test/**/*.test.tsx` (happy-dom) via `apps/web-platform/vitest.config.ts:44,60`. New component test MUST live under `apps/web-platform/test/components/` (co-located `components/**/*.test.tsx` is NOT collected). Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NO `npm run -w` — repo root has no `workspaces` field).

0.4 happy-dom does NOT implement `scrollTop`, `scrollHeight`, `clientHeight`. The autoscroll test MUST define them via `Object.defineProperty` on the container (`get`/`set` backed by a mutable closure var, so the test can drive `scrollTop` and assert the post-effect value) — `test/setup-dom.ts` does not provide them.

### Phase 1 — Fix the server idle watchdog (TDD: RED first)

**Single path (Path A — verified viable at deepen time; the earlier Path B "raise the constant" fallback is deleted: it would dissolve hung-tool detection into the 10-min hard cap, an unfalsifiable magic-number raise both reviewers rejected).**

1.1 RED — add a failing test to `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` (the existing watchdog test surface; it already asserts `DEFAULT_WALL_CLOCK_TRIGGER_MS`, `DEFAULT_MAX_TURN_DURATION_MS`, `reason: "idle_window"` / `"max_turn_duration"` at `:507,600,604,810`). New cases, using the existing fake-timer harness:
- **(reset case)** a single `tool_use` block followed by N `tool_progress` messages spaced < 90s apart, total elapsed > 90s → asserts `runner_runaway` does NOT fire (the `tool_progress` signals re-armed `state.runaway`).
- **(hung-tool case, AC2b)** a single `tool_use` block then SDK silence — NO `tool_progress`, NO result — for > 90s → asserts `runner_runaway` STILL fires with `reason: "idle_window"`. This pins that the heartbeat reset does not blind the watchdog to a genuinely hung tool.

1.2 GREEN — in `apps/web-platform/server/soleur-go-runner.ts`, add one branch to the dispatch switch (`:2158-2172`, after the `user` branch) for `msg.type === "tool_progress"` that calls `armRunaway(state)` guarded by `!state.closed && !state.awaitingUser` (mirroring `handleUserMessage:2034-2035`). Touch `state.runaway` ONLY — do NOT touch `state.turnHardCap` (the 10-min ceiling stays anchored on `firstToolUseAt`, comment `:2028-2031`). The branch reads NO fields off the message (a pure re-arm), so it deliberately does NOT replicate `agent-runner.ts:1910-1927`'s runtime shape-guard — document that choice in a one-line comment. Add a comment citing (a) the `agent-runner.ts:1901` precedent, (b) `includePartialMessages: true` at `agent-runner-query-options.ts:156` as the load-bearing precondition (so a future edit there is grep-discoverable), and (c) this plan.

1.3 Server-internal re-arm ONLY — do NOT add a new WS message type or forward `tool_progress` to the client in this PR (cc-dispatcher does not forward it today; the `chat-state-machine.ts:498-500` chip-regression guard is therefore moot since nothing new is emitted client-ward). The client 45s watchdog residual on the cc surface is acknowledged in Follow-ups.

1.4 REFACTOR — run `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-awaiting-user.test.ts` and any other test surfaced by the Phase 0.2 grep.

### Phase 2 — Debug stream sticky autoscroll (TDD: RED first)

2.1 RED — add `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` (vitest + `@testing-library/react`, matching `test/components/debug-stream-panel.test.tsx` import style at `:9-13`). Define `scrollTop`/`scrollHeight`/`clientHeight` on the `<ul>` per Phase 0.4. Three cases:
- (a) New entry arrives while the container is at the bottom → `ul.scrollTop` is set to `ul.scrollHeight`.
- (b) New entry arrives while the user has scrolled up (drive `scrollTop` well below bottom, fire `onScroll`) → autoscroll is NOT triggered (scroll position not yanked).
- (c) User scrolls back to bottom (fire `onScroll` at bottom) → autoscroll resumes on the next entry.

2.2 GREEN — in `apps/web-platform/components/chat/debug-stream-panel.tsx`:
- Add a `useRef<HTMLUListElement>(null)` on the `<ul>` at `:156`. (Do NOT add a sentinel `<li>` — the `<ul>` ref is needed anyway for the threshold math, and scrolling the list directly avoids the ancestor-scroll yank that `scrollIntoView` causes in a nested `overflow-y-auto`.)
- Add a `stickToBottom` as a **`useRef(true)`** (NOT `useState` — the flag is never rendered; state would re-render on every scroll event and risk a stale-closure read inside the effect).
- Add a named constant `const STICK_TO_BOTTOM_THRESHOLD_PX = 32;` with a one-line comment (sub-pixel rounding + last-row height). An `onScroll` handler on the `<ul>` sets `stickToBottom.current = (scrollHeight - scrollTop - clientHeight) < STICK_TO_BOTTOM_THRESHOLD_PX`.
- Add a `useEffect` keyed on `events.length` that, only when `stickToBottom.current` is true and the ref is set, does `ul.scrollTop = ul.scrollHeight`.
- Keep entries in arrival order (oldest-at-top) — autoscroll-to-bottom is the chosen pattern (conventional log-tail), NOT reverse order. The operator explicitly preferred autoscroll.

2.3 REFACTOR — run `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel-autoscroll.test.tsx test/components/debug-stream-panel.test.tsx`.

### Phase 3 — Typecheck + affected suite + ADR amendment

3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-awaiting-user.test.ts test/components/debug-stream-panel-autoscroll.test.tsx test/components/debug-stream-panel.test.tsx` (plus any file surfaced by the Phase 0.2 grep).
3.3 ADR-022 one-line amendment: append to `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` recording the full `state.runaway` reset-trigger set — `recordAssistantBlock` (block boundary) + `handleUserMessage` (`tool_use_result`) + the new `tool_progress` (mid-tool heartbeat), all feeding `state.runaway`, with `state.turnHardCap` deliberately fed by none. Closes the #3225 follow-up debt.
3.4 Manual/QA: confirm the "Agent stopped responding" card no longer appears for a long single-tool turn, and the debug panel stays pinned to newest unless scrolled up.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — add a `tool_progress` branch to the dispatch switch that re-arms `state.runaway` (server-internal heartbeat reset).
- `apps/web-platform/components/chat/debug-stream-panel.tsx` — sticky autoscroll-to-bottom (`<ul>` ref + `stickToBottom` useRef + onScroll threshold + useEffect on `events.length`).
- `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` — RED tests: tool_progress re-arm case + hung-tool (silence) still-fires case.
- `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` — one-line amendment recording the three `state.runaway` reset triggers (closes #3225 follow-up debt).

## Files to Create

- `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` — sticky-autoscroll tests (3 cases).

## Open Code-Review Overlap

None — query ran at plan time (`gh issue list --label code-review --state open`). No open scope-out names `soleur-go-runner.ts` or `debug-stream-panel.tsx`. (If the work phase finds otherwise, fold-in or acknowledge per the standard disposition.)

## ✅ Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (watchdog reset):** `runner_runaway` does NOT fire during a single tool execution that exceeds 90s wall-clock while the SDK emits `tool_progress` messages spaced < 90s apart. Verified by the new RED→GREEN reset-case test in `test/soleur-go-runner-awaiting-user.test.ts`.
- [x] **AC2 (no regression on generic idle):** A turn with NO assistant block, NO `tool_use_result`, AND NO `tool_progress` for > the idle window still fires `runner_runaway` with `reason: "idle_window"` (the existing `:810` assertion still passes).
- [x] **AC2b (hung-tool detection preserved):** A single `tool_use` block followed by SDK silence (NO `tool_progress`, NO result) for > 90s STILL fires `runner_runaway` with `reason: "idle_window"` — the heartbeat reset must NOT blind the watchdog to a genuinely hung tool. Verified by the new hung-tool-case test.
- [x] **AC3 (hard cap intact):** `DEFAULT_MAX_TURN_DURATION_MS` (10 min) absolute ceiling still fires with `reason: "max_turn_duration"` even when forward-progress keeps arriving (existing `:604` test passes). The forward-progress reset touches `state.runaway` only, never `state.turnHardCap`.
- [x] **AC4 (sticky pin):** New debug entry arriving while the `<ul>` is scrolled to the bottom scrolls the newest entry into view (test case (a)).
- [x] **AC5 (no yank):** New debug entry arriving while the user has scrolled up does NOT move the scroll position (test case (b)).
- [x] **AC6 (resume):** Scrolling back to the bottom re-enables sticky autoscroll on the next entry (test case (c)).
- [x] **AC7 (order unchanged):** Debug entries remain oldest-at-top / newest-at-bottom (no reverse-order regression); the existing `debug-stream-panel.test.tsx` assertions still pass.
- [x] **AC8 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.

### Post-merge (operator)

- None. Pure code change; the `web-platform-release.yml` pipeline restarts the container on merge to main touching `apps/web-platform/**` — the merge IS the deploy. No migration, no Terraform, no secret.

## Observability

```yaml
liveness_signal:
  what: existing `log.warn(..., "runner_runaway fired (idle window)")` at soleur-go-runner.ts:1821; a DROP in idle-window fire frequency post-deploy on a stable traffic level is the success signal
  cadence: per-fire (event-driven, not polled)
  alert_target: Better Stack / Sentry (existing pino → log sink for the WS server process)
  configured_in: apps/web-platform/server/soleur-go-runner.ts (existing log.warn call; no new sink)
error_reporting:
  destination: Sentry via existing reportSilentFallback wraps at soleur-go-runner.ts:1849,1892 (onWorkflowEnded / onCloseQuery)
  fail_loud: yes — the watchdog-reset handler must NOT swallow a throwing armRunaway; mirror any new catch to Sentry per cq-silent-fallback-must-mirror-to-sentry
failure_modes:
  - mode: forward-progress reset fails to fire (handler not wired to the right SDK message) → premature runaway persists
    detection: the new RED test in soleur-go-runner-awaiting-user.test.ts fails at GREEN
    alert_route: CI test failure (pre-merge); post-merge, idle-window fire frequency unchanged in logs
  - mode: forward-progress reset blinds the watchdog to a genuinely hung tool
    detection: AC2 + AC3 tests; turnHardCap (10 min) remains the bound and still fires reason=max_turn_duration
    alert_route: CI test failure; runner_runaway reason=max_turn_duration in Sentry/logs
  - mode: autoscroll yanks scroll on user scroll-up
    detection: AC5 test case (b)
    alert_route: CI test failure (pre-merge only — client-side, no server telemetry)
logs:
  where: pino structured logs from the WS server process (existing), keyed conversationId + reason
  retention: existing log-sink retention (no change)
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-awaiting-user.test.ts
  expected_output: all watchdog cases pass, including the new "forward-progress re-arms runaway" case and the unchanged idle_window + max_turn_duration cases
```

## Domain Review

**Domains relevant:** Product (Concierge core conversation surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline context — plan file path supplied as argument)
**Skipped specialists:** none — this modifies an EXISTING UI component (`debug-stream-panel.tsx`) and an existing server timer; it creates no new user-facing page, flow, or component. The mechanical UI-surface override does NOT fire (no new `components/**/*.tsx` / `app/**/page.tsx` in Files to Create; the only created file is a test). The debug panel is a Soleur-team-only dev-cohort drawer, not an end-user surface.
**Pencil available:** N/A (no new UI surface — modifying existing component behavior only)

#### Findings

The timeout fix is server-internal (no UI change beyond the absence of a spurious error card). The debug-panel change is an autoscroll behavior on an existing, team-internal drawer. No wireframe needed (ADVISORY tier, existing component). CPO sign-off is required by the `single-user incident` brand-survival threshold (not by the UX tier) and is tracked in `## User-Brand Impact`.

## Risks & Mitigations

### Precedent-diff — server `tool_progress` consumer

`git grep -n "tool_progress" apps/web-platform/server/agent-runner.ts` → the sibling runner already consumes `SDKToolProgressMessage` at `agent-runner.ts:1901-1948`. Diff of intended `soleur-go-runner.ts` handler vs the precedent:

| Aspect | `agent-runner.ts:1901` (precedent) | `soleur-go-runner.ts` (this fix) |
|---|---|---|
| Discriminator | `message.type === "tool_progress"` | same |
| Runtime shape-guard | validates `tool_use_id`/`tool_name`/`elapsed_time_seconds`, mirrors malformed-shape to Sentry (`:1910-1927`) | **omitted by design** — the handler reads NO fields (pure `armRunaway` re-arm), so there is nothing to validate; documented inline |
| Debounce | `TOOL_PROGRESS_DEBOUNCE_MS = 5_000` (throttles WS forward) | **N/A** — no WS forward; re-arming `state.runaway` every message is idempotent and cheap |
| Watchdog touched | client 45s `STUCK_TIMEOUT_MS` (via WS forward) | server 90s `state.runaway` only, never `state.turnHardCap` |
| Pause guard | n/a | `!state.closed && !state.awaitingUser`, mirroring `handleUserMessage:2034` |

Conclusion: not a novel pattern — the consume-and-act shape is established; this fix is the minimal server-internal subset.

### Other risks

- **Cadence invariant:** the fix is correct only if `SDK tool_progress emit interval < DEFAULT_WALL_CLOCK_TRIGGER_MS (90s)`. The ≤5s floor inferred from `agent-runner.ts:1864` `TOOL_PROGRESS_DEBOUNCE_MS` makes this hold with large margin. If a future SDK throttles `tool_progress` above 90s, the gap returns — named here so it is grep-discoverable.
- **`includePartialMessages` precondition:** Path A silently regresses if `agent-runner-query-options.ts:156` ever flips `includePartialMessages` to false (`tool_progress` would stop arriving). Mitigation: the new branch carries a comment citing that line as the load-bearing precondition.
- **happy-dom scroll APIs absent:** autoscroll tests test nothing if scroll props are unmocked. Mitigation: Phase 0.4 mandates `Object.defineProperty` get/set on the container; the test drives `scrollTop` and asserts the post-effect value.
- **Autoscroll precedent (do NOT copy verbatim):** `chat-surface.tsx:303-305` is the in-repo precedent but is UNCONDITIONAL (`scrollIntoView` on the page scroller). The debug panel is a nested `overflow-y-auto` list and the operator requires no-yank-when-scrolled-up, so it uses `ul.scrollTop = ul.scrollHeight` (avoids ancestor-scroll yank) gated by a `stickToBottom` ref — the sticky guard is a real requirement, not gold-plating.

## Follow-ups

- **Client 45s watchdog on the cc surface (residual — MUST file at ship, unconditionally):** `cc-dispatcher.ts` does not forward `tool_progress` WS events, so the client `STUCK_TIMEOUT_MS` (45s) is not heartbeat-fed during a long single tool on the Concierge surface (unlike the `agent-runner` surface). This does NOT produce the server "stopped responding" card (that is the server `runner_runaway`, which THIS PR fixes). **Severity correction (review, user-impact-reviewer):** the residual is NOT a "transient Retrying… chip flicker." The first client timeout at 45s shows the "Retrying…" chip and resets; a SECOND consecutive timeout at ~90s drives the client bubble to a TERMINAL `error` state (`chat-state-machine.ts` `applyTimeout` stage 2) and evicts the leader from `activeStreams`, so the eventual real answer renders as a NEW bubble appended BELOW the orphaned error bubble — the user sees "the agent failed" followed by the answer. This is reachable on routine traffic (any `Read`/`Bash`/web-search > 90s on the cc surface) and is itself a single-user-visible incident on the product's core surface. The server fix reduces its frequency (the stream is no longer torn down server-side) but does not prevent the client from independently painting the error at 90s. **File a follow-up issue at ship to forward `tool_progress` to the client on the cc surface — unconditionally, not gated on "if it proves user-visible" (it is already known-reachable).**

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with a concrete artifact, vector, and `single-user incident` threshold.
- happy-dom (vitest jsdom-equivalent) does NOT implement `scrollTop`/`scrollHeight`/`scrollIntoView` — the autoscroll test must mock them or it tests nothing.
- The new component test MUST live at `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` — vitest collects `test/**/*.test.tsx`, NOT co-located `components/**/*.test.tsx`.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT `npm run -w` (no root `workspaces` field).
- The `tool_progress` reset must touch `state.runaway` ONLY, never `state.turnHardCap` — the 10-min absolute ceiling is a deliberate chatty-stall defense (PR #3225) and is load-bearing for the hard-cap regression guard (existing `:604` test).
- `stickToBottom` MUST be a `useRef`, not `useState` — state re-renders on every scroll event and risks a stale-closure read inside the `events`-keyed effect.
- Use `ul.scrollTop = ul.scrollHeight`, NOT `scrollIntoView` — in a nested `overflow-y-auto` list, `scrollIntoView` also scrolls ancestor containers, yanking the whole page to surface the last `<li>`.
- The Phase 0.2 test-enumeration grep is mandatory (per the cited `2026-05-05` learning §Sub-Lesson 6) — changing the watchdog reset *semantic* can break a test that pinned the old contract; enumerate, do not sample.
