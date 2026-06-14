---
title: Tasks — Durable session resume v1
issue: 5240
branch: feat-durable-session-resume
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-14-feat-durable-session-resume-v1-plan.md
---

# Tasks: Durable session resume v1 (#5240)

## Phase 0 — Preconditions
- [ ] 0.1 Pin the `set_current_workspace_id` switch call site (active-repo route; ref `workspace-resolver.ts:295`); reuse its exact shape/locking.
- [ ] 0.2 Confirm resolver path: `resolveActiveWorkspacePath:339` → `resolveCurrentWorkspaceId:190` reads `user_session_state.current_workspace_id` (`?? userId` at :217).
- [ ] 0.3 Confirm resume SELECT `ws-handler.ts:~1615` lacks `workspace_id`; terminal catch `~1649-1653` (no `.catch` replay).
- [ ] 0.4 Confirm cc-dispatcher `persistUserMessage` reads `conversations.workspace_id` (`~2203-2218`) — FR2 branches off it.
- [ ] 0.5 Check reducer for a connection-state input distinct from the activity watchdog (decides FR4 state-split vs retire-lie-only).
- [ ] 0.6 Baseline `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 1 — FR1 verified rebind (server) [RED→GREEN]
- [ ] 1.1 RED: test resume aligns `user_session_state.current_workspace_id` to `conversations.workspace_id` (assert the field/resolved cwd, NOT the in-memory map).
- [ ] 1.2 Add `workspace_id` to the resume `.select(...)` at `ws-handler.ts:~1615`.
- [ ] 1.3 On resume, write `current_workspace_id = conv.workspace_id` via the existing switch (0.1); guard to only fire on conversationId (re)assignment (R4).
- [ ] 1.4 On read failure/null → `reportSilentFallback(op:"resume-workspace-rebind")`; honest client error via the existing catch (no `.catch` replay assumption).

## Phase 2 — FR2/FR3 probe + honest message (server) [RED→GREEN]
- [ ] 2.1 RED: `.git`-absent at resolved path → honest "workspace reclaimed — resume with context?" message, not a fresh greeting.
- [ ] 2.2 Reuse `conversationWorkspaceId` from cc-dispatcher's existing read; add `.git` `existsSync` probe (shape from `ensure-workspace-repo.ts:78`) at the pre-greeting/dispatch branch.
- [ ] 2.3 Branch around the agent greeting (mutually exclusive, R3); `warnSilentFallback(op:"resume-workspace-gone")`.

## Phase 3 — FR4 retire the "Retrying…" lie (client) [RED→GREEN]
- [ ] 3.1 RED: 45s silent stream → accurate status, never "Retrying…".
- [ ] 3.2 Replace `RetryingChip` copy + misleading semantic (`message-bubble.tsx:~50`, `chat-state-machine.ts:~1113`) with accurate "No response yet".
- [ ] 3.3 If 0.5 found a connection-state input → split states 1/2; else ship accurate single state and defer split to #5282.

## Phase 4 — FR5 + honesty consequences (AC6/AC7/AC8) [RED→GREEN]
- [ ] 4.1 FR5: resumed turn with existing bound workspace continues in it (verify; falls out of Phase 1).
- [ ] 4.2 AC6: turn-completed-while-away renders completed transcript (existing UI), no spinner/resume-prompt.
- [ ] 4.3 AC7: failed `[Resume]` self-heal → honest retryable error (`op:"resume-action-failed"`), no silent loop/fresh greeting.
- [ ] 4.4 AC8: define decline/ignore resting state (read-only transcript + persistent affordance + composer behavior).

## Phase 5 — Verification
- [ ] 5.1 `tsc --noEmit` clean; vitest for touched suites (deterministic — assert server message/reducer state, not LLM prose).
- [ ] 5.2 Browser QA of the 4 wireframed states (`/soleur:qa`).
- [ ] 5.3 AC-obs: op-slug grep over `server/` + `lib/`; Sentry discoverability curl.
- [ ] 5.4 Pre-ship: `/soleur:preflight`; PR body uses `Closes #5240`; `user-impact-reviewer` at review (single-user threshold).

## Out of scope (tracked)
- #5273 stream-since-disconnect buffer · #5274 physical durability · #5275 in-flight work (incl. AC9) · #5282 reconnect state-machine hardening (AC10–AC12 + state 1/2 split).
