# Tasks — fix-workflow-ended-copy

Derived from `knowledge-base/project/plans/2026-10-05-fix-workflow-ended-status-copy-plan.md`.

## Phase 1 — RED (tests first)

- [ ] 1.1 Create `apps/web-platform/test/workflow-ended-copy.test.tsx`:
  map exhaustiveness vs `WORKFLOW_END_STATUSES`, no-snake_case guard over
  all values + generic, `hasWorkflowEndedCopy` proto-key/unknown
  rejection, `workflowEndedStatusCopy` `{copy, mapped}` contract,
  `<WorkflowLifecycleBar>` render asserting `internal_error` never
  reaches the DOM (mapped label rendered; `completed` keeps emerald),
  ChatSurface render via `createWebSocketMock` with a synthesized
  `workflow_ended` message (pattern: `test/chat-surface-context-reset.test.tsx`).
- [ ] 1.2 Update `apps/web-platform/test/workflow-lifecycle-bar.test.tsx`:
  replace `toContain("completed")` with the mapped label; add
  raw-token negative on a failure status.
- [ ] 1.3 Update `apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts`:
  keep `[data-lifecycle-status="cost_ceiling"]` selector; add
  visible-text assertion for the mapped label + `not.toContainText`
  guard on the raw token.

## Phase 2 — GREEN

- [ ] 2.1 Create `apps/web-platform/lib/workflow-ended-copy.ts`:
  `WORKFLOW_ENDED_STATUS_COPY` (`Record<WorkflowEndStatus, string>`),
  `WORKFLOW_ENDED_GENERIC_COPY`, `hasWorkflowEndedCopy`
  (hasOwnProperty-gated), `workflowEndedStatusCopy` — pure module, no
  Sentry import.
- [ ] 2.2 `apps/web-platform/components/chat/chat-surface.tsx` —
  `case "workflow_ended"`: render mapped copy; keep
  `msg.status === "completed"` styling; retire dormant comment.
- [ ] 2.3 `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx`
  — badge renders mapped copy; keep `=== "completed"` styling and raw
  `data-lifecycle-status`; retire dormant comment.
- [ ] 2.4 `apps/web-platform/lib/ws-client.ts` — `warnSilentFallback`
  arm (`op: "workflow-ended-unmapped-status"`, 64-char-bound status in
  `extra`) before the grouped `stream_event` dispatch.

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/workflow-ended-copy.test.tsx test/workflow-lifecycle-bar.test.tsx
  test/session-ended-copy.test.tsx` — green.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` —
  clean.
- [ ] 3.3 `cd apps/web-platform && npx playwright test
  e2e/cc-soleur-go-routing.e2e.ts` if runnable; else flag for CI.
- [ ] 3.4 Merge-conflict watch: re-check draft PR #9051 state before
  merge (`gh pr view 9051 --json state`).
