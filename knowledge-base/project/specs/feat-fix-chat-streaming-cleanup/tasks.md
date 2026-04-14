# Tasks — feat-fix-chat-streaming-cleanup

**Plan:** `knowledge-base/project/plans/2026-04-14-refactor-chat-ws-streaming-cleanup-plan.md`
**PR target title:** refactor(chat): extract state machine, tighten WS event lifecycle, and optimize rendering
**Closes:** #2124, #2125, #2135, #2136, #2137, #2138, #2139

## Phase 1 — State machine extraction (#2124)

- [ ] 1.1 Create `apps/web-platform/lib/chat-state-machine.ts` with `applyStreamEvent` pure reducer
  - 1.1.1 Move `ChatMessage` / `ChatTextMessage` / `ChatGateMessage` types to a shared types module or export from the new file so tests don't reach into ws-client
  - 1.1.2 Port switch cases: `stream_start`, `tool_use`, `stream`, `stream_end`, `review_gate`, `error`, `session_ended`
  - 1.1.3 Return `{ messages, activeStreams, timeoutAction }` — no setState, no refs, no setTimeout
- [ ] 1.2 Rewrite `apps/web-platform/test/ws-streaming-state.test.ts` to import `applyStreamEvent` (delete shadow `processEvents`)
  - 1.2.1 Run test to confirm all 9 existing scenarios still pass
- [ ] 1.3 Update `apps/web-platform/lib/ws-client.ts` to call `applyStreamEvent` for the 7 streaming event types
  - 1.3.1 Keep non-streaming events (`auth_ok`, `session_started`, `usage_update`) inline in the hook
  - 1.3.2 Apply `timeoutAction` by delegating to `resetLeaderTimeout` / `clearLeaderTimeout` / `clearAllTimeouts`
- [ ] 1.4 Verify `node node_modules/vitest/vitest.mjs run test/ws-streaming-state.test.ts` passes

## Phase 2 — Lifecycle bugs (#2135, #2136)

- [ ] 2.1 Write failing test `apps/web-platform/test/ws-reconnect-cleanup.test.ts` (TDD — must fail against current code)
- [ ] 2.2 Add reconnect cleanup to `connect()` in `ws-client.ts`: clear `activeStreamsRef`, `clearAllTimeouts()`, reset `activeLeaderIds`
- [ ] 2.3 Verify reconnect-cleanup test passes
- [ ] 2.4 Write failing test `apps/web-platform/test/ws-timeout-guard.test.ts` (TDD)
  - 2.4.1 Test: bubble with `state: "streaming"` + timeout callback → state unchanged
  - 2.4.2 Test: bubble with `state: "thinking"` + timeout callback → state `"error"`
- [ ] 2.5 Guard the timeout callback in `resetLeaderTimeout` — only set `error` if state is `thinking` or `tool_use`
- [ ] 2.6 Verify timeout-guard test passes

## Phase 3 — Protocol hygiene (#2125, #2138)

- [ ] 3.1 Add TSDoc to `WSMessage.stream.partial` in `lib/types.ts` explaining client ignores it (#2125)
- [ ] 3.2 Remove `tool` from `WSMessage.tool_use` variant in `lib/types.ts` (#2138)
- [ ] 3.3 Update `server/agent-runner.ts:1104-1113` to emit `label` only (map `TOOL_LABELS[toolName]` server-side)
- [ ] 3.4 Update `ws-client.ts` `tool_use` handler to push `msg.label` into `toolsUsed` instead of `msg.tool`
- [ ] 3.5 Update `ws-streaming-state.test.ts` expectations — `toolsUsed` now contains labels (`"Reading file..."`, not `"Read"`)
- [ ] 3.6 Grep `apps/web-platform` for any other consumer of `toolsUsed` raw-name strings — confirm only ws-client and page.tsx
- [ ] 3.7 Run full web-platform test suite — no regressions

## Phase 4 — MessageBubble memo (#2137)

- [ ] 4.1 Write failing test `apps/web-platform/test/message-bubble-memo.test.tsx` — render 3 bubbles, update one, assert other 2 do not re-render (use render-count ref or `React.Profiler`)
- [ ] 4.2 Wrap `MessageBubble` in `React.memo` in `page.tsx`
- [ ] 4.3 Verify `getDisplayName` / `getIconPath` from `useTeamNames` are stable — if not, wrap in `useCallback`
- [ ] 4.4 Verify memo test passes
- [ ] 4.5 Manual QA: open chat with 20+ messages, stream a new response, confirm no visible flicker on prior bubbles

## Phase 5 — Rendering chain simplification (#2139)

- [ ] 5.1 Update `ws-client.ts` history hydration (line ~488) to assign `state: "done"` for assistant role
- [ ] 5.2 Extract `ErrorIndicator` and `ToolUsageChip` as local sub-components in `page.tsx`
- [ ] 5.3 Replace 7-branch content chain with `isUser` short-circuit + `switch(messageState)` (5 cases + default)
- [ ] 5.4 Remove all `!messageState && content === "" && role === "assistant"` fallbacks
- [ ] 5.5 Verify `chat-page.test.tsx` and any snapshot tests pass
- [ ] 5.6 Manual QA: load a conversation with history, verify historical bubbles render as markdown (not thinking dots or streaming cursor)
- [ ] 5.7 Manual QA flag: check if checkmark badge now appears on all historical assistant messages — if undesired, follow up in same PR with a session-scoped `Set<string>` to distinguish "just-completed" from "loaded-from-history"

## Phase 6 — Review & Ship

- [ ] 6.1 Run `node node_modules/vitest/vitest.mjs run` — full suite green
- [ ] 6.2 Push branch to remote (`git push -u origin feat-fix-chat-streaming-cleanup`)
- [ ] 6.3 Run `skill: soleur:review` — multi-agent review
- [ ] 6.4 Address review comments
- [ ] 6.5 Run `skill: soleur:qa` — functional QA with screenshots (chat page affected)
- [ ] 6.6 Run `skill: soleur:compound` — capture learnings
- [ ] 6.7 Run `skill: soleur:ship` with semver label `refactor` (patch bump)
- [ ] 6.8 Poll `gh pr view <N> --json state` until MERGED
- [ ] 6.9 Run `skill: soleur:postmerge` — verify deploy workflow succeeded

## Notes

- All 7 issues target the same 4 files — split into 7 commits for reviewability, squash on merge.
- PR body uses `Closes #N` for all 7 issues (one per line, in body not title).
- Use `node node_modules/vitest/vitest.mjs run` in worktree (AGENTS.md rule).
- After each phase, commit intermediate work — don't batch into one 500-line commit.
