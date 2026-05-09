---
title: Abort Conversation in Web Application
date: 2026-05-07
status: Decided
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Brainstorm: Abort Conversation in Web Application

## What We're Building

A user-initiated **Stop** capability in the Soleur Command Center web app (`apps/web-platform/`) that aborts the current assistant turn, mirrors the muscle memory of `Ctrl+C` in the terminal/plugin, and leaves the conversation in a clean, continuable state. Trigger surfaces: a Stop button (replacing Send during streaming) **and** an `Esc` keyboard shortcut.

The plumbing is ~70% in place. `apps/web-platform/server/agent-runner.ts` already exposes `abortSession(userId, conversationId)` driven by a per-session `AbortController`, and `ws-handler.ts:357-370` already calls it on socket close (precedents: PR #1610 / #1554, PR #922 / #840, PR #1197). What is missing is a client-initiated trigger and the user-facing semantics (preserve partial output, distinguish "user-aborted turn" from "session disconnected", surface billing transparency, propagate the AbortSignal into the SDK so cancellation is preemptive rather than cooperative-at-message-boundary).

## User-Brand Impact

- **Artifact at risk:** authoritative conversation state — partial assistant message, in-flight tool side effects, BYOK token spend.
- **Vector:** a Stop click that visually implies "undone" while the model continues to generate, sub-agents continue to run on the user's API key, or already-dispatched writes (git push, Supabase mutation, MCP call, file write) silently complete.
- **Threshold:** `single-user incident`. Catastrophic outcomes — "I clicked Stop and the agent still force-pushed to main" / "Stop took 30s to register but I was charged for 50k tokens" — are brand-survival level. Visual jank is polish.

The user explicitly tagged billing surprise + data loss + cross-session leak as in-scope worst outcomes. The plan derived from this brainstorm inherits `Brand-survival threshold: single-user incident` and triggers `user-impact-reviewer` at PR review time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Why This Approach

A two-PR sequence (recommended Approach B):

- **PR1 — server correctness + DB migration + legal docs.** Wire `controller.signal` into the Agent SDK `query()` call so cancellation is preemptive. Persist partial assistant text on abort (today's silent discard is both a trust failure and a billing transparency failure). Distinguish user-initiated abort from disconnect at the conversation/turn status level so a user-aborted turn keeps the conversation `active` (today the whole conversation is marked `failed`). Bundle both legal-doc updates: T&C §5 metered-usage / partial-consumption clause and Privacy Policy §4.2 transcript processing entry. PR1 alone fixes a real existing bug class — the close-tab-during-stream path silently discards partial output and traps users in `failed` state — addressing patterns surfaced in #2855 / #3382 / #3044 / #3429.
- **PR2 — client UI.** New `WSMessage` variant `{type: "abort_turn"}` (client→server) and `{type: "session_ended", reason: "user_aborted"}` (server→client). `useWebSocket` exposes an `abort()` method. Stop button replaces Send during streaming. `Esc` keystroke binding when a stream is active. Abort marker shows partial output, token cost, USD, and a list of side-effecting tools that completed before stop landed.

The reason to split:

1. PR1 is independently shippable user value — the existing tab-close path stops marking conversations as `failed` and stops silently discarding partial text the user paid for.
2. Legal-doc review parallelizes with PR2 implementation rather than blocking it.
3. User-brand-critical features benefit from incremental rollout: each PR is reviewable, reverteable, and independently observable in production.

A single bundled PR (Approach A) was rejected because it couples legal review (days) with code review (hours) and concentrates risk in a single landing window. A three-PR split (Approach C) was rejected because legal docs that promise behavior the code doesn't yet deliver is a worse posture than bundling them with the server change that delivers it.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Scope: turn-level abort, conversation stays active** | Matches Claude.ai / ChatGPT mental model. Today's "drop WS → mark conversation `failed`" path is wrong for user-initiated stop. User can immediately type a follow-up or edit-and-retry. |
| 2 | **Side-effect promise: best-effort cancel + honest disclosure** | Wire `controller.signal` into the SDK `query()` call so the underlying Anthropic stream and any cancellable tools stop ASAP. For non-cancellable writes already dispatched (git push, Supabase mutation, MCP write), let them complete and surface them in the abort marker: "Stopped — these actions completed before stop: …". Hard rollback (Approach 2) was rejected because rollback can compound the original problem; cooperative-only (Approach 4) was rejected because a sub-agent spawned 200ms before Stop could run for minutes on the user's API key. |
| 3 | **Trigger UX: Stop button + `Esc` shortcut** | Stop button replaces Send during streaming (Claude.ai parity). `Esc` works whenever a stream is active (terminal `Ctrl+C` muscle memory). Two paths, one behavior. Slash-command rejected (chat input is disabled while streaming anyway). |
| 4 | **Persist & disclose: partial text + inline cost + completed actions** | On abort, persist what streamed as an assistant message marked `[stopped by user]`. Abort marker shows: input/output tokens consumed, USD cost (or "included in your plan"), and the list of side-effecting tool calls that completed before the abort landed. Discarding partial output (today's behavior) is both a trust failure ("user paid for tokens they never see persisted") and a CLO-flagged misleading-omission risk under EU consumer-transparency rules. |
| 5 | **Legal scope: bundle both updates with PR1** | T&C §5 needs a metered-usage / partial-consumption clause; Privacy Policy §4.2 needs a "conversation transcripts" processing entry that's load-bearing for GDPR Art. 17 erasure rights regardless of whether Stop ships. Bundling avoids a window where T&C promises behavior the code doesn't yet deliver. |
| 6 | **Two-PR sequence (Approach B)** | PR1 = server correctness + DB + legal docs; PR2 = Stop button + `Esc` + abort_turn WS message. Separates concerns; PR1 is independently shippable and fixes today's silent-discard bug class even before PR2 lands. |

## Open Questions (deferred to plan time)

- **SDK AbortSignal propagation.** Verify against `@anthropic-ai/claude-agent-sdk@^0.2.80` (via context7) whether `query({ options })` accepts an external `AbortSignal` and whether it propagates to (a) the underlying Anthropic streaming HTTP request, (b) `PreToolUse`-launched Bash processes, (c) the `Agent` tool's spawned sub-agents. If yes — a one-line wiring fix in `agent-runner.ts:204-348`. If no — file an SDK feature request, document the cooperative-at-message-boundary ceiling, and define a per-turn wall-clock budget so a runaway sub-agent on the user's BYOK key has a hard upper bound.
- **`messages.status` shape.** Today's persistence model writes the assistant message only on the SDK `result` event (`agent-runner.ts:373`). The abort path must persist `fullText` exactly once with a status that distinguishes `streaming → aborted` from `streaming → complete`. Likely shape: `enum { streaming, complete, aborted }` on `messages.status` plus a `usage` blob captured at abort time. The migration is small but warrants its own ADR.
- **Architecture decision record.** The conversation/turn status semantics will outlive this feature and shape how every future "long-running operation" is resumed/cancelled. CTO recommends running `/soleur:architecture create "Conversation abort semantics and partial-output persistence"` once the plan lands a direction.

## Capability Gaps

None. Existing engineering domain (CTO + work/plan/review) covers the code path; existing legal domain (CLO + legal-document-generator + legal-compliance-auditor) covers the T&C and Privacy Policy updates; existing review tooling (`user-impact-reviewer`, `code-reviewer`, `kieran-rails-reviewer`, `architecture-strategist`) covers the user-brand-critical review gate.

Evidence basis for "no gaps":

- `grep -n "AbortController\|AbortSignal\|abort\(\)\|abortSession" apps/web-platform/server/agent-runner.ts` returns matches at lines 54, 60-67, 158-167, 204, 354, 401-411 — full per-session abort plumbing already in place.
- `grep -n "abort\|close" apps/web-platform/server/ws-handler.ts | grep -i "ws\.on\|abortSession"` confirms the existing close-handler abort path at lines 357-370.
- `grep -n "WSMessage" apps/web-platform/lib/types.ts:14-24` confirms the WS protocol union has no `abort_turn` variant — a one-line additive change.
- Repo-research found PR #1610, #1554, #1197, #922, #840, #1989 all already in main as relevant precedents.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The plumbing is already 80% there. The gap is (a) a client-initiated WS message to call the existing `abortSession(userId, conversationId)`, (b) wiring `controller.signal` into the SDK `query()` call so cancellation is preemptive, and (c) splitting "turn aborted" (conversation stays `active`) from "session terminated" (today's `failed`). Cross-user blast-radius is strong by construction (`activeSessions` keyed by server-resolved `userId:conversationId`); confirm the new abort-message handler reads `userId` from the auth-resolved socket session, not from the client message body.

### Product (CPO)

**Summary:** Stop UX = Stop button + `Esc`. Post-abort state = conversation editable, partial assistant turn preserved with `[stopped by user]` marker. The load-bearing decision is committed-tool semantics: best-effort cancel + honest disclosure of completed-before-stop actions. The brand-survival line: any post-Stop side effect the user did not consent to.

### Legal (CLO)

**Summary:** Two gaps surface once Stop ships. (a) T&C §5 has no metered-usage / partial-consumption clause to anchor "you paid for tokens generated before Stop landed." (b) Privacy Policy §4.2 doesn't list conversation transcripts as a processing category, which is load-bearing for GDPR Art. 17 erasure rights. EU consumer-transparency rules treat a Stop button that visually implies undo while leaving side effects intact as a misleading omission. Both updates bundled into PR1.

### Marketing (CMO)

**Summary:** This is a "control & trust" message, not table-stakes parity. Frame as "you're always in control of agents you spawn." Ship as a changelog highlight + short post (not a full launch); pair thematically with BYOK and audit-log into a future "You own the loop" pillar. Absence is an active negative signal for power users.

### Support (CCO)

**Summary:** Real recurring "conversation won't end" pain (#2855, #3382, #3044, #3429, #3040, #3335). Server-side reapers exist; user-facing abort does not. One FAQ entry covers launch documentation needs.

## References

- Repo research: `apps/web-platform/server/agent-runner.ts:54,60-67,158-167,204-348,354,401-411`
- Repo research: `apps/web-platform/server/ws-handler.ts:47-51,102-216,262-322,357-370`
- Repo research: `apps/web-platform/server/review-gate.ts:8-52`
- Repo research: `apps/web-platform/lib/ws-client.ts:33-49,86-226,261-290`
- Repo research: `apps/web-platform/lib/types.ts:14-24`
- Repo research: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Prior precedent: PR #1610 / #1554 (SIGTERM abort), PR #922 / #840 (review-gate abort), PR #1197 / #1194 (abort before conv replace), PR #1989 (XHR abort for uploads)
- Learning: `knowledge-base/project/learnings/2026-03-20-review-gate-promise-leak-abort-timeout.md` — manual `setTimeout`/`clearTimeout` with `.unref()` for safety-net timers; allowlist abort error messages in `error-sanitizer.ts`
- Learning: `knowledge-base/project/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md` — wrap every fire-and-forget abort/start promise with `.catch` (Node 22 `--unhandled-rejections=throw`)
- Learning: `knowledge-base/project/learnings/2026-03-20-websocket-first-message-auth-toctou-race.md` — re-check `ws.readyState` and session-ID equality after every async hop
- Learning: `knowledge-base/project/learnings/runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md` — null-out before async delete for idempotent cleanup; double-click safety
- Learning: `knowledge-base/project/learnings/2026-03-02-telegram-streaming-repurpose-status-message.md` — `streamState` field as single source of truth for partial-message lifecycle
- AGENTS.md: `cq-ref-removal-sweep-cleanup-closures` (client React: grep ref name in same file before removing; covers Stop-button useEffect cleanup)
- AGENTS.md: `hr-weigh-every-decision-against-target-user-impact` (this brainstorm satisfies Phase 0.1)
- Legal: `docs/legal/terms-and-conditions.md` §5 (Subscriptions, Cancellation, Refunds), `docs/legal/privacy-policy.md` §4.2 (Web Platform data inventory), `docs/legal/disclaimer.md`
