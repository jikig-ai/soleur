# Plan: feat(cc-soleur-go) — Stage 4 chat-UI bubble components

**Issue:** #2886
**Branch:** `feat-one-shot-2886-stage4-chat-ui-bubbles`
**Worktree:** `.worktrees/feat-one-shot-2886-stage4-chat-ui-bubbles/`
**Parent plan:** [`knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`](./2026-04-23-feat-cc-route-via-soleur-go-plan.md) (Stage 4 §307–351)
**Source PR:** #2858
**Stage 3 dep:** #2885 — **CLOSED** (verified `gh issue view 2885 --json state` → CLOSED)
**Designs:** `knowledge-base/product/design/command-center/screenshots/06-11` (six PNGs)
**Milestone:** Post-MVP / Later

## Overview

Stage 4 of the cc-soleur-go pivot delivers the **client-side rendering surfaces** that Stage 3 (#2885) reserved typed shapes for. With `WSMessage` already widened (`subagent_spawn`, `subagent_complete`, `interactive_prompt`, `interactive_prompt_response`, `workflow_started`, `workflow_ended`) and the chat-state-machine routing those events as inert pass-throughs (chat-state-machine.ts §74–89), Stage 4 turns each typed payload into a rendered bubble or chip.

This is purely a **components + render dispatch** stage. No server changes; no protocol changes; no migrations. The runner (Stage 2 / #2883/#2884) and protocol (Stage 3 / #2885) supply the events; this PR draws them.

The plan delivers four components and three small edits to existing chat surfaces:

1. `subagent-group.tsx` — parent assessment bubble + nested children renderer (Option A; expand threshold ≤2 / ≥3).
2. `interactive-prompt-card.tsx` — base + 6 per-`kind` variants (`ask_user`, `plan_preview`, `diff`, `bash_approval`, `todo_write`, `notebook_edit`).
3. `workflow-lifecycle-bar.tsx` — sticky context bar (routing / active / ended states) with "Switch workflow" + "Start new conversation" CTAs.
4. `tool-use-chip.tsx` — inline status chip per in-flight tool_use (every tool, not just Skill).

Plus four edits:

- `chat-surface.tsx` render-loop dispatch
- `message-bubble.tsx` `parentId` indentation
- `leader-colors.ts` audit (already has `cc_router` + `system`; verify gold-synthesis palette)
- `chat-input.tsx` disabled state when `workflow_ended_at` set.

## Research Reconciliation — Spec vs. Codebase

| Plan / Brainstorm Claim | Codebase Reality (verified 2026-04-27) | Plan Response |
|---|---|---|
| Master plan §332 says Stage 4 must "add gold-bordered palette for synthesis bubble + neutral palette for `system`" in `leader-colors.ts`. | `leader-colors.ts` (29 lines) already contains `system: border-l-neutral-600` and `cc_router: border-l-yellow-500` (gold) entries — Stage 3 added them. | **Task 4.9 reduced to verification.** Audit color values against design screenshots `08-*.png` (synthesis), `07-*.png` (workflow bar). If gold tone is wrong, edit `cc_router` value. **No new entries needed.** |
| Master plan §326 says `tool-use-chip.tsx` "labels come from `buildToolLabel` (existing util in agent-runner.ts)". | `buildToolLabel` lives in `apps/web-platform/server/tool-labels.ts` (server-only — imports `./observability` and `@/lib/sandbox-path-patterns`). It is invoked by `agent-runner.ts:55` and emits the label **on the server** before the WS frame leaves. | **Labels arrive pre-built** in the `tool_progress`/`stream` WS events as `toolLabel: string`. Client `tool-use-chip.tsx` reads `toolLabel` directly — does NOT import or re-call `buildToolLabel`. Eliminates a server→client import that would pull `observability` into the bundle. |
| Master plan §322 routing-state copy "Routing your message…" fired on first `tool_use(Skill)`. | Reducer (`chat-state-machine.ts`) currently routes `interactive_prompt` and `subagent_spawn` as inert pass-throughs (no rendering side effect). The "Routing to right experts" copy already exists at `chat-surface.tsx:382` driven by `isClassifying`. | **Replace the existing `isClassifying` chip** with the new `WorkflowLifecycleBar` routing state. Don't double-render. Reuse the early-return amber pulse pattern visually but drive from the lifecycle bar's routing variant. |
| Plan §314–320 says new "ChatMessage union" needed for new variants. | `ChatMessage = ChatTextMessage | ChatGateMessage` (chat-state-machine.ts §50). `applyStreamEvent`'s `StreamEvent` set already INCLUDES the new event types as inert pass-throughs (§74–89). | **Extend `ChatMessage` minimally.** Add `ChatSubagentGroupMessage`, `ChatInteractivePromptMessage`, `ChatWorkflowLifecycleMessage`, `ChatToolUseChipMessage` variants. The reducer already accepts the events; this stage materializes them into renderable `ChatMessage`s and grows the `: never` rail per `cq-union-widening-grep-three-patterns`. |
| `interactive_prompt_response` is "client→server only". | Confirmed: chat-state-machine.ts §74 explicitly excludes it from the reducer's `StreamEvent` union. | `interactive-prompt-card.tsx` posts the response via `useWebSocket().send` (existing escape hatch) and locally optimistically marks the prompt as resolved. The reducer never sees the response frame. |

## Open Code-Review Overlap

None. Verified via `jq` on `gh issue list --label code-review --state open --json number,title,body --limit 200` for each planned file path (`components/chat/chat-surface.tsx`, `components/chat/message-bubble.tsx`, `components/chat/leader-colors.ts`). Zero matches.

## Hypotheses

Stage 4 inherits Stage 0–3 hypotheses already proven; the only new structural assumption:

1. **`InteractivePromptPayload` shape (Stage 3 / #2885) is final and the runner emits the discriminated payload as nested `kind`+`payload` rather than a flat per-kind union.** Verified via `lib/types.ts` lines on `InteractivePromptPayload` — six kinds, each with a typed `payload: {…}` block. UI cards key off `event.kind` with TS narrowing on `event.payload`.
2. **Existing `chat-surface.tsx` render loop (§330–388) is single-list `messages.map(...)` with one switch on `msg.type`.** Verified at chat-surface.tsx §335–375. Adding new `ChatMessage` variants requires extending that switch and adding a `: never` exhaustiveness rail.
3. **The `WorkflowLifecycleBar` is sticky/persistent (one per conversation), not part of the message list.** This component lives outside the `messages.map(...)` loop and is driven by reducer-derived state (`activeWorkflow`, `workflowEndedAt`). Confirmed by master plan §321 ("sticky context bar") and design screenshot 07.

## Implementation Phases

### Phase 1 — ChatMessage union extension + render-loop dispatch (foundation)

**Goal:** Grow the `ChatMessage` discriminated union to cover the four new visual variants and wire the `chat-surface.tsx` render switch with a `: never` rail (per `cq-union-widening-grep-three-patterns`). No new components yet; just placeholder `null` returns from the new branches so the union widening doesn't break the build.

**Files to edit:**

- `apps/web-platform/lib/chat-state-machine.ts` — extend `ChatMessage`:
  ```ts
  interface ChatSubagentGroupMessage extends ChatMessageBase {
    type: "subagent_group";
    parentSpawnId: string;
    parentLeaderId: DomainLeaderId;
    parentTask?: string;
    children: Array<{ spawnId: string; leaderId: DomainLeaderId; task?: string; status?: SubagentCompleteStatus }>;
  }
  interface ChatInteractivePromptMessage extends ChatMessageBase {
    type: "interactive_prompt";
    promptId: string;
    conversationId: string;
    promptKind: InteractivePromptPayload["kind"];
    promptPayload: InteractivePromptPayload["payload"];
    resolved?: boolean;
    selectedResponse?: InteractivePromptResponsePayload["response"];
  }
  interface ChatWorkflowEndedMessage extends ChatMessageBase {
    type: "workflow_ended";
    workflow: WorkflowName;
    status: WorkflowEndStatus;
    summary?: string;
  }
  interface ChatToolUseChipMessage extends ChatMessageBase {
    type: "tool_use_chip";
    toolUseId: string;
    toolName: string;
    toolLabel: string;
    completed?: boolean;
  }

  export type ChatMessage =
    | ChatTextMessage
    | ChatGateMessage
    | ChatSubagentGroupMessage
    | ChatInteractivePromptMessage
    | ChatWorkflowEndedMessage
    | ChatToolUseChipMessage;
  ```
  Note: `workflow_started` does NOT produce a `ChatMessage`. It mutates ambient `WorkflowLifecycleBar` state (sticky, outside the message list). The bar is rendered from a small reducer-side state slice (`activeWorkflow`, `workflowEndedAt`) on the next phase.

- `apps/web-platform/lib/chat-state-machine.ts` — `applyStreamEvent` cases for the new event types now produce real messages (replacing the inert pass-throughs at §85–89):
  - `subagent_spawn` with no `parentId` match → start a new `subagent_group` message; with `parentId` → append to existing group's `children`.
  - `subagent_complete` → mutate matching child's `status`.
  - `interactive_prompt` → push `ChatInteractivePromptMessage`.
  - `workflow_started` → set ambient `workflowState`, NO message.
  - `workflow_ended` → set ambient `workflowState`, push `ChatWorkflowEndedMessage` for the in-list summary card.
  - `tool_progress` (existing) → emit ephemeral `tool_use_chip` while in-flight; remove on `stream` text arrival or `tool_complete`. **Decision:** chip lifecycle is reducer-managed (created on `tool_progress`, removed when same `toolUseId` produces a `text` delta). Document the chip lifetime in the runner header per `cq-code-comments-symbol-anchors-not-line-numbers`.

- `apps/web-platform/components/chat/chat-surface.tsx` — extend the `messages.map(...)` switch (§335–375) with branches for `subagent_group`, `interactive_prompt`, `workflow_ended`, `tool_use_chip`. Add an exhaustiveness rail using a helper:
  ```ts
  function assertNever(x: never): never { throw new Error(`Unexpected message type: ${JSON.stringify(x)}`); }
  ```
  Branch bodies return `null` placeholders for now (Phase 2–4 fills them).

**Tasks (per `cq-write-failing-tests-before` — RED before GREEN):**

- [ ] 1.1 — RED: extend `apps/web-platform/test/chat-state-machine.test.ts` with cases for each new event → ChatMessage mapping (subagent_spawn → subagent_group; interactive_prompt → interactive_prompt; workflow_ended → workflow_ended message; tool_progress → tool_use_chip with completed=false; matching content_block_stop → completed=true).
- [ ] 1.2 — RED: add a TS-only test file `apps/web-platform/test/chat-message-exhaustiveness.test-d.ts` (or inline assertion) that fails `tsc --noEmit` if any new variant is missing the `: never` rail in `chat-surface.tsx`. Per `cq-union-widening-grep-three-patterns`, also `rg "msg\.type === \""` and `rg "msg\?\.type === \""` to confirm no other consumer needs updating.
- [ ] 1.3 — GREEN: extend `ChatMessage` union with the four new variants.
- [ ] 1.4 — GREEN: wire reducer cases for `subagent_spawn`, `subagent_complete`, `interactive_prompt`, `workflow_started`, `workflow_ended`, `tool_progress` chip lifecycle.
- [ ] 1.5 — GREEN: extend `chat-surface.tsx` render loop with `null`-returning branches + `: never` rail.
- [ ] 1.6 — Run `bun --cwd apps/web-platform test chat-state-machine` (or `node node_modules/vitest/vitest.mjs run` per `cq-in-worktrees-run-vitest-via-node-node`) — RED tests should now go GREEN.

### Phase 2 — `subagent-group.tsx` (parent + nested children)

**Goal:** Render the parent leader's assessment bubble with nested per-child sub-bubbles (Option A from brainstorm Q#3). Default expanded ≤2 children, collapsed ≥3 children. Each child renders its own `MessageBubble` with `parentId` indentation.

**Files to create:**

- `apps/web-platform/components/chat/subagent-group.tsx` (~120 lines):
  ```ts
  interface SubagentGroupProps {
    parentSpawnId: string;
    parentLeaderId: DomainLeaderId;
    parentTask?: string;
    children: Array<{ spawnId: string; leaderId: DomainLeaderId; task?: string; status?: SubagentCompleteStatus }>;
    getDisplayName?: (id: DomainLeaderId) => string;
    getIconPath?: (id: DomainLeaderId) => string | null;
    variant?: "full" | "sidebar";
  }
  ```
  - Header row: parent leader avatar + name + count chip (`{N} subagents spawned`).
  - Default expanded if `children.length <= 2`; collapsed if `>= 3`. Use `useState(initialExpanded)` derived once from `children.length` at mount.
  - Per-child status badge: `success` → check, `error` → red x, `timeout` → amber clock, `undefined` (still running) → pulse dot.
  - Renders each child via `<MessageBubble parentId={parentSpawnId} ... />` with `data-parent-spawn-id` for test hooks.
  - Per `cq-jsdom-no-layout-gated-assertions`: tests assert via `data-*` attributes not `clientWidth`.

**Files to edit:**

- `apps/web-platform/components/chat/message-bubble.tsx` — add optional `parentId?: string` prop; when set, apply Tailwind indent class (`ml-6` or `ml-8` per design screenshot 08); add `data-parent-id={parentId}` for test hooks. Memo dep array gets `parentId` added (per `cq-ref-removal-sweep-cleanup-closures` discipline — verify no orphan refs).
- `apps/web-platform/components/chat/chat-surface.tsx` — replace the `null` placeholder at the `subagent_group` branch with `<SubagentGroup ... />`.

**Tasks:**

- [ ] 2.1 — RED: create `apps/web-platform/test/subagent-group.test.tsx` covering: (a) ≤2 children renders expanded with no expand button; (b) ≥3 children renders collapsed with expand button; (c) per-child status badge variants (success/error/timeout/in-flight); (d) partial-failure rendering (mix of success and timeout); (e) `data-parent-spawn-id` attribute is set on each child bubble. Use `data-*` hooks NOT layout APIs per `cq-jsdom-no-layout-gated-assertions`.
- [ ] 2.2 — GREEN: implement `subagent-group.tsx` referencing screenshot `08-subagent-spawn-A-vs-B.png`.
- [ ] 2.3 — GREEN: extend `message-bubble.tsx` with `parentId` indentation prop. Re-read existing component first per `hr-always-read-a-file-before-editing-it`. Ensure memo prop list includes `parentId`.
- [ ] 2.4 — GREEN: wire `chat-surface.tsx` `subagent_group` branch to `<SubagentGroup>`.
- [ ] 2.5 — Verify `bun --cwd apps/web-platform test subagent-group message-bubble` passes.

### Phase 3 — `interactive-prompt-card.tsx` (6 variants, V1 minimal fidelity)

**Goal:** Render every `interactive_prompt` event type the runner can emit. Avoid blank/error bubbles (V1 minimal fidelity); polished interactions deferred per V2.

**Files to create:**

- `apps/web-platform/components/chat/interactive-prompt-card.tsx` (~250 lines, all variants in one file initially; if it crosses 350 lines we split per variant in a follow-up):
  ```ts
  interface InteractivePromptCardProps {
    promptId: string;
    conversationId: string;
    kind: InteractivePromptPayload["kind"];
    payload: InteractivePromptPayload["payload"];
    resolved?: boolean;
    selectedResponse?: InteractivePromptResponsePayload["response"];
    onRespond: (response: InteractivePromptResponsePayload) => void;
  }
  ```
  Inside, switch on `kind` with `: never` exhaustiveness rail. Per-variant renderers:
  - **`ask_user`** — full chip selector (single/multi-select per `payload.multiSelect`). Select clicks call `onRespond({ kind: "ask_user", response: selectedOption })`. Multi-select uses checkbox-pattern with a "Submit" button. **Load-bearing per DHH** — full fidelity at V1.
  - **`plan_preview`** — render `payload.markdown` via existing markdown renderer (look up — likely `react-markdown` or local `format-assistant-text.ts`); two buttons "Accept" / "Iterate" → `onRespond({ kind: "plan_preview", response: "accept" | "iterate" })`.
  - **`diff`** — collapsed summary `Edited file <code>{path}</code> (+{additions} -{deletions})`. No inline diff yet (V2). Single "Acknowledge" button → `onRespond({ kind: "diff", response: "ack" })`.
  - **`bash_approval`** — `<code>` block with `payload.command`, `cwd: {cwd}` muted. If `payload.gated === true` show Approve/Deny buttons → `onRespond({ kind: "bash_approval", response: "approve" | "deny" })`. If `gated === false`, auto-display only (no buttons; the runner already approved). V1: no live stream (V2 adds output streaming).
  - **`todo_write`** — count `{N} todos` + collapsed list of items showing `id`, `content`, status badge. Single "Acknowledge" → `onRespond({ kind: "todo_write", response: "ack" })`.
  - **`notebook_edit`** — count `{N} cells` + cell IDs as chip list, `notebookPath` muted. Single "Acknowledge" → `onRespond({ kind: "notebook_edit", response: "ack" })`.

  When `resolved === true`, the card renders disabled with `selectedResponse` shown as the chosen pill / "Plan accepted" / etc.

**Files to edit:**

- `apps/web-platform/components/chat/chat-surface.tsx` — replace `interactive_prompt` `null` placeholder with `<InteractivePromptCard ... onRespond={handleInteractivePromptResponse} />`. Add `handleInteractivePromptResponse` callback that calls `useWebSocket().send({ type: "interactive_prompt_response", promptId, conversationId, ...response })` and dispatches a local optimistic mark-resolved action to the reducer.

**Tasks:**

- [ ] 3.1 — RED: create `apps/web-platform/test/interactive-prompt-card.test.tsx` with one `describe` block per `kind`. Each block asserts: render shape, button presence/labels, `onRespond` invocation with correct discriminated payload, resolved-state rendering. Per `cq-mutation-assertions-pin-exact-post-state` use `.toBe(...)` not `.toContain(...)` for the response payload.
- [ ] 3.2 — RED: add a 5-min timeout test for `ask_user` if dismiss-on-timeout is part of UX (review master plan §339). If not, omit. Decision: V1 keeps the prompt active until either responded or replaced by next reducer action — server-side reaper (per Stage 2 §2.10) handles staleness; the UI doesn't auto-dismiss. **Skip 5-min timeout test in V1.**
- [ ] 3.3 — RED: assert that `interactive_prompt_response` WS frame fires with the exact `kind` + `response` shape on user click for each variant.
- [ ] 3.4 — GREEN: implement `interactive-prompt-card.tsx` with all 6 variants. Reference screenshots `06-askuserquestion-chip-selector.png` (ask_user), `09-exitplanmode-preview-accept.png` (plan_preview), `10-file-edit-write-diff-viewer.png` (diff), `11-bash-command-bubble.png` (bash_approval).
- [ ] 3.5 — GREEN: wire `chat-surface.tsx` `interactive_prompt` branch + `handleInteractivePromptResponse` callback.
- [ ] 3.6 — Per `cq-jsdom-no-layout-gated-assertions`: confirm no test asserts on `clientWidth`/`scrollHeight`. Use `data-prompt-kind` attribute and button presence checks instead.
- [ ] 3.7 — Per `cq-raf-batching-sweep-test-helpers`: if any variant uses `requestAnimationFrame` (likely no — no animations needed at V1), wrap with `vi.useFakeTimers + vi.advanceTimersByTime`.

### Phase 4 — `workflow-lifecycle-bar.tsx` (sticky context bar, 3 states)

**Goal:** A persistent bar ABOVE the message list (or sticky at top of the chat surface) carrying the current workflow's lifecycle state. Replaces the existing `isClassifying` chip at chat-surface.tsx:382.

**Files to create:**

- `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` (~150 lines):
  ```ts
  type WorkflowLifecycleState =
    | { state: "idle" } // no bar shown
    | { state: "routing"; skillName?: string } // first tool_use(Skill) seen, before workflow_started
    | { state: "active"; workflow: WorkflowName; phase?: string; cumulativeCostUsd?: number }
    | { state: "ended"; workflow: WorkflowName; status: WorkflowEndStatus; summary?: string };

  interface WorkflowLifecycleBarProps {
    lifecycle: WorkflowLifecycleState;
    onSwitchWorkflow?: () => void; // active-state CTA
    onStartNewConversation?: () => void; // ended-state CTA
  }
  ```
  - **Routing variant** — amber pulse + "Routing your message…" or "Routing to `{skillName}`…" if extracted from the first `tool_use(Skill)` event's input.
  - **Active variant** — workflow name pill + phase indicator + `~$<cost>` cumulative cost + "Switch workflow" button (Flow 1.2).
  - **Ended variant** — completion summary + workflow name + outcome badge + final cost + "Start new conversation" button.
  - **Idle** — render nothing (return null).

**Files to edit:**

- `apps/web-platform/lib/chat-state-machine.ts` — add ambient state slice tracked by reducer:
  ```ts
  export interface ChatStateSnapshot {
    messages: ChatMessage[];
    activeStreams: Map<DomainLeaderId, number>;
    workflow: WorkflowLifecycleState; // NEW
  }
  ```
  Reducer transitions:
  - `tool_progress(toolName: "Skill")` → `workflow.state = "routing"`, extract `skillName` from event input if present.
  - `workflow_started` → `workflow.state = "active"; workflow = event.workflow`.
  - `workflow_ended` → `workflow.state = "ended"`.
- `apps/web-platform/components/chat/chat-surface.tsx` — replace existing `isClassifying` chip (§382 `isClassifying && (...)`) with `<WorkflowLifecycleBar lifecycle={workflow} onSwitchWorkflow={...} onStartNewConversation={...} />` rendered ABOVE the `messages.map(...)` block, sticky positioning. The new bar absorbs `isClassifying`'s "Routing to right experts" responsibility. **Decision:** Keep the legacy `isClassifying`-driven amber chip for the legacy router code path (when `active_workflow` is NULL); show the new bar only when `routing | active | ended`. Two render paths gated by `useFeatureFlag("command-center-soleur-go")` OR by checking `conversation.active_workflow !== null`. Pick the latter (no flag re-read at render — avoids stale flag risk).
- `apps/web-platform/components/chat/chat-input.tsx` — disable input + show "This conversation has ended" placeholder when `conversation.workflow_ended_at !== null`. ~15 lines. Re-read existing chat-input.tsx (608 lines) first.

**Tasks:**

- [ ] 4.1 — RED: create `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` covering all 4 states (idle / routing / active / ended). Assert per state: visible elements, button labels, click → callback. Use `data-lifecycle-state` attribute hook.
- [ ] 4.2 — RED: extend `apps/web-platform/test/workflow-lifecycle-bar-routing-state.test.tsx` (split file per master plan §350) — routing state renders within 8s of user-message timestamp. Use `vi.setSystemTime` for determinism per `cq-raf-batching-sweep-test-helpers`. Skill name extracted from `tool_use.input.skill_name` (verify Stage 3 stream payload exposes this).
- [ ] 4.3 — RED: extend `apps/web-platform/test/chat-state-machine.test.ts` with reducer transitions: `tool_progress(Skill)` → routing; `workflow_started` → active; `workflow_ended` → ended.
- [ ] 4.4 — GREEN: implement `workflow-lifecycle-bar.tsx` referencing screenshot `07-workflow-lifecycle-indicators.png`.
- [ ] 4.5 — GREEN: extend reducer with `workflow` slice + transitions.
- [ ] 4.6 — GREEN: replace `chat-surface.tsx` `isClassifying` chip with `<WorkflowLifecycleBar>`.
- [ ] 4.7 — GREEN: extend `chat-input.tsx` ended-state disable. Re-read first per `hr-always-read-a-file-before-editing-it`.
- [ ] 4.8 — Visual QA: take screenshot of all 3 lifecycle states for PR description.

### Phase 5 — `tool-use-chip.tsx` (inline progress chip per tool_use)

**Goal:** Continuous perceived progress instead of 5-30s silence gaps during tool calls. Renders on `tool_progress` (or content_block_start equivalent) and removes when text deltas arrive for the same `toolUseId`.

**Files to create:**

- `apps/web-platform/components/chat/tool-use-chip.tsx` (~60 lines):
  ```ts
  interface ToolUseChipProps {
    toolName: string;
    toolLabel: string; // pre-built by server (server/tool-labels.ts)
    completed?: boolean;
  }
  ```
  - Render: small pill with tool icon (or first char), label, pulse-dot while in-flight, fade-out on `completed=true`.
  - Multiple in-flight chips coexist (parent renders a `<div className="flex flex-wrap gap-2">` of all active chips).
  - **Labels arrive pre-built** via the `toolLabel` field on the `tool_progress` WS event (set server-side by `server/tool-labels.ts:buildToolLabel`). The chip does NOT import the server module. (See Research Reconciliation row 2.)

**Files to edit:**

- `apps/web-platform/components/chat/chat-surface.tsx` — replace the `tool_use_chip` branch's `null` placeholder with `<ToolUseChip toolName={msg.toolName} toolLabel={msg.toolLabel} completed={msg.completed} />`.

**Tasks:**

- [ ] 5.1 — RED: create `apps/web-platform/test/tool-use-chip.test.tsx`: (a) chip renders with provided `toolLabel`; (b) `completed=false` shows pulse; (c) `completed=true` removes pulse; (d) multiple chips coexist when reducer state has multiple `tool_use_chip` messages.
- [ ] 5.2 — RED: extend `apps/web-platform/test/chat-state-machine.test.ts`: `tool_progress` event creates `tool_use_chip` ChatMessage; subsequent `text` delta with matching `toolUseId` (or matching `tool_complete` if such an event exists in Stage 3 — verify) marks the chip `completed: true`.
- [ ] 5.3 — GREEN: implement `tool-use-chip.tsx`.
- [ ] 5.4 — GREEN: wire `chat-surface.tsx` render dispatch.
- [ ] 5.5 — Verify `bun --cwd apps/web-platform test tool-use-chip chat-state-machine` passes.

### Phase 6 — Integration smoke + visual QA

**Goal:** Confirm the four components render correctly when fed real WS event sequences. Pre-merge `wg-when-a-feature-creates-external` discipline at the component scope: fixture-driven smoke tests using recorded event sequences.

**Tasks:**

- [ ] 6.1 — Create `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` (component-level integration): replay a fixture sequence (`workflow_started → tool_progress(Skill) → subagent_spawn → subagent_complete → interactive_prompt → workflow_ended`) through the reducer and assert the full chat surface renders the expected component tree. Use `data-*` hooks; no layout-gated assertions per `cq-jsdom-no-layout-gated-assertions`.
- [ ] 6.2 — Run `node node_modules/vitest/vitest.mjs run apps/web-platform/test/{subagent-group,interactive-prompt-card,workflow-lifecycle-bar,workflow-lifecycle-bar-routing-state,tool-use-chip,cc-soleur-go-end-to-end-render,chat-state-machine,message-bubble-memo}` — all green.
- [ ] 6.3 — Run `tsc --noEmit` from `apps/web-platform/` to confirm union widening + `: never` rails compile clean.
- [ ] 6.4 — Doppler-run `dev`: `cd apps/web-platform && doppler run -p soleur -c dev -- ./scripts/dev.sh 3001` per `cq-for-local-verification-of-apps-doppler`. Manually drive the chat surface with a recorded WS replay (or a tiny test page). Capture screenshots of each new component for the PR description.
- [ ] 6.5 — `git status` — verify only the planned files are touched; no `.claude/settings.json` drift; no incidental edits.
- [ ] 6.6 — Commit, push, open PR with `Closes #2886` in body. Include screenshots (one per component) and the integration test output.

## Files to Edit (consolidated)

| Path | Phase | Why |
|---|---|---|
| `apps/web-platform/lib/chat-state-machine.ts` | 1, 4, 5 | Extend `ChatMessage` union with 4 new variants; add `workflow` slice; reducer transitions for new events. |
| `apps/web-platform/components/chat/chat-surface.tsx` | 1, 2, 3, 4, 5 | Render-loop dispatch for new variants + `: never` rail; replace `isClassifying` chip with lifecycle bar; wire interactive-prompt response callback. |
| `apps/web-platform/components/chat/message-bubble.tsx` | 2 | Accept optional `parentId` prop for nested-subagent indentation. |
| `apps/web-platform/components/chat/chat-input.tsx` | 4 | Disabled state when `workflow_ended_at IS NOT NULL`. |
| `apps/web-platform/components/chat/leader-colors.ts` | 4.9 (audit only) | **Verification only.** `cc_router` + `system` already present (Stage 3). Confirm gold tone matches design. |

## Files to Create (consolidated)

| Path | Phase | Why |
|---|---|---|
| `apps/web-platform/components/chat/subagent-group.tsx` | 2 | Parent + nested children renderer (Option A; ≤2 expanded / ≥3 collapsed). |
| `apps/web-platform/components/chat/interactive-prompt-card.tsx` | 3 | Base + 6 variants (`ask_user` / `plan_preview` / `diff` / `bash_approval` / `todo_write` / `notebook_edit`). |
| `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` | 4 | Sticky context bar (routing / active / ended). |
| `apps/web-platform/components/chat/tool-use-chip.tsx` | 5 | Inline status chip per in-flight tool_use. |
| `apps/web-platform/test/subagent-group.test.tsx` | 2 | RED tests for Option A nested layout + status badges. |
| `apps/web-platform/test/interactive-prompt-card.test.tsx` | 3 | RED tests, one `describe` per `kind`. |
| `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` | 4 | RED tests for all 4 states + CTAs. |
| `apps/web-platform/test/workflow-lifecycle-bar-routing-state.test.tsx` | 4 | Routing state timing + skill-name extraction. |
| `apps/web-platform/test/tool-use-chip.test.tsx` | 5 | RED tests for chip lifecycle. |
| `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` | 6 | Component-level integration replay. |
| `apps/web-platform/test/chat-message-exhaustiveness.test-d.ts` | 1 | TS-level union-widening exhaustiveness assertion. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — All 4 new components ship with co-located tests written RED-first per `cq-write-failing-tests-before`. (Phase 1.1, 2.1, 3.1, 4.1, 5.1, 6.1.)
- [ ] **AC2** — `ChatMessage` union extended with `subagent_group`, `interactive_prompt`, `workflow_ended`, `tool_use_chip` variants; `chat-surface.tsx` switch has `: never` exhaustiveness rail; per `cq-union-widening-grep-three-patterns`, `rg "msg\.type === \""` and `rg "msg\?\.type === \""` show no orphan consumers. (Phase 1.2, 1.3.)
- [ ] **AC3** — `subagent-group.tsx` renders Option A nested layout: ≤2 children expanded, ≥3 collapsed; per-child status badges (success/error/timeout/in-flight) visible via `data-child-status` attribute. (Phase 2.)
- [ ] **AC4** — `interactive-prompt-card.tsx` renders all 6 variants at V1 minimal fidelity; clicking each variant's primary action posts an `interactive_prompt_response` WS frame with the correct discriminated payload. Asserted via `.toBe()` per `cq-mutation-assertions-pin-exact-post-state`. (Phase 3.)
- [ ] **AC5** — `workflow-lifecycle-bar.tsx` renders all 4 states (idle/routing/active/ended); routing state appears within 8s of user message send (driven by first `tool_use(Skill)` event); ended state shows "Start new conversation" CTA. (Phase 4.)
- [ ] **AC6** — `tool-use-chip.tsx` renders for every in-flight `tool_use`; multiple chips coexist; label is pre-built server-side and passed through the WS event (NO client-side `buildToolLabel` import). (Phase 5.)
- [ ] **AC7** — `chat-input.tsx` disabled when `workflow_ended_at IS NOT NULL`; visible "This conversation has ended" placeholder. (Phase 4.7.)
- [ ] **AC8** — `message-bubble.tsx` accepts optional `parentId` prop and applies indent class; `data-parent-id` attribute set; memo prop list updated. (Phase 2.3.)
- [ ] **AC9** — All Stage 4 tests pass: `subagent-group`, `interactive-prompt-card`, `workflow-lifecycle-bar`, `workflow-lifecycle-bar-routing-state`, `tool-use-chip`, `cc-soleur-go-end-to-end-render`, `chat-state-machine`, `message-bubble-memo` (regression). Run with `node node_modules/vitest/vitest.mjs run` per `cq-in-worktrees-run-vitest-via-node-node`. (Phase 6.2.)
- [ ] **AC10** — `tsc --noEmit` clean from `apps/web-platform/`. (Phase 6.3.)
- [ ] **AC11** — Per `cq-jsdom-no-layout-gated-assertions`: zero test assertions on `clientWidth`, `scrollWidth`, `offsetHeight`, `getBoundingClientRect`. Verified by `rg "(clientWidth|scrollWidth|offsetHeight|getBoundingClientRect)" apps/web-platform/test/{subagent-group,interactive-prompt-card,workflow-lifecycle-bar*,tool-use-chip,cc-soleur-go-end-to-end-render}.test.tsx` returning zero hits.
- [ ] **AC12** — Screenshots of all 4 components captured for PR description (Phase 4.8 + 6.4).
- [ ] **AC13** — `Closes #2886` in PR body per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] **AC14** — `compound` skill run before each commit per `wg-before-every-commit-run-compound-skill`.
- [ ] **AC15** — No incidental file drift. `git diff main --name-only` lists only the planned files. Per `hr-never-git-add-a-in-user-repo-agents`, allowlist commits to chat components + tests.

### Post-merge (none required)

This is a pure-component PR; no migrations, no infra, no Doppler changes, no external resource creation. The feature flag `FLAG_CC_SOLEUR_GO` (Stage 2) gates whether the new bubbles ever render in prod — Stage 4 just makes them ready when the flag flips. No post-merge operator action required.

## Test Strategy

- **Unit:** Vitest + React Testing Library per existing `apps/web-platform/test/` pattern. RED-before-GREEN per phase. Use `data-*` attribute hooks per `cq-jsdom-no-layout-gated-assertions`. Stable, structural assertions only.
- **Integration:** `cc-soleur-go-end-to-end-render.test.tsx` replays a recorded WS event sequence through the reducer and asserts the rendered tree. Uses `applyStreamEvent` directly, not jsdom event simulation.
- **Type-level:** `chat-message-exhaustiveness.test-d.ts` ensures `: never` rails fire if a future `ChatMessage` variant is missed (per `cq-union-widening-grep-three-patterns`).
- **Visual QA:** Manual screenshots via `doppler run -- ./scripts/dev.sh 3001` for PR description (Phase 6.4). No Playwright tests in this PR — the new bubbles' real exercise is Stage 6 smoke tests in the master plan (#2886.5+).
- **Regression:** Re-run `chat-state-machine`, `message-bubble-memo`, `chat-surface-sidebar*` to confirm Phase-1 union widening did not break existing variants.

## Risks

1. **`isClassifying` legacy code path conflict** — the existing legacy router emits `classify_response` events that drive the `isClassifying` chip. The new `WorkflowLifecycleBar` replaces it ONLY when `active_workflow !== null`. **Mitigation:** Phase 4 task 4.6 specifies the gate is on `conversation.active_workflow`, not on the feature flag (avoids stale-flag-at-render risk per `wg-mid-conversation-flag-flip`). Tests cover both paths: classic chip when `active_workflow === null`, lifecycle bar otherwise.
2. **`InteractivePromptPayload` shape drift** — Stage 3 froze the discriminated payload shape; if Stage 2 runner emits a `payload` shape the type doesn't match, the cards crash. **Mitigation:** Stage 3's WS-boundary Zod parser already enforces this. Stage 4 trusts Stage 3's parsed shape and uses `kind`-narrowed payload TS access.
3. **`tool-use-chip` overload** — chains of 20+ rapid tool_use events could spawn 20+ chips and cause layout thrash. **Mitigation:** chip lifetime is reducer-managed (created on `tool_progress`, removed on text-delta arrival OR chip cap of 5 latest, whichever first). Document the cap inline. Per `cq-jsdom-no-layout-gated-assertions`, the test verifies chip count via `data-chip-count` attribute, not DOM measurement.
4. **`message-bubble.tsx` memo regression** — adding `parentId` to props changes the memo input contract. If dep array isn't updated, stale renders. **Mitigation:** Phase 2.3 explicitly re-reads the file first (`hr-always-read-a-file-before-editing-it`) and updates the memo. RED test `message-bubble-memo.test.tsx` already exists; extend it for `parentId` re-render trigger.
5. **`workflow-lifecycle-bar` skill-name extraction failure** — if the `tool_use(Skill)` event input doesn't expose `skill_name` (Stage 3 may have stripped it), the routing state falls back to generic "Routing your message…". **Mitigation:** verify at Phase 4 task 4.2 by reading `apps/web-platform/lib/types.ts` for the `tool_progress` event payload. If `skill_name` not exposed, file a V2 issue to plumb it through; ship V1 with generic copy.
6. **Server `tool-labels.ts` import temptation** — a careless GREEN pass might `import { buildToolLabel } from "@/server/tool-labels"` from the chip component, pulling `observability` and Sentry into the client bundle. **Mitigation:** the chip props specify `toolLabel: string` (pre-built); reviewers must reject any client → server import. Add a sentinel grep in Phase 6: `rg "from \"@/server/tool-labels\"" apps/web-platform/components/` returns zero.
7. **Markdown rendering for `plan_preview`** — if the codebase doesn't already have a markdown renderer, this PR pulls in a new dep, conflicting with master plan's "no new deps" stance. **Mitigation:** Phase 3 task 3.4 first greps `rg "react-markdown\|marked\|markdown-to-jsx" apps/web-platform/`. If absent, fall back to plain-text rendering with line breaks (V1 minimal); file V2 issue for full markdown rendering. Per `cq-write-failing-tests-before` the test pins behavior so the V2 swap is safe.

## Domain Review

**Domains relevant:** Product (UX Gate)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline mode — Stage 4 implements artifacts already specified by master plan's Stage 4 design pass: 6 design screenshots in `knowledge-base/product/design/command-center/screenshots/`, brainstorm Q#3 resolution Option A, master-plan §313–326 component contracts)
**Skipped specialists:** ux-design-lead (designs already exist as `cc-embedded-skill-surfaces.pen` + 6 screenshots — re-running wireframes is duplicate work; advisory tier carry-forward), copywriter (V1 minimal copy — "Routing to {skill}…", "Edited file {path}", "Acknowledge", "Start new conversation" — straight functional descriptors, no brand-voice opportunity at this fidelity. V2 polish issue tracks copy review.)
**Pencil available:** N/A (advisory + pre-existing designs)

#### Findings

The master plan's design pass (#2858) already produced wireframes-as-screenshots and a `cc-embedded-skill-surfaces.pen` source. Stage 4 implements those artifacts. The advisory-tier auto-accept is correct: this PR modifies existing UI surfaces (chat-surface, message-bubble) and adds new components whose visual contract is already specified. No new flows are introduced beyond what the master plan's BLOCKING-tier review already approved.

If implementation deviates visually from the screenshots, capture the deviation in PR description for reviewer call-out. Do not unilaterally repaint.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-27-feat-cc-stage4-chat-ui-bubbles-plan.md. Branch: feat-one-shot-2886-stage4-chat-ui-bubbles. Worktree: .worktrees/feat-one-shot-2886-stage4-chat-ui-bubbles/. Issue: #2886. Plan reviewed and ready; implement Phase 1 (ChatMessage union extension) first, then Phases 2–5 (4 new components), then Phase 6 (integration QA + screenshots).
```
