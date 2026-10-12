---
title: "Fix KB document chat resume hydration + button label + Command Center empty body"
type: bug
created: 2026-05-05
branch: feat-one-shot-kb-doc-chat-resume-bug
classification: ui-bug
requires_cpo_signoff: false
deepened_on: 2026-05-05
---

# Fix KB document chat resume hydration + button label + Command Center empty body

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** 6 (Hypotheses, Files to Edit, Implementation Phases, Test Strategy, Sharp Edges, new Research Insights)
**Research surfaces consulted:** local code grep on `apps/web-platform/lib/`, `apps/web-platform/server/`, `apps/web-platform/components/chat/`, `apps/web-platform/components/kb/`, `apps/web-platform/test/`; existing test file `ws-client-resume-history.test.tsx` as fixture template; existing `client-observability.ts` API surface; AGENTS.md hard rule `cq-silent-fallback-must-mirror-to-sentry`.

### Key Improvements (vs. plan-skill output)

1. **`reportSilentFallback` import path verified.** `ws-client.ts` already imports `reportSilentFallback` from `@/lib/client-observability` (line 24); the existing `console.warn` calls just need to be replaced — no new import. `server/api-messages.ts` will use the server variant from `@/server/observability` (already imported by `lookup-conversation-for-path.ts`, sibling pattern).
2. **`mountedRef` is redundant for the resume-history fetch.** Both fetch effects already use `AbortController`; the cleanup `controller.abort()` rejects the in-flight fetch with `AbortError`. The `if (!result || !mountedRef.current) return` guard at lines 761 and 792 is belt-and-suspenders. Replacing it with `if (!result || controller.signal.aborted) return` removes the React-strict-mode-double-mount race entirely.
3. **The `filter_prepend` reducer correctly preserves ordering.** Line 205: `messages: [...unique, ...state.messages]` — history (oldest first) is prepended to whatever stream events arrived during the in-flight fetch. No reducer change needed; the bug is upstream.
4. **`thread-info` and `api-messages` use DIFFERENT row-lookup filters.** `thread-info` → `lookupConversationForPath` filters by `(user_id, repo_url, context_path)`; `api-messages` filters by `(id, user_id)` only. The `repo_url` mismatch can be silent. Adding the Sentry breadcrumb to `api-messages` (Phase 2 T3.5) makes this observable.
5. **Empty-state placeholder timing depends on FOUR signals**, not just `messages.length`. The corrected guard is `messages.length === 0 && !isClassifying && !lastError && !historyLoading`. The fourth signal must thread through the hook return value.
6. **Test framework is vitest with `bun test`** (per `package.json` `test: vitest`). Fixtures from `ws-client-resume-history.test.tsx` (MockWebSocket, fetchSpy, supabase mock) are reusable verbatim — no new mocking infrastructure needed.

### New Considerations Discovered

