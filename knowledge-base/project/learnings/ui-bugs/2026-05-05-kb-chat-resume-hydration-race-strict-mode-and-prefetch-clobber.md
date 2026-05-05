---
module: KB Chat
date: 2026-05-05
problem_type: ui_bug
component: react_hook
symptoms:
  - "KB doc-chat sidebar 'Continuing from <ts>' banner fires but message list renders empty"
  - "Trigger button stays on 'Ask about this document' even when prior thread exists"
  - "Command Center conversation pane shows 'Untitled · In progress' but body is blank"
  - "console.warn on history-fetch failure invisible in Sentry, no production observability"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags: [useeffect, react-hooks, abortcontroller, strict-mode, history-fetch, sentry, silent-fallback, kb-chat, command-center]
synced_to: []
---

# Learning: KB chat resume hydration race — three failure modes share one fetch path

## Problem

Three user-visible bugs reported together turned out to share a single class of
hydration race in `apps/web-platform/lib/ws-client.ts`:

1. KB doc-chat sidebar opens with "Continuing from <ts>" banner (proof
   `session_resumed` arrived) but the message list renders the
   "Send a message to get started" empty-state placeholder.
2. KB header trigger stays on "Ask about this document" instead of flipping to
   "Continue thread" with the amber dot indicator.
3. Command Center `/dashboard/chat/<id>` renders the same conversation with
   the recent-conversations sidebar showing "Untitled · In progress · 2m ago"
   but the conversation body is blank.

## Root cause

Three intertwined async signals collide on the messageCount slot in
`KbChatContext` and the dispatch site of two history-fetch effects:

**H1 — React 19 strict-mode double-mount race on `mountedRef`.** Both
history-fetch effects had `if (!result || !mountedRef.current) return;` as
the post-await dispatch guard. In strict mode, the dev double-effect runs
`mount → cleanup → mount`. A fetch resolved during the cleanup window could
observe its remounted-effect's `mountedRef.current = true` and dispatch into
a stale reducer. **Fix:** swap to `controller.signal.aborted` — the
`AbortController` is per-effect-instance, deterministic across the double-
mount, and aborts cleanly when the effect re-runs.

**H2 — `onMessageCountChange?.(0)` clobbers prefetched count.**
`useKbLayoutState` prefetches `messageCount` via `/api/chat/thread-info`
BEFORE the sidebar mounts, seeding `KbChatContext.messageCount = N`. When
the user opens the sidebar, `KbChatContent` mounts → `ChatSurface` mounts →
its `useEffect(() => onMessageCountChange?.(messages.length), ...)` fires
immediately with `messages.length === 0`, overwriting N back to 0. The
trigger label flips to "Ask about this document" until the history fetch
resolves — and sticks there permanently if the fetch silently fails.

**H3 — Silent fallback masks H1/H2 in production.** All four error paths
(`/api/conversations/:id/messages` 401, 401-invalid, 404, 500) and the
client-side history-fetch failures used `console.warn` / `console.error`.
Pino stdout is invisible in Sentry; the bug went undiagnosed in prod.

## Solution

Five concrete edits:

```ts
// apps/web-platform/lib/ws-client.ts — collapse two duplicate effects
// into one helper so future seed/retry/telemetry changes can't drift:
async function runHistoryFetch(targetId: string, controller: AbortController) {
  setHistoryLoading(true);
  try {
    const result = await fetchConversationHistory(targetId, controller.signal);
    if (!result || controller.signal.aborted) return;  // H1 fix
    dispatch({ type: "filter_prepend", messages: result.messages });
    seedCostData(result.costData);
    seedWorkflowEndedAt(result.workflowEndedAt);
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") return;
    reportSilentFallback(err, {                         // H3 fix
      feature: "kb-chat", op: "history-fetch-error",
      extra: { conversationId: targetId },
    });
  } finally {
    if (!controller.signal.aborted) setHistoryLoading(false);
  }
}
```

```tsx
// apps/web-platform/components/chat/chat-surface.tsx — H2 producer fix.
// Scope the zero-write guard to resumedFrom (server-confirmed prior thread),
// NOT realConversationId — the latter is over-broad and would suppress the
// legitimate 0-write for fresh session_started flows.
useEffect(() => {
  if (messages.length === 0 && (historyLoading || resumedFrom)) return;
  onMessageCountChange?.(messages.length);
}, [messages.length, onMessageCountChange, historyLoading, resumedFrom]);

// Empty-state placeholder gated on !historyLoading so it cannot flash:
{messages.length === 0 && !isClassifying && !lastError && !historyLoading && (...)}
```

```tsx
// apps/web-platform/components/chat/kb-chat-content.tsx — independent
// invariant: messageCount must never regress below historicalCountRef floor
// once a resumed thread is confirmed. This is NOT redundant with the producer
// guard above — it owns its own invariant that survives a future producer
// refactor.
if (count === 0 && historicalCountRef.current > 0) return;
```

```ts
// apps/web-platform/server/api-messages.ts — H3 fix on every 4xx/5xx branch.
// Success breadcrumb gated on count===0 only (the H1 row-mismatch signal),
// not every successful fetch (would burn 100-entry breadcrumb buffer):
if (messageCount === 0) {
  Sentry.addBreadcrumb({
    category: "kb-chat", message: "history-fetch-success-empty",
    level: "info", data: { conversationId, count: 0 },
  });
}
```

## Key Insight

Three rules that compound across React + observability + state-flow:

1. **Per-effect `AbortController.signal.aborted` beats `mountedRef.current`
   for any post-await dispatch guard.** The controller is bound to the
   effect-instance lifecycle; the ref is shared across mounts and races
   in strict mode. Where one async boundary needs cancellation, never mix
   the two.
2. **A prefetch that seeds a context slot must not be clobbered by a
   mount-time effect on the same slot.** When a parent prefetches state
   and a child component independently writes the same state on mount,
   gate the child's write on a "loading" or "resumed" signal — otherwise
   the child's stale write wins until the slow path resolves.
3. **Two guards defending different invariants are not duplication.**
   The producer guard (chat-surface.tsx) prevents a stale 0-write at the
   source. The consumer guard (kb-chat-content.tsx) enforces "messageCount
   must never regress below the historicalCountRef floor" as an independent
   invariant that survives a future producer refactor. Both belong in the
   codebase; "belt-and-suspenders" framing in the comment was wrong and
   was rewritten to describe each guard's distinct responsibility.

## Prevention

- When two `useEffect` blocks share a fetch + dispatch lifecycle (e.g.,
  mount-time + resume), extract the lifecycle into a single helper that
  takes `(targetId, controller)`. Drift between two effects on the same
  hook was the proximate cause of this PR's bug class — the duplication
  itself was the hazard.
- When using `Sentry.addBreadcrumb` on a hot success path (any endpoint
  that fires per-page-load), gate on the diagnostic-relevant case only
  (e.g., `count === 0` for a "fetch-but-empty" anomaly) so the 100-entry
  breadcrumb buffer doesn't displace useful UI/nav context in error scopes.
- When refactoring a comment from "belt-and-suspenders for race X" to
  describe distinct invariants, double-check both guards are not
  semantically redundant. If they are, delete one. If not, write each
  comment in terms of its own invariant.

## Cross-references

- **Precursor:** `knowledge-base/project/learnings/ui-bugs/2026-04-16-kb-chat-resume-empty-messages.md`
  introduced the resume-history effect this PR hardens (PR #2426). Same
  surface, prior bug class.
- **Same-day follow-up pattern:** `knowledge-base/project/learnings/bug-fixes/2026-04-16-kb-chat-cost-estimate-not-restored-on-resume.md`
  was the same-day follow-up to #2426 (#2437) that added `seedCostData`.
  Both are now collapsed into `runHistoryFetch` so a future seed addition
  (e.g., `seedAttachments`) cannot drift between effects.
- **Silent-fallback rule:** AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`
  is the load-bearing rule that converted the four `console.warn` /
  `console.error` sites to `reportSilentFallback`.
- **AbortController vs mountedRef:** AGENTS.md
  `cq-ref-removal-sweep-cleanup-closures` is the related class of ref-based
  closure hazard. `mountedRef` was kept here for synchronous WS-callback
  guards (no async boundary, no race surface) and only swapped at the two
  history-fetch async sites.

## Session Errors

1. **Wrong issue reference in initial commit message.** First commit used
   `Closes #3236` without verifying the issue existed or matched topic.
   #3236 was an unrelated workflow-heartbeat issue. Recovery: filed correct
   tracking issue #3241, amended the local-only commit message before push.
   **Prevention:** Before writing `Closes #N`/`Ref #N` in any commit or PR
   body, run `gh issue view N --json state,title` and confirm topic match.
   Route to commit-commands skill Sharp Edges.

2. **`expect.anything()` matcher does not match `null` in vitest.**
   The api-messages-handler test asserted `mockReportSilentFallback` was
   called with `expect.anything()` when the implementation passed `null`
   (no row, no error — `.single()` returning empty). Recovery: changed
   the assertion to literal `null`. **Prevention:** When the SUT may
   legitimately pass `null` as an error arg (e.g., Supabase `.single()`
   returning `data: null, error: null`), assert with literal `null`, not
   `expect.anything()`. Route to test-fixtures reference.

3. **Bash CWD does not persist across tool calls.** First post-fix vitest
   invocation ran from worktree root and failed (`No such file or
   directory`) because the prior call had been `cd apps/web-platform && ...`.
   Recovery: re-prefixed with `cd apps/web-platform && ...`. **Prevention:**
   Already established (`cm-bash-cwd-non-persistent` family); the violation
   here was forgetting to chain. No new rule warranted.

## Files

- `apps/web-platform/lib/ws-client.ts` — `runHistoryFetch` helper, 2 effects
- `apps/web-platform/components/chat/chat-surface.tsx` — H2 producer guard
- `apps/web-platform/components/chat/kb-chat-content.tsx` — invariant guard
- `apps/web-platform/components/kb/kb-chat-trigger.tsx` — comment + data-testid
- `apps/web-platform/server/api-messages.ts` — Sentry mirrors + gated breadcrumb
- `apps/web-platform/test/kb-chat-resume-hydration.test.tsx` — 5 cases (RED→GREEN)
- `apps/web-platform/test/kb-chat-trigger.test.tsx` — 5 cases (regression guard)
- `apps/web-platform/test/api-messages-handler.test.ts` — 5 cases (mockQueryChain)

PR #3237 · Issue #3241

**Same-week follow-up:** same surface, two new failure paths surfaced after merge — see `2026-05-05-kb-chat-continuing-banner-h1-h5-residual-races.md` (PR #3267). H1 (silent no-session at fetch time) and H5 (post-teardown `ws.onmessage` observability gap) were not exercised by this PR's `vi.useFakeTimers` harness.
