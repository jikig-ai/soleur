# Tasks: feat — Command Center routes via `/soleur:go`

**Issue:** #2853
**Branch:** `feat-cc-single-leader-routing`
**PR:** #2858
**Plan:** [knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md](../../plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md)

## Stage 0 — Invocation-Form Spike (BLOCKS all other stages)

- [ ] 0.1 Read `apps/web-platform/server/agent-runner.ts:670-900` to confirm live `query()` invocation pattern
- [ ] 0.2 Read `spike/agent-sdk-test.ts` (predecessor spike)
- [ ] 0.3 Write `apps/web-platform/scripts/spike-soleur-go-invocation.ts` (`query` against `/soleur:go test brainstorm idea` with `plugins`, `settingSources: ["project"]`, `canUseTool`)
- [ ] 0.4 Iterate prompt form if needed (max 2 iterations); fall back to systemPrompt directive
- [ ] 0.5 Capture metrics: P50/P95 first-token latency (10 runs), `total_cost_usd`, `parent_tool_use_id` presence, `canUseTool` interception
- [ ] 0.6 Append Stage 0 Findings to plan file
- [ ] 0.7 `git rm` spike script before merge
- [ ] 0.X Exit gate: (a) Hyp 1 confirmed within 2 iterations, (b) P95 ≤ 10s, (c) parent_tool_use_id present. Any failure → STOP + Approach B re-plan

## Stage 1 — Schema, Sticky-Workflow State, AGENTS.md Rule

- [ ] 1.1 RED: `apps/web-platform/test/supabase-migrations/032-workflow-state.test.ts` (column existence + nullability)
- [ ] 1.2 GREEN: `apps/web-platform/supabase/migrations/032_conversation_workflow_state.sql` (`active_workflow text NULL`, `workflow_ended_at timestamptz NULL`)
- [ ] 1.3 REFACTOR: regenerate types (`supabase gen types`)
- [ ] 1.4 Apply migration to dev Supabase + verify via REST API
- [ ] 1.5 Update `AGENTS.md` `pdr-when-a-user-message-contains-a-clear` rule (preserve ID; ≤ 600 bytes)
- [ ] 1.6 Run `bash plugins/soleur/scripts/lint-rule-ids.py`

## Stage 2 — Soleur-Go Runner (server core)

- [ ] 2.1 RED: `apps/web-platform/test/soleur-go-runner.test.ts` — dispatch + sticky + sentinel consumption + cost breaker (mocked SDK with synthetic SDKResultMessage)
- [ ] 2.2 RED: `apps/web-platform/test/router-flag-stickiness.test.ts` — flag flip mid-conversation does NOT change `active_workflow`
- [ ] 2.3 GREEN: scaffold `apps/web-platform/server/soleur-go-runner.ts` (dispatch + state persistence + sentinel handling)
- [ ] 2.4 GREEN: inline interactive-tool bridging in runner (translate `tool_use` → `interactive_prompt` events; `pendingPrompts: Map`); document container-restart UX in header comment
- [ ] 2.5 GREEN: per-workflow terminal detection (one-shot/brainstorm/plan/work/review/drain); document exit signals in header
- [ ] 2.6 GREEN: cost circuit breaker (compare against `CC_MAX_CONVERSATION_COST_USD`)
- [ ] 2.7 GREEN: extend `apps/web-platform/server/tool-tiers.ts` (`Bash`, `Edit`, `Write`, `AskUserQuestion`, `ExitPlanMode`, `TodoWrite`, `NotebookEdit`)
- [ ] 2.8 GREEN: extend `apps/web-platform/server/permission-callback.ts` allow-branches (workspace containment via `realpathSync`)
- [ ] 2.9 GREEN: wire `apps/web-platform/server/ws-handler.ts:1185-1352` `sendUserMessage` branching on `active_workflow`
- [ ] 2.10 GREEN: wire `apps/web-platform/server/ws-handler.ts:455-640` `start_session` to set `'__unrouted__'` sentinel when `FLAG_CC_SOLEUR_GO=true`
- [ ] 2.11 GREEN: add `FLAG_CC_SOLEUR_GO` + `CC_MAX_CONVERSATION_COST_USD` to `lib/feature-flags/server.ts` + `.env.example` + Doppler `dev`/`prd`
- [ ] 2.12 File V2 issue: "Persist `pendingPrompts` to `conversations.pending_prompts jsonb` for container-restart survival" (Post-MVP)

## Stage 3 — WebSocket Protocol Extension

