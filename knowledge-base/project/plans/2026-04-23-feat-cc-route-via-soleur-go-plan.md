# Plan: feat — Command Center routes via `/soleur:go`

**Issue:** #2853
**Branch:** `feat-cc-single-leader-routing`
**Worktree:** `.worktrees/feat-cc-single-leader-routing/`
**Draft PR:** #2858
**Brainstorm:** [knowledge-base/project/brainstorms/2026-04-23-cc-single-leader-routing-brainstorm.md](../brainstorms/2026-04-23-cc-single-leader-routing-brainstorm.md)
**Spec:** [knowledge-base/project/specs/feat-cc-single-leader-routing/spec.md](../specs/feat-cc-single-leader-routing/spec.md)
**Designs:** [knowledge-base/product/design/command-center/](../../product/design/command-center/) (`cc-embedded-skill-surfaces.pen` + 6 screenshots)
**Milestone:** Post-MVP / Later

> **Plan Review applied (2026-04-23):** DHH + Kieran + code-simplicity reviewers consolidated. 15 simplifications applied — 9 stages → 6, 17 new files → 12, 6 migration columns → 2.

## Overview

Replace the Command Center's bespoke web router (`apps/web-platform/server/domain-router.ts` + the multi-leader fan-out branch in `agent-runner.ts`) with literal invocation of the `/soleur:go` skill via the **already-integrated** `@anthropic-ai/claude-agent-sdk`. Implements sticky-workflow turns, new chat-UI bubble variants for interactive tools, and feature-flagged rollout.

The brainstorm framed this as a major SDK embedding rewrite. Research established that the SDK is **already wired** in `agent-runner.ts` (line 1 import, line 204 + 830 `query()` calls); bubblewrap-inside-Docker sandbox with apparmor + seccomp profiles already configured; per-conversation cost telemetry present. This is a **refactor** of the routing layer that sits *around* an existing SDK call, not a greenfield embed.

The largest deltas are:

1. Delete `dispatchToLeaders` / `routeMessage` / `classifyMessage` (the bespoke Haiku classifier + parallel leader fan-out).
2. Replace with a single `/soleur:go <message>` SDK invocation gated by an `active_workflow` field on `conversations` (with `'__unrouted__'` sentinel value at conversation creation when flag is on).
3. Add new WS event types (`subagent_spawn`, `subagent_complete`, `interactive_prompt`, `workflow_started`, `workflow_ended`) + matching reducer cases.
4. Add 3 new chat-UI components (subagent group + interactive prompt card with 6 internal variants + workflow lifecycle bar that absorbs routing/ended states).
5. Migrate behind feature flag `FLAG_CC_SOLEUR_GO`; legacy router and new runner coexist until flip-to-100% + Stage 8 cleanup PR.

## Research Reconciliation — Spec vs. Codebase

| Spec / Brainstorm Claim | Codebase Reality | Plan Response |
|---|---|---|
| TR1 says "embed `@anthropic-ai/claude-agent-sdk` in `apps/web-platform/server/`". | Already integrated. `agent-runner.ts:1` imports the SDK; `query()` called at L204 + L830. Plugin loading via `plugins: [{ type: "local", path: pluginPath }]` already wired (L830). | Reframe stages from "embed" to "consolidate routing into the existing SDK call". |
| Open Q #1 (sandbox model) framed as undecided between Docker volume / virtual fs / ephemeral worktree. | bubblewrap-inside-Docker is already in production. `Dockerfile:47-49` installs `bubblewrap` + `socat` + `qpdf`; `infra/server.tf` mounts `apparmor-soleur-bwrap.profile` and `seccomp-bwrap.json`; `agent-runner.ts:807-829` configures `denyRead: ["/workspaces", "/proc"]` + `allowWrite: [workspacePath]`. `gh` intentionally absent (PR #2843 → `github_read_*` MCP tools). | Open Q #1 closed: use the existing bwrap sandbox unchanged. The 3-layer constraint per `bwrap-sandbox-three-layer-docker-fix-20260405` learning is preserved. |
| Open Q #5 (SDK availability + stability) flagged as unverified. | SDK is GA at v0.2.118+; pin policy governed by ADR-020 "exact version pinning". v0.2.80 had a `canUseTool` ZodError regression (`2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`). | Open Q #5 closed: pin exact (e.g., `0.2.118`); reference ADR-020. Bumps require a minimal-reproducer check before merge. |
| Open Q #6 (cost ceiling needs new infra). | `increment_conversation_cost` RPC + `total_cost_usd` / `input_tokens` / `output_tokens` columns on `conversations` already exist (migration 017, called at `agent-runner.ts:950-967`). | Extend the existing infra; add a per-conversation soft-cap circuit breaker (no new pipeline). |
| Open Q #7 framed as "feature-flag rollout". | `lib/feature-flags/server.ts` is env-var driven (binary on/off, toggled via Doppler + container restart). NO per-user-percentage rollout. | Decision: binary on/off via `FLAG_CC_SOLEUR_GO` for V1; per-user rollout deferred to a dedicated tracking issue. |
| Spec FR2/TR1: "one runner instance per active conversation". | `agent-runner.ts:778-877` constructs a fresh `query()` per turn, persisting sticky state via DB + the SDK's `resume_session_id` (L894-902). | Adopt the per-turn `query()` pattern (matches existing infra). Sticky-workflow state lives on the `conversations` row. |
| Spec TR3 references "the streamIndexRef Map<DomainLeaderId, number>". | Already migrated to reducer-side `activeStreams` (`ws-client.ts:91-95`, `chat-state-machine.ts:79-216`). The 2026-03-27 learning is stale on this point. | Plan references `activeStreams` directly. Re-key for `(parent_id, leader_id)` to support nested-children rendering. |
| AC #3 (`@mention` escalation UI) listed as work to do. | Already implemented in `at-mention-dropdown.tsx` (139 lines) + `parseAtMentions` (`domain-router.ts:31-76`). | No work; carry forward unchanged. `parseAtMentions` stays in `domain-router.ts` until Stage 8 cleanup (avoids dual-path import churn). |

