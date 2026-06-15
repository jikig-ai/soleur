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

[Updated 2026-06-15 deepen — T1 folded into T2; T3 collapsed to one case; added T-race.]

- [ ] 1.1 Create `apps/web-platform/test/cc-soleur-go-checkpoint-on-disconnect.test.ts` (vitest, node, SDK removed from assertion path — injected factory/spies).
- [ ] 1.2 T2: `closeConversation(convId, "disconnected")` with a live `activeQueries` entry → `closeQuery` → `onCloseQuery` with `reason:"disconnected"` → hook calls `checkpointInflightWorkForConversation` → `checkpointInflightWork(path, convId, userId)` once with conversation-bound path.
- [ ] 1.3 T3 (one parametrized case): `closeConversation(convId)` no-reason AND natural completion (`onWorkflowEnded status:"completed"`) both leave `reason` undefined → no checkpoint.
- [ ] 1.4 T4: helper resolves clone from `conversations.workspace_id` via `workspacePathForWorkspaceId`, NOT `fetchUserWorkspacePath`/`resolveActiveWorkspacePath`.
- [ ] 1.5 T5: checkpoint/resolve rejection → close path still completes (bash-gate drain runs), `reportSilentFallback` mirrored, no throw escapes `onCloseQuery`.
- [ ] 1.6 T6: ws-handler grace timer calls BOTH `abortSession` and `getSoleurGoRunner().closeConversation(convId, "disconnected")`.
- [ ] 1.7 T-race: a conversation whose `activeQueries` entry was already deleted (natural completion) does NOT checkpoint when `closeConversation(convId, "disconnected")` is later called (lookup undefined → no-op).
- [ ] 1.8 Confirm all RED for the right reason (missing reason-plumbing/hook), not harness error.

## Phase 2 — cc runner: thread `reason` through existing close path (soleur-go-runner.ts)

[Updated 2026-06-15 deepen — reuse dead-code `closeConversation`; NO new method.]

- [ ] 2.1 Widen `closeConversation(conversationId, reason?: "disconnected")` (`:3115`) — no behavior change to existing (zero) callers.
- [ ] 2.2 Widen `closeQuery(state, reason?)` (`:1942`); thread `reason` to the `onCloseQuery({conversationId, userId, reason})` call (`:1971`). HAND-CHECK all 3 `closeQuery` callers (`emitWorkflowEnded :1939`, `reapIdle :3108`, `closeConversation :3119`) — first two pass no reason. `tsc` does NOT enumerate this internal seam (P1-2).
- [ ] 2.3 Widen `onCloseQuery` type (`:1115`) → `{conversationId, userId, reason?: "disconnected"}`. One consumer (`cc-dispatcher.ts:1909`); `tsc --noEmit` sufficient for this surface (additive optional field).
- [ ] 2.4 (No new export — `closeConversation` already exported at `:3220-3231`.)

## Phase 3 — shared helper + dispatcher hook (inflight-checkpoint.ts, agent-runner.ts, cc-dispatcher.ts)

[Updated 2026-06-15 deepen — EXTRACT the checkpoint block; refactor legacy + wire cc.]

- [ ] 3.1 Add `checkpointInflightWorkForConversation(userId, conversationId[, stage])` to `inflight-checkpoint.ts` = verbatim legacy block (`getFreshTenantClient` → SELECT `workspace_id` → `workspacePathForWorkspaceId` → `checkpointInflightWork` → `reportSilentFallback` try/catch, `op:"checkpoint-on-abort"`). Never throws.
- [ ] 3.2 Refactor legacy site (`agent-runner.ts:2368-2406`) to call the helper inside its `if (isDisconnected)` guard (kill the duplicate, same PR).
- [ ] 3.3 In `getSoleurGoRunner` `onCloseQuery` (`cc-dispatcher.ts:1909-1910`), when `reason === "disconnected"` → `await checkpointInflightWorkForConversation(userId, conversationId)` (cc-tagged `stage:"cc-resolve-workspace-path"`). Keep bash-gate drain unconditional.
- [ ] 3.4 (Phase 2 reason-plumbing MUST land before 3.3 consumes `reason`.)

## Phase 4 — ws-handler trigger (ws-handler.ts)

- [ ] 4.1 In grace-timer callback (`:2923-2931`), after `abortSession(uid, convId)` also call `getSoleurGoRunner().closeConversation(convId, "disconnected")`.
- [ ] 4.2 Add comment citing #5356 + the dual-path-terminal learning (turn-boundary hooks need BOTH lineages wired). Note registries are mutually exclusive (no double-checkpoint).

## Phase 5 — Observability + GREEN + exit gate

- [ ] 5.1 Confirm new emit uses `op: "checkpoint-on-abort"` (no new orphan slug).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-soleur-go-checkpoint-on-disconnect.test.ts` → GREEN.
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean (let tsc enumerate widening rails).
- [ ] 5.4 `cd apps/web-platform && ./node_modules/.bin/vitest run` → full suite green (esp. `cc-dispatcher-bash-gate.test.ts` T13/T13b, `inflight-checkpoint.test.ts`).
- [ ] 5.5 Verify all Acceptance Criteria AC1–AC11.
- [ ] 5.6 File the two deferral tracking issues (cc idle-reaper unscheduled; SIGTERM cc-drain) with re-eval criteria + roadmap milestone.
- [ ] 5.7 Run `/soleur:gdpr-gate` against the diff (expect "no new regulated surface; inherits #5275").
- [ ] 5.8 PR body: `Closes #5356`.
