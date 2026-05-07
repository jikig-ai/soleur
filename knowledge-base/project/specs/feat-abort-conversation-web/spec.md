---
title: Abort Conversation in Web Application
feature: feat-abort-conversation-web
date: 2026-05-07
status: Spec Drafted
brainstorm: knowledge-base/project/brainstorms/2026-05-07-abort-conversation-web-brainstorm.md
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Spec: Abort Conversation in Web Application

## Problem Statement

The Soleur Command Center web app (`apps/web-platform/`) has no user-facing way to abort an in-flight assistant turn. Users today can only kill a conversation by closing the browser tab, which (a) silently discards any partial assistant output the user has already paid for in BYOK tokens, (b) marks the entire conversation as `failed` even though the user only wanted to stop the current turn, and (c) provides no way to interrupt a runaway sub-agent that may continue consuming the user's API key for minutes after the tab is closed if the SDK doesn't propagate the abort signal to spawned tools.

Recurring support patterns (#2855, #3382, #3044, #3429, #3040, #3335) confirm that "stuck" / "won't end" conversations are a real user-impact issue. Plugin/CLI users have `Ctrl+C` parity; web users do not.

## Goals

- **G1.** A user can stop the current assistant turn from the browser without losing the conversation.
- **G2.** Stop is honest about what was undone vs. what already completed (no silent post-Stop side effects, no hidden token charges).
- **G3.** Cross-user blast radius is provably zero: a Stop click on user A's conversation cannot affect user B's stream.
- **G4.** Existing tab-close abort path is corrected (today's silent partial-text discard + wrong `failed` status are bugs even without new UI).
- **G5.** Legal documents accurately describe what happens on abort: T&C §5 has a metered-usage / partial-consumption clause; Privacy Policy §4.2 lists conversation transcripts as a processing category.

## Non-Goals

- **NG1.** Hard rollback of completed side-effecting tool calls (no auto-revert of git pushes, Supabase writes, MCP calls, or file writes that already landed). Rollback is its own design problem; for v1 we surface what completed and let the user decide.
- **NG2.** "Stop all my running conversations" multi-conversation kill switch. v1 is per-conversation only.
- **NG3.** Refund flows for tokens consumed before Stop. Disclosure (the abort marker copy + T&C §5 update) is the v1 contract; user-initiated refund requests fall under the existing discretionary-refund policy in T&C §5.4.
- **NG4.** Stopping a conversation from a different device/tab than the one it's running in. Abort is bound to the active WebSocket session.
- **NG5.** Edit-and-retry affordance on the aborted assistant message. Possible follow-up; out of scope here.

## Functional Requirements

### Server (PR1)

- **FR1.** A new client→server WebSocket message variant `{ type: "abort_turn", conversationId }` is added to `apps/web-platform/lib/types.ts` and dispatched in `apps/web-platform/server/ws-handler.ts` `handleMessage`. The handler resolves `userId` from the authenticated socket session (NOT from the client payload) before calling `abortSession(userId, conversationId)` — this is the load-bearing cross-user invariant.
- **FR2.** A new server→client variant `{ type: "session_ended", reason: "user_aborted" }` (the field already exists as a free-string) is sent by `agent-runner.ts` when `controller.signal.aborted` is observed and the abort reason was user-initiated.
- **FR3.** `agent-runner.ts` abort branch is split: user-initiated abort persists the **turn** with `messages.status='aborted'` and flips the **conversation** to `waiting_for_user` (the same continuable terminus the result branch writes on a normal turn complete). Only disconnect / SIGTERM aborts mark the conversation `failed`. (Plan-time correction: the Conversation status enum has no `active`-as-continuable semantic; `waiting_for_user` is the right terminus.)
- **FR4.** Partial assistant output accumulated in `fullText` (`agent-runner.ts:351`) is persisted as an assistant message with status `aborted` on user-initiated abort. The persisted message includes a `usage` snapshot (input/output tokens, USD cost) captured at abort time and a `completed_actions` array listing tool calls that resolved before abort landed.
- **FR5.** `controller.signal` is wired into the Agent SDK `query()` call in `agent-runner.ts:204-348` so cancellation is preemptive (best-effort cancel of the underlying Anthropic stream + spawned tools). If the SDK does not accept a signal in this version, fall back to cooperative-at-message-boundary and document the runaway-sub-agent ceiling (see TR3).
- **FR6.** The error message string used in `controller.abort()` differentiates `Session aborted: user disconnected` (today's only string) from `Session aborted: user requested stop`. `error-sanitizer.ts` allowlists both so the user-facing message renders correctly.
- **FR7.** `abort_turn` is idempotent: a second click while `[stopped by user]` is already settled is a no-op (existing `abortSession` no-op-on-missing-session behavior at `agent-runner.ts:63-66` covers this; verify the WS handler does not log spurious errors).

### Client (PR2)

- **FR8.** `useWebSocket` (`apps/web-platform/lib/ws-client.ts`) exposes a new `abort()` method that sends `{ type: "abort_turn", conversationId }` over the existing socket and locally transitions the streaming UI to a `stopping` state.
- **FR9.** During streaming, the chat surface (`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` and the relevant chat-input component) replaces the Send button with a Stop button. Click → `useWebSocket.abort()`.
- **FR10.** While a stream is active, pressing `Esc` invokes `useWebSocket.abort()`. The shortcut is scoped to the chat surface and disabled when no stream is active. (Per AGENTS.md `cq-ref-removal-sweep-cleanup-closures`: the `useEffect` cleanup MUST clear any keyboard-listener refs, abort-controller refs, and RAF/throttle timers on unmount; grep the ref name in the same file before removing.)
- **FR11.** On receipt of `{ type: "session_ended", reason: "user_aborted" }`, the client renders an abort marker on the partial assistant message showing: `[stopped by user]`, input/output token counts, USD cost (or "included in your plan" for non-BYOK plans), and a chip-list of any tool calls that completed before stop. The marker copy is the load-bearing user-disclosure surface (see legal coverage below).
- **FR12.** After abort settles, the chat input is re-enabled and the conversation is editable; the user can immediately send a new turn or scroll to the prior user message. No reload required.

### Legal (PR1)

- **FR13.** `docs/legal/terms-and-conditions.md` §5 adds a metered-usage / partial-consumption clause covering: (a) tokens generated before Stop are billed, (b) side-effecting tool calls already dispatched are not auto-reversed, (c) discretionary-refund posture from §5.4 still applies.
- **FR14.** `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy mirror) is updated in sync with FR13 — both files are kept identical per the existing T&C process.
- **FR15.** `docs/legal/privacy-policy.md` §4.2 adds "conversation transcripts (including partial assistant outputs from aborted turns)" to the Web Platform data inventory, with retention rules matching existing transcript handling and a cross-reference to GDPR Art. 17 erasure rights in §7.
- **FR16.** Both legal-doc updates are reviewed by the `legal-compliance-auditor` agent before merge.

## Technical Requirements

- **TR1.** Database migration: extend `messages.status` enum (or equivalent column) to include `aborted`. Add or verify a `usage` JSONB column on `messages` that can store input/output tokens, USD cost, and a `completed_actions` array. Migration must be backward-compatible (additive; existing `streaming` / `complete` rows are unchanged).
- **TR2.** No new transport. The existing WebSocket connection carries the new `abort_turn` and `session_ended` variants. No HTTP route handler changes.
- **TR3.** SDK signal verification: at plan time, query Context7 (`@anthropic-ai/claude-agent-sdk@^0.2.80`) to confirm whether `query({ options: { signal } })` is supported and whether the SDK propagates the signal to (a) the underlying Anthropic streaming HTTP `fetch`, (b) `PreToolUse`-launched Bash processes inside the bubblewrap sandbox, (c) the `Agent` tool's spawned sub-agents. Encode the answer in the plan; if any of (a)/(b)/(c) is unsupported, document a per-turn wall-clock budget so a runaway sub-agent has a hard upper bound on the user's BYOK key.
- **TR4.** Cross-user invariant: the abort_turn handler in `ws-handler.ts` MUST read `userId` from the server-resolved socket session (already present at `ws-handler.ts:262-322`) and never trust a client-supplied userId. A unit test asserts that an abort message with a forged `userId` field is silently dropped or aborts only the *socket's own* session.
- **TR5.** Partial-output persistence is exactly-once: the abort handler at `agent-runner.ts:401-411` MUST call the existing `saveMessage` path (today only invoked at SDK `result`) and a duplicate save from a late `result` event arriving after abort is suppressed. Race-window guard: check the `streamState` field as the single source of truth (per learning `2026-03-02-telegram-streaming-repurpose-status-message`).
- **TR6.** Abort error messages flow through `error-sanitizer.ts` allowlist; both `Session aborted: user disconnected` and `Session aborted: user requested stop` MUST be on the allowlist before they reach client code.
- **TR7.** Fire-and-forget promise hygiene per learning `2026-03-20-fire-and-forget-promise-catch-handler.md`: every async path involved in start/abort/persist is wrapped in `.catch` to avoid Node 22 `--unhandled-rejections=throw` killing the server for all connected users on a single abort error.
- **TR8.** Safety-net timers use manual `setTimeout` + `.unref()` (NOT `AbortSignal.timeout()`) per learning `2026-03-20-review-gate-promise-leak-abort-timeout.md`.
- **TR9.** Test coverage:
  - Server: abort-turn handler dispatches to `abortSession`; partial-text persistence; status split (turn vs conversation); cross-user invariant unit test; idempotency.
  - Client: Stop button click triggers abort message; `Esc` shortcut triggers abort message; abort marker renders token cost and completed-actions list; double-click safety.
  - End-to-end (Playwright via `soleur:test-browser`): user starts a turn, clicks Stop, sees abort marker, sends a follow-up message in the same conversation.
- **TR10.** Sentry observability: any silent fallback or error path in the abort flow mirrors `logger.error`/`warn` to Sentry via `reportSilentFallback(err, { feature: "abort-turn", op, extra })` per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`. The abort path is exactly the kind of "degraded condition that returns to the user" the rule covers.

## Sequencing

Two PRs, in order:

1. **PR1 — Server correctness + DB + legal docs.** All FR1–FR7, FR13–FR16, TR1, TR3–TR8, TR10. Independently shippable: fixes today's silent-discard bug class on the existing tab-close abort path before any new UI lands. Reviewers: `code-reviewer`, `architecture-strategist`, `kieran-rails-reviewer`, `user-impact-reviewer` (mandatory per `single-user incident` threshold), `legal-compliance-auditor`. ADR optional (run `/soleur:architecture create "Conversation abort semantics and partial-output persistence"` if scope warrants).
2. **PR2 — Client UI.** FR8–FR12, the relevant subset of TR9 (client + e2e). Reviewers: `code-reviewer`, `kieran-rails-reviewer`, `user-impact-reviewer`, plus `soleur:qa` browser walkthrough.

## Acceptance Criteria

- AC1. With a turn streaming, clicking Stop or pressing `Esc` aborts within 250ms (UI transitions to `stopping` immediately; server-side abort completes within 1s under nominal load).
- AC2. After Stop settles, the partial assistant message is visible in the conversation marked `[stopped by user]`, with input/output token count and USD cost displayed, and a chip-list of any side-effecting tool calls that completed before abort landed.
- AC3. After Stop settles, the chat input is enabled and the user can immediately send a follow-up message in the same conversation. The conversation is NOT marked `failed`.
- AC4. Cross-user invariant: a forged `abort_turn` message claiming a different `userId` aborts only the sender's own session (or is silently dropped). Unit test in place.
- AC5. Closing the browser tab during a stream still aborts the session AND now persists partial assistant text with the same `aborted` status used for user-initiated abort. Conversation is no longer marked `failed`.
- AC6. T&C §5 metered-usage clause and Privacy Policy §4.2 transcript entry are merged in PR1, reviewed by `legal-compliance-auditor`, and present in both `docs/legal/` and `plugins/soleur/docs/pages/legal/` mirrors.
- AC7. No unhandled promise rejection during 100 consecutive abort+restart cycles in CI integration test.
- AC8. Sentry receives a structured event for any abort-path error (not just pino logs).

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SDK does not accept `AbortSignal` in `query()` | Medium | Medium | Plan-time Context7 verification (TR3); fallback to cooperative-at-message-boundary with documented per-turn wall-clock ceiling and an SDK feature request. |
| Partial-text persistence races with late `result` event | Medium | Medium | `streamState` single source of truth (TR5); idempotent `saveMessage` guarded by status. |
| Abort marker copy under-discloses (CLO transparency risk) | Low | High | Marker copy reviewed by `legal-compliance-auditor` alongside T&C/Privacy updates; copy is the load-bearing disclosure surface. |
| Stop button + `Esc` listener leaks (cleanup miss) | Low | Low | AGENTS.md `cq-ref-removal-sweep-cleanup-closures` enforced; grep ref names in same file before removing. |
| Forged `userId` cross-user abort | Low | Critical | TR4 server-resolved userId; unit test; review-time `user-impact-reviewer` mandatory. |

## Rollout

- PR1 lands behind no flag (server-side correctness fixes today's bug class — safer to land than not). Sentry watch for unhandled rejections on the abort path during the 24h window after merge.
- PR2 lands behind a feature flag at first (`flags.web_abort_turn`) for a 24-48h dogfood window, then defaults on. The flag covers the new UI; the server already speaks `abort_turn` from PR1.
- No data backfill required (additive `aborted` status; existing rows untouched).

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-abort-conversation-web-brainstorm.md`
- Repo paths: `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/server/ws-handler.ts`, `apps/web-platform/server/review-gate.ts`, `apps/web-platform/lib/ws-client.ts`, `apps/web-platform/lib/types.ts`, `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Legal: `docs/legal/terms-and-conditions.md` §5, `docs/legal/privacy-policy.md` §4.2, `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
- Precedents: PR #1610, #1554, #1197, #922, #840, #1989
