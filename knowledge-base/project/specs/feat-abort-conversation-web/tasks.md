---
date: 2026-05-07
issue: 3448
plan: knowledge-base/project/plans/2026-05-07-feat-abort-conversation-web-plan.md
spec: knowledge-base/project/specs/feat-abort-conversation-web/spec.md
draft_pr: 3447
---

# Tasks: Abort Conversation in Web Application

Two-PR sequence (Approach B). PR1 = server correctness + DB + legal. PR2 = client UI.

## Phase 0 — Preflight

- [x] 0.1 — Confirm migration number is free: `ls apps/web-platform/supabase/migrations/ | sort | tail -3`. Plan assumed `040`; bump if taken.
- [x] 0.2 — Re-confirm `abortController?: AbortController` exists on the SDK Options type: `grep -n "abortController" apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts`. Should hit line ~816. If missing, halt and re-plan.
- [x] 0.3 — Identify exact tool-event name in SDK types: `grep -nE "type.*tool_use|tool_use_complete|content_block_stop" apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts | head`. Encode the actual event name into Phase 2.5.
- [x] 0.4 — Confirm `tool-use-chip.tsx` shape compatibility for the abort-marker chip-list: read the component, decide reuse-vs-new at the top of Phase 6.

## Phase 1 — RED (PR1 server tests, failing first)

- [x] 1.1 — Create `apps/web-platform/server/__tests__/abort-turn.test.ts` with Vitest scaffolding mirroring sibling test conventions.
- [x] 1.2 — Write failing test: `abortSession(userId, conv, "user_requested_stop")` calls `controller.abort` with an Error whose message contains `"user_requested_stop"`.
- [x] 1.3 — Write failing test: cross-user invariant. Mock `activeSessions` with `alice:conv1` and `bob:conv2`; simulate `handleMessage` with WS-resolved `userId="alice"` and forged `msg.userId="bob"`. Assert `aliceAbortSpy` and `bobAbortSpy` are NOT called when `conversationId="conv2"` is forged.
- [x] 1.4 — Write failing test: multi-leader broadcast. Seed `alice:conv1:cpo`, `alice:conv1:cmo`, `alice:conv1:cto`. Call `abortSession("alice", "conv1", "user_requested_stop")` (no `leaderId`). Assert all three controller.abort spies fire.
- [x] 1.5 — Write failing test: idempotency. Two consecutive `abortSession` calls; assert second is no-op (no thrown error, no second WS frame).
- [x] 1.6 — Write failing test: race-window. Simulate `result` event yielded 50ms after `controller.signal.aborted === true`; assert exactly one `saveMessage` call (the `messagePersisted` guard short-circuits the late `result` branch).
- [x] 1.7 — Write failing test: persistence with `status='aborted'`. Capture the `saveMessage` payload; assert `status: 'aborted'` and `usage.input_tokens > 0` and `usage.output_tokens > 0`.
- [x] 1.8 — Write failing test: turn-vs-conversation status split. After abort with `user_requested_stop`, conversation status is `'active'`. After abort with `disconnected`, conversation status is `'failed'`.
- [x] 1.9 — Run `cd apps/web-platform && ./node_modules/.bin/vitest run server/__tests__/abort-turn.test.ts` → all RED.

## Phase 2 — GREEN: PR1 server implementation

### 2.1 — DB migration

- [x] 2.1.1 — Create `apps/web-platform/supabase/migrations/040_message_status_aborted.sql` (or next free number from 0.1) with `ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'complete' CHECK (status IN ('complete', 'aborted'))` and `ADD COLUMN IF NOT EXISTS usage jsonb`.
- [ ] 2.1.2 — Apply locally: `supabase migration up` (or project-specific equivalent). Verify column existence: `psql -c "\d public.messages"`. (Deferred to pre-merge QA / deploy pipeline; migration file complete.)
- [ ] 2.1.3 — Verify RLS policies still apply (existing `Users can read own messages` / `Users can insert own messages` gate on `conversation_id`, not column shape). (Deferred to pre-merge QA; migration design preserves the FK-join policy.)

