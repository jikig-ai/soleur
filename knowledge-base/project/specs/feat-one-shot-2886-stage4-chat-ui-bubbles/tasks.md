# Tasks: Stage 4 — chat-UI bubble components (#2886)

**Plan:** [`knowledge-base/project/plans/2026-04-27-feat-cc-stage4-chat-ui-bubbles-plan.md`](../../plans/2026-04-27-feat-cc-stage4-chat-ui-bubbles-plan.md)
**Parent plan:** [`2026-04-23-feat-cc-route-via-soleur-go-plan.md`](../../plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md) Stage 4 §307–351
**Issue:** #2886
**Branch:** `feat-one-shot-2886-stage4-chat-ui-bubbles`

## Phase 1 — ChatMessage union extension + render-loop dispatch

- [ ] 1.1 — RED: extend `apps/web-platform/test/chat-state-machine.test.ts` with new event → ChatMessage mappings (subagent_spawn, subagent_complete, interactive_prompt, workflow_started, workflow_ended, tool_progress→chip lifecycle).
- [ ] 1.2 — RED: add `apps/web-platform/test/chat-message-exhaustiveness.test-d.ts` to fail `tsc --noEmit` on missing `: never` rail. Run `rg "msg\.type === \""` and `rg "msg\?\.type === \""` per `cq-union-widening-grep-three-patterns`.
- [ ] 1.3 — GREEN: extend `ChatMessage` union (`apps/web-platform/lib/chat-state-machine.ts`) with `subagent_group`, `interactive_prompt`, `workflow_ended`, `tool_use_chip` variants.
- [ ] 1.4 — GREEN: implement reducer transitions in `applyStreamEvent`.
- [ ] 1.5 — GREEN: extend `chat-surface.tsx` render switch with `null`-returning branches + `: never` rail (placeholders for Phases 2–5).
- [ ] 1.6 — Tests green: `node node_modules/vitest/vitest.mjs run apps/web-platform/test/chat-state-machine`.

## Phase 2 — `subagent-group.tsx`

- [ ] 2.1 — RED: `apps/web-platform/test/subagent-group.test.tsx` covering ≤2/≥3 expand thresholds + per-child status badges + partial-failure rendering. `data-*` hooks only per `cq-jsdom-no-layout-gated-assertions`.
- [ ] 2.2 — GREEN: implement `apps/web-platform/components/chat/subagent-group.tsx` per screenshot `08-subagent-spawn-A-vs-B.png`.
- [ ] 2.3 — GREEN: extend `apps/web-platform/components/chat/message-bubble.tsx` with `parentId` prop + `data-parent-id` attribute. Re-read first per `hr-always-read-a-file-before-editing-it`.
- [ ] 2.4 — GREEN: wire `chat-surface.tsx` `subagent_group` branch.
- [ ] 2.5 — Tests green: `node node_modules/vitest/vitest.mjs run apps/web-platform/test/{subagent-group,message-bubble-memo}`.

## Phase 3 — `interactive-prompt-card.tsx`

- [ ] 3.1 — RED: `apps/web-platform/test/interactive-prompt-card.test.tsx` with one `describe` per `kind`. `.toBe()` per `cq-mutation-assertions-pin-exact-post-state`.
- [ ] 3.2 — Decision recorded: V1 keeps prompt active until responded; no client-side 5min auto-dismiss. Server reaper handles staleness.
- [ ] 3.3 — RED: assertions for WS-frame shape per variant (correct discriminated `interactive_prompt_response` payload).
- [ ] 3.4 — GREEN: implement `apps/web-platform/components/chat/interactive-prompt-card.tsx` (all 6 variants V1 minimal; reference screenshots 06/09/10/11). Grep for existing markdown renderer first; fall back to plain text if absent.
- [ ] 3.5 — GREEN: wire `chat-surface.tsx` `interactive_prompt` branch + `handleInteractivePromptResponse`.
- [ ] 3.6 — Sentinel grep: `rg "(clientWidth|scrollWidth|offsetHeight|getBoundingClientRect)"` over the new test files returns zero.
- [ ] 3.7 — Sentinel grep: `rg "requestAnimationFrame"` over the new component files; if any, wrap tests with `vi.useFakeTimers + vi.advanceTimersByTime` per `cq-raf-batching-sweep-test-helpers`.

## Phase 4 — `workflow-lifecycle-bar.tsx`

