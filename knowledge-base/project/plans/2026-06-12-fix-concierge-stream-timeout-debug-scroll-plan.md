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
| "the debug stream kept moving (`cat` commands) but the stream stopped and connection dropped" | Two SEPARATE timers exist: a CLIENT 45s `STUCK_TIMEOUT_MS` (reset by `tool_use`/`tool_progress` in `chat-state-machine.ts:486,522`) and a SERVER 90s `armRunaway` idle window (`soleur-go-runner.ts:1779`). The "stopped responding" card and the `runner_runaway` workflow-end come from the SERVER timer, NOT the client one. | Fix targets the SERVER `armRunaway` reset surface. The client timer is already heartbeat-fed and is not the bug. |
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

**The SDK emits a finer-grained forward-progress signal during this window that the runner currently drops.** `chat-state-machine.ts:490-532` already consumes a `tool_progress` event ("FR4 (#2861): SDK heartbeat for long-running tool execution") and uses it to reset the CLIENT 45s watchdog (`timerAction: { type: "reset" }`). The server runner has the symmetric blind spot: it does not re-arm `state.runaway` on the same heartbeat. **The fix is to feed the server idle watchdog from the SDK's mid-tool forward-progress signal**, exactly as `handleUserMessage` already does for `tool_use_result`.

### Defect 2 — Debug stream panel has no autoscroll

`debug-stream-panel.tsx:156` renders entries oldest-at-top into a `<ul className="max-h-72 overflow-y-auto">` with **no ref and no scroll effect** (confirmed: the panel has zero `useRef`/`useEffect`/scroll logic). Entries arrive append-bottom (`chat-state-machine.ts:1044`, `messages: [...prev, debugMsg]`). The operator must scroll down to see new entries.

The chat message list already has an **unconditional** autoscroll precedent at `chat-surface.tsx:303-305` (`messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })` on `[messages]`). The debug panel needs the **sticky** variant: pin only when the user is already at the bottom.

## 🛠️ Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

0.1 Re-read `apps/web-platform/server/soleur-go-runner.ts` around `handleUserMessage` (`:2032-2058`) and the SDK message dispatch loop (`:2150-2180`, the `// Other SDKMessage variants (partial assistant, hook, task notifications) are ignored at V1` comment at `:2171-2172`). **Confirm the exact SDK message discriminator for the mid-tool forward-progress / partial signal** (`stream_event`, `partial_assistant`, or the SDK's `tool_progress`-equivalent) by reading the installed SDK's type file: `grep -nE "stream_event|partial|tool_progress|SDKPartialAssistantMessage" apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/**/*.d.ts` (adjust package dir to the installed name found via `grep '"@anthropic-ai' apps/web-platform/package.json`). The reset must hook the signal the SDK actually fires DURING a single long tool execution — NOT a signal that only fires at tool boundaries (which is the current `tool_use_result` behavior that already fails to cover the gap). **Sharp edge:** per `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools`, the SDK's `.d.ts` is the source of truth for when a callback/message actually fires; do not infer from docs.

0.2 If the SDK does NOT emit any mid-tool forward-progress message (only `tool_use_result` at tool completion), the watchdog cannot be heartbeat-driven from SDK signals alone. In that case the fix is a **bounded raise of `DEFAULT_WALL_CLOCK_TRIGGER_MS` to a value that covers the worst-case single-tool wall time** (a multi-MB PDF Read + Anthropic round-trip) AND a separate, explicit naming of the ceiling that still bounds a truly-hung tool — per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`, raising the idle window dissolves the "single hung tool" detection unless the 10-min `turnHardCap` is documented as the load-bearing ceiling for that threat. Record which path (heartbeat reset vs. bounded raise) the SDK reality dictates in a `## Research Reconciliation` row in the work session-state. **Default recommendation: heartbeat reset if the SDK emits a mid-tool signal; bounded raise only as fallback.**

0.3 Confirm test runner + globs (already verified at plan time): vitest, happy-dom env, `test/**/*.test.ts` (node) + `test/**/*.test.tsx` (happy-dom) via `apps/web-platform/vitest.config.ts:43,59`. New component test MUST live under `apps/web-platform/test/components/` (co-located `components/**/*.test.tsx` is NOT collected). Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NO `npm run -w` — repo root has no `workspaces` field).

0.4 happy-dom does NOT implement `scrollIntoView`, `scrollTop`, `scrollHeight`, `clientHeight`. The autoscroll test MUST mock these (`vi.spyOn(HTMLElement.prototype, "scrollIntoView")` and define `scrollTop`/`scrollHeight`/`clientHeight` via `Object.defineProperty` on the container) — `test/setup-dom.ts` does not provide them.