### 2.2 — Protocol additions

- [x] 2.2.1 — `apps/web-platform/lib/types.ts`: add `| { type: "abort_turn"; conversationId: string }` to the `WSMessage` union.
- [x] 2.2.2 — Verify `tsc --noEmit` passes from `apps/web-platform/` after the union extension.

### 2.3 — `abortSession` reason widening

- [x] 2.3.1 — `apps/web-platform/server/agent-runner.ts:142`: widen reason union to `"disconnected" | "superseded" | "user_requested_stop"`.
- [x] 2.3.2 — Confirm three-pattern grep is still clean: `grep -rEn '\.reason ===|\?\.reason ===|_exhaustive: never' apps/web-platform/server/ apps/web-platform/lib/ | grep -v abort`. No new silent-drop sites.

### 2.4 — WS handler abort_turn branch

- [x] 2.4.1 — `apps/web-platform/server/ws-handler.ts handleMessage`: add `case "abort_turn":` branch. Resolve `userId` from the authenticated socket session (NEVER from `msg.userId`). Call `abortSession(userId, msg.conversationId, "user_requested_stop")`. No `leaderId` argument — broadcast to all leader sessions.

### 2.5 — agent-runner: closure-scoped accumulators + abort branch + SDK signal wiring

- [x] 2.5.1 — In `startAgentSession`'s for-await closure, declare:
  - `let messagePersisted = false;`
  - `let accumulatedUsage = { input_tokens: 0, output_tokens: 0 };`
  - `const completedActions: Array<{ tool_name: string; input_summary: string; result_summary: string }> = [];`
- [x] 2.5.2 — Wire `abortController: controller` into the SDK `query({ ... })` call (around line 204).
- [x] 2.5.3 — Inside the for-await loop, capture tool-use-completion events (event name from 0.3) into `completedActions`. Capture `result.usage` into `accumulatedUsage` when the SDK yields its `result` event.
- [x] 2.5.4 — Split the abort branch (around line 401): read `controller.signal.reason`, classify as `user_requested_stop` vs `disconnected | superseded`. Persist `fullText` via `saveMessage` with `status: 'aborted'` and `usage` snapshot when `!messagePersisted && fullText.length > 0`. Set `messagePersisted = true`.
- [x] 2.5.5 — Conversation status: `updateConversationStatus(userId, conversationId, isUserRequested ? 'active' : 'failed')`.
- [x] 2.5.6 — Send `{ type: 'session_ended', reason: 'user_aborted', conversationId }` via `sendToClient` when `isUserRequested` is true.
- [x] 2.5.7 — In the normal `result` branch, also check `messagePersisted` before saving — keeps both paths on a single guarded site.

### 2.6 — `saveMessage` signature

- [x] 2.6.1 — Extend `saveMessage` (`agent-runner.ts:377`) with optional 7th parameter `meta?: { status?: 'complete' | 'aborted'; usage?: UsageSnapshot }`. Default `status='complete'`, `usage=null`. Insert payload accordingly.
- [x] 2.6.2 — Confirm all existing callers continue to work without change (additive parameter).

### 2.7 — Sentry observability

- [x] 2.7.1 — Import `reportSilentFallback` from `@/server/observability` in `agent-runner.ts`.
- [x] 2.7.2 — Mirror to Sentry on every catch / abort-error path: `reportSilentFallback(err, { feature: "abort-turn", op, extra: { userId, conversationId, reason, hadPartialText: fullText.length > 0 } })`.

### 2.8 — Run tests

- [x] 2.8.1 — `vitest run server/__tests__/abort-turn.test.ts` → all GREEN.
- [x] 2.8.2 — `tsc --noEmit` from `apps/web-platform/` → clean.
- [x] 2.8.3 — Existing test suite: `vitest run` → no regressions.

## Phase 3 — GREEN: PR1 legal docs

