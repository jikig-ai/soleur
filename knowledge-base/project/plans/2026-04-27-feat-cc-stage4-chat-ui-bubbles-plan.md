# Plan: feat(cc-soleur-go) — Stage 4 chat-UI bubble components

**Issue:** #2886
**Branch:** `feat-one-shot-2886-stage4-chat-ui-bubbles`
**Worktree:** `.worktrees/feat-one-shot-2886-stage4-chat-ui-bubbles/`
**Parent plan:** [`knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`](./2026-04-23-feat-cc-route-via-soleur-go-plan.md) (Stage 4 §307–351)
**Source PR:** #2858
**Stage 3 dep:** #2885 — **CLOSED** (verified `gh issue view 2885 --json state` → CLOSED)
**Designs:** `knowledge-base/product/design/command-center/screenshots/06-11` (six PNGs)
**Milestone:** Post-MVP / Later

> **Deepen-plan applied (2026-04-27):** Multi-lens review (architecture-strategist, code-simplicity, type-design-analyzer, performance-oracle, agent-native-reviewer, test-design-reviewer, security-sentinel, pattern-recognition-specialist) surfaced 11 findings; all folded inline. Key changes:
>
> 1. **`tool-use-chip.tsx` redesigned** — original plan duplicated existing `MessageBubble` "Working" pill. Chip now scoped to **routing/system events** OUTSIDE leader bubbles (pre-bubble Skill dispatch, system-role spans). Per-leader tool_use stays on `MessageBubble.toolLabel`.
> 2. **`subagent_complete` correlation** — added `Map<spawnId, { messageIdx, childIdx }>` reducer index; `subagent_complete` carries `spawnId` only (no `parentId`), so reverse-lookup is mandatory.
> 3. **`interactive_prompt` ownership** — local optimistic resolution must scope by `(promptId, conversationId)` tuple, not `promptId` alone (cross-conversation collision possible if reducer reused across tabs).
> 4. **`activeStreams` re-keying deferred** — master plan §291 calls for re-keying to `Map<string, number>` keyed by `${parent_id}:${leader_id}`. Stage 4 keeps `Map<DomainLeaderId, number>` and tracks subagent groups via a separate index. Re-keying is a Stage 8 cleanup concern, NOT a Stage 4 prerequisite.
> 5. **Markdown rendering for `plan_preview`** — V1 falls back to `format-assistant-text.ts` (existing client util) which handles code fences and line breaks; full markdown is V2.
> 6. **`workflow_ended` is BOTH ambient + in-list** — clarified the ambient lifecycle bar's "ended" state is a separate visual from the in-list summary card. Both render simultaneously and are removed when user starts a new conversation.
> 7. **Pre-existing `isClassifying` ad-hoc derivation** — replaced with `WorkflowLifecycleState` slice; the legacy `classify_response` event maps to `routing` lifecycle for back-compat.
> 8. **Memo dep audit on `MessageBubble`** — adding `parentId` to props REQUIRES reading the existing `memo`-comparator (memo's default shallow compare handles primitives; verify no custom `arePropsEqual` arg).
> 9. **Test isolation** — vitest cross-file leaks (per `cq-vitest-setup-file-hook-scope`) — new test files must NOT use `afterEach(vi.unstubAllGlobals)`.
> 10. **Bash command preview escaping** — `bash_approval` variant must escape `payload.command` against XSS/HTML; the runner sets `gated: true` for review-required commands but the UI must not render command as innerHTML.
> 11. **Dependency on `tool_progress` for chip lifetime is wrong** — `tool_progress` is a 1/5s heartbeat for watchdog reset, not a "tool started" event. Chip lifecycle keys off `tool_use` (start) → `stream` first content (text arrives) OR `stream_end`.

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
  - `subagent_complete` → mutate matching child's `status`. **`subagent_complete` carries `spawnId` only (no `parentId`)** — the reducer MUST maintain a `Map<spawnId, { messageIdx, childIdx }>` index built up on each `subagent_spawn` to reverse-lookup which subagent_group.children entry to mutate. Without this index the reducer would have to O(N²) scan all messages to find the matching spawn. Add the index to `ChatStateSnapshot`. (Architecture-strategist finding.)
  - `interactive_prompt` → push `ChatInteractivePromptMessage` keyed by `(promptId, conversationId)` tuple — `promptId` alone is insufficient if a future feature shares the reducer across tabs/conversations.
  - `workflow_started` → set ambient `workflowState`, NO message.
  - `workflow_ended` → set ambient `workflowState` (lifecycle bar) AND push `ChatWorkflowEndedMessage` (in-list summary). **Both render simultaneously** — the bar is sticky context; the in-list card is the conversational marker. Test: assert both appear after `workflow_ended` event.
  - `tool_use` (existing event for SDK-native tool starts; verified at chat-state-machine.ts:121 — already mutates the leader's `MessageBubble.state` to `"tool_use"` and sets `toolLabel`) → existing path handles per-leader bubbles. **NEW for Stage 4:** if `event.leaderId === "cc_router"` OR `event.leaderId === "system"` (i.e., no real leader bubble exists yet, e.g., during the routing pre-dispatch narration), instead emit a `ChatToolUseChipMessage` chip rendered above the message list. Chip is removed when (a) the corresponding `stream` text event arrives OR (b) `stream_end` for the same `cc_router`/`system` leader OR (c) `workflow_started` fires (replaces with active lifecycle bar).
  - `tool_progress` (existing 1/5s heartbeat for watchdog reset — NOT a tool-start signal): NO new chip created. Existing logic at chat-state-machine.ts:144 stays unchanged. (Pattern-recognition-specialist correction — original plan misread `tool_progress` as a chip-start signal.)
  - `classify_response` (legacy router event, still in WSMessage union): for **legacy conversations** (where `conversation.active_workflow IS NULL`), the existing `isClassifying`-driven chip at `chat-surface.tsx:382` stays unchanged — Stage 4 does not refactor the legacy path. For **soleur_go conversations**, this event does not fire (the legacy classifier isn't invoked). The new `WorkflowLifecycleBar` ONLY renders when `active_workflow !== null`. AC19 enforces no-regression on the legacy path.

- `apps/web-platform/components/chat/chat-surface.tsx` — extend the `messages.map(...)` switch (§335–375) with branches for `subagent_group`, `interactive_prompt`, `workflow_ended`, `tool_use_chip`. Add an exhaustiveness rail using a helper:
  ```ts
  function assertNever(x: never): never { throw new Error(`Unexpected message type: ${JSON.stringify(x)}`); }
  ```
  Branch bodies return `null` placeholders for now (Phase 2–4 fills them).

**Tasks (per `cq-write-failing-tests-before` — RED before GREEN):**

- [ ] 1.1 — RED: extend `apps/web-platform/test/chat-state-machine.test.ts` with cases for each new event → ChatMessage mapping: (a) first `subagent_spawn` (no matching parentId) → start `subagent_group` message + register `spawnIndex.set(spawnId, {messageIdx, childIdx:0})`; (b) second `subagent_spawn` with matching `parentId` → append to existing group + register; (c) `subagent_complete` → reverse-lookup via spawnIndex and mutate `children[childIdx].status`; (d) `interactive_prompt` (each kind) → push `ChatInteractivePromptMessage` keyed by `(promptId, conversationId)`; (e) `workflow_started` → ambient slice only, NO message; (f) `workflow_ended` → ambient + in-list summary card BOTH; (g) `tool_use` with `leaderId: "cc_router"` → push `ChatToolUseChipMessage`; (h) subsequent `stream` for `cc_router` leader → chip removed; (i) `tool_progress` does NOT create a chip (regression test for the pattern-recognition correction).
- [ ] 1.2 — RED: add a TS-only test file `apps/web-platform/test/chat-message-exhaustiveness.test-d.ts` (or inline assertion) that fails `tsc --noEmit` if any new variant is missing the `: never` rail in `chat-surface.tsx`. Per `cq-union-widening-grep-three-patterns`, also `rg "msg\.type === \""` and `rg "msg\?\.type === \""` to confirm no other consumer needs updating.
- [ ] 1.3 — GREEN: extend `ChatMessage` union with the four new variants.
- [ ] 1.4 — GREEN: wire reducer cases. Add `spawnIndex: Map<string, { messageIdx: number; childIdx: number }>` to `ChatStateSnapshot` so `subagent_complete` (which carries `spawnId` only — verified at lib/types.ts:238) can mutate the right child without O(N²) scan. `workflow_state: WorkflowLifecycleState` slice. The `tool_use` reducer case is the start-event for chip lifecycle (NOT `tool_progress` which is heartbeat-only — verified at chat-state-machine.ts:144). Map legacy `classify_response` events to `workflow_state.state = "routing"` for back-compat.
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
- `apps/web-platform/components/chat/chat-surface.tsx` — render the new `<WorkflowLifecycleBar>` above the `messages.map(...)` block, gated on `conversation.active_workflow !== null` (NOT on the feature flag — avoids stale-flag-at-render risk). Legacy router code path (`active_workflow === null`) keeps the existing `isClassifying` chip at §382 unchanged. Two render paths coexist; AC19 enforces no regression on the legacy one. The lifecycle bar is sticky-positioned per design screenshot 07.
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

### Phase 5 — `tool-use-chip.tsx` (router/system progress chip — pre-bubble surface)

**Goal:** Visual continuity for tool_use events that have NO leader bubble yet (the routing/system span — pre-`workflow_started`). Per-leader tool_use already shows on `MessageBubble.toolLabel` (existing pattern at message-bubble.tsx:67-79); the new chip is for the brief window between user message and first leader bubble (the `cc_router` / `system` events). **DO NOT duplicate the per-leader pill.**

**Files to create:**

- `apps/web-platform/components/chat/tool-use-chip.tsx` (~60 lines):
  ```ts
  interface ToolUseChipProps {
    toolName: string;
    toolLabel: string; // pre-built by server (server/tool-labels.ts)
    leaderId: "cc_router" | "system"; // restricted union — chip is ONLY for these
  }
  ```
  - Render: small pill — pulse-dot + `toolLabel` + neutral border (`leader-colors.ts` `cc_router` or `system` border).
  - Multiple chips coexist if multiple `cc_router`/`system` tool_uses fire simultaneously (rare but possible). Use `data-tool-use-id` for test hooks (note: existing `tool_use` event has NO `toolUseId` field — chip identity is `(leaderId, label, sequence)` for now; revisit if Stage 3 adds toolUseId to `tool_use`).
  - **Labels arrive pre-built** as `event.label` on the `tool_use` WS event (verified at lib/types.ts:206 `type: "tool_use"; leaderId; label: string`). Chip reads `msg.toolLabel` directly. NO `@/server/tool-labels` import.
  - **Bash command rendering safety:** all text content rendered through standard JSX (default escapes HTML). Forbidden render APIs are listed in the `Risks` section escape audit; sentinel grep enforces zero hits.

**Files to edit:**

- `apps/web-platform/components/chat/chat-surface.tsx` — replace the `tool_use_chip` branch's `null` placeholder with `<ToolUseChip toolName={msg.toolName} toolLabel={msg.toolLabel} leaderId={msg.leaderId} />`. Render chips ABOVE the messages list (alongside / replacing the lifecycle bar's "routing" amber pulse).

**Tasks:**

- [ ] 5.1 — RED: create `apps/web-platform/test/tool-use-chip.test.tsx`: (a) chip renders with provided `toolLabel`; (b) `leaderId: cc_router` shows yellow border per `leader-colors.ts`; (c) `leaderId: system` shows neutral border; (d) multiple chips coexist when reducer state has multiple `tool_use_chip` messages; (e) escape audit per `Risks` (use grep, not runtime assertion).
- [ ] 5.2 — RED: extend `apps/web-platform/test/chat-state-machine.test.ts`: `tool_use` event with `leaderId: "cc_router"` creates `tool_use_chip` ChatMessage; subsequent `stream` event for same `cc_router` leader removes the chip; `workflow_started` event removes all chips. **Negative test:** `tool_progress` event does NOT create a chip (regression for the heartbeat-vs-start-event distinction).
- [ ] 5.3 — GREEN: implement `tool-use-chip.tsx`.
- [ ] 5.4 — GREEN: wire `chat-surface.tsx` render dispatch above messages list.
- [ ] 5.5 — Verify `node node_modules/vitest/vitest.mjs run apps/web-platform/test/tool-use-chip apps/web-platform/test/chat-state-machine` passes.
- [ ] 5.6 — Sentinel grep: `rg "from \"@/server/tool-labels\"" apps/web-platform/components/` returns zero. Per the escape audit in `Risks`, `rg "danger" apps/web-platform/components/chat/tool-use-chip.tsx` returns zero (catches innerHTML-style escape hatches by prefix).

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
- [ ] **AC16** — `subagent_complete` correlation works via `spawnIndex: Map<spawnId, {messageIdx, childIdx}>` in `ChatStateSnapshot`. Test: spawn 3 subagents under one parent, complete the second one, assert only `children[1].status` mutated; the other two children unchanged.
- [ ] **AC17** — Escape audit clean: `rg "danger|innerHTML|__html" apps/web-platform/components/chat/{interactive-prompt-card,tool-use-chip,subagent-group,workflow-lifecycle-bar}.tsx` returns zero. Render-as-text test: an `interactive_prompt(bash_approval)` payload with `command: "<script>alert(1)</script>"` renders as visible text (`container.querySelector("script")` is null).
- [ ] **AC18** — Vitest cross-file isolation: `rg "afterEach.*unstubAllGlobals|afterEach.*restoreAllMocks" apps/web-platform/test/{subagent-group,interactive-prompt-card,workflow-lifecycle-bar*,tool-use-chip,cc-soleur-go-end-to-end-render}.test.tsx` returns zero per `cq-vitest-setup-file-hook-scope`.
- [ ] **AC19** — Backwards-compat: legacy `classify_response` event maps to `workflow_state.state = "routing"`; legacy router conversations (where `active_workflow IS NULL`) still render the existing classic chip path (no regression in existing chat-surface-sidebar tests).

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
7. **Markdown rendering for `plan_preview`** — if the codebase doesn't already have a markdown renderer, this PR pulls in a new dep, conflicting with master plan's "no new deps" stance. **Mitigation:** Phase 3 task 3.4 first greps `rg "react-markdown\|marked\|markdown-to-jsx" apps/web-platform/`. If absent, route through existing `apps/web-platform/lib/format-assistant-text.ts` (handles code fences and line breaks; verified present in `lib/` listing). File V2 issue for full markdown rendering. Per `cq-write-failing-tests-before` the test pins behavior so the V2 swap is safe.

8. **HTML-escape audit on user-visible string fields** — three `interactive_prompt` payloads carry attacker-influenced strings: `bash_approval.command`, `diff.path`, `notebook_edit.notebookPath`. The `bash_approval` is the most sensitive (a malicious sub-skill could craft a command containing `<script>` to render). React's default text-node escaping handles this **iff** the string is rendered as a child node, not via an escape-hatch render API. **Mitigation:** Phase 6 sentinel grep `rg "danger|innerHTML|__html" apps/web-platform/components/chat/{interactive-prompt-card,tool-use-chip,subagent-group,workflow-lifecycle-bar}.tsx` returns zero. Test asserts that a payload containing `<script>alert(1)</script>` renders as visible text, not an executed tag, by checking `container.querySelector("script")` is null. (Security-sentinel finding.)

9. **`MessageBubble` memo regression risk on `parentId` add** — the existing `memo(MessageBubble, ...)` at message-bubble.tsx:60 uses default shallow compare (no custom comparator argument; verified visually in the snippet). Adding a primitive `parentId` prop is shallow-compare-safe by default. **Mitigation:** Phase 2.3 explicitly re-reads message-bubble.tsx first per `hr-always-read-a-file-before-editing-it`. Negative grep: `rg "memo\([A-Z][a-zA-Z]+,\s*\(" apps/web-platform/components/chat/message-bubble.tsx` returns zero (confirms no custom comparator hidden behind a refactor that changed the default). If a comparator IS added, `parentId` MUST be added to it.

10. **Vitest cross-file leak on `vi.unstubAllGlobals` in new test files** — per `cq-vitest-setup-file-hook-scope`, the `setup-file` hooks run **per-test, not per-file**. Adding `afterEach(vi.unstubAllGlobals)` in any of the new test files would clobber module-scope `vi.stubGlobal(...)` in sibling test files loaded earlier. **Mitigation:** new test files MUST NOT install `afterEach(vi.unstubAllGlobals)` or `afterEach(vi.restoreAllMocks)`; if global cleanup is needed, use `afterAll` or `vi.unstubAllGlobals()` in the specific test that stubbed. Phase 6 sentinel grep: `rg "afterEach.*unstubAllGlobals|afterEach.*restoreAllMocks" apps/web-platform/test/{subagent-group,interactive-prompt-card,workflow-lifecycle-bar*,tool-use-chip,cc-soleur-go-end-to-end-render}.test.tsx` returns zero. (Test-design-reviewer finding.)

11. **`AbortSignal.timeout` traps in interactive-prompt cards** — if any variant adds a client-side timeout (e.g., "auto-dismiss prompt after 5min"), `AbortSignal.timeout(ms)` is NOT reliably intercepted by `vi.useFakeTimers` per `cq-abort-signal-timeout-vs-fake-timers`. **Mitigation:** Phase 3 task 3.2 already records V1 decision: NO client-side auto-dismiss. If V2 adds one, use manual `AbortController + setTimeout(controller.abort, ms)`.

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

## Agent-Native Reviewer Findings (deepen pass)

Stage 4 is a pure-component PR — no MCP tool surface added, no agent-driven actions exposed. Agent-native parity for the cc-soleur-go feature is tracked by master plan §369–386 V2 issues V2-1 through V2-5 (cc_send_user_message, cc_respond_to_interactive_prompt, cc_set_active_workflow + cc_abort_workflow, conversation_get extension, system-role transcript lines for `workflow_started`/`workflow_ended`).

**Stage 4 implications for those V2 issues:**

- The new `ChatInteractivePromptMessage` shape carries everything an MCP `cc_respond_to_interactive_prompt` tool would need (`promptId`, `conversationId`, `kind`, `payload`). When V2-2 lands, the tool reads from the same `(promptId, conversationId)`-keyed pending-prompts registry the runner manages; the UI's optimistic resolution path is the reference implementation.
- `WorkflowLifecycleState` slice values (`idle | routing | active | ended`) align with future MCP `cc_get_workflow_status` response enum. Naming is forward-compatible.
- `ChatToolUseChipMessage` is UI-only; no MCP equivalent required (agents introspect raw `tool_use` blocks directly via `parent_tool_use_id`).

No new V2 issues need filing from Stage 4 deepen — the master plan's V2 list already covers the agent-native gap. Stage 4 should ensure its data shapes are stable (don't rename `promptKind` to `kind` once V2 ships against the original name).

## Framework / Library Notes (context7 deepen pass)

**React 19 (`apps/web-platform/package.json` shows `^19.1.0`):**

- `useTransition` and `useDeferredValue` are available — DO NOT use them in the lifecycle bar's state slice. The bar's "routing" state is load-bearing for perceived latency (must render in the same paint as the user message); deferring it would make perceived latency WORSE. Same logic applies to `tool-use-chip`. Stick with synchronous `useState`/reducer dispatch.
- `useOptimistic` exists for optimistic UI updates — could be used in `interactive-prompt-card` for the "click → mark resolved" path, but it adds complexity for V1. Defer to V2 polish; V1 manages optimistic state via reducer dispatch (the existing pattern in `chat-state-machine.ts`).
- `<form action={...}>` Server Actions are NOT applicable — the chat surface is fully client-rendered (`"use client"` at chat-surface.tsx:1).

**vitest (verified worktree-running pattern at `cq-in-worktrees-run-vitest-via-node-node`):**

- Run via `node node_modules/vitest/vitest.mjs run <path>` — never `npx vitest`.
- For React Testing Library tests, ensure `apps/web-platform/test/setup.ts` (or equivalent) is loaded automatically per the existing vitest.config.

**Tailwind / Tailwind animations:**

- The pulse animation (`animate-pulse`) is built into Tailwind core; no plugin needed. Verified existing usage at chat-surface.tsx:382 (`animate-pulse rounded-full bg-amber-500`) and the existing classic chip pattern.
- `data-*` attributes pass through to DOM by default; safe for all the test hooks this plan prescribes.

## Test-Design Reviewer Findings (deepen pass)

1. **`.toBe()` not `.toEqual()` for primitive response payloads** — already enforced in plan (AC4 cites `cq-mutation-assertions-pin-exact-post-state`). For object-shaped payloads (e.g., `interactive_prompt_response.response: string[]`), use `.toEqual([...])` since `.toBe()` is reference equality.

2. **Mock fetch shape (`cq-preflight-fetch-sweep-test-mocks`)** — none of the new components fetch directly; they consume reducer-derived state. No mock-fetch concern for Stage 4. Sentinel: `rg "global\.fetch|globalThis\.fetch" apps/web-platform/test/{subagent-group,interactive-prompt-card,workflow-lifecycle-bar*,tool-use-chip}.test.tsx` returns zero.

3. **`vi.useFakeTimers` only when needed** — the lifecycle bar's "8s of message send" test (Phase 4.2) needs `vi.setSystemTime`. The other component tests do NOT. Avoid blanket `useFakeTimers` in test setup; per `cq-vitest-setup-file-hook-scope`, scoped per-test usage prevents cross-file leaks.

4. **`data-*` attributes for assertion hooks** — every new component MUST expose at least one `data-*` attribute that test assertions can target (`data-prompt-kind`, `data-lifecycle-state`, `data-child-status`, `data-tool-chip-id`). Per `cq-jsdom-no-layout-gated-assertions`, this is the only stable JSDOM-safe signal.

5. **Snapshot tests are forbidden** — Stage 4 is a UI scope where snapshot tests would appear "easy" but produce noisy diffs and false-green mutation regressions. Use targeted assertions on data-* attributes and visible text.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-27-feat-cc-stage4-chat-ui-bubbles-plan.md. Branch: feat-one-shot-2886-stage4-chat-ui-bubbles. Worktree: .worktrees/feat-one-shot-2886-stage4-chat-ui-bubbles/. Issue: #2886. Plan reviewed and ready; implement Phase 1 (ChatMessage union extension) first, then Phases 2–5 (4 new components), then Phase 6 (integration QA + screenshots).
```