### Phase 1 — Fix the server idle watchdog (TDD: RED first)

**Path A (preferred, if SDK emits a mid-tool forward-progress message):**

1.1 RED — add a failing test to `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` (the existing watchdog test surface; it already asserts `DEFAULT_WALL_CLOCK_TRIGGER_MS`, `DEFAULT_MAX_TURN_DURATION_MS`, `reason: "idle_window"` / `"max_turn_duration"` at `:507,600,604,810`). New case: a single `tool_use` block followed by N mid-tool forward-progress signals spaced < 90s apart, total elapsed > 90s, asserts `runner_runaway` does NOT fire (the forward-progress signals re-armed `state.runaway`). Use the existing fake-timer harness in that file.

1.2 GREEN — in `apps/web-platform/server/soleur-go-runner.ts`, add a handler for the SDK's mid-tool forward-progress message in the dispatch loop (near the `:2171` "ignored at V1" branch) that calls `armRunaway(state)` (guarded by `!state.closed && !state.awaitingUser`, mirroring `handleUserMessage:2034`). Do NOT touch `state.turnHardCap` — the 10-min absolute ceiling stays anchored on `firstToolUseAt` (defense pair, comment `:2028-2031`). Add a one-line comment citing this plan + the heartbeat parity with `chat-state-machine.ts` `tool_progress`.

1.3 If the runner forwards this signal to the client as a `tool_progress` WS event, confirm no double-emit / no new chip (`chat-state-machine.ts:498-500` regression guard: `tool_progress` MUST NOT spawn a chip). If the runner does NOT currently forward it, scope the WS-forward as a SEPARATE concern (the timeout fix is server-internal; forwarding is optional UX). Default: do NOT add a new WS message type in this PR — re-arm server-side only.

**Path B (fallback, if SDK has no mid-tool signal):**

1.1b RED — add a test asserting the new (higher) `DEFAULT_WALL_CLOCK_TRIGGER_MS` value and that `DEFAULT_MAX_TURN_DURATION_MS` (the 10-min ceiling) is the documented bound for a genuinely-hung single tool.
1.2b GREEN — raise `DEFAULT_WALL_CLOCK_TRIGGER_MS` (`:528`) to a value covering worst-case single-tool wall time (justify the number against the largest expected Read/round-trip; do not pick an arbitrary value). Add a comment naming `turnHardCap` as the load-bearing ceiling for a hung tool, per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`.

1.4 REFACTOR — run `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-awaiting-user.test.ts` and the full server suite touching the runner.

### Phase 2 — Debug stream sticky autoscroll (TDD: RED first)

2.1 RED — add `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` (vitest + `@testing-library/react`, matching `test/components/debug-stream-panel.test.tsx` import style at `:9-13`). Mock `scrollIntoView` + `scrollTop`/`scrollHeight`/`clientHeight` per Phase 0.4. Three cases:
- (a) New entry arrives while the container is at the bottom → `scrollIntoView` (or `scrollTop = scrollHeight`) is called.
- (b) New entry arrives while the user has scrolled up (simulate `scrollTop` well below bottom) → autoscroll is NOT triggered (scroll position not yanked).
- (c) User scrolls back to bottom → autoscroll resumes on the next entry.

2.2 GREEN — in `apps/web-platform/components/chat/debug-stream-panel.tsx`:
- Add a `useRef<HTMLUListElement>(null)` on the `<ul>` at `:156` (and/or a bottom-anchor sentinel `<li ref={endRef} />` after the `.map`, mirroring `chat-surface.tsx:839`).
- Add a `stickToBottom` ref/state, defaulting true. An `onScroll` handler on the `<ul>` sets it true when `scrollHeight - scrollTop - clientHeight < THRESHOLD` (small px tolerance), false otherwise.
- Add a `useEffect` keyed on `events` (or `events.length`) that, only when `stickToBottom` is true, scrolls to bottom (`endRef.current?.scrollIntoView({ behavior: "smooth" })` or `ul.scrollTop = ul.scrollHeight`).
- Keep entries in arrival order (oldest-at-top) — autoscroll-to-bottom is the chosen pattern (conventional log-tail), NOT reverse order. The operator explicitly preferred autoscroll.

2.3 REFACTOR — run `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel-autoscroll.test.tsx test/components/debug-stream-panel.test.tsx`.

### Phase 3 — Typecheck + full affected suite

3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-awaiting-user.test.ts test/components/debug-stream-panel.test.tsx test/components/debug-stream-panel-autoscroll.test.tsx test/chat-state-machine.test.ts test/message-bubble-retry.test.tsx` (the watchdog + debug-panel + state-machine + error-bubble surfaces).
3.3 Manual/QA: confirm the "Agent stopped responding" card no longer appears for a long single-tool turn, and the debug panel stays pinned to newest unless scrolled up.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — re-arm `state.runaway` on the SDK mid-tool forward-progress signal (Path A) OR raise `DEFAULT_WALL_CLOCK_TRIGGER_MS` + document `turnHardCap` as the hung-tool ceiling (Path B).
- `apps/web-platform/components/chat/debug-stream-panel.tsx` — sticky autoscroll-to-bottom (ref + onScroll + useEffect).
- `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` — RED test for the watchdog reset / raised-window.