- [ ] 3.1 Read `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`; document REPLACE-not-APPEND in runner header
- [ ] 3.2 RED: `apps/web-platform/test/ws-protocol.test.ts` (round-trip per new event type)
- [ ] 3.3 RED: extend `apps/web-platform/test/chat-state-machine.test.ts` (each new variant has reducer case; exhaustive `: never` switch passes `tsc --noEmit`)
- [ ] 3.4 GREEN: extend `apps/web-platform/lib/types.ts:84-115` `WSMessage` union with `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`, `interactive_prompt`, `interactive_prompt_response`
- [ ] 3.5 GREEN: extend `apps/web-platform/lib/chat-state-machine.ts:42-216` `ChatMessage` union; extract render dispatch to `: never`-railed switch
- [ ] 3.6 GREEN: add reducer cases in `apps/web-platform/lib/ws-client.ts:99-148`; re-key `activeStreams` to composite `${parent_id}:${leader_id}` (folds in #2225)
- [ ] 3.7 GREEN: dispatch new event types in `apps/web-platform/lib/ws-client.ts:329-440` `onmessage` switch
- [ ] 3.8 Run `rg "\.kind === " apps/web-platform/lib/` and `rg "\?\.kind === " apps/web-platform/lib/` per `cq-union-widening-grep-three-patterns`
- [ ] 3.9 REFACTOR: derive `activeLeaderIds` via `useMemo` in any consumer (per #2225 fold-in)

## Stage 4 — Chat-UI Bubble Components

- [ ] 4.1 RED: `apps/web-platform/test/subagent-group.test.tsx` (Option A nested layout, ≤2/≥3 expand threshold, per-child status badges, partial-failure rendering)
- [ ] 4.2 GREEN: `apps/web-platform/components/chat/subagent-group.tsx` (reference screenshot `08-*.png`)
- [ ] 4.3 RED: `apps/web-platform/test/interactive-prompt-card.test.tsx` (one `describe` per kind: chip selector + dismiss/timeout, plan accept/iterate, diff summary, bash approve/deny, todo+notebook minimal display)
- [ ] 4.4 GREEN: `apps/web-platform/components/chat/interactive-prompt-card.tsx` (base + 6 internal variants at V1 minimal fidelity)
- [ ] 4.5 RED: `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` (3 states: routing/active/ended; "Switch workflow" CTA; "Start new conversation" CTA)
- [ ] 4.6 GREEN: `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` (reference screenshot `07-*.png`)
- [ ] 4.7 GREEN: wire `apps/web-platform/components/chat/chat-surface.tsx:300-388` render dispatch + `apps/web-platform/components/chat/chat-input.tsx` ended-state disable
- [ ] 4.8 GREEN: extend `apps/web-platform/components/chat/message-bubble.tsx:60-129` for `parentId` indentation
- [ ] 4.9 GREEN: extend `apps/web-platform/components/chat/leader-colors.ts` with gold synthesis palette + `system` neutral
- [ ] 4.10 Verify per `cq-jsdom-no-layout-gated-assertions`: tests use `data-*` hooks, not layout APIs
- [ ] 4.11 Verify per `cq-raf-batching-sweep-test-helpers`: any rAF/queueMicrotask requires `vi.useFakeTimers + vi.advanceTimersByTime`
- [ ] 4.12 File tracking issue: "Mobile-narrow `kb-chat-sidebar.tsx` design pass for cc-soleur-go bubbles" (Post-MVP)

## Stage 5 — Migration & Rollout

- [ ] 5.1 Set `FLAG_CC_SOLEUR_GO=true` in Doppler `dev`
- [ ] 5.2 Write `knowledge-base/engineering/ops/runbooks/cc-soleur-go-rollout.md` (enable + rollback playbook)
- [ ] 5.3 File V2 issue: "Drain-mode rollback for cc-soleur-go" (Post-MVP)
- [ ] 5.4 File V2 issue: "Per-user / per-cohort percentage rollout for FLAG_CC_SOLEUR_GO" (Post-MVP)

## Stage 6 — Pre-merge Verification (Smoke Tests)

- [ ] 6.1 Smoke: "fix issue 2853" → routes to `one-shot` (single leader voice)
- [ ] 6.2 Smoke: "plan a new feature" → routes to `brainstorm` (multi-leader spawn allowed inside)
- [ ] 6.3 Smoke: sticky workflow — turn 2+ stays inside chosen workflow
- [ ] 6.4 Smoke: `@CTO` mid-workflow → parallel side-bubble; pending prompt remains active
- [ ] 6.5 Smoke: cost circuit breaker (set `CC_MAX_CONVERSATION_COST_USD=0.05` temporarily; verify graceful exit + ended-state UX)
- [ ] 6.6 Smoke: workflow-ended state shows disabled input + "Start new conversation" CTA
- [ ] 6.7 Smoke: container restart drops `pendingPrompts`; client reconnect shows session-reset notice
- [ ] 6.8 Capture screenshots for PR description

## Stage 8 — Cleanup (SEPARATE PR — gated by 14-day soak + 0 P0/P1)

- [ ] 8.1 Delete `apps/web-platform/server/domain-router.ts`; relocate `parseAtMentions` → `apps/web-platform/server/at-mentions.ts`
- [ ] 8.2 Relocate `apps/web-platform/test/domain-router.test.ts` → `apps/web-platform/test/at-mentions.test.ts`
- [ ] 8.3 Delete `apps/web-platform/test/multi-leader-session-ended.test.ts` or migrate cases
- [ ] 8.4 Delete `apps/web-platform/test/classify-response.test.ts`
- [ ] 8.5 Collapse `agent-runner.ts` `activeSessions` Map keying to `userId:conversationId`
- [ ] 8.6 Delete `dispatchToLeaders` shim from `agent-runner.ts`
- [ ] 8.7 Delete legacy code-path branch in `ws-handler.ts` `sendUserMessage`
- [ ] 8.8 Delete `FLAG_CC_SOLEUR_GO` from feature-flag module
