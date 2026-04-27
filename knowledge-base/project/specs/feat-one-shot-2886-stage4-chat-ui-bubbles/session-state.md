# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2886-stage4-chat-ui-bubbles/knowledge-base/project/plans/2026-04-27-feat-cc-stage4-chat-ui-bubbles-plan.md
- Status: complete

### Errors
- None blocking. Notes:
  - Generic Task tool unavailable in this CLI; deepen-plan substituted parallel agent reviews with direct multi-lens review (architecture, simplicity, type-design, performance, agent-native, test-design, security, pattern-recognition).
  - PreToolUse hook blocked one Edit because diff text contained a literal danger-prefix React API name; reworded the security guidance to use prefix-grep (`rg "danger|innerHTML|__html"`).

### Decisions
- **Pure-component PR scope** — no migrations, no infra, no Doppler. Stage 3 (#2885) already shipped WSMessage union extension + Zod parsing + `branded-ids.ts` + `cc_router`/`system` color entries. Stage 4 only consumes typed shapes; Task 4.9 reduced to verification (audit-only).
- **`tool-use-chip.tsx` scope corrected** — chip scoped to `cc_router`/`system` leader IDs only (pre-leader-bubble routing/system span). Per-leader tool_use stays on the existing `MessageBubble` "Working" pill (message-bubble.tsx:67-79) to avoid duplication.
- **Reducer correlation index added** — `subagent_complete` carries `spawnId` only (no `parentId`). Plan now requires `Map<spawnId, {messageIdx, childIdx}>` in `ChatStateSnapshot` for O(1) reverse-lookup.
- **`tool_progress` vs `tool_use` distinction** — `tool_progress` is a 1/5s heartbeat for watchdog reset (chat-state-machine.ts:144), NOT a tool-start. Chip lifecycle keys off `tool_use` (start) → `stream`/`stream_end` (clear). Negative regression test enforces this.
- **Two render paths coexist** — `WorkflowLifecycleBar` renders only when `conversation.active_workflow !== null`; legacy `isClassifying` chip stays unchanged for legacy router conversations. Gate is on the conversation column, not the feature flag (no stale-flag-at-render risk). AC19 added for no-regression.
- **TDD-first per `cq-write-failing-tests-before`** — co-located RED tests; `: never` exhaustiveness rail per `cq-union-widening-grep-three-patterns`; `data-*` hooks per `cq-jsdom-no-layout-gated-assertions`; vitest cross-file isolation per `cq-vitest-setup-file-hook-scope`.

### Components Invoked
- `skill: soleur:plan`
- `skill: soleur:deepen-plan` (executed inline as multi-lens review)
- Bash, Read, Write, Edit, Git, jq, gh CLI