- [x] 3.1 — Run `legal-document-generator` agent with prompt: "Draft a metered-usage / partial-consumption sub-section for T&C §5 covering tokens generated before Stop are billed; side-effecting tool calls already dispatched are not auto-reversed; cross-reference Privacy §4.2."
- [x] 3.2 — Apply the generated copy to BOTH `docs/legal/terms-and-conditions.md` AND `plugins/soleur/docs/pages/legal/terms-and-conditions.md`. Keep them line-for-line identical except for the relative-vs-absolute link convention.
- [x] 3.3 — Run `legal-document-generator` agent with prompt: "Draft an addition to Privacy Policy §4.2 listing 'conversation transcripts (including partial assistant outputs from aborted turns)' as a Web Platform processing category, with retention rules matching existing transcript handling and a cross-reference to GDPR Art. 17 erasure rights in §7."
- [x] 3.4 — Apply to BOTH `docs/legal/privacy-policy.md` AND `plugins/soleur/docs/pages/legal/privacy-policy.md`.
- [x] 3.5 — Run `legal-compliance-auditor` agent against both T&C and Privacy edits before marking PR1 ready.

## Phase 4 — PR1 ship

- [ ] 4.1 — Push branch (already pushed via draft PR); update PR #3447 description to scope it to PR1 (server + DB + legal) and add `## Changelog` section.
- [ ] 4.2 — PR body uses `Ref #3448` (NOT `Closes #3448` — feature is two-PR; close after PR2). Per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] 4.3 — Run `skill: soleur:review` against PR1 (multi-agent: `code-reviewer`, `architecture-strategist`, `kieran-rails-reviewer`, `user-impact-reviewer` MANDATORY per `single-user incident` threshold, `legal-compliance-auditor`).
- [ ] 4.4 — Resolve review comments inline (default-fix-inline per AGENTS.md `rf-review-finding-default-fix-inline`).
- [ ] 4.5 — Mark PR1 ready for review; merge with `gh pr merge 3447 --squash --auto`; poll until MERGED.
- [ ] 4.6 — Post-merge: verify migration deployed to prd Supabase. Confirm `\d public.messages` shows `status` and `usage` columns.
- [ ] 4.7 — 24h Sentry watch: monitor `feature: "abort-turn"` events for unhandled rejections.
- [ ] 4.8 — Manual prd verification: open a chat, send a long prompt, close the tab mid-stream, return; verify the partial assistant message is now persisted with `status='aborted'` (run `psql -c "SELECT status, usage->'output_tokens' FROM messages ORDER BY created_at DESC LIMIT 1"`).

## Phase 5 — RED (PR2 client tests, failing first)

- [ ] 5.1 — Create new feature branch `feat-abort-conversation-web-pr2` off updated main (after PR1 merge).
- [ ] 5.2 — Create `apps/web-platform/components/chat/__tests__/abort-marker.test.tsx`. Failing test: rendering a message with `status='aborted'` shows partial text + `[stopped by user]` chip + token count + USD cost + completed-actions chip-list.
- [ ] 5.3 — Failing test: Stop button replaces Send when `streamState === 'streaming' | 'stopping'`. Click invokes `useWebSocket.abort()`.
- [ ] 5.4 — Failing test: `Esc` keystroke invokes abort when chat surface is focused AND (textarea is empty OR not focused).
- [ ] 5.5 — Failing test: `Esc` does NOT invoke abort when textarea is focused AND has 10+ chars of content.
- [ ] 5.6 — Failing test: double-click safety — second click while `stopping` is a no-op.
- [ ] 5.7 — Failing test: `useEffect` cleanup removes the keydown listener on unmount.
- [ ] 5.8 — Failing test: `useWebSocket.abort()` sends `{ type: "abort_turn", conversationId }` over the socket and transitions local `streamState` to `'stopping'`.
- [ ] 5.9 — Run vitest → all RED.

## Phase 6 — GREEN: PR2 client implementation

