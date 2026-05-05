---
date: 2026-05-05
category: ui-bugs
tags: [react, websocket, supabase, sentry, observability, kb-chat]
related_pr: "#3267"
precursor_pr: "#3237"
precursor_learning: 2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md
---

# KB chat "Continuing from <ts>" banner-without-messages — H1/H5 residual races

## Symptom

Same week, second occurrence on the same surface. The KB right-hand chat panel
showed `Continuing from 5/5/26, 12:56 PM` (proof a `session_resumed` arrived
and `setResumedFrom(...)` fired) but the message list rendered the empty-state
placeholder instead of the prior thread. PR #3237 was intended to close this
class — H1 and H5 paths were both unguarded against.

## Two paths, both observability gaps in #3237

**H1 — `fetchConversationHistory` returns `null` on missing Supabase session.**
`apps/web-platform/lib/ws-client.ts:725` early-returned with NO Sentry mirror
when `supabase.auth.getSession()` returned a null session. The WS uses its
own auth path; the SSR-side Supabase JWT can drift on long-idle reopens
(tab freeze + auto-refresh skew) without breaking the socket. The user opens
a doc 2.5h after last-active → WS auths fine → the resume effect kicks off
the history fetch → no session → null return → `historyLoading=false`,
`messages=[]`, banner already showing. No telemetry.

**H5 — `ws.onmessage` post-teardown.** `wsRef.current.onclose = null` at
teardown does NOT clear `onmessage`. A buffered `session_resumed` arriving
in the close-handshake window can dispatch into a torn-down hook. The
existing `mountedRef.current` guard at line 430 mechanically prevents the
state mutation, but nothing recorded that the path was hit — so a real-user
recurrence was invisible.

## Why precursor #3237 missed both

The #3237 test harness used `vi.useFakeTimers` + synthetic clock advances.
Neither path reproduces under synthetic time:

- H1 needs a real-world long-idle gap to drift the Supabase session.
- H5 needs a real cross-mount WebSocket lifecycle (capture `onmessage` on
  one mount, `unmount()`, dispatch synchronously) — fake-timer harnesses
  don't model the message-buffering window between `ws.close()` and the
  final close frame.

## Fix shape (#3267)

Three surgical edits in `ws-client.ts` + a level bump in `api-messages.ts`:

1. **H1**: `reportSilentFallback(null, { feature: "kb-chat", op: "history-fetch-no-session", extra: { conversationId } })` at line 725 before `return null`. Distinct `op` so triage can disambiguate from `history-fetch-failed` (4xx/5xx) and `history-fetch-error` (network throw).
2. **H5**: `Sentry.addBreadcrumb({ category: "kb-chat", message: "ws-message-after-teardown", level: "warning", data: { type } })` BEFORE the early-return at line 430. Re-parses the frame for `type` only on the rare guard-trip path — fine.
3. **H2** (diagnostic only — no behavior fix): split the combined `if (!result || controller.signal.aborted) return;` guard. Add `Sentry.addBreadcrumb({ category: "kb-chat", message: "abort-after-success", level: "info", data: { messageCount } })` on the aborted branch. Gated on `result !== null` so the routine "abort before fetch resolved" case (which throws AbortError into the catch) does not generate noise.
4. **api-messages**: bump `history-fetch-success-empty` breadcrumb from `info` to `warning` so it survives Sentry's per-event downsampling. Added a TODO referencing the H4 disambiguation path (`X-Resumed-Count` response header).

## Test prescription that mattered

- **`mockImplementationOnce`, never `mockImplementation`, for shared mocks** — `vi.clearAllMocks()` resets `.mock.calls` but does NOT reset the implementation queue. A `mockImplementation(...)` set in one test leaks to all subsequent tests in the same file. Defensive reset in `beforeEach`: `mockGetSession.mockImplementation(async () => ({ data: { session: { access_token: "test-token" } } }))` — restores the valid-session default so a prior test's null-session override does not poison siblings.
- **Real WebSocket lifecycle for post-teardown tests** — capture the `onmessage` handler reference BEFORE calling `unmount()`, then synchronously invoke the captured handler with a `MessageEvent`. Asserting state setters indirectly via the rendered output is brittle here; assert the breadcrumb call directly.
- **Deferred-promise mock for abort-after-success timing** — `fetchSpy.mockImplementationOnce(() => deferredPromise)` lets the test interleave `unmount()` between the spy invocation and the resolution. Verify the spy was called via `fetchSpy.mock.calls.some(...)` rather than `toHaveBeenCalledWith` with a complex `objectContaining({ signal: expect.any(AbortSignal) })` matcher — the matcher's failure message reports `Number of calls: 0` even when the spy WAS called, which masks the real cause.

## Cross-references

- Precursor: `2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md`
- Eager-factory mock class: `2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race.md`
- RED-test-must-simulate-preconditions: `2026-04-22-red-test-must-simulate-suts-preconditions.md`
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — the rule H1 fix instantiates.

## Session Errors

- **Vitest matcher reported "Number of calls: 0" for a spy that WAS called.** `expect(fetchSpy).toHaveBeenCalledWith(url, expect.objectContaining({signal: expect.any(AbortSignal)}))` failed with "Number of calls: 0" while `console.log(fetchSpy.mock.calls)` showed one call. **Recovery:** swapped the assertion to `fetchSpy.mock.calls.some(([url]) => url === expected)`. **Prevention:** when a vitest matcher fails with a confusingly absolute "Number of calls: 0", use the spy's `.mock.calls` array directly to disambiguate matcher mismatch from spy-not-called. Discoverable via clear failure mode; not rule-worthy.

- **Plan prescribed adding code that already existed.** The plan (post-deepen) said add `if (!mountedRef.current) return;` at `ws-client.ts:430`, but that guard was added by precursor PR #3237. **Recovery:** read the actual source file, narrowed the new work to the breadcrumb (the new behavior). **Prevention:** already covered by `hr-when-a-plan-specifies-relative-paths-e-g` — verify plan offsets via grep BEFORE implementing. The Pre-Implementation Verification block in the plan would have caught this if I had checked H5's existing-state separately from line-number-only verification.

- **Bash tool CWD non-persistence between calls.** First `cd apps/web-platform && ./node_modules/.bin/vitest` failed because the prior call had set CWD elsewhere. **Recovery:** chained `cd <worktree-abs-path>/apps/web-platform && <cmd>` in single calls. **Prevention:** already in AGENTS.md as a code-quality bullet; this session reinforces it.

- **`next lint` interactive prompt hang.** Project has no eslint config; `next lint` opened an interactive setup wizard that blocks CI. **Recovery:** treated lint as not-a-gate (typecheck via `tsc --noEmit` is the actual code-quality gate). **Prevention:** pre-existing project condition (Next 15 deprecated `next lint`); not introduced by this PR. Actionable as a separate cleanup if lint is to be re-enabled.

- **Scope-out criterion mislabeled, code-simplicity-reviewer DISSENTed.** Filed Sentry MCP retrieval gap as `architectural-pivot` when `pre-existing-unrelated` was the correct criterion (the gap predates this PR; fix is additive tooling, not a pattern pivot). **Recovery:** dropped the filing (DISSENT flips disposition to fix-inline; for a tooling-gap that can't be fixed inline, dropping is the safe default; agent-native finding stands as a recommendation in the review summary). **Prevention:** when filing review scope-outs, distinguish the four criteria carefully — `architectural-pivot` is "we have a pattern and choose not to change it," `pre-existing-unrelated` is "this gap predates the PR." The triage downstream of each label is different; mislabeling routes work to the wrong queue.