- [ ] 4.1 — RED: `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` covering 4 states + CTAs.
- [ ] 4.2 — RED: `apps/web-platform/test/workflow-lifecycle-bar-routing-state.test.tsx` — routing state ≤8s of message; skill-name extraction; `vi.setSystemTime` for determinism.
- [ ] 4.3 — RED: extend `chat-state-machine.test.ts` with reducer transitions for `tool_progress(Skill)` → routing, `workflow_started` → active, `workflow_ended` → ended.
- [ ] 4.4 — GREEN: implement `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` per screenshot `07-workflow-lifecycle-indicators.png`.
- [ ] 4.5 — GREEN: extend reducer with `workflow` slice.
- [ ] 4.6 — GREEN: replace `isClassifying` chip in `chat-surface.tsx` with `<WorkflowLifecycleBar>`. Gate on `conversation.active_workflow !== null` (NOT on feature flag, to avoid stale-flag-at-render risk).
- [ ] 4.7 — GREEN: extend `chat-input.tsx` ended-state disable. Re-read first.
- [ ] 4.8 — Capture screenshots of all 3 states for PR description.
- [ ] 4.9 — Audit `leader-colors.ts` — `cc_router` and `system` already present (Stage 3); confirm gold tone matches design.

## Phase 5 — `tool-use-chip.tsx`

- [ ] 5.1 — RED: `apps/web-platform/test/tool-use-chip.test.tsx` for chip render, completed lifecycle, multiple-coexist.
- [ ] 5.2 — RED: extend `chat-state-machine.test.ts` for `tool_progress` → chip; matching event → `completed: true`.
- [ ] 5.3 — GREEN: implement `apps/web-platform/components/chat/tool-use-chip.tsx`. NO `@/server/tool-labels` import — `toolLabel` arrives pre-built on the WS event.
- [ ] 5.4 — GREEN: wire `chat-surface.tsx` `tool_use_chip` branch.
- [ ] 5.5 — Sentinel grep: `rg "from \"@/server/tool-labels\"" apps/web-platform/components/` returns zero.

## Phase 6 — Integration smoke + visual QA + ship

- [ ] 6.1 — Create `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` — fixture-driven WS event replay through reducer; assert full component tree.
- [ ] 6.2 — `node node_modules/vitest/vitest.mjs run apps/web-platform/test/{subagent-group,interactive-prompt-card,workflow-lifecycle-bar,workflow-lifecycle-bar-routing-state,tool-use-chip,cc-soleur-go-end-to-end-render,chat-state-machine,message-bubble-memo}` — all green.
- [ ] 6.3 — `cd apps/web-platform && npx tsc --noEmit` clean.
- [ ] 6.4 — Local manual QA: `cd apps/web-platform && doppler run -p soleur -c dev -- ./scripts/dev.sh 3001`. Screenshot each new component for PR description.
- [ ] 6.5 — `git status` — only planned files touched. No `.claude/settings.json` drift. Commit allowlist scoped to `apps/web-platform/{components/chat,lib,test}` + `knowledge-base/project/{plans,specs}` per `hr-never-git-add-a-in-user-repo-agents`.
- [ ] 6.6 — Run `compound` per `wg-before-every-commit-run-compound-skill`.
- [ ] 6.7 — Commit, push, open PR with `Closes #2886` in body. Include screenshots + integration test summary.
- [ ] 6.8 — `/ship` lifecycle.

## Acceptance Criteria Mapping

| AC | Phase / Tasks |
|----|---|
| AC1 (RED-first tests) | 1.1, 1.2, 2.1, 3.1, 3.3, 4.1–4.3, 5.1, 5.2, 6.1 |
| AC2 (union widening + `: never`) | 1.2, 1.3, 1.5 |
| AC3 (subagent-group Option A) | 2.1, 2.2 |
| AC4 (interactive-prompt-card 6 variants + `.toBe()` response) | 3.1, 3.3, 3.4, 3.5 |
| AC5 (lifecycle bar 4 states + 8s routing) | 4.1, 4.2, 4.4, 4.6 |
| AC6 (tool-use-chip pre-built label) | 5.1–5.4, 5.5 |
| AC7 (chat-input ended disable) | 4.7 |
| AC8 (message-bubble parentId) | 2.3 |
| AC9 (all tests green) | 6.2 |
| AC10 (tsc clean) | 6.3 |
| AC11 (no layout-gated assertions) | 3.6 + sentinel rg in 6.x |
| AC12 (screenshots) | 4.8, 6.4 |
| AC13 (`Closes #2886`) | 6.7 |
| AC14 (compound) | 6.6 |
| AC15 (no incidental drift) | 6.5 |