## Files to Create

- `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` — sticky-autoscroll tests (3 cases).

## Open Code-Review Overlap

None — query ran at plan time (`gh issue list --label code-review --state open`). No open scope-out names `soleur-go-runner.ts` or `debug-stream-panel.tsx`. (If the work phase finds otherwise, fold-in or acknowledge per the standard disposition.)

## ✅ Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (watchdog reset / raise):** `runner_runaway` does NOT fire during a single tool execution that exceeds 90s wall-clock while the SDK emits mid-tool forward-progress (Path A), OR the idle window is raised to cover worst-case single-tool wall time with `turnHardCap` documented as the hung-tool ceiling (Path B). Verified by the new RED→GREEN test in `test/soleur-go-runner-awaiting-user.test.ts`.
- [ ] **AC2 (no regression on genuine idle):** A turn with NO assistant block, NO `tool_use_result`, AND NO forward-progress signal for > the idle window still fires `runner_runaway` with `reason: "idle_window"` (the existing `:810` assertion still passes). The fix must not blind the watchdog to a truly-stalled turn.
- [ ] **AC3 (hard cap intact):** `DEFAULT_MAX_TURN_DURATION_MS` (10 min) absolute ceiling still fires with `reason: "max_turn_duration"` even when forward-progress keeps arriving (existing `:604` test passes). The forward-progress reset touches `state.runaway` only, never `state.turnHardCap`.
- [ ] **AC4 (sticky pin):** New debug entry arriving while the `<ul>` is scrolled to the bottom scrolls the newest entry into view (test case (a)).
- [ ] **AC5 (no yank):** New debug entry arriving while the user has scrolled up does NOT move the scroll position (test case (b)).
- [ ] **AC6 (resume):** Scrolling back to the bottom re-enables sticky autoscroll on the next entry (test case (c)).
- [ ] **AC7 (order unchanged):** Debug entries remain oldest-at-top / newest-at-bottom (no reverse-order regression); the existing `debug-stream-panel.test.tsx` assertions still pass.
- [ ] **AC8 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.

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

- **Wrong SDK signal hooked (Path A):** if the handler hooks `tool_use_result` (tool-boundary) instead of a true mid-tool signal, the gap persists. Mitigation: Phase 0.1 reads the installed SDK `.d.ts` to confirm the discriminator fires DURING tool execution; the RED test exercises the >90s single-tool case specifically.
- **Defense relaxation (Path B):** raising the idle window without naming a replacement ceiling would dissolve hung-tool detection. Mitigation: Path B explicitly documents `turnHardCap` (10 min) as the bound, per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`; AC3 guards it.
- **happy-dom scroll APIs absent:** autoscroll tests silently pass/fail if scroll props are unmocked. Mitigation: Phase 0.4 mandates `Object.defineProperty` mocks; the test asserts the mock was called.
- **Precedent for the autoscroll pattern:** `chat-surface.tsx:303-305` is the in-repo precedent (unconditional `scrollIntoView`); the debug panel adds the sticky guard on top. No novel pattern.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with a concrete artifact, vector, and `single-user incident` threshold.
- happy-dom (vitest jsdom-equivalent) does NOT implement `scrollTop`/`scrollHeight`/`scrollIntoView` — the autoscroll test must mock them or it tests nothing.
- The new component test MUST live at `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` — vitest collects `test/**/*.test.tsx`, NOT co-located `components/**/*.test.tsx`.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT `npm run -w` (no root `workspaces` field).
- The forward-progress reset must touch `state.runaway` ONLY, never `state.turnHardCap` — the 10-min absolute ceiling is a deliberate chatty/hung-tool defense (PR #3225) and is load-bearing for AC3.