### 6.1 — `useWebSocket.abort()`

- [ ] 6.1.1 — `apps/web-platform/lib/ws-client.ts`: add `abort()` method to the hook's return surface. Sends `abort_turn`, transitions local state to `'stopping'`. Coordinate with #3280 (history-fetch reducer refactor).
- [ ] 6.1.2 — Extend `streamState` type to include `'stopping'`. Update reducer / `_exhaustive: never` rails accordingly. Per AGENTS.md `cq-union-widening-grep-three-patterns`, run the 3-pattern grep on `streamState`.

### 6.2 — Stop button

- [ ] 6.2.1 — `apps/web-platform/components/chat/chat-input.tsx`: when `streamState ∈ {'streaming', 'stopping'}`, render Stop button in place of Send. While `'stopping'`, disable the button + show "Stopping…" label.
- [ ] 6.2.2 — Wire the click handler through to `useWebSocket.abort()` (via prop drilling from `page.tsx`).

### 6.3 — Esc shortcut

- [ ] 6.3.1 — `apps/web-platform/components/chat/chat-surface.tsx`: register a `keydown` listener (in `useEffect`) when `streamState ∈ {'streaming', 'stopping'}`.
- [ ] 6.3.2 — Listener checks: `e.key === 'Escape'`, AND (focus is NOT a non-empty textarea), then `e.preventDefault()` + `abort()`.
- [ ] 6.3.3 — `useEffect` cleanup returns `() => document.removeEventListener('keydown', handler)`.

### 6.4 — Abort marker

- [ ] 6.4.1 — `apps/web-platform/components/chat/message-bubble.tsx`: when `message.status === 'aborted'`, render the marker:
  - The accumulated `content` text.
  - `[stopped by user]` chip.
  - Token count: `usage.input_tokens + usage.output_tokens` and `usage.cost_usd` (or "included in your plan").
  - Completed-actions chip-list (one chip per `usage.completed_actions[]` entry; reuse `tool-use-chip.tsx` if shape matches per 0.4).
- [ ] 6.4.2 — If #3242 (raw tool name field) is merged before this PR, use the raw name. Otherwise use today's shape.

### 6.5 — Page wiring

- [ ] 6.5.1 — `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`: pass `useWebSocket().abort` through to `ChatInput` and `ChatSurface` props.

### 6.6 — Run tests

- [ ] 6.6.1 — `vitest run components/chat/__tests__/abort-marker.test.tsx` → all GREEN.
- [ ] 6.6.2 — `tsc --noEmit` from `apps/web-platform/` → clean.

## Phase 7 — PR2 verification + ship

- [ ] 7.1 — Run `skill: soleur:test-browser` for end-to-end Playwright verification: start turn → click Stop → see marker → send follow-up.
- [ ] 7.2 — Same e2e via `Esc` keystroke.
- [ ] 7.3 — Same e2e for tab-close (verifies PR1 server path under PR2 client).
- [ ] 7.4 — Run `skill: soleur:review` against PR2 (`code-reviewer`, `kieran-rails-reviewer`, `user-impact-reviewer`).
- [ ] 7.5 — Resolve review comments inline.
- [ ] 7.6 — PR body uses `Closes #3448` (this PR completes the feature).
- [ ] 7.7 — Mark PR2 ready; merge with `gh pr merge <pr2-number> --squash --auto`; poll until MERGED.
- [ ] 7.8 — Post-merge: 24h Sentry watch for `feature: "abort-turn"` regressions.
- [ ] 7.9 — Manual prd dogfood: long prompt → click Stop → verify marker rendering with token count + completed-actions chip-list end-to-end.

## Phase 8 — Capture + ship

- [ ] 8.1 — Run `skill: soleur:compound` after each PR to capture learnings.
- [ ] 8.2 — Run `skill: soleur:ship` after PR2 merge for the lifecycle checklist (CMO content-opportunity gate may surface — bundle into a "You own the loop" thematic post per CMO assessment).