## Open Code-Review Overlap

- **#2225** — `refactor(chat): tighten activeStreams key type and derive activeLeaderIds via useMemo` → **Fold in.** This plan rewrites `chat-state-machine.ts` `activeStreams` keying. Add `Closes #2225` to the PR body.
- **#2191** — `refactor(ws): introduce clearSessionTimers helper + add refresh-timer jitter and consecutive-failure close` → **Acknowledge.** Orthogonal to routing changes. Stay open. Annotate via `gh issue comment`.

## Hypotheses

The plan rests on three load-bearing assumptions verified during research; if any prove false in implementation, the corresponding stage gates re-planning:

1. **`prompt: "/soleur:go <message>"` invokes the soleur plugin's `/soleur:go` skill via the SDK with `settingSources: ["project"]`.** Per Anthropic docs (claude-code-guide research), skills load from filesystem only and are NOT invokable by direct API; prompt-mention is the documented path. **Verification:** Stage 0 spike.
2. **Subagents spawned by `/soleur:go` (e.g., brainstorm Phase 0.5 spawning CPO + CTO Tasks) emit identifiable events with `parent_tool_use_id`.** Per docs, subagents run in-process and emit `parent_tool_use_id`. **Verification:** Stage 0 spike extends to invoke `/soleur:brainstorm "test feature"`.
3. **`canUseTool` callback intercepts skill-invoked tools when those tools are NOT pre-approved by `allowedTools`.** Per learning `2026-03-16-agent-sdk-spike-validation.md`. **Verification:** existing `permission-callback.ts` tests cover this path; extend with a test that `AskUserQuestion` triggers `canUseTool` rather than auto-execute.

## Implementation Phases

### Stage 0 — Invocation-Form Spike (front-loaded, blocks all other stages)

**Goal:** Verify the three Hypotheses above before touching production code.

**Deliverable:** A throwaway script `apps/web-platform/scripts/spike-soleur-go-invocation.ts` (NOT shipped — deleted after findings recorded). Outputs JSON: skill-invocation success, subagent-spawn event shape, `canUseTool` interception confirmation, first-token latency, total cost.

**Tasks:**

- [ ] 0.1 — Read existing `apps/web-platform/server/agent-runner.ts:670-900` to confirm the live `query()` invocation pattern.
- [ ] 0.2 — Read existing `spike/agent-sdk-test.ts` (predecessor spike — surface for streaming-message handling reference).
- [ ] 0.3 — Write spike script that invokes `query({ prompt: "/soleur:go test brainstorm idea", plugins: [{type:"local", path: pluginPath}], settingSources: ["project"], canUseTool: ... })` against a known-empty workspace.
- [ ] 0.4 — Iterate on prompt form if `/soleur:go <msg>` doesn't trigger the skill — fall back to a system-prompt directive (`systemPrompt: "Always invoke /soleur:go with the user's message"`).
- [ ] 0.5 — Capture: first-token latency (median + P95 over 10 runs), `SDKResultMessage.total_cost_usd`, presence/absence of `parent_tool_use_id` on spawned subagent events, `canUseTool` interception of `AskUserQuestion`.
- [ ] 0.6 — Append findings to this plan as `### Stage 0 Findings` section before proceeding to Stage 1.
- [ ] 0.7 — Delete the spike script from the PR before merge (`git rm`).

**Exit criteria (sharpened per Kieran P1):**

- [ ] (a) Hypothesis 1 confirmed within **2 prompt-form iterations** (skill invocation reported in `tool_use` events).
- [ ] (b) **P95 first-token latency ≤ 10s** per spec TR4 (10 runs, controlled workspace).
- [ ] (c) **`parent_tool_use_id` present** on at least one spawned subagent event.

Any (a/b/c) failure → STOP; append findings with "Stage 0 BLOCKED" header; present Approach B re-plan to user before any Stage 1 work.

### Stage 1 — Schema, Sticky-Workflow State, AGENTS.md Rule Update

**Goal:** Persist sticky-workflow state on `conversations`; update the AGENTS.md routing rule (folded in from former Stage 9 — one-line change).

**Files to create:**

- `apps/web-platform/supabase/migrations/032_conversation_workflow_state.sql` — adds two columns:
  - `active_workflow text NULL` — workflow name when set; sentinel value `'__unrouted__'` when conversation is born under the flag but `/soleur:go` hasn't run yet; NULL = legacy router.
  - `workflow_ended_at timestamptz NULL` — set when `workflow_ended` WS event fires.

  No `router_version`, no `workflow_metadata`, no `workflow_started_at`, no `workflow_outcome`. The `active_workflow IS NOT NULL` check (which includes the `'__unrouted__'` sentinel) is the single discriminator for new vs legacy router. Workflow start time is derivable from row insertion timestamp + first message; outcome is derivable from `workflow_ended_at IS NOT NULL` + the WS-emitted summary (added later if a consumer needs it). Per `cq-supabase-migration-concurrently-forbidden`: read 2-3 most recent migrations first; plain `ALTER TABLE ADD COLUMN` is transactional-safe.

**Files to edit:**

