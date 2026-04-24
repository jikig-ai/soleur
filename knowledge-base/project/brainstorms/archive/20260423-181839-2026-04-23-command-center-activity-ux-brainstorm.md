---
name: command-center-activity-ux
description: Brainstorm for Command Center activity display — replace raw commands/paths with verb-based labels, fix "Agent stopped responding" regression via SDKToolProgressMessage heartbeat forwarding.
type: brainstorm
date: 2026-04-23
issue: "#2861"
status: decided
---

# Command Center Activity UX — Brainstorm

**Domain:** Engineering + Product
**Branch:** `feat-command-center-activity-ux`
**Draft PR:** #2860

## What We're Building

Two tightly-coupled improvements to the web-platform Command Center activity display:

1. **Verb-based activity labels** — replace raw echoes like `Running: ls /tmp/claude-1001/-workspaces-754ee124-…` with deterministic server-derived phrases ("Exploring project structure", "Reading `_includes/base.njk`", "Searching for 'tool_progress'"). Also strip repo-internal paths from assistant-text output rendered in the chat.

2. **Fix post-#2843 "Agent stopped responding" regression** — a long-running single tool call (Bash, Grep over knowledge-base, large Read) starves the client's 45-second stuck-watchdog and flips the bubble to a terminal `error` state. Forward the SDK's `SDKToolProgressMessage` heartbeats from `agent-runner.ts` as a new `tool_progress` WS event; state machine resets the stuck timer on it without changing bubble state.

Same PR also adds a single auto-retry with visible "Retrying…" indicator before the terminal "Agent stopped responding" chip, so transient failures don't surface as hard stops.

## Why This Approach

**Root cause of the regression is NOT a #2843 regression.** PR #2843 fixed the `stream_end` emission in exception paths and the reducer's `review_gate` sweep. But the `STUCK_TIMEOUT_MS = 45_000` watchdog in `ws-client.ts:70` + `applyTimeout` in `chat-state-machine.ts:239` fires on any quiet window during a bubble's `thinking`/`tool_use` state. `tool_use` fires only when the model *issues* the call; actual tool execution (sandbox Bash, Grep, Read) runs silent from the client's POV. The SDK already emits `SDKToolProgressMessage` with `elapsed_time_seconds` heartbeats — `rg` across `agent-runner.ts` confirms zero forwarding. Forwarding them as a no-state-change timer-reset event is architecturally consistent with #2843's "reset on any activity" discipline and is the minimal correct fix.

**Server-side label derivation (approach A) beats system-prompt-emitted progress notes (approach B).**

- A is deterministic and testable (single edit site: extend `server/tool-labels.ts`).
- B is probabilistic — agent compliance with "emit a progress note before every tool_use" is greenfield with no prior data; failure mode is silent stuck-looking bubbles.
- Open issue #2854 (Command Center delegates to `/soleur:go`) would likely subsume B's design via coarser phase-level events. Shipping B now risks throwaway work.

**Client-side render-time scrub for assistant text (not server stream-time).** Server-side scrubbing would corrupt `conversation_messages` in Supabase, cost-tracking token counts, SDK `resume-session` replay, and Sentry breadcrumbs — the message would diverge from what the model actually said. Client-side `formatAssistantText(raw)` in the bubble renderer preserves verbatim storage.

