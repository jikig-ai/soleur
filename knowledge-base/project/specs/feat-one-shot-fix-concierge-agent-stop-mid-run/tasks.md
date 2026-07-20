---
title: "Tasks: Concierge false mid-run stop (orphan client error + hard cap)"
branch: feat-one-shot-fix-concierge-agent-stop-mid-run
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-16-fix-concierge-agent-stop-mid-run-plan.md
date: 2026-07-16
---

# Tasks — feat-one-shot-fix-concierge-agent-stop-mid-run

Derived from plan `2026-07-16-fix-concierge-agent-stop-mid-run-plan.md` (post plan-review / deepen).

## Phase 0 — Preflight + RED tests

- [x] 0.1 `curl -sS --max-time 10 https://app.soleur.ai/health | jq '{status,version,build_sha}'` — record baseline SHA
- [x] 0.2 Grep shipped heartbeats still present on branch:
  - `rg -n 'msg\.type === "tool_progress"' apps/web-platform/server/soleur-go-runner.ts`
  - `rg -n 'onToolProgress' apps/web-platform/server/cc-dispatcher.ts`
  - `rg -n 'MAX_LIVENESS_REARMS|case "debug_event"' apps/web-platform/lib/chat-state-machine.ts`
- [x] 0.3 RED: add failing tests in `apps/web-platform/test/chat-state-machine.test.ts`:
  - Stage-2 error + `cc_router` not in `activeStreams` + `tool_use` → rebind (state tool_use, stream map has leader, timerAction reset)
  - Same + `tool_progress` → non-error + timerAction reset
  - Error + no events → sticky error
  - `command_stream` after error rebinds tip (no permanent orphan error as sole text tip)
- [x] 0.4 RED (or extend): `test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` — error bubble + progress heals
- [x] 0.5 Confirm RED fails: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/cc-soleur-go-tool-progress-no-terminal-error.test.ts`

## Phase 1 — Path A recovery (client)

- [x] 1.1 Implement `findRecoverableErrorBubble` in `apps/web-platform/lib/chat-state-machine.ts`
- [x] 1.2 Wire rebind into `tool_use` (before cc_router chip-only branch when recoverable error exists)
- [x] 1.3 Wire rebind into `tool_progress` (replace inert unknown-leader no-op when recoverable)
- [x] 1.4 Wire rebind into `command_stream`, `stream`, and `stream_start` (prefer rebind over new bubble when recoverable)
- [x] 1.5 Optional: `debug_event` zero-activeStreams single-orphan rebind (only if unambiguous)
- [x] 1.6 Preserve chip path when no recoverable error (pre-stream cold tool_use)
- [x] 1.7 GREEN Phase 0 tests + `test/ws-streaming-state.test.ts` if contracts drift
- [x] 1.8 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`

## Phase 2 — Path C hard-cap budget (server)

- [x] 2.1 Set `DEFAULT_MAX_TURN_DURATION_MS = 45 * 60 * 1000` in `apps/web-platform/server/soleur-go-runner.ts`
- [x] 2.2 Update constant pins (full enum — do not sample):
  - `test/soleur-go-runner-awaiting-user.test.ts` (`DEFAULT_MAX_TURN_DURATION_MS is 10 min…`)
  - `test/soleur-go-runner-tool-result-idle-reset.test.ts` (`scenario B-pin…`)
  - Comments that say "10-min" for **this** constant (not `DEFAULT_IDLE_REAP_MS`)
- [x] 2.3 Confirm `tool_progress` still never calls `armTurnHardCap` / never re-arms hard cap (existing AC3-class tests)
- [x] 2.4 Confirm idle hang still fires `reason: "idle_window"` (AC2b)
- [x] 2.5 Amend `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` absolute ceiling to 45 min; reaffirm tool_progress does not touch hard cap
- [x] 2.6 GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-awaiting-user.test.ts test/soleur-go-runner-tool-result-idle-reset.test.ts`

## Phase 3 — Path B (only if needed)

- [x] 3.1 Skip unless Phase 1 dogfood/tests show Stage-2 races rebind on >90s pure model silence with no frames
- [x] 3.2 Skipped (Path A sufficient): `lastLivenessAt` Stage-2 suppress with `MAX_LIVENESS_REARMS` ceiling + tests

## Phase 4 — Verify + ship prep

- [x] 4.1 Full targeted vitest batch from plan AC6
- [x] 4.2 Diff hygiene: no nav-rail / settings-resume files (AC8)
- [ ] 4.3 Post-merge: health `build_sha` cutover check (AC9)
- [ ] 4.4 Post-merge: long Concierge continuous-tool dogfood (AC10); optionally close dogfood #2869 if verified — **not** plan frontmatter `closes:`

## Non-goals (do not implement)

- Re-implement server `tool_progress` → `armRunaway` or cc `onToolProgress` forward
- Raise `STUCK_TIMEOUT_MS` / `DEFAULT_WALL_CLOCK_TRIGGER_MS` without mechanism
- Nav-rail position resume / settings last-tab
- Re-arm `turnHardCap` on every `tool_progress`
