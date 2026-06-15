---
title: "Tasks: cc-soleur-go in-flight work checkpoint parity (#5356)"
plan: knowledge-base/project/plans/2026-06-15-feat-cc-soleur-go-checkpoint-parity-plan.md
issue: 5356
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — cc-soleur-go checkpoint parity (#5356)

Derived from `2026-06-15-feat-cc-soleur-go-checkpoint-parity-plan.md`. Scope is
**write-side only** — the restore path is already path-agnostic.

## Phase 0 — Preconditions (read-only, gate the design)

- [ ] 0.1 `git grep -n checkpointInflightWork apps/web-platform/server/` → hits only in `agent-runner.ts` + `inflight-checkpoint.ts` (0 in cc). Capture output.
- [ ] 0.2 Read `ws-handler.ts:1994` + `inflight-checkpoint.ts:286-320` — confirm `restoreInflightCheckpoint` keys solely on `conversationId` and runs for any resumed conversation (not legacy-gated). If gated → re-scope (add read-side phase).
- [ ] 0.3 `git grep -n "reapIdle\|closeConversation" apps/web-platform/server/ | grep -v test` → only comments + runner def/export (no production `setInterval`/caller). Load-bearing premise for Phase 2.
- [ ] 0.4 Confirm `userId`/`conversationId` in scope at `ws-handler.ts:2920-2934` (already `uid`/`convId`); confirm `workspace_id` resolvable from `conversations.workspace_id` at the cc checkpoint site (symmetric with `agent-runner.ts:2378-2393`). Use `workspacePathForWorkspaceId`, NOT `resolveActiveWorkspacePath`.
- [ ] 0.5 Confirm vitest + `test/**/*.test.ts` glob (`apps/web-platform/vitest.config.ts:44`).
- [ ] 0.6 Re-run Open Code-Review Overlap (skill Step 1.7.5) against the 3 edited files.

## Phase 1 — Failing tests first (RED) — `cq-write-failing-tests-before`

- [ ] 1.1 Create `apps/web-platform/test/cc-soleur-go-checkpoint-on-disconnect.test.ts` (vitest, node, SDK removed from assertion path — injected factory/spies).
- [ ] 1.2 T1: `abortConversation(convId, "disconnected")` fires the cc close path (`onCloseQuery`) for that conversation.
- [ ] 1.3 T2: on `reason === "disconnected"`, the close hook calls `checkpointInflightWork(path, convId, userId)` exactly once with the conversation-bound path.
- [ ] 1.4 T3: natural completion (`onWorkflowEnded status:"completed"`) + non-disconnect `closeConversation` do NOT checkpoint.
- [ ] 1.5 T4: checkpoint resolves clone from `conversations.workspace_id` via `workspacePathForWorkspaceId`, NOT `resolveActiveWorkspacePath`.
- [ ] 1.6 T5: `checkpointInflightWork` rejection → close path still completes (bash-gate drain runs), `reportSilentFallback` mirrored, no throw escapes.
- [ ] 1.7 T6: ws-handler disconnect grace timer signals BOTH `abortSession` and `abortConversation(convId, "disconnected")`.
- [ ] 1.8 Confirm all RED for the right reason (missing trigger/hook), not harness error.

## Phase 2 — cc runner: `abortConversation` (soleur-go-runner.ts)

- [ ] 2.1 Add `abortConversation(conversationId, reason)` — lookup `activeQueries.get(conversationId)`, no-op if absent (idempotent).
- [ ] 2.2 Abort controller/interrupt the SDK query (mirror `reapIdle`/`closeConversation` internals), then route through `closeQuery(state)` so `onCloseQuery` fires (`:1966-1983`).
- [ ] 2.3 Widen `onCloseQuery` signature `{conversationId, userId}` → `{conversationId, userId, reason?}`; per `hr-type-widening-cross-consumer-grep` + `cq-union-widening-grep-three-patterns`, grep + update all consumers; existing `reapIdle`/`closeConversation` callers pass NO reason.
- [ ] 2.4 Export `abortConversation` in the returned object (`:3220-3231`).

## Phase 3 — cc dispatcher: checkpoint on disconnect (cc-dispatcher.ts)

- [ ] 3.1 In `getSoleurGoRunner` `onCloseQuery` (`:1909-1910`), when `reason === "disconnected"`: `getFreshTenantClient(userId)` → SELECT `workspace_id` from `conversations` where `id = conversationId`; on error/null → Sentry-mirror + skip (no throw).
- [ ] 3.2 `checkpointWorkspacePath = workspacePathForWorkspaceId(boundWorkspaceId)`.
- [ ] 3.3 `await checkpointInflightWork(checkpointWorkspacePath, conversationId, userId)` (reuse as-is).
- [ ] 3.4 Wrap resolution in try/catch → `reportSilentFallback({feature:"inflight-checkpoint", op:"checkpoint-on-abort", extra:{…, stage:"cc-resolve-workspace-path"}})`.
- [ ] 3.5 Keep bash-gate cleanup on EVERY close (reason or not). (Phase 2 MUST land before Phase 3 consumes `reason`.)

## Phase 4 — ws-handler trigger (ws-handler.ts)

- [ ] 4.1 In grace-timer callback (`:2923-2931`), after `abortSession(uid, convId)` also call `abortConversation(convId, "disconnected")` (via `getSoleurGoRunner()`/dispatch surface).
- [ ] 4.2 Add comment citing #5356 + the dual-path-terminal learning (turn-boundary hooks need BOTH lineages wired).

## Phase 5 — Observability + GREEN + exit gate

- [ ] 5.1 Confirm new emit uses `op: "checkpoint-on-abort"` (no new orphan slug).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-soleur-go-checkpoint-on-disconnect.test.ts` → GREEN.
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean (let tsc enumerate widening rails).
- [ ] 5.4 `cd apps/web-platform && ./node_modules/.bin/vitest run` → full suite green (esp. `cc-dispatcher-bash-gate.test.ts` T13/T13b, `inflight-checkpoint.test.ts`).
- [ ] 5.5 Verify all Acceptance Criteria AC1–AC11.
- [ ] 5.6 File the two deferral tracking issues (cc idle-reaper unscheduled; SIGTERM cc-drain) with re-eval criteria + roadmap milestone.
- [ ] 5.7 Run `/soleur:gdpr-gate` against the diff (expect "no new regulated surface; inherits #5275").
- [ ] 5.8 PR body: `Closes #5356`.