- The `useKbLayoutState` thread-info prefetch races the `KbChatContent` mount-time `onMessageCountChange?.(0)` because both write to the same `messageCount` slot in `KbChatContext`. Both edit sites (consumer in `kb-chat-content.tsx`, producer in `chat-surface.tsx`) need the fix — H3 race remediation requires belt-and-suspenders.
- The Sentry mirror is mandatory (AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`) AND solves the diagnosis problem: the user's screenshots can't be cross-referenced with prod because nothing surfaces in Sentry today. After the fix, Phase 0 (manual repro) becomes optional — the breadcrumb tells us H1 vs H2 vs H4 from prod data alone.
- React 19 (per `package.json`) — Strict mode double-effect semantics are the same as React 18. AbortController-based cancellation is the canonical fix.

## Overview

Three related bugs share a root cause in the message hydration / messageCount-propagation path for resumed conversations:

1. **KB document chat does not hydrate prior messages on revisit.** Reopening a document with a prior chat session shows the "Continuing from <ts>" banner (proof that `session_resumed` arrived) but the message list renders the empty-state placeholder ("Send a message to get started"). Expected: prior messages render above the input.
2. **KB header button is stuck on "Ask about this document".** When a prior session exists for that document, the button should read "Continue thread" (per `kb-chat-trigger.tsx:55`). User-reported wording "Continue conversation" matches the intent — keep the existing label `Continue thread` (no string churn) since the existing test file `kb-chat-sidebar*.test.tsx` and copy already use that label.
3. **Command Center conversation pane renders empty while sidebar shows "In progress · 2m ago".** Same conversation, opened from `/dashboard/chat/<conversationId>`, renders 0 message bubbles even though the row has messages and `status='active'`. Either the body must hydrate, or the sidebar status / empty-state must agree.

The shared mechanism: `useWebSocket(conversationId)` is the hydration entry point for both the KB sidebar (`conversationId="new"` → resumed via `resumeByContextPath`) and the Command Center (`conversationId=<uuid>` → resumed via `resume_session`). Both surfaces depend on a successful `GET /api/conversations/:id/messages` to populate `chatState.messages`. If that fetch fails or the dispatch is skipped, the surface renders empty.

## User-Brand Impact

- **If this lands broken, the user experiences:** prior chat history vanishing whenever they revisit a KB document — the document-chat panel and the Command Center both look empty even though the data exists in Postgres. The user has no way to know whether the prior conversation was lost or merely not displayed; trust in the data layer collapses.
- **If this leaks, the user's data is exposed via:** N/A — this is a hydration / read-side bug, not a write or auth path. The `/api/conversations/:id/messages` route already enforces `eq("user_id", user.id)`; the fix preserves that constraint and adds tests for it.
- **Brand-survival threshold:** none. This is a UX correctness bug, not a data-loss or privacy bug. Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`: no sensitive-path regex match (no auth/credentials/payments/data-write surface). `threshold: none, reason: read-only hydration fix on already-authenticated WS + REST routes; no new data flows or persistence.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — KB sidebar revisit: opening a document with a prior conversation, then opening the chat panel, renders all prior messages in chronological order within ≤2s of `session_resumed` arriving. Verified by extending `apps/web-platform/test/kb-chat-sidebar.test.tsx` with a "resume hydrates messages end-to-end" case that mounts `KbChatSidebar`, simulates `session_resumed` + history-fetch response, and asserts ≥1 message bubble rendered.
- [ ] AC2 — KB trigger label flips when a prior session exists: `kb-chat-trigger.tsx` renders "Continue thread" + the amber dot indicator iff `ctx.messageCount > 0`. Verified by extending `apps/web-platform/test/` with a `kb-chat-trigger.test.tsx` (currently absent) that exercises both branches.
- [ ] AC3 — Command Center revisit hydration: opening `/dashboard/chat/<id>` for a conversation with N≥1 messages renders all N messages within ≤2s. Verified by extending `apps/web-platform/test/ws-client-resume-history.test.tsx` with a non-`"new"` `conversationId` case (current tests exercise only the `"new"` resume path).
- [ ] AC4 — Empty-state coherence: `ChatSurface` does NOT render the "Send a message to get started" placeholder while `realConversationId` is non-null AND a history fetch is in-flight (otherwise the user sees a flash of empty-state during the round-trip). The placeholder gates on `messages.length === 0 && !isClassifying && !lastError && !historyLoading`.
- [ ] AC5 — Diagnostic logging: a hydration failure (4xx/5xx from `/api/conversations/:id/messages`, network abort that is NOT a navigation cancel, dispatch skipped due to mountedRef false) MUST mirror to Sentry via `reportSilentFallback({ feature: "kb-chat", op: "history-fetch-failed", extra: { status, conversationId } })` per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`. The current `console.warn(\`History fetch failed for ${targetId}: ${res.status}\`)` is invisible in Sentry.
- [ ] AC6 — `useKbLayoutState` thread-info prefetch must NOT be clobbered by the ChatSurface mount-time `onMessageCountChange?.(0)`. Either: (a) ChatSurface does not call `onMessageCountChange(0)` until the first non-zero history-fetch result lands, OR (b) `KbChatContent`'s `handleMessageCountChange` ignores incoming `0` values when `historicalCountRef.current > 0` (already partially handled — extend to the `0`-during-bootstrap window).
- [ ] AC7 — A new browser-shaped test reproduces the original repro path with a real fetch mock: open document → open sidebar → assert messages hydrate. Lives in `apps/web-platform/test/kb-chat-resume-hydration.test.tsx`.
- [ ] AC8 — Tests pre-existing on main pass on this branch (`bun test` exit code 0); no regressions in the 24-test kb-chat-* suite or the 5-test ws-client-resume-history suite.
- [ ] AC9 — `tsc --noEmit` passes; `next lint` passes; no new ESLint suppressions.
- [ ] AC10 — `Closes #<issue-number>` (or `Ref` if a tracking issue is filed for partial scope) appears in PR body, not title.

### Post-merge (operator)

- [ ] PM1 — Production smoke: open a KB document with prior chat → open sidebar → verify messages render and button reads "Continue thread"; open the same conversation in `/dashboard/chat/<id>` → verify messages render. Capture both screenshots in PR description.
- [ ] PM2 — Sentry filter: search for `feature:kb-chat op:history-fetch-failed` over the 24h window post-deploy; expected count = 0. Any non-zero count is a regression signal — file a follow-up issue.

## Research Reconciliation — Spec vs. Codebase

| Spec claim from bug report | Reality in code | Plan response |
|---|---|---|
| Button "should read 'Continue conversation'" when a prior session exists | The existing `kb-chat-trigger.tsx:55` already conditionally renders "Continue thread" (different label), keyed on `ctx.messageCount > 0` | Keep existing "Continue thread" label (matches existing tests + UX copy review). Bug is NOT a string mismatch — it's that `ctx.messageCount` stays at 0 because hydration fails or is overwritten. Document the label decision in PR description. |
| "Same root cause across all three" | Partially true. KB sidebar (#1) and KB trigger (#2) share a root cause via `messageCount` state; CC pane (#3) shares the history-fetch path but not the `messageCount` propagation path | Treat as one fix on the hydration path with a focused secondary fix on the `messageCount` race. Both flow from the same `useWebSocket` history fetch. |
| `/api/conversations/[id]/messages` endpoint exists in the App Router | The endpoint exists ONLY in the Node custom server (`server/api-messages.ts` wired via `server/index.ts:75-81` regex match), NOT in `app/api/conversations/`. Vitest tests bypass the network with `fetch` mocks, so the wiring works in prod (`node dist/server/index.cjs`) and test, but a Next.js `next dev` standalone (without the custom server) would 404 | No code change required — confirm via README/runbook that `bun run dev` (which runs the custom server bundle) is the only supported dev entrypoint. Add a comment in `ws-client.ts:701` noting the endpoint lives in the custom server, not the App Router, so future contributors don't add a duplicate. |

## Open Code-Review Overlap

- **#2962** (extract memoized `getServiceClient()` shared lazy singleton) — touches `apps/web-platform/server/ws-handler.ts` (one of the files this plan inspects). **Disposition: acknowledge.** Different concern (ergonomics refactor of a 4-site duplication). Not blocking and not in this plan's scope. The scope-out remains open.
- **#2191** (introduce `clearSessionTimers` helper + jitter) — touches `apps/web-platform/server/ws-handler.ts`. **Disposition: acknowledge.** Different concern (timer-teardown abstraction). Not blocking and not in this plan's scope. The scope-out remains open.

## Hypotheses

The bug must be one of these (ordered by likelihood given the screenshots: banner DID fire ⇒ `session_resumed` arrived ⇒ `realConversationId` is set):

### H1 — History fetch returns 200 with `messages: []` because of a row-mismatch bug

The `lookupConversationForPath` helper (used by `thread-info` and the WS handler) filters by `(user_id, repo_url, context_path)`. The `api-messages.ts` handler filters only by `(id, user_id)`. If a user's `current_repo_url` was changed between sessions, the WS handler's `session_resumed` lookup might find a DIFFERENT conversation than the one referenced by `id`, and api-messages.ts could fetch messages for a DIFFERENT row, OR the row exists but has 0 messages because messages were never persisted. Need a SQL probe to confirm `(user_id, conversation_id)` row count vs. `messages.conversation_id` count.

**Test:** Add a Sentry breadcrumb in `api-messages.ts` that records `(conversationId, messages.length, total_cost_usd)`. If 200 + `messages: []` is the failure mode, this surfaces it.

### H2 — `mountedRef.current` is false when the resume-history fetch resolves

The mount-time effect (line 810-826 in `ws-client.ts`) sets `mountedRef.current = true` at mount and `false` at unmount. In React 18 strict mode, the dev double-effect runs cleanup between the two mounts. The async fetch in the resume-history effect captures `mountedRef` by closure; if the fetch resolves DURING the cleanup window, the dispatch is skipped.

**Test:** Run `bun run dev` (which runs strict-mode React) and reproduce manually with browser DevTools network throttling set to "Slow 3G" so the fetch resolves AFTER the cleanup. If the bug reproduces only under throttling, this is the cause.

### H3 — `onMessageCountChange?.(0)` from the mount-time effect overwrites the prefetch

`useKbLayoutState` prefetches `messageCount` via `/api/chat/thread-info` and seeds the KbChatContext to N. When the user opens the sidebar, `KbChatContent` mounts → `ChatSurface` mounts → `useEffect(() => onMessageCountChange?.(messages.length), [messages.length, onMessageCountChange])` fires immediately with `messages.length === 0`, overwriting the prefetched N back to 0.

The button label now reads "Ask about this document" (because `messageCount === 0`) until history fetches complete and re-trigger the effect. If history fetch silently fails, the label sticks at the wrong value forever.

This is the most likely cause for bug #2 (button label) AND it is causally linked to bug #1 if the history fetch also fails for any reason — H1 or H2 explains the message list, H3 alone explains why the button label desyncs even when messages eventually load.

**Test:** Inspect `KbChatContent.handleMessageCountChange` (line 128-136 of `kb-chat-content.tsx`) — confirm it accepts `0` and propagates it to KbChatContext.

### H4 — Custom server's regex route handler is not matched in the user's environment

The endpoint `/api/conversations/:id/messages` is wired in `server/index.ts:75-81` via a regex on `parsedUrl.pathname`. If the user's deploy is somehow running `next start` directly (bypassing the custom server) or there's a reverse-proxy rewrite that strips the prefix, the route 404s and the `console.warn` swallows the failure.

**Test:** `curl -i https://<deploy>/api/conversations/<known-id>/messages -H 'Authorization: Bearer <token>'` and check the status code. If the prod container is running `node dist/server/index.cjs` (per Dockerfile), this is correctly wired.

### H5 — Network-outage / firewall blast radius

NOT applicable — the failing call is a same-origin HTTP fetch from the browser to the user's own session. No firewall/SSH/L3 path is in scope.

(Plan does not match the SSH/network-outage trigger pattern from `plan.md` Phase 1.4 — skipping that gate per its own conditional.)

## Files to Edit

- **`apps/web-platform/lib/ws-client.ts`** — (a) replace both `console.warn(\`History fetch failed for ${targetId}: ${res.status}\`)` (inside `fetchConversationHistory`, line 708) AND the two `console.error("Failed to load history:", err)` / `console.error("Failed to load resume history:", err)` calls (lines 771, 803) with `reportSilentFallback(err, { feature: "kb-chat", op: "history-fetch-failed", extra: { conversationId, ...(typeof status === "number" ? { status } : {}) } })`. The import is **already present** at line 24: `import { reportSilentFallback } from "@/lib/client-observability";` — no new import needed. (b) Introduce a `historyLoading: boolean` state (lifted to module scope of the hook); set to `true` at the start of each fetch-effect, set to `false` in a `try/finally` so abort-rejection still settles. Expose from the hook return (`return { ..., historyLoading }`). (c) Replace the `if (!result || !mountedRef.current) return;` guard at lines 761 and 792 with `if (!result || controller.signal.aborted) return;` — eliminates the React-strict-mode-double-mount race (H2). (d) Add a code comment at line 701 (just above the `fetch(\`/api/conversations/${targetId}/messages\`, ...)` call) noting: `// NOTE: this endpoint is wired in the Node custom server (server/api-messages.ts via server/index.ts:75-81 regex), NOT in app/api/conversations/. Do not add a duplicate route.ts — Next.js routing precedence is undefined.`
- **`apps/web-platform/components/chat/chat-surface.tsx`** — (a) extend the empty-state guard at line 468 to include `!historyLoading`; (b) when `realConversationId` is non-null AND `messages.length === 0`, do NOT call `onMessageCountChange?.(0)` — defer until the first non-zero result lands or until `historyLoading` flips false. Keep the existing call for the genuine "no prior messages" case after history fetch completes.
- **`apps/web-platform/components/chat/kb-chat-content.tsx`** — `handleMessageCountChange` should ignore `count === 0` writes when `historicalCountRef.current > 0` (we already know there are N historical messages). This belt-and-suspenders the H3 race even if `chat-surface.tsx` is changed.
- **`apps/web-platform/server/api-messages.ts`** — add a `reportSilentFallback` call on every error branch (401 missing-auth at line 19, 401 invalid-token at line 31, 404 conversation-not-found at line 49, 500 messages-load-failed at line 62). Import: `import { reportSilentFallback } from "@/server/observability";` (sibling pattern — `lookup-conversation-for-path.ts` line 6 already does this). Add a Sentry breadcrumb on the success path before `res.end(...)` at line 69: `Sentry.addBreadcrumb({ category: "kb-chat", message: "history-fetch-success", data: { conversationId, count: messages?.length ?? 0 } })` (requires `import * as Sentry from "@sentry/nextjs"` — also a sibling pattern from `server/index.ts` line 5). The breadcrumb makes H1 (row mismatch / 0-row hit) observable in prod without needing a manual repro.
- **`apps/web-platform/components/kb/kb-chat-trigger.tsx`** — verify the label and dot logic at line 54-55 is correct. No code change expected — bug is in the upstream `messageCount` propagation, not in the trigger's branching. Add a comment pointing to `useKbLayoutState`'s thread-info prefetch as the source of truth for `messageCount` when the panel is closed.

## Files to Create

- **`apps/web-platform/test/kb-chat-resume-hydration.test.tsx`** — end-to-end-shaped test that mounts `KbChatSidebar` with `resumeByContextPath`, mocks the WS to send `session_resumed`, mocks `fetch` to return 3 history messages, and asserts (i) all 3 message bubbles render, (ii) the "Send a message to get started" placeholder does NOT render, (iii) `KbChatContext.messageCount` ends at 3, (iv) the trigger button reads "Continue thread".
- **`apps/web-platform/test/kb-chat-trigger.test.tsx`** — unit test for `KbChatTrigger` covering: (i) `enabled=false` → fallback Link; (ii) `enabled=true, messageCount=0` → "Ask about this document", no dot; (iii) `enabled=true, messageCount=3` → "Continue thread" + amber dot.
- **`apps/web-platform/test/api-messages-handler.test.ts`** — unit test for `handleConversationMessages` covering: (i) 401 on missing/invalid token; (ii) 404 on conversation not owned by user (Sentry breadcrumb fires); (iii) 200 on success with non-empty messages array; (iv) 200 with empty messages array when row exists but has 0 messages (NOT 404 — this is a real state).

## Implementation Phases

### Phase 0 — Reproduction + diagnosis (T1)

- T1.1 — Run `bun run dev` from `apps/web-platform/`, log in, open a doc, send a chat message, navigate away, navigate back, open the chat panel. Check whether the bug reproduces locally (it should, given the screenshots).
- T1.2 — Open browser DevTools → Network tab. Confirm `/api/conversations/<id>/messages` is called and returns 200 vs 404 vs `[]`. This narrows H1 vs H2 vs H4.
- T1.3 — If 200 + `[]`: H1 confirmed (row mismatch or empty messages — investigate via SQL probe via Supabase MCP). If 404: H4 confirmed (custom server bypass — fix routing). If 200 + non-empty messages BUT UI still empty: H2 or H3 (mountedRef race or messageCount overwrite).
- T1.4 — Document the confirmed hypothesis in the PR description before writing fix code.

### Phase 1 — RED (failing tests)

- T2.1 — Write `kb-chat-resume-hydration.test.tsx` per "Files to Create" above. Confirm it fails on main (`git checkout main -- <file>` is not viable since the file is new; instead, run the test against the current branch's pre-fix code — it should fail because either messages don't hydrate or the placeholder renders alongside hydrated messages).
- T2.2 — Write `kb-chat-trigger.test.tsx` per "Files to Create" — case (iii) (`messageCount=3` → "Continue thread") should pass on main; case (ii) → "Ask about this document" should also pass. The new failing test is one that simulates the prefetch → mount → overwrite race: mount `KbChatTrigger` inside a test harness that simulates the H3 race (initial messageCount=3, then a child component sets it to 0, then to 3 again). The button label should never flip to "Ask about this document" if the prefetch succeeded.
- T2.3 — Write `api-messages-handler.test.ts` per "Files to Create" — at least one case (e.g., Sentry breadcrumb on success) should fail on main because the breadcrumb does not yet exist.

### Phase 2 — GREEN (minimal fix)

- T3.1 — `ws-client.ts`: replace both `console.warn` / `console.error` calls in the two history-fetch effects with `reportSilentFallback`. Verified import already present at line 24: `import { reportSilentFallback } from "@/lib/client-observability";` — no new import needed. Concrete diff shape:

  ```ts
  // BEFORE (line 708)
  if (!res.ok) {
    console.warn(`History fetch failed for ${targetId}: ${res.status}`);
    return null;
  }

  // AFTER
  if (!res.ok) {
    reportSilentFallback(null, {
      feature: "kb-chat",
      op: "history-fetch-failed",
      extra: { conversationId: targetId, status: res.status },
    });
    return null;
  }

  // BEFORE (lines 770-771, 802-803)
  if (err instanceof DOMException && err.name === "AbortError") return;
  console.error("Failed to load history:", err);

  // AFTER
  if (err instanceof DOMException && err.name === "AbortError") return;
  reportSilentFallback(err, {
    feature: "kb-chat",
    op: "history-fetch-error",
    extra: { conversationId: targetId },
  });
  ```
- T3.2 — `ws-client.ts`: introduce `historyLoading: boolean` state. Set `true` immediately before the fetch call in BOTH history-fetch effects (lines 754-776 and 782-808). Set `false` in a `try/finally` block so abort-rejection still settles. Add `historyLoading` to the hook return object (line 908-928). Concrete diff shape:

  ```ts
  // Add at line ~290 with other useState
  const [historyLoading, setHistoryLoading] = useState(false);

  // Effect 1 (line 754-776) — wrap inside the IIFE:
  setHistoryLoading(true);
  try {
    const result = await fetchConversationHistory(conversationId, controller.signal);
    if (!result || controller.signal.aborted) return;
    dispatch({ type: "filter_prepend", messages: result.messages });
    seedCostData(result.costData);
    seedWorkflowEndedAt(result.workflowEndedAt);
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") return;
    reportSilentFallback(err, { feature: "kb-chat", op: "history-fetch-error", extra: { conversationId } });
  } finally {
    if (!controller.signal.aborted) setHistoryLoading(false);
  }
  // Same shape for Effect 2 (resume path).

  // Return value (line ~927):
  return { ..., historyLoading };
  ```

  Replace `mountedRef.current` checks at lines 761, 792 with `controller.signal.aborted` (already in scope, deterministic, not subject to React strict-mode double-mount).
- T3.3 — `chat-surface.tsx`: destructure `historyLoading` from `useWebSocket(conversationId)` (line 184-204 of chat-surface.tsx — add after `workflowEndedAt`). Extend the empty-state placeholder guard at line 468:

  ```tsx
  // BEFORE
  {messages.length === 0 && !isClassifying && !lastError && (

  // AFTER
  {messages.length === 0 && !isClassifying && !lastError && !historyLoading && (
  ```

  Skip the `onMessageCountChange?.(0)` overwrite while still hydrating. Replace effect at line 281-283:

  ```tsx
  // BEFORE
  useEffect(() => {
    onMessageCountChange?.(messages.length);
  }, [messages.length, onMessageCountChange]);

  // AFTER
  useEffect(() => {
    // While history is still loading or has not yet returned for a known
    // realConversationId, do not overwrite the prefetched messageCount with 0.
    // useKbLayoutState seeds messageCount via /api/chat/thread-info before the
    // sidebar mounts; clobbering with 0 here flips the trigger label back to
    // "Ask about this document" until history fetch resolves (race H3).
    if (messages.length === 0 && (historyLoading || realConversationId)) return;
    onMessageCountChange?.(messages.length);
  }, [messages.length, onMessageCountChange, historyLoading, realConversationId]);
  ```
- T3.4 — `kb-chat-content.tsx`: extend `handleMessageCountChange` (line 128-136) — ignore `0` writes when `historicalCountRef.current > 0`:

  ```tsx
  // BEFORE
  const handleMessageCountChange = useCallback(
    (count: number) => {
      setMessageCount(count);
      if (count > historicalCountRef.current) {
        setResumedBanner(null);
      }
    },
    [setMessageCount],
  );

  // AFTER
  const handleMessageCountChange = useCallback(
    (count: number) => {
      // Belt-and-suspenders for race H3: if we already know there are N
      // historical messages (set by handleThreadResumed), do NOT clobber
      // KbChatContext.messageCount back to 0 — even if ChatSurface fires
      // a transient onMessageCountChange(0) during its mount-time effect.
      if (count === 0 && historicalCountRef.current > 0) return;
      setMessageCount(count);
      if (count > historicalCountRef.current) {
        setResumedBanner(null);
      }
    },
    [setMessageCount],
  );
  ```
- T3.5 — `api-messages.ts`: wrap each non-200 branch with `reportSilentFallback`. Add a success breadcrumb. Verified imports already work in the custom-server bundle (sibling `lookup-conversation-for-path.ts` already imports `@/server/observability`; `server/index.ts` imports `@sentry/nextjs`). Concrete diff shape:

  ```ts
  import * as Sentry from "@sentry/nextjs";
  import { reportSilentFallback } from "@/server/observability";

  // 401 missing-auth (line 19-22)
  reportSilentFallback(null, {
    feature: "kb-chat",
    op: "history-fetch-401-missing-auth",
    extra: { conversationId },
  });

  // 401 invalid-token (line 31-34)
  reportSilentFallback(authErr, {
    feature: "kb-chat",
    op: "history-fetch-401-invalid-token",
    extra: { conversationId },
  });

  // 404 conversation-not-found (line 49-52)
  reportSilentFallback(convErr, {
    feature: "kb-chat",
    op: "history-fetch-404-not-owned-or-missing",
    extra: { conversationId, userId: user.id },
  });

  // 500 messages-load-failed (line 62-66)
  reportSilentFallback(msgErr, {
    feature: "kb-chat",
    op: "history-fetch-500-messages-load",
    extra: { conversationId },
  });

  // Success path — before res.end at line 69
  Sentry.addBreadcrumb({
    category: "kb-chat",
    message: "history-fetch-success",
    data: { conversationId, count: messages?.length ?? 0 },
    level: "info",
  });
  ```

  Note: `reportSilentFallback`'s first arg is the `Error | null`; the `feature` / `op` / `extra` shape is per `@/server/observability` line 25 `SilentFallbackOptions`.

### Phase 3 — verify + REFACTOR

- T4.1 — Run `bun test` from `apps/web-platform/`. All new tests pass; no regressions in existing 24 kb-chat-* tests + 5 ws-client-resume-history tests.
- T4.2 — Run `bun run typecheck`. No new errors.
- T4.3 — Manual smoke test: revisit a doc → sidebar → messages render → trigger label is "Continue thread". `/dashboard/chat/<id>` → messages render.
- T4.4 — If H1 was the confirmed root cause (Phase 0 result), additional fix may be required in `lookupConversationForPath` or the WS handler's resume lookup — that is a separate sub-plan.

## Test Strategy

Existing test runner is **vitest** (per `package.json` `test` script: `vitest`). Tests live in `apps/web-platform/test/`. Use `@testing-library/react` (already a dev dep, used in `kb-chat-sidebar*.test.tsx`).

**Mocks:** `WebSocket` mock from `ws-client-resume-history.test.tsx` (lines 17-46) is reusable verbatim. `fetch` mock pattern from same file (lines 67-72). Supabase mock from same file (lines 5-14).

No new test framework; no new dev dep. Test discovery is by glob `**/*.test.{ts,tsx}` so new files in `apps/web-platform/test/` are auto-picked-up.

## Research Insights

### React 19 Strict-Mode Effect Semantics

In `next dev` mode, every effect runs `mount → cleanup → mount` to surface cleanup-correctness bugs (verified: `package.json` line lists `"react": "^19.1.0"`). Pattern: closure-captured refs read across the cleanup boundary are unreliable. Canonical fix is `AbortController` + `signal.aborted` because the controller is per-effect-instance — there is exactly one signal per scheduled effect, and the cleanup aborts that signal before the second mount creates a fresh one.

```ts
// Anti-pattern (race-prone in strict mode):
const mountedRef = useRef(true);
useEffect(() => {
  mountedRef.current = true;
  fetch(url).then(r => {
    if (!mountedRef.current) return; // race: ref could be true again after re-mount
    setState(r);
  });
  return () => { mountedRef.current = false; };
}, [...]);

// Pattern (deterministic):
useEffect(() => {
  const c = new AbortController();
  fetch(url, { signal: c.signal }).then(r => {
    if (c.signal.aborted) return; // deterministic: signal is per-effect-instance
    setState(r);
  });
  return () => c.abort();
}, [...]);
```

`ws-client.ts` already uses `AbortController` for the fetch lifecycle — the `mountedRef` check on top of it is redundant defensive code that introduces the very race it tries to prevent.

### `reportSilentFallback` Surface

`@/lib/client-observability` (browser-safe variant) — used by `lib/supabase/client.ts`, `lib/format-assistant-text.ts`, `components/error-boundary-view.tsx`, `lib/sandbox-path-patterns.ts`, `lib/ws-known-types.ts`, `lib/ws-client.ts` (already imported, just unused for the history-fetch path).

`@/server/observability` (server-side variant, mirrors to pino + Sentry) — used by `server/lookup-conversation-for-path.ts` (sibling), `server/ws-handler.ts`, `server/agent-runner.ts`, etc.

Both share the `(err, { feature, op, extra })` signature. The browser variant uses `Sentry.captureException` from `@sentry/nextjs`'s client SDK; the server variant adds a pino structured log line via `@/server/logger`. Both are guaranteed to surface in Sentry per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`.

### `useReducer` `filter_prepend` Action — Verified Correct

`apps/web-platform/lib/ws-client.ts:202-206`:

```ts
case "filter_prepend": {
  const existingIds = new Set(state.messages.map(m => m.id));
  const unique = action.messages.filter(m => !existingIds.has(m.id));
  return { ...state, messages: [...unique, ...state.messages] };
}
```

Properties verified by `apps/web-platform/test/ws-client-resume-history.test.tsx`:

- Chronological order preserved (oldest first) — line 138-162 test case.
- Deduplication against in-flight stream events — line 164-200 test case.
- Cost data + `workflowEndedAt` seeded with functional updaters so racing WS events don't clobber.

No reducer change needed.

### Vitest + `@testing-library/react` Pattern

Test fixtures from `apps/web-platform/test/ws-client-resume-history.test.tsx`:

- `MockWebSocket` (line 27-46) — captures the WS instance for `serverSend` simulation.
- `fetchSpy` via `vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify(...)))` (line 67-72).
- Supabase mock: `vi.mock("@/lib/supabase/client", ...)` (line 10-14).
- Helper `connectAndAuth(result)` (line 90-103) — drives WS to `connected` + `auth_ok`.

The new test files (`kb-chat-resume-hydration.test.tsx`, `kb-chat-trigger.test.tsx`, `api-messages-handler.test.ts`) reuse these fixtures verbatim. No new mocking infrastructure.

### Empty-State Placeholder Coordination

The user-visible empty state ("Send a message to get started") at `chat-surface.tsx:468-474` currently gates on three signals:

```tsx
{messages.length === 0 && !isClassifying && !lastError && (
  <div>...Send a message...</div>
)}
```

The fourth signal (`!historyLoading`) closes the FOUC window where the placeholder briefly renders during the round-trip. This matches the established Soleur pattern — see `cq-eleventy-critical-css-screenshot-gate` for a sibling FOUC-aware gate. No screenshot test required here (different surface, different failure mode), but a vitest `waitFor` assertion that the placeholder NEVER appears between mount and history-resolution is sufficient.

### Diagnostic Observability (Phase 0 Replacement)

After the Sentry mirrors land, manual reproduction (Phase 0 T1.1-T1.3) becomes optional. Filter: `feature:kb-chat AND (op:history-fetch-failed OR op:history-fetch-error OR op:history-fetch-404-not-owned-or-missing OR op:history-fetch-500-messages-load)` over a 24h window post-deploy. Non-zero count localizes the root cause:

- `op:history-fetch-failed` with status=404 → H4 (custom-server route bypass).
- `op:history-fetch-failed` with status=500 → H1 (DB error in lookup or messages query).
- `op:history-fetch-success` breadcrumb with `count=0` AND user reports messages missing → H1 confirmed (row mismatch — different conversation row resolved than the one referenced by id).
- `op:history-fetch-error` with `AbortError` filtered out → H2 (network or React-strict-mode race; the `controller.signal.aborted` switch removes this entirely).

If Sentry shows zero hits but the user still reports the bug, H3 (messageCount overwrite) is the residual cause and is fully addressed by T3.3 + T3.4.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled — threshold `none` with reason.)
- The endpoint `/api/conversations/:id/messages` lives in the Node custom server (`apps/web-platform/server/api-messages.ts`, wired via `server/index.ts` regex), NOT in `app/api/conversations/`. Future contributors who try to "fix" the missing route file by adding `app/api/conversations/[id]/messages/route.ts` will create a duplicate that may shadow the custom-server route depending on Next.js routing precedence. Document this in a code comment at `ws-client.ts:701`.
- `reportSilentFallback` may be server-only (`@/server/observability`). If `ws-client.ts` (browser code) cannot import it, use `Sentry.captureException` with the `tags` object directly (the `@sentry/nextjs` client SDK is browser-safe).
- The hooks `useKbLayoutState` thread-info prefetch and the ChatSurface mount-time `onMessageCountChange?.(0)` race is fixed in `kb-chat-content.tsx` (consumer side) and `chat-surface.tsx` (producer side) — both edits are required to belt-and-suspenders the race; one alone leaves a window.
- React 18 strict-mode double-effect can cause `mountedRef.current` to flip false→true during the resume-history fetch's await window. The `if (!result || !mountedRef.current) return` check is at the dispatch site — if the dispatch is skipped, the bug surfaces. Consider replacing the bare `mountedRef` check with the `controller.signal.aborted` check (controllers are per-effect-instance, not stale across mounts).
- The Sentry `reportSilentFallback` mirror is mandatory per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — the existing `console.warn` is invisible in Sentry and was the reason this bug went undiagnosed.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a UI hydration bug in the KB chat / Command Center surface. No product/marketing/legal/finance/ops/security implications. Not user-facing in a copy-or-flow-changing way (label remains "Continue thread"). No new third-party services or schema changes.

### CTO

**Status:** carried forward (no fresh agent invocation — single-domain technical bug, no architectural decision required).
**Assessment:** Fix is local: `ws-client.ts`, `chat-surface.tsx`, `kb-chat-content.tsx`, `api-messages.ts`. No schema migration. No new dependency. The Sentry mirror addition aligns with existing AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` and adds production observability that was missing.

(No Product/UX gate triggered — no new pages, no flow changes, no new components. Mechanical scan of "Files to create" yields three test files, which do not match `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` — gate is NONE.)

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-05-fix-kb-doc-chat-resume-hydration-and-button-label-plan.md

Context: branch feat-one-shot-kb-doc-chat-resume-bug, worktree .worktrees/feat-one-shot-kb-doc-chat-resume-bug, no PR yet, no issue yet.
Plan written, ready for deepen-plan + work. Three related KB-chat resume bugs sharing a hydration / messageCount-overwrite root cause.
```
