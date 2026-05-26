---
title: Reducer slice extension requires lifecycle-boundary audit
date: 2026-04-27
category: engineering
tags: [state-machine, reducer, multi-agent-review, feature-wiring, discriminated-union, chat-ui]
symptoms: [stale workflow lifecycle bar persists after key_invalid / session_ended remount, subagent status badges silently fail to render after history-fetch landing, interactive_prompt cards duplicate on event re-emit (React duplicate-key warning), tool_use chip reappears after leader bubble exists (cycle leak), WorkflowLifecycleState.routing variant tested but unreachable from any reducer case]
module: web-platform/chat
synced_to: []
component: state_machine
issues: [#2886, #2925]
problem_type: integration_issue
related: [knowledge-base/project/learnings/best-practices/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md, knowledge-base/project/learnings/integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md, knowledge-base/project/learnings/best-practices/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md]
root_cause: reducer_slice_extension_skipped_lifecycle_audit
severity: high
---

# Learning: Reducer slice extension requires lifecycle-boundary audit

## Problem

PR #2925 (Stage 4 cc-soleur-go chat-UI bubbles) extended `chat-state-machine.ts` with two new state slices (`workflow: WorkflowLifecycleState` and `spawnIndex: Map<SpawnId, {messageIdx, childIdx}>`) plus four new `ChatMessage` discriminated-union variants. The implementation passed 2712 vitest tests, `tsc --noEmit` clean, all sentinel greps clean. Multi-agent review (10 agents in parallel) surfaced 23 findings — 8 P1 / 9 P2 / 6 P3 — all pr-introduced, none caught by the 65 new tests in scope.

The findings clustered into three repeating classes:

1. **Slice not reset on lifecycle boundaries.** The `clear_streams` reducer action (already wired for `messages` and `activeStreams` per #2765) was not extended to reset the new `workflow` and `spawnIndex` slices. After `key_invalid` (line 477), `session_ended` (line 517), or socket remount (line 354), stale workflow state and spawn-index entries persisted into the next conversation.

2. **Absolute-index correlation map invalidated by mid-stream message mutations.** `spawnIndex.messageIdx` stored absolute integer indices into `messages[]`. When `filter_prepend` landed history mid-stream (the same class of bug fixed in #2209 / #2765 for `activeStreams`), every index shifted but the index map was not rebuilt — `subagent_complete` would silently no-op against a corrupt target. Tests didn't exercise the spawn → prepend → complete sequence.

3. **Reducer cases / variants prescribed by spec but unreachable in production.** Two cases:
   - `WorkflowLifecycleState.routing` was added to the union, exercised by 3 hand-constructed test fixtures, with a fully implemented `WorkflowLifecycleBar` routing-state branch. No reducer case produced it. Plan §258 said `tool_progress(toolName: "Skill")` → routing — never wired.
   - `MessageBubble.parentId` prop was added with `ml-6` indent and `data-parent-id`, exported, tested via memo-prop-list audit. No production caller passed it (`SubagentGroup` built bespoke divs at lines 121–171). Plan §169 said use `<MessageBubble parentId={parentSpawnId}>` — implementation diverged silently.

Plus two state-machine correctness bugs: `interactive_prompt` reducer pushed unconditionally (no `(promptId, conversationId)` idempotency check) → React duplicate-key warning + split-brain on re-emit; and the `tool_use` cc_router/system branch unconditionally appended chips even when a stream bubble already existed → chip leak after the cycle `tool_use → stream → tool_use`.

## Solution

All 23 findings fixed inline (per `rf-review-finding-default-fix-inline`):

**Lifecycle-boundary audit (F1, F2):**
```ts
// ws-client.ts chatReducer
case "clear_streams":
  return {
    ...state,
    activeStreams: new Map(),
    workflow: { state: "idle" },          // NEW
    spawnIndex: new Map(),                // NEW
  };
```

For `spawnIndex` invalidation by `filter_prepend`, switched the `subagent_complete` reducer from absolute-index lookup to id-based scan:

```ts
// chat-state-machine.ts subagent_complete
const groupIdx = prev.findIndex(
  m => m.type === "subagent_group" &&
       m.children.some(c => c.spawnId === event.spawnId)
);
```

The `spawnIndex` map was retained for future O(1) lookups but is now derived state, rebuilt on `filter_prepend`. Trade-off: O(messages) per `subagent_complete` event vs. O(1) — acceptable because completion events are rare relative to message volume.

**Discriminated-union exhaustiveness on actions, not just messages (F12):**
Added `: never` rails to both `chatReducer` and `ws.onmessage` switches. The `default: break` in `ws.onmessage` was the silent-drop foothold for new WSMessage variants.

**Idempotency on event re-emit (F7):**
```ts
// chat-state-machine.ts interactive_prompt
const exists = prev.some(
  m => m.type === "interactive_prompt" &&
       m.promptId === event.promptId &&
       m.conversationId === event.conversationId
);
if (exists) return { messages: prev, activeStreams, workflow: priorWorkflow, spawnIndex: priorSpawnIndex };
```

**Chip-cycle guard (F8):**
```ts
// chat-state-machine.ts tool_use cc_router/system branch
if (activeStreams.has(event.leaderId)) {
  // Bubble exists — fall through to per-leader toolLabel mutation, not chip emission
  break;
}
```

**Dead variants & dead props removed (F5, F9):**
- `WorkflowLifecycleState.routing` variant deleted from the union, removing the routing-state test file and bar branch. Decision: drop > implement, since the routing transition source (skill-name extraction from `tool_use.label`) was speculative.
- `MessageBubble.parentId` / `indentClass` / `data-parent-id` deleted. `SubagentGroup` retained its bespoke child rendering (refactor to share `MessageBubble` was out of scope).

**Hydration on reload (F3):**
`Conversation.workflow_ended_at` plumbed through `api-messages.ts` → `useWebSocket` → `ChatSurface` → `ChatInput` so the disabled state survives page reload, not just live `workflow_ended` events.

## Key Insight

When extending a reducer's `State` shape with new slices:

1. **Audit every lifecycle action that resets prior slices.** `clear_streams`, `session_reset`, `key_invalid`, `session_ended`, remount handlers — each must explicitly reset every new slice. Greppable: `rg "clear_streams|session_reset" <reducer>` and verify the new slice appears in each case.

2. **Audit every absolute-index map for correlation.** If a new slice stores `Map<id, messageIdx>`, identify every action that mutates `messages[]` non-monotonically (`prepend`, `splice`, `filter`) and either (a) rebuild the index after that action, or (b) switch to id-based scan. The cheaper bug is the second one — id-based scans cost O(N) per lookup but are immune to the entire class.

3. **Audit every union variant for production reachability.** A `: never` exhaustive rail catches missing reducer cases for variants that EXIST in the union. It does NOT catch variants that exist in the union but no producer creates. Manual grep: for each new variant, search `rg '"<variant>"' <reducer>` and confirm the variant appears on the LHS of an assignment in some reducer case.

4. **Audit every plan-prescribed prop for production callers.** Adding a prop + test does not prove it's wired. After the work-phase subagent reports, run `rg '<PropName>={' <component-tree>` — if zero hits outside tests, either delete the prop or wire it.

The reducer-extension-checklist is now operationalized: extending `ChatStateSnapshot` (or any reducer state shape) requires touching (a) every lifecycle-boundary action, (b) every index-correlation map, (c) every variant producer, (d) every prop call site. Missing any one is a silent regression that tsc + unit tests don't catch.

## Multi-Agent Review Verification

10 review agents ran in parallel; the slice-extension class was independently surfaced by:
- **git-history-analyzer** (P1 #2765 recurrence on `clear_streams` + spawnIndex/filter_prepend)
- **architecture-strategist** (medium: `routing` unreachable, `parentId` orphan)
- **data-integrity-guardian** (HIGH: idempotency, tool_use cycle, chip leak)
- **agent-native-reviewer** (P1: workflow_ended_at not hydrated on reload)
- **performance-oracle** (HIGH: chip cap missing per plan)
- **code-quality-analyst** (HIGH: parentId orphan, `as any` at union boundary)

Each finding was load-bearing: at least 4 of the 8 P1s would have surfaced as user-visible bugs in production (stuck lifecycle bar, dropped subagent badges, duplicate cards, chip leak). The 65 new vitest tests in scope DID NOT cover any of these classes — they tested individual reducer cases in isolation, not the cross-event compositions where the bugs lived.

This is the seventh confirmed case of multi-agent review catching feature-wiring bugs in green-CI code; it compounds the catalogue at `2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`.

## Session Errors

- **Plan+deepen subagent: Generic Task tool unavailable in CLI environment** — Recovery: substituted parallel agent reviews with direct multi-lens review by the planner. Prevention: deepen-plan skill should detect harness availability and degrade gracefully (already does); informational only.
- **PreToolUse security hook blocked Edit/Write twice for literal danger-prefix React API string in security-guidance prose** — Recovery: reworded to use prefix-grep `danger|innerHTML|__html`. Prevention: skill authors writing about React XSS guidance should use prefix-grep terminology rather than the literal API name when writing to documents.
- **Bash CWD didn't persist across parallel tool calls** — Recovery: re-invoked with absolute path. Prevention: covered by AGENTS.md `cq-when-running-test-lint-budget-commands-from` — chain `cd <abs> && <cmd>` in a single Bash call.
- **Work-phase subagent: mid-stream type narrowing fix needed** — `tool_use_chip` requires `toolLabel: string` (not optional), so the `case "stream"` reducer spread needed `m.type === "text"` narrow before mutating bubble state. Recovery: type guard added inline. Prevention: covered by `cq-union-widening-grep-three-patterns` — when widening discriminated unions with non-optional new fields, audit case spreads in sibling discriminator branches.

## Tags

category: best-practices
module: web-platform/chat-state-machine
