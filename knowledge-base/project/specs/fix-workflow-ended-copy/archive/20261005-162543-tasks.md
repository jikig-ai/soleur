# Tasks — fix-workflow-ended-copy

Source plan: `knowledge-base/project/plans/2026-10-05-fix-workflow-ended-status-copy-plan.md` (deepened 2026-10-05)

## Phase 1 — Contract first (module + tests)

- [x] 1.1. Write `apps/web-platform/test/workflow-ended-copy.test.tsx` (RED first):
  - badge-map exhaustiveness (`Object.keys(WORKFLOW_ENDED_BADGE_COPY).sort()` == `WORKFLOW_END_STATUSES.sort()`)
  - no-snake_case regex (`/[a-zA-Z]+_[a-zA-Z]+/`) over every badge label, `WORKFLOW_ENDED_BADGE_GENERIC`, `WORKFLOW_ENDED_GENERIC_COPY`
  - `hasWorkflowEndedBadge` proto-key rejection (`constructor`, `toString`, `hasOwnProperty`, `__proto__`, `valueOf`, `isPrototypeOf`) + unknown status → `false`; `internal_error`/`completed` → `true`
  - `workflowEndedBadge` / `workflowEndedCopy` `{copy, mapped}` semantics; non-member status (direct call — the only reachable unmapped path) → generic copy + `mapped:false`
  - `workflowEndedCopy` delegation: mapped status returns the verbatim `SESSION_ENDED_COPY` sentence
  - ChatSurface render test (harness: `test/chat-surface-context-reset.test.tsx` + `test/mocks/use-websocket.ts`): injected `workflow_ended{status:"internal_error"}` card shows mapped copy; `container.textContent` does NOT contain `internal_error`
  - `WorkflowLifecycleBar` render test: `lifecycle={state:"ended",status:"internal_error"}` badge shows the mapped label; `container.textContent` does NOT contain `internal_error`; `status:"completed"` keeps `bg-emerald-900/40` classes
  - NOTE: no ws-client warn test — an unmapped status is unreachable through any frame path (`parseWSMessage` `z.enum` gate; `test/ws-zod-schemas.test.ts:310` already covers the reject). See plan Enhancement Summary #1.
- [x] 1.2. Create `apps/web-platform/lib/workflow-ended-copy.ts`:
  - `WORKFLOW_ENDED_BADGE_COPY: Record<WorkflowEndStatus, string>` (labels per plan)
  - `WORKFLOW_ENDED_BADGE_GENERIC_COPY = "Ended"`
  - `WORKFLOW_ENDED_GENERIC_COPY = "This workflow ended. Start a new conversation to continue."`
  - `hasWorkflowEndedBadge(status)` — `Object.prototype.hasOwnProperty.call` membership gate
  - `workflowEndedBadge(status)` → `{copy, mapped}`
  - `workflowEndedCopy(status)` → delegates to `sessionEndedCopy`; unmapped → `WORKFLOW_ENDED_GENERIC_COPY` + `mapped:false`

## Phase 2 — Render sites

- [x] 2.1. `apps/web-platform/components/chat/chat-surface.tsx` `case "workflow_ended"`: replace the `{msg.status}` JSX-text render (~line 1120) with `{workflowEndedCopy(msg.status).copy}`; keep `msg.status === "completed"` emerald/red check; update the dormant-leak comment to describe the mapping. Do NOT touch the `status={msg.status}` MessageBubble prop at ~line 1042 (different type).
- [x] 2.2. `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` `ended` branch: replace `{lifecycle.status}` (~line 90) with `{workflowEndedBadge(lifecycle.status).copy}`; keep `lifecycle.status === "completed"` styling check and `data-lifecycle-status={lifecycle.status}` attribute on the raw value; update the comment.
- [x] 2.3. `apps/web-platform/lib/session-ended-copy.ts`: one-line docstring note naming the sibling module (no behavior change).

## Phase 3 — Coverage comment (no warn)

- [x] 3.1. `apps/web-platform/lib/ws-client.ts`: inside the grouped `stream_event` case arm (~line 1074), add a comment noting that an unmapped `workflow_ended.status` cannot reach this arm — `parseWSMessage` (~line 951) validates against `z.enum(WORKFLOW_END_STATUSES)` and reports shape-misses via `ws-zod-parse-failure`. Do NOT add a `warnSilentFallback` — it is provably unreachable dead code (plan Enhancement Summary #1).

## Phase 4 — Test updates

- [x] 4.1. `apps/web-platform/test/workflow-lifecycle-bar.test.tsx`: update `toContain("completed")` (line ~61) to the mapped badge label `toContain("Completed")`.
- [x] 4.2. `apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts` FR2.4 (~lines 291-294): keep the `[data-lifecycle-state="ended"][data-lifecycle-status="cost_ceiling"]` selector; add `await expect(endedBar).toContainText("Cost cap reached")` (mapped badge label) and `await expect(endedBar).not.toContainText("cost_ceiling")`.

## Phase 5 — Verify

- [x] 5.1. `grep -cn '^\s*{msg\.status}\s*$' apps/web-platform/components/chat/chat-surface.tsx` → 0; `grep -cn '^\s*{lifecycle\.status}\s*$' apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` → 0 (AC1).
- [x] 5.2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (AC2).
- [x] 5.3. `cd apps/web-platform && ./node_modules/.bin/vitest run test/workflow-ended-copy.test.tsx` (AC3) and `vitest run test/session-ended-copy.test.tsx test/workflow-lifecycle-bar.test.tsx test/chat-state-machine.test.ts test/cc-soleur-go-end-to-end-render.test.tsx` (AC4) — all green.
- [x] 5.4. `grep -cn 'warnSilentFallback' apps/web-platform/lib/ws-client.ts` unchanged from `origin/main` (currently 3 — AC5); `grep -n 'status === "completed"'` both component files ≥ 2 and `data-lifecycle-status` still raw (AC6); e2e FR2.4 updated (AC7); `git grep -n '{lifecycle.status}\|{msg.status}' -- 'apps/web-platform/components/**/*.tsx'` shows only prop/attribute uses (AC8).
- [x] 5.5. PR #9051 merge state re-check before marking PR ready (`gh pr view 9051 --json state`); if merged, re-run AC1/AC8 census greps after rebase.