**Allowlist-with-fallback labeling** mirrors the `error-sanitizer.ts` precedent (learning `2026-03-20-websocket-error-sanitization-cwe-209.md`): known tools/verbs → specific phrases; unknown → generic "Working…" fallback. Never emit raw command.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Stopped-responding fix | Forward `SDKToolProgressMessage` → new `tool_progress` WS event → state machine resets stuck timer, no state change | Root cause is client-side watchdog starvation during long tool execution; SDK already emits heartbeats, just not forwarded |
| Label derivation site | Server: extend `apps/web-platform/server/tool-labels.ts` | Deterministic, one-site, already the established pattern (PR #2428) |
| Approach B (agent-emitted progress notes) | **Dropped** — not in this PR | System-prompt compliance is probabilistic; #2854 may subsume it; ship deterministic A, revisit only if A proves insufficient |
| Assistant-text path scrub | Client-side render only | Server scrub corrupts conversation history, cost tracking, replay, Sentry breadcrumbs |
| Scrub default | On by default, `reportSilentFallback` on unmatched sandbox-shape patterns | Protects dogfood-screenshot surface; unmatched patterns surface via Sentry as observability signal per `cq-silent-fallback-must-mirror-to-sentry` |
| Path-strip coverage | Both host (`/workspaces/<uuid>/…`) and sandbox-mapped (`/tmp/claude-<uid>/-workspaces-<uuid>/…`) | Sandbox path is what the model sees and quotes back; current stripper only matches host form |
| Label shape | Allowlist: known tool+arg shapes → specific verb-based label; unknown → "Working…" | Mirrors `error-sanitizer.ts`; never emit raw command or tool JSON |
| "Agent stopped responding" UX | One auto-retry with visible "Retrying…" indicator, then terminal error with (a) what leader was doing, (b) Retry button | Balances trust (visible) with fix rate (single retry handles transient failures); no indefinite retry |
| #2853 (single-leader default routing) | **Out of scope**, no cross-reference | Tracks independently; brainstorm stays tight on labels + stopped-responding only |
| Architecture decision record | Capture server-side-derivation vs system-prompt-emission trade-off via `/soleur:architecture create` during work phase | CTO-flagged — prevents future drift if B is revived |
| Success metric | Count raw-path leaks (fallthrough hits in scrubber) per session, target trend to zero | Observable via Sentry breadcrumbs from `reportSilentFallback` |

## Non-Goals

- **Approach B (agent-emitted progress notes) in this PR** — deferred indefinitely; may be subsumed by #2854.
- **Single-leader default routing (#2853)** — stays in its own issue.
- **Command Center delegates to `/soleur:go` (#2854)** — stays in its own issue.
- **Retry of hard-failed tool calls themselves** — only the streaming/connection-level retry is in scope. Tool-level retry is a separate concern.
- **Accessibility of Retrying indicator beyond `aria-live="polite"`** — adequate for this PR; broader a11y pass is separate work.
- **Changes to `conversation_messages` storage shape, cost-tracking pipeline, or WS protocol versioning** — all covered by the "store verbatim, render-scrub" invariant.

## Open Questions

1. **SDK `SDKToolProgressMessage` shape details.** The learning file mentions `elapsed_time_seconds` but the full field set needs cross-reference against `node_modules/@anthropic-ai/claude-agent-sdk/*.d.ts` during implementation. Is the message per-tool_use_id? Does it include a `tool_name`? Affects whether the WS `tool_progress` event can carry a richer "still working on <verb>" label during long execution.

2. **Sandbox-path regex canonical set.** Observed: `/tmp/claude-<uid>/-workspaces-<uuid>/…` where `<uid>` is decimal and `<uuid>` is a 36-char dash-escaped GUID. Needs confirmation from `apps/web-platform/server/sandbox.ts` that this is the only shape, and that the bubblewrap mount never varies. Single centralized table with unit tests enumerating known patterns per CTO guidance.

3. **Assistant-text render scrub scope.** Need to preserve: fenced code blocks, backticked identifiers, URLs, GitHub `#NNNN` references (per `cq-prose-issue-ref-line-start`). Regex must only match the specific sandbox/host workspace prefix patterns, not any `/path` string.

4. **Retry trigger condition.** Should auto-retry fire on (a) any `error` terminal state, (b) only the stuck-timeout error specifically, or (c) only when server emits a specific WS close code? Preference: narrow — only the stuck-timeout path; server errors shouldn't silently retry.

## Domain Assessments

**Assessed:** Engineering, Product (CMO/COO/CLO/CRO/CFO/CCO not relevant to this narrow UX polish + bug fix)

### Product (CPO)

**Summary:** Narrow scope is correct but fragile — duplicate parallel-leader bubbles (not fixed by this PR) will make the new natural-language labels more noticeable, not less. Recommends #2853 as the natural follow-up after this PR ships. Layering: A is the floor (always renders verb label), progress-note failures must never fall through to raw output. Stopped-responding UX: single auto-retry with visible "Retrying…" before terminal error with recovery affordance. Assistant-text scrub should be client-side render with system-prompt guidance as prompt-side primary layer (agent uses repo-relative paths). Success metric: raw-path leak count per session trending to zero.

### Engineering (CTO)

**Summary:** Server-side SDK interception via extended `tool-labels.ts` is the architecturally correct site for labels (deterministic vs probabilistic system-prompt compliance). Assistant-text scrub MUST be client-side render, not server stream-time, to preserve verbatim storage for conversation history, cost tracking, SDK replay, and Sentry breadcrumbs. Stopped-responding hypothesis: most likely long-running single tool call starving the 45s client watchdog — SDK emits `SDKToolProgressMessage` heartbeats that `agent-runner.ts` does not forward. Add `tool_progress` WS event; reducer default branch must handle unknown events as no-op (test-covered) to preserve backward-compat. Approach B may be subsumed by #2854 — recommend deferring. Test matrix: sandbox-path table, client render scrub preserving code fences / URLs / `#NNNN`, chat-state-machine unknown-event default branch no-op, `agent-runner` per-leader `AbortController` isolation, `tool_progress` timer-reset forwarding.

## References

- PR #2843 — stuck-bubble lifecycle invariants (adjacent but does not address the watchdog starvation path)
- Learning: `2026-04-23-command-center-bubble-lifecycle-invariants.md`
- Learning: `2026-03-20-websocket-error-sanitization-cwe-209.md` (allowlist-with-fallback sanitization pattern)
- Learning: `2026-04-16-kb-chat-multi-leader-session-ended-tool-labels-context.md` (`buildToolLabel` precedent to extend)
- Learning: `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md` (raw SDK content leakage precedent)
- Issue #2853 — single-leader default routing (out of scope, independent follow-up)
- Issue #2854 — Command Center delegates to `/soleur:go` (out of scope, may subsume deferred approach B)
- Code: `apps/web-platform/server/tool-labels.ts` (extension site)
- Code: `apps/web-platform/server/agent-runner.ts` lines 880-940 (stream branch, `SDKToolProgressMessage` forwarding site)
- Code: `apps/web-platform/lib/chat-state-machine.ts` (reducer — add `tool_progress` no-op branch + `applyTimeout` test coverage)
- Code: `apps/web-platform/lib/ws-client.ts:70` (`STUCK_TIMEOUT_MS`)
- AGENTS.md rules: `cq-silent-fallback-must-mirror-to-sentry`, `cq-prose-issue-ref-line-start`, `cq-union-widening-grep-three-patterns`