- `apps/web-platform/server/types.ts` (or wherever `Conversation` row type lives) — add the two new optional fields.
- `AGENTS.md` — replace `pdr-when-a-user-message-contains-a-clear` rule wording. Preserve rule ID per `cq-rule-ids-are-immutable`.

  **Proposed wording (~570 bytes — under the 600-byte cap):**

  ```
  - When a user message contains a clear domain signal unrelated to the current task, route based on signal orthogonality: spawn multiple leaders ONLY when the message contains distinct asks across different domains (e.g., "review expense AND audit privacy policy"); spawn a single leader for single-domain signals. Spawn via `run_in_background: true` per `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Note: governs CLI agent routing; Command Center web app routes via `/soleur:go`. **Why:** #2853.
  ```

**Tasks:**

- [ ] 1.1 — RED: write `test/supabase-migrations/032-workflow-state.test.ts` asserting both columns exist with correct types and that legacy rows accept NULL.
- [ ] 1.2 — GREEN: write the migration SQL.
- [ ] 1.3 — REFACTOR: regenerate types if the project uses `supabase gen types`.
- [ ] 1.4 — Apply migration to dev Supabase and assert via REST API per `wg-when-a-pr-includes-database-migrations`. Document the apply step in Acceptance Criteria → Post-merge.
- [ ] 1.5 — Apply AGENTS.md rule edit. Verify byte length: `awk '/pdr-when-a-user-message-contains-a-clear/ {print length($0)}' AGENTS.md` ≤ 600.
- [ ] 1.6 — Run `bash plugins/soleur/scripts/lint-rule-ids.py` to verify rule ID preserved.

### Stage 2 — Soleur-Go Runner (server core)

**Goal:** Single source of truth for `/soleur:go` SDK invocation + interactive-tool bridging + pending-prompt registry. Replaces the routing core of `agent-runner.ts` for new conversations.

**Files to create:**

- `apps/web-platform/server/soleur-go-runner.ts` — exports `dispatchSoleurGo(conversationId, userMessage, opts)`. Internally:
  - Calls `query()` against the soleur plugin with `settingSources: ["project"]`.
  - Persists `active_workflow` on first dispatch (replaces `'__unrouted__'` sentinel with the actual workflow name).
  - Translates SDK `tool_use` blocks for `AskUserQuestion`/`ExitPlanMode`/`Edit`/`Write`/`Bash`/`TodoWrite`/`NotebookEdit` directly into `interactive_prompt` WS events (inline, no separate bridge module — single consumer per code-simplicity review).
  - Maintains a per-conversation `pendingPrompts: Map<string, PendingPrompt>` field for reconnect replay (per Flow 3.2 spec-flow gap).
  - Detects per-workflow terminal conditions and emits `workflow_ended`.
  - On each `SDKResultMessage`, compares cumulative `total_cost_usd` against `CC_MAX_CONVERSATION_COST_USD` (default `$1.00`); on exceed, emits `workflow_ended { status: "cost_ceiling" }`.
  - Per `cq-silent-fallback-must-mirror-to-sentry`: every catch block calls `reportSilentFallback(err, { feature: "soleur-go-runner", op })`.

  ~350 lines (larger than original because it absorbs the bridge logic).

**Files to edit:**

- `apps/web-platform/server/agent-runner.ts:1127-1180` — delete `dispatchToLeaders` (or shim during dual-path window). The leader-keyed `activeSessions` Map (L84-90) gets a parallel workflow-keyed Map for the new path; full collapse to single Map deferred to Stage 8 cleanup.
- `apps/web-platform/server/ws-handler.ts:1185-1352` — `sendUserMessage` orchestration: branch on `conversation.active_workflow` (NULL → legacy router, non-NULL including `'__unrouted__'` → `dispatchSoleurGo`). On router-init, `dispatchSoleurGo` consumes `'__unrouted__'` and updates the column with the actual chosen workflow.
- `apps/web-platform/server/ws-handler.ts:455-640` — `start_session`: when `FLAG_CC_SOLEUR_GO=true`, set `active_workflow='__unrouted__'` on the new conversation row. Existing conversations are unaffected. The flag is read **once at conversation creation time only** — mid-conversation flag flips do NOT change the routing path for existing conversations (per Flow 6.2 spec-flow gap).
- `apps/web-platform/server/tool-tiers.ts:20-47` — extend `TOOL_TIER_MAP` with `Bash`, `Edit`, `Write`, `AskUserQuestion`, `ExitPlanMode`, `TodoWrite`, `NotebookEdit`. Default is `gated` (fail-closed) — every new SDK-native tool needs an explicit entry.
- `apps/web-platform/server/permission-callback.ts` — extend `canUseTool` allow-branches for skill-spawned tools. Workspace containment via `realpathSync` per `2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`.
- `apps/web-platform/server/agent-env.ts:42-72` — add any `CLAUDE_CODE_*` / `MCP_*` env passthrough required by `/soleur:go` plugin tools (informed by Stage 0 spike).
- `apps/web-platform/lib/feature-flags/server.ts:10-13` — add `command-center-soleur-go: process.env.FLAG_CC_SOLEUR_GO === "true"`.
- `.env.example` + Doppler `dev` and `prd` configs — add `FLAG_CC_SOLEUR_GO=false` (default off; admin flips per-environment) and `CC_MAX_CONVERSATION_COST_USD=1.00`.

**Tasks:**

- [ ] 2.1 — RED: write `test/soleur-go-runner.test.ts` covering: dispatch on first turn (consumes `'__unrouted__'` sentinel), sticky workflow on turn 2+, NULL active_workflow → legacy router branch, cost circuit breaker graceful exit (assertions inject synthetic `SDKResultMessage` with controlled cost values; the SDK is mocked per `cq-llm-sdk-security-tests-need-deterministic-invocation`), pending-prompt registry behaviour (Map field).
- [ ] 2.2 — RED: assert flag-flip mid-conversation does NOT change `active_workflow` on existing conversations (`test/router-flag-stickiness.test.ts`).
- [ ] 2.3 — GREEN: implement `soleur-go-runner.ts` skeleton (no streaming yet — just dispatch + state persistence + sentinel handling).
- [ ] 2.4 — GREEN: implement inline interactive-tool bridging in the runner (translate `tool_use` blocks → `interactive_prompt` events; pending-prompt Map). Document accepted UX in runner header comment: **"Container restart drops in-memory pendingPrompts. User sees a 'session reset — please reply to continue' notice on reconnect with a then-empty registry."** File V2 issue: persist `pendingPrompts` to `conversations.pending_prompts jsonb` for restart-survival.
- [ ] 2.5 — GREEN: implement per-workflow terminal detection (one-shot → PR opened or user-aborted; brainstorm → spec written or user-aborted; plan → tasks.md written or user-aborted; work → all tasks completed or user-aborted; review → review report posted or user-aborted; drain → no more issues or user-aborted). Document per-workflow exit signals in the runner header comment.
- [ ] 2.6 — GREEN: implement cost circuit breaker.
- [ ] 2.7 — GREEN: extend `tool-tiers.ts` (review each new tool against TOOL_TIER_MAP defaults).
- [ ] 2.8 — GREEN: extend `permission-callback.ts` allow-branches.
- [ ] 2.9 — GREEN: wire `ws-handler.ts` `sendUserMessage` branching on `active_workflow` (NULL → legacy; non-NULL → soleur-go-runner).
- [ ] 2.10 — GREEN: wire `ws-handler.ts` `start_session` to set `'__unrouted__'` sentinel on new conversations when flag is on.
- [ ] 2.11 — GREEN: add `FLAG_CC_SOLEUR_GO` and `CC_MAX_CONVERSATION_COST_USD` to feature-flag module + `.env.example` + Doppler.
- [ ] 2.12 — File V2 issue: "Persist `pendingPrompts` to `conversations.pending_prompts jsonb` for container-restart survival". Milestone Post-MVP / Later.

### Stage 3 — WebSocket Protocol Extension

**Goal:** Add new event types so the runner's structured output renders as new bubble variants.

**Files to edit:**

- `apps/web-platform/lib/types.ts:84-115` — extend the `WSMessage` discriminated union with:
  - `subagent_spawn { type: "subagent_spawn", parent_id: string, leader_id: DomainLeaderId, spawn_id: string }`
  - `subagent_complete { type: "subagent_complete", spawn_id: string, status: "success" | "error" | "timeout" }`
  - `workflow_started { type: "workflow_started", workflow: WorkflowName, conversation_id: string }`
  - `workflow_ended { type: "workflow_ended", workflow: WorkflowName, status: "completed" | "error" | "user_aborted" | "cost_ceiling", summary?: string }`
  - `interactive_prompt { type: "interactive_prompt", prompt_id: string, kind: "ask_user" | "plan_preview" | "diff" | "bash_approval" | "todo_write" | "notebook_edit", payload: ... }`
  - `interactive_prompt_response { type: "interactive_prompt_response", prompt_id: string, response: ... }` (client → server)
- `apps/web-platform/lib/chat-state-machine.ts:42-216` — extend `ChatMessage` discriminated union with matching variants. Per `cq-union-widening-grep-three-patterns`: extract render dispatch into a `: never`-railed switch. **Folds in #2225** (activeStreams key tightening).
- `apps/web-platform/lib/ws-client.ts:99-148` (`chatReducer`) — add reducer cases for each new event type. Re-key `activeStreams` from `Map<DomainLeaderId, number>` to `Map<string, number>` keyed by composite `${parent_id}:${leader_id}`.
- `apps/web-platform/lib/ws-client.ts:329-440` (`onmessage` switch) — dispatch new event types.

**Tasks:**

- [ ] 3.1 — Read `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`. Every new partial event type must REPLACE not APPEND on the client side. Document this in the runner's header comment.
- [ ] 3.2 — RED: write `test/ws-protocol.test.ts` cases for each new event type round-trip (server emit → client parse → state mutation).
- [ ] 3.3 — RED: write `test/chat-state-machine.test.ts` cases asserting each new variant has a reducer case AND that the exhaustive `: never` switch passes `tsc --noEmit`.
- [ ] 3.4 — GREEN: implement union widenings + reducer cases. Per `cq-union-widening-grep-three-patterns`, run `rg "\.kind === " apps/web-platform/lib/` and `rg "\?\.kind === " apps/web-platform/lib/` to catch all consumer if-ladders.
- [ ] 3.5 — REFACTOR: per #2225 fold-in, derive `activeLeaderIds` via `useMemo` in any consumer.

### Stage 4 — Chat-UI Bubble Components

**Goal:** Implement 3 new components that absorb the 6 designed surfaces.

**Files to create:**

- `apps/web-platform/components/chat/subagent-group.tsx` — parent assessment bubble + nested children renderer (Option A from brainstorm Q#3 resolution). Default expanded for ≤2 children, collapsed for ≥3. Per-child status badges (per Flow 4.1 spec-flow gap).
- `apps/web-platform/components/chat/interactive-prompt-card.tsx` — base component dispatching to per-`kind` variants. **V1 minimal renderers** (avoid blank/error bubbles when SDK fires these tools; polished interactions deferred to V2):
  - **`ask_user`** — full chip selector (single + multi-select per the design — load-bearing per DHH).
  - **`plan_preview`** — markdown preview + Accept / Iterate buttons.
  - **`diff`** — collapsed summary "Edited file `<path>` (+N -M)" with no inline diff yet (V2: full diff viewer).
  - **`bash_approval`** — command + collapsed output + Approve/Deny if gated, auto-display if approved (V1: no streaming; V2: live stream).
  - **`todo_write`** — count + collapsed list.
  - **`notebook_edit`** — count + cell IDs + collapsed display.
- `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` — sticky context bar carrying:
  - **Routing state** ("Routing your message…" — replaces the original `routing-indicator.tsx`).
  - **Active state** (workflow name + phase indicator + cumulative cost + "Switch workflow" CTA per Flow 1.2).
  - **Ended state** (completion summary + workflow name + outcome + cost + "Start new conversation" CTA — replaces the original `workflow-ended-card.tsx`).

**Files to edit:**

- `apps/web-platform/components/chat/chat-surface.tsx:300-388` — render loop dispatches on `subagent_group` / `interactive_prompt_card` / `workflow_lifecycle_bar` variants in addition to existing `text` / `review_gate`.
- `apps/web-platform/components/chat/message-bubble.tsx:60-129` — accept `parentId` for indentation; preserve existing `leaderId` + `messageState`.
- `apps/web-platform/components/chat/leader-colors.ts` — add gold-bordered palette for synthesis bubble + neutral palette for `system` workflow attribution.
- `apps/web-platform/components/chat/chat-input.tsx` — disabled state when `conversation.workflow_ended_at IS NOT NULL`. ~15 lines.

**Tasks (per Kieran P1: decompose Stage 4 into RED→GREEN pairs per component):**

- [ ] 4.1 — RED: write `test/subagent-group.test.tsx` asserting Option A nested-children layout, expand/collapse threshold (≤2 / ≥3), per-child status badges, partial-failure rendering.
- [ ] 4.2 — GREEN: implement `subagent-group.tsx`. Reference Pencil screenshot `08-subagent-spawn-A-vs-B.png`.
- [ ] 4.3 — RED: write `test/interactive-prompt-card.test.tsx` with one `describe` block per kind asserting: chip selector keyboard nav + dismiss-without-selecting (null sentinel after 5min timeout per Flow 3.1), plan preview accept/iterate, diff collapsed summary present, bash approve/deny, todo+notebook minimal display.
- [ ] 4.4 — GREEN: implement `interactive-prompt-card.tsx` with all 6 variants at V1 minimal fidelity.
- [ ] 4.5 — RED: write `test/workflow-lifecycle-bar.test.tsx` asserting all 3 states (routing → active → ended) render correctly, "Switch workflow" CTA fires the right WS event, "Start new conversation" CTA opens `start_session`.
- [ ] 4.6 — GREEN: implement `workflow-lifecycle-bar.tsx`. Reference Pencil screenshot `07-workflow-lifecycle-indicators.png`.
- [ ] 4.7 — GREEN: wire `chat-surface.tsx` render dispatch + `chat-input.tsx` ended-state disable.
- [ ] 4.8 — Per `cq-jsdom-no-layout-gated-assertions`: tests assert structure or `data-*` hooks, NOT `clientWidth`/`offsetHeight`/`getBoundingClientRect`.
- [ ] 4.9 — Per `cq-raf-batching-sweep-test-helpers`: any `requestAnimationFrame` / `queueMicrotask` introduced in components requires `vi.useFakeTimers({ shouldAdvanceTime: true }) + vi.advanceTimersByTime(<frame-ms>)`.
- [ ] 4.10 — File tracking issue: "Mobile-narrow `kb-chat-sidebar.tsx` design pass for cc-soleur-go bubbles" (Phase 2 design pass per ux-design-lead handoff).

### Stage 5 — Migration & Rollout

**Goal:** Safe coexistence of legacy router + new runner during validation window.

**Decisions:**

- **Default off in prod** (`FLAG_CC_SOLEUR_GO=false` in Doppler `prd`).
- **On in dev** (`FLAG_CC_SOLEUR_GO=true` in Doppler `dev`) — operator dogfoods first.
- **Mid-conversation flag flip is forbidden** by design (per Flow 6.2 spec-flow gap): conversation router is decided at conversation creation time via the `'__unrouted__'` sentinel, persisted on the row.
- **Flag-disable does NOT terminate active runners** — in-flight conversations on the new runner continue to completion even after admin disables the flag.
- **Rollback story:** hard cutoff acceptable (drop in-flight) for V1; drain-mode is V2 work — file as a tracking issue.

**Tasks:**

- [ ] 5.1 — Set `FLAG_CC_SOLEUR_GO=true` in Doppler `dev` per `cq-doppler-service-tokens-are-per-config`.
- [ ] 5.2 — Document the rollout playbook in `knowledge-base/engineering/ops/runbooks/cc-soleur-go-rollout.md` (NEW): "On enable: confirm `FLAG_CC_SOLEUR_GO=true` in Doppler config; restart container. On rollback: set to `false`; in-flight conversations continue, new conversations revert to legacy router."
- [ ] 5.3 — File V2 issue: "Drain-mode rollback for cc-soleur-go (terminate in-flight gracefully on flag disable)". Milestone Post-MVP / Later.
- [ ] 5.4 — File V2 issue: "Per-user / per-cohort percentage rollout for FLAG_CC_SOLEUR_GO (current infra is binary on/off only)". Milestone Post-MVP / Later.

### Stage 6 — Pre-merge Verification

**Goal:** AGENTS.md `wg-when-a-feature-creates-external-resources` discipline — black-box probe of user-visible outcomes before flipping prod.

**Tasks:**

- [ ] 6.1 — Smoke-test new conversation in dev: type "fix issue 2853" → assert routes to `one-shot` (single leader voice).
- [ ] 6.2 — Smoke-test new conversation in dev: type "plan a new feature" → assert routes to `brainstorm` (multi-leader spawn allowed inside brainstorm).
- [ ] 6.3 — Smoke-test sticky workflow: turn 2+ stays inside the chosen workflow.
- [ ] 6.4 — Smoke-test `@CTO` mid-workflow: parallel side-bubble; pending prompt remains active.
- [ ] 6.5 — Smoke-test cost circuit breaker by setting `CC_MAX_CONVERSATION_COST_USD=0.05` in dev temporarily; trigger a brainstorm; verify graceful exit + workflow-ended-card.
- [ ] 6.6 — Smoke-test workflow-ended state shows disabled input + "Start new conversation" CTA.
- [ ] 6.7 — Smoke-test container restart: verify in-memory `pendingPrompts` drops; client reconnect shows session-reset notice.
- [ ] 6.8 — Capture screenshots for PR description.

### Stage 8 — Cleanup (separate PR — gated by 14-day dev soak + 0 P0/P1 incidents)

**Goal:** Delete legacy router after dual-path validation. **Separate PR** — keep DHH's recommendation; flag-flip rollback only works while legacy code path exists.

**Tasks (separate PR, NOT in this plan's PR):**

- [ ] 8.1 — Delete `apps/web-platform/server/domain-router.ts` (relocate `parseAtMentions` to `at-mentions.ts`).
- [ ] 8.2 — Relocate `test/domain-router.test.ts` → `test/at-mentions.test.ts` (preserves the 20-test surface).
- [ ] 8.3 — Delete `test/multi-leader-session-ended.test.ts` if multi-leader fan-out is gone, or migrate cases to brainstorm-spawned subagent fan-out semantics if still relevant.
- [ ] 8.4 — Delete `test/classify-response.test.ts` (classifier path gone).
- [ ] 8.5 — Collapse `agent-runner.ts` `activeSessions` Map keying from `userId:conversationId:leaderId` to `userId:conversationId` (single key per conversation).
- [ ] 8.6 — Delete the now-unreachable `dispatchToLeaders` shim from `agent-runner.ts`.
- [ ] 8.7 — Delete the legacy code-path branch in `ws-handler.ts` `sendUserMessage`.
- [ ] 8.8 — Delete `FLAG_CC_SOLEUR_GO` from feature-flag module (now always on).

## Files to Edit (consolidated)

| Path | Stage | Why |
|---|---|---|
| `apps/web-platform/server/agent-runner.ts` | 2 | Delete `dispatchToLeaders`; thin shim during dual-path. Full collapse Stage 8. |
| `apps/web-platform/server/ws-handler.ts` | 2 | `sendUserMessage` branching, `start_session` sentinel set, `workflow_ended` handling. |
| `apps/web-platform/server/tool-tiers.ts` | 2 | Extend `TOOL_TIER_MAP` with skill-execution tools. |
| `apps/web-platform/server/permission-callback.ts` | 2 | Allow-branches for skill-spawned tools. |
| `apps/web-platform/server/agent-env.ts` | 2 | Env passthrough for plugin tools. |
| `apps/web-platform/server/types.ts` | 1 | Conversation type adds `active_workflow?`, `workflow_ended_at?`. |
| `apps/web-platform/lib/types.ts` | 3 | Extend `WSMessage` union. |
| `apps/web-platform/lib/chat-state-machine.ts` | 3 | Extend `ChatMessage` union; exhaustive switch; folds in #2225. |
| `apps/web-platform/lib/ws-client.ts` | 3 | Reducer cases + `onmessage` switch + activeStreams re-key. |
| `apps/web-platform/lib/feature-flags/server.ts` | 2 | `FLAG_CC_SOLEUR_GO`. |
| `apps/web-platform/components/chat/chat-surface.tsx` | 4 | Render loop dispatch for new variants. |
| `apps/web-platform/components/chat/message-bubble.tsx` | 4 | `parentId` indentation. |
| `apps/web-platform/components/chat/leader-colors.ts` | 4 | Gold synthesis palette + `system` neutral. |
| `apps/web-platform/components/chat/chat-input.tsx` | 4 | Ended-state disable. |
| `.env.example` | 2 | `FLAG_CC_SOLEUR_GO`, `CC_MAX_CONVERSATION_COST_USD`. |
| `AGENTS.md` | 1 | Rule wording update (folded in from former Stage 9). |

## Files to Create (consolidated)

| Path | Stage | Why |
|---|---|---|
| `apps/web-platform/supabase/migrations/032_conversation_workflow_state.sql` | 1 | `active_workflow` (with `'__unrouted__'` sentinel), `workflow_ended_at`. |
| `apps/web-platform/server/soleur-go-runner.ts` | 2 | Single source of truth: `/soleur:go` invocation + sticky workflow + inline tool-bridging + pending-prompt registry + workflow-ended detection + cost circuit breaker. |
| `apps/web-platform/components/chat/subagent-group.tsx` | 4 | Parent assessment bubble + nested children (Q#3 Option A). |
| `apps/web-platform/components/chat/interactive-prompt-card.tsx` | 4 | Base + 6 internal variants (chip / plan / diff / bash / todo / notebook) at V1 minimal fidelity. |
| `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` | 4 | Sticky bar carrying routing / active / ended states. |
| `apps/web-platform/test/soleur-go-runner.test.ts` | 2 | Dispatch + sticky + ended state + cost breaker (mocked SDK). |
| `apps/web-platform/test/router-flag-stickiness.test.ts` | 2 | Flag flip mid-conversation invariance. |
| `apps/web-platform/test/supabase-migrations/032-workflow-state.test.ts` | 1 | Migration column existence + nullability. |
| `apps/web-platform/test/ws-protocol.test.ts` | 3 | Round-trip per new event type. |
| `apps/web-platform/test/subagent-group.test.tsx` | 4 | Nested layout + threshold + partial failure. |
| `apps/web-platform/test/interactive-prompt-card.test.tsx` | 4 | Per-variant interactions. |
| `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` | 4 | All 3 states + CTAs. |
| `knowledge-base/engineering/ops/runbooks/cc-soleur-go-rollout.md` | 5 | Enable / rollback playbook. |

## Files to Delete (Stage 8 — separate PR)

| Path | Why |
|---|---|
| `apps/web-platform/server/domain-router.ts` | Routing core gone; `parseAtMentions` relocated. |
| `apps/web-platform/test/domain-router.test.ts` | Tests relocated. |
| `apps/web-platform/test/multi-leader-session-ended.test.ts` | Multi-leader fan-out gone (or migrate). |
| `apps/web-platform/test/classify-response.test.ts` | Classifier gone. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: Stage 0 spike findings appended to this plan; Hypothesis 1 confirmed (or alternative invocation form documented).
- [ ] AC2: Migration 032 applied to dev Supabase + verified via REST API per `wg-when-a-pr-includes-database-migrations`.
- [ ] AC3: With `FLAG_CC_SOLEUR_GO=true`, new Command Center conversations route via `/soleur:go`. Verified by Stage 6 smoke-tests.
- [ ] AC4: Existing in-flight conversations (created with `FLAG_CC_SOLEUR_GO=false`) continue on legacy router after flag flip — `active_workflow IS NULL` is sticky.
- [ ] AC5: All 3 new chat-UI components render per the Pencil designs at V1 fidelity (manual QA against `screenshots/06-*.png` through `11-*.png`).
- [ ] AC6: Sticky-workflow turns work — turn 2+ stays inside the chosen workflow's dialogue without re-invoking `/soleur:go`.
- [ ] AC7: `@mention` escalation continues to work as before (no regression on existing 20 tests).
- [ ] AC8: Cost circuit breaker test asserts graceful exit at `CC_MAX_CONVERSATION_COST_USD`. **Test approach:** the SDK is mocked; tests inject synthetic `SDKResultMessage` with controlled `total_cost_usd` values; the assertion threshold (`$0.10` for fast iteration) is independent of any real-API budget.
- [ ] AC9: Workflow-ended state shows disabled input + "Start new conversation" CTA (in `workflow-lifecycle-bar.tsx` ended state) per design.
- [ ] AC10: `pdr-when-a-user-message-contains-a-clear` rule updated in Stage 1; byte length ≤ 600; rule ID preserved.
- [ ] AC11: All test scenarios pass: `soleur-go-runner`, `router-flag-stickiness`, `032-workflow-state`, `ws-protocol`, `subagent-group`, `interactive-prompt-card`, `workflow-lifecycle-bar`.
- [ ] AC12: Closes #2225 (chat-state-machine `activeStreams` refactor folded in).
- [ ] AC13: TypeScript build passes; no fabricated CLI tokens in any user-facing docs per `cq-docs-cli-verification`.
- [ ] AC14: Per `cq-silent-fallback-must-mirror-to-sentry`: every catch block in `soleur-go-runner.ts` calls `reportSilentFallback`.
- [ ] AC15: Stage 6 smoke-tests passed; screenshots attached to PR description.
- [ ] AC16: V2 tracking issues filed: drain-mode rollback (Stage 5.3), per-user rollout (Stage 5.4), pendingPrompts persistence (Stage 2.12), mobile-narrow design pass (Stage 4.10).

### Post-merge (operator)

- [ ] PM1: Confirm `FLAG_CC_SOLEUR_GO=true` in Doppler `dev`; restart `apps/web-platform` container; smoke-test a new conversation.
- [ ] PM2: Soak in dev for 14 days. Track: P95 first-token latency (must hold ≤ 10s per TR4), P95 conversation cost (≤ $1 per TR5), 0 stuck-bubble incidents, 0 plugin-load failures.
- [ ] PM3: After soak passes (zero P0/P1 incidents over 14 days), file Stage 8 cleanup PR.
- [ ] PM4: Verify migration 032 applied to prod Supabase before flipping prod flag.
- [ ] PM5: Post-flip smoke test on prod with a synthetic conversation.

## Test Strategy

**Framework:** Vitest (existing). Per `cq-in-worktrees-run-vitest-via-node-node`, run via `node node_modules/vitest/vitest.mjs run` from worktree root, NOT `npx vitest`.

**Per `cq-write-failing-tests-before` (TDD gate):** every Files-to-Create test file lands RED before its corresponding source file lands GREEN. Stage 4 test tasks are explicitly decomposed into per-component RED→GREEN pairs.

**Per `cq-jsdom-no-layout-gated-assertions`:** UI tests use `data-*` hooks, not layout APIs.

**Per `cq-vitest-setup-file-hook-scope`:** any cross-file leak fix goes in `afterAll` or `isolate: true`, never `afterEach`.

**Per `cq-test-mocked-module-constant-import`:** if any test fully `vi.mock()`s `domain-router.ts`, constants imported from that module must come via the mock factory.

**Per `cq-llm-sdk-security-tests-need-deterministic-invocation`:** the `soleur-go-runner.test.ts` MUST NOT exercise security or cost invariants via natural-language prompts. Direct invocation of `dispatchSoleurGo()` with mocked SDK responses is the assertion path.

**Per `cq-mutation-assertions-pin-exact-post-state`:** assertions on `active_workflow` / `workflow_ended_at` columns use `.toBe(...)` exact values.

## Risks

1. **Stage 0 spike fails Hypothesis 1.** If `/soleur:go` is not invokable via prompt (or system-prompt directive within 2 iterations), the architecture must revert to Approach B (port the classifier). Re-plan with same brainstorm but Approach B instead.
2. **SDK breaking change.** Per ADR-020 exact pinning. Bumps require minimal-reproducer test before merge.
3. **Cold-start latency exceeds TR4 (P95 < 10s).** Stage 0 spike measures this. If exceeded, options: (a) warm-pool the SDK runner per-conversation, (b) accept higher latency for V1 with clear loading indicator (the lifecycle-bar's "Routing your message…" state already covers this UX), (c) defer to V2.
4. **In-process subagent concurrency limits.** No prior learning. Stage 0 spike attempts at least 3 concurrent subagent spawns; if Node process struggles, brainstorm Phase 0.5 multi-leader spawn must be capped at N=2 (currently MAX_LEADERS_PER_MESSAGE=3).
5. **Stuck-bubble regression.** PR #2843 just fixed this for the legacy multi-leader path. New event types must follow the same lifecycle invariants — every bubble in `thinking` / `tool_use` / `streaming` must transition to `done` / `error` before activeStreams clears.
6. **Pencil designs assume specific layout primitives.** The 6 .pen frames target the wide `chat-surface.tsx` layout. Narrow `kb-chat-sidebar.tsx` variant deferred (Stage 4.10 tracking issue).
7. **Sandbox audit gap.** The `bwrap` sandbox is configured but skill execution exercises tool surfaces the existing audit may not have covered (e.g., `Edit`/`Write` from inside a brainstorm subagent). Stage 6 black-box smoke-test is the gate before flipping prod.
8. **Pending-prompt registry drops on container restart.** Accepted V1 UX (session-reset notice). V2 persistence tracked in Stage 2.12 issue.

## Domain Review

**Domains relevant:** Engineering, Product (carry-forward from brainstorm).

### Engineering (CTO, brainstorm carry-forward)

**Status:** reviewed
**Assessment:** Largest impact area. SDK already integrated; sandbox model already configured (bubblewrap + apparmor + seccomp). Real risks are (a) Hypothesis 1 (skill invocation form), (b) per-conversation concurrent SDK session limits, (c) cost telemetry under-counting subagents. Plan front-loads spike (Stage 0) and adds explicit risk tracking.

### Product (CPO, brainstorm carry-forward)

**Status:** reviewed
**Assessment:** UX shift mostly invisible for routine messages (single leader voice replaces today's parallel bubbles for execution intents). Brainstorm-mode conversations look the same. New surfaces (workflow lifecycle bar with routing/active/ended states, interactive prompt card) extend the chat language without breaking existing patterns.

### Product/UX Gate

**Tier:** blocking (mechanical escalation: new `components/chat/*.tsx` files)
**Decision:** reviewed (carry-forward)
**Agents invoked:** spec-flow-analyzer (this plan, fresh — 33 flow gaps surfaced and resolved), ux-design-lead (brainstorm phase, .pen + 6 screenshots), CPO (brainstorm phase, inline)
**Skipped specialists:** copywriter (no domain leader recommended; no brand-voice surfaces beyond existing chat patterns)
**Pencil available:** yes (verified)

#### Findings

`spec-flow-analyzer` returned 33 flow gaps including 12 blockers. Resolutions folded into the plan:

- **Flow 1.1** (pre-classification gap) → Stage 4 `workflow-lifecycle-bar.tsx` routing state
- **Flow 1.2** (sticky-trap escape) → Stage 4 `workflow-lifecycle-bar.tsx` "Switch workflow" CTA
- **Flow 2.1** (terminal states) → Stage 2.5 per-workflow exit detection
- **Flow 3.1** (dismiss-without-selecting) → Stage 2.4 inline bridge null sentinel + 5min timeout
- **Flow 3.2** (refresh-mid-prompt) → Stage 2.4 in-memory `pendingPrompts` Map; container-restart UX documented; V2 persistence in Stage 2.12 tracking issue
- **Flow 3.3** (Bash approval model) → preserved by existing `permission-callback.ts` allow-list (Stage 2.8)
- **Flow 4.1** (partial subagent failure) → Stage 4 per-child status badges + N/M synthesis
- **Flow 4.3** (per-subagent budget) → DEFERRED to V2 entirely per all-3-reviewer consensus
- **Flow 5.1** (workflow-ended state) → Stage 4 `workflow-lifecycle-bar.tsx` ended state + Stage 4.7 chat-input ended-state disable
- **Flow 6.2** (mid-conversation flag flip) → Stage 2.10 `'__unrouted__'` sentinel set at conversation creation; flag is read once at creation, never mid-conversation
- **Flow 7.1, 7.2, 7.3** (at-mention semantics) → at-mention preserved as parallel side-bubble (existing pattern); explicit "at-mention does NOT answer pending prompt" added to runner header comment (Stage 2.4)
- **X.1-X.7** (cross-cutting error states) → distributed across Stage 2.4 (timeouts, plugin load failure → `reportSilentFallback`, MCP errors), Stage 2.6 (cost ceiling)

Two flow gaps deferred to V2 issues (Stage 5.3 drain-mode, Stage 5.4 per-user rollout).

## Stage 0 Findings

_To be appended after the spike runs._
