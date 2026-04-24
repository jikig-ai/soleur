# Feature: command-center-activity-ux

**Brainstorm:** [`2026-04-23-command-center-activity-ux-brainstorm.md`](../../brainstorms/2026-04-23-command-center-activity-ux-brainstorm.md)
**Draft PR:** #2860
**Branch:** `feat-command-center-activity-ux`

## Problem Statement

The web-platform Command Center activity display leaks internal sandbox paths and raw shell commands into user-visible bubbles and assistant-text output (e.g., `Running: ls /tmp/claude-1001/-workspaces-754ee124-706a-4f21-a4f4-e828257b0380…` and `/workspaces/<uuid>/_includes/base.njk` in assistant prose). The surface is used as the primary driver for Soleur's own development — visible decay directly affects the dogfooding feedback loop.

Separately, post-PR-#2843 deploy, the "Agent stopped responding" terminal chip still surfaces when a leader runs a single long tool call (Bash, Grep over knowledge-base, large Read). Root cause traced: client-side `STUCK_TIMEOUT_MS = 45_000` watchdog (`ws-client.ts:70` + `applyTimeout` in `chat-state-machine.ts:239`) starves during tool execution because `tool_use` fires only when the model *issues* the call, not during execution. The SDK's `SDKToolProgressMessage` heartbeats are not forwarded — this is an architectural gap distinct from #2843's stream-end emission fix.

## Goals

- Replace raw shell commands and internal paths in Command Center activity bubbles with deterministic, verb-based natural-language labels derived server-side from `tool_use.input`.
- Prevent repo-internal sandbox and host workspace paths from appearing in assistant-text output rendered in the chat, without corrupting the verbatim model message stored in `conversation_messages`.
- Eliminate the "Agent stopped responding" false-terminal state during long-running single tool calls by forwarding SDK tool-progress heartbeats as a client-watchdog-resetting WS event.
- Surface transient stream failures via a single auto-retry with visible "Retrying…" indicator before the terminal error chip; terminal state must show what the leader was doing and offer a Retry affordance.
- Instrument unmatched path-scrub patterns via `reportSilentFallback` so new sandbox shapes surface as Sentry observability, not user-visible leaks.

## Non-Goals

- **Agent-emitted progress notes via system prompt (approach B from brainstorm)** — dropped; system-prompt compliance is probabilistic and #2854 may subsume the design space.
- **Single-leader default routing (#2853)** — tracks independently; this spec does not change domain-routing behavior.
- **Command Center delegates to `/soleur:go` (#2854)** — architectural change, out of scope.
- **Tool-level retry** — only the streaming/connection-level auto-retry is in scope; hard-failed tool calls are not re-executed.
- **WS protocol versioning / `protocol_version` negotiation** — noted as a future concern; this spec requires only that the `chat-state-machine` reducer default branch handle unknown event types as no-op to preserve backward-compat.
- **Changes to `conversation_messages` storage, cost-tracking pipeline, or SDK `resume-session` payload** — preserved by the "store verbatim, render-scrub" invariant.
- **Accessibility pass beyond `aria-live="polite"` on the Retrying indicator** — broader a11y work is separate.

## Functional Requirements

### FR1: Verb-based activity labels

Activity bubbles in the Command Center display verb-based, path-stripped phrases instead of raw shell commands.

- `Read` / `Edit` / `Write` with a known repo-relative path → `Reading <rel>…` / `Editing <rel>…` / `Writing <rel>…`.
- `Bash` commands → mapped via allowlist: `ls` / `find` / `rg` / `grep` / `cat` / `git` / `gh` / `npm` / `doppler` / `terraform` → verb-based phrasing (e.g., `Exploring project structure`, `Searching for '<pattern>'`). Unknown commands → generic `Running command…`.
- `Grep` / `Glob` → `Searching for '<pattern>'…` / `Finding <pattern>…` (already implemented; extend sandbox-path coverage).
- Any unknown tool or unparseable input → `Working…` fallback. **Never emit raw command or tool JSON.**

### FR2: Sandbox-path stripping

The label pipeline strips both host workspace paths (`/workspaces/<uuid>/…`) and sandbox-mapped paths (`/tmp/claude-<uid>/-workspaces-<uuid>/…`) from tool-label text before rendering.

- A centralized canonical regex set lives alongside `tool-labels.ts` with a unit test enumerating all known patterns.
- Unmatched path-shape fallthrough is reported to Sentry via `reportSilentFallback({ feature: "command-center", op: "tool-label-scrub" })`.

### FR3: Assistant-text render scrub

Assistant-message text is stored verbatim but rendered with a client-side scrub that removes sandbox and host workspace path prefixes.

- Scrub runs in the chat message-bubble renderer, not on the server stream.
- Preserves fenced code blocks, inline backticked identifiers, URLs, and GitHub `#NNNN` references.
- Fallthrough hits (text matching a leaked-path suspect but not a known prefix) mirrored to Sentry via `reportSilentFallback`.
- Default: **on**. No user toggle.

### FR4: `tool_progress` WS event — long-tool watchdog fix

Server forwards SDK `SDKToolProgressMessage` heartbeats to the client as a new `tool_progress` WS event.

- `chat-state-machine` reducer handles `tool_progress` as a timer-reset-only no-state-change event.
- Reducer default branch returns `state` unchanged (no-op) on any unknown event type — covered by a RED test to guarantee backward-compat.
- Client bubble state is unaffected by `tool_progress`; only the stuck-watchdog resets.

### FR5: Single auto-retry before terminal "Agent stopped responding"

When the stuck-watchdog fires (45s silence on a bubble in `thinking`/`tool_use`), the client performs a single auto-retry attempt.

- Transitional state shows a `Retrying…` indicator with `aria-live="polite"`.
- On second failure, transitions to terminal `error` state with (a) the last known activity label for that leader, (b) a Retry button, (c) a `File an issue` link pre-populated with session context.
- Narrow trigger: only fires on the stuck-timeout path. Server-emitted errors (agent-runner exception, session ended with error) do NOT trigger auto-retry.

## Technical Requirements

### TR1: Extension site — `apps/web-platform/server/tool-labels.ts`

All server-side label derivation extends the existing `buildToolLabel` function. No parallel label module.

- Extend `stripWorkspacePath` to match both host (`/workspaces/<uuid>/…`) and sandbox (`/tmp/claude-<uid>/-workspaces-<uuid>/…`) prefixes.
- Add a `mapBashVerb(command)` helper implementing the allowlist table (FR1).
- Allowlist-with-fallback shape per `error-sanitizer.ts` precedent (learning `2026-03-20-websocket-error-sanitization-cwe-209.md`).

### TR2: SDK-event forwarding — `apps/web-platform/server/agent-runner.ts`

Forward `SDKToolProgressMessage` events inside the existing `stream_event` branch (around lines 880-940).

- Emit a new WS event shape: `{ type: "tool_progress", leaderId, toolUseId, elapsed_time_seconds }`. Exact field set confirmed against `@anthropic-ai/claude-agent-sdk` `.d.ts` during implementation.
- Guard with the same `streamStartSent` idempotency check PR #2843 introduced so `tool_progress` never lands before `stream_start`.

### TR3: State-machine changes — `apps/web-platform/lib/chat-state-machine.ts` and `lib/ws-client.ts`

- Add a `tool_progress` reducer branch that resets the bubble's stuck-timer (`pendingTimerAction`) without mutating bubble `state`.
- Guarantee the reducer's default branch returns `state` unchanged for any unknown event type (RED test).
- `applyTimeout` branch adds a retry-attempt counter to the bubble state; first timeout transitions to `retrying`, second timeout transitions to `error` per FR5.

### TR4: Client-side render scrub — chat message-bubble renderer

Introduce `formatAssistantText(raw, { reportFallthrough })` as a pure function co-located with the renderer.

- Pure: same input → same output, no IO on the happy path.
- Fallthrough reporter is the only IO, invoked only when text contains a suspected leaked path that doesn't match a known prefix.
- `conversation_messages` stores `raw`; render pipeline computes `formatted`.
- Replay via SDK `resume-session` and cost-tracking token counts operate on `raw` (unchanged).

### TR5: Observability — `reportSilentFallback` instrumentation

Every fallthrough path (unknown Bash verb, unmatched sandbox prefix, unknown event type in reducer default branch) mirrors to Sentry via the project's existing `reportSilentFallback` helper per `cq-silent-fallback-must-mirror-to-sentry`.

- Feature tag: `"command-center"`.
- Op tag: `"tool-label-fallback"` / `"asstext-scrub-fallthrough"` / `"ws-unknown-event"`.
- Used as the success metric — raw-path leak trend over time.

### TR6: Test coverage

Expanded test matrix covers:

- `tool-labels.test.ts`: sandbox-path stripping table (host, sandbox-mapped, no-match fallback); Bash verb allowlist table; unknown-command fallback to `Running command…`; idempotency (double-scrub = single-scrub).
- Client `formatAssistantText.test.tsx`: path scrub preserves code fences, backticked identifiers, URLs, `#NNNN` refs; round-trip raw→formatted does not mutate source.
- `chat-state-machine.test.ts`: `tool_progress` branch is no-op on bubble state but resets `pendingTimerAction`; unknown event type default branch is no-op; `applyTimeout` retry counter transitions (`thinking` → `retrying` → `error`).
- `agent-runner.test.ts`: `SDKToolProgressMessage` forwards to client as `tool_progress`; `streamStartSent` idempotency preserved; per-leader `AbortController` isolation (abort one, assert the other's stream continues and emits `stream_end`).

### TR7: Architecture Decision Record

Before implementation fans out, run `/soleur:architecture create "Command Center progress-label derivation strategy"` to capture the server-side-derivation vs. system-prompt-emission trade-off so the deferred approach B decision is durable.

## Acceptance Criteria

- [ ] No raw sandbox or host workspace path appears in any Command Center activity bubble label under the tested tool matrix.
- [ ] No raw sandbox or host workspace path appears in rendered assistant-text output for the tested leak patterns; `conversation_messages` row content equals the verbatim model output.
- [ ] A long-running Grep or Bash call exceeding 45 seconds does NOT flip the bubble to `error` state, as long as `SDKToolProgressMessage` heartbeats are flowing.
- [ ] When the stuck-watchdog does fire, the bubble transitions to `retrying` with a visible indicator before any terminal `error` state.
- [ ] Unknown WS event types received by the `chat-state-machine` reducer do not mutate state (RED test covering the default branch).
- [ ] `reportSilentFallback` fires on each of: unknown Bash verb, unmatched sandbox-prefix, WS unknown-event; all tagged with `feature: "command-center"`.
- [ ] All existing Command Center tests continue to pass (`./node_modules/.bin/vitest run` from `apps/web-platform/`, ~2322 cases at brainstorm time).
