# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-06-fix-concierge-duplicate-question-and-still-working-plan.md
- Status: complete

### Errors
None

### Decisions
- Duplicate box root cause: AskUserQuestion is turned into BOTH an `ask_user` `interactive_prompt` (soleur-go-runner.ts, plain box) AND a `review_gate` (permission-callback.ts, amber card). Fix: `classifyInteractiveTool` returns `null` for `AskUserQuestion`, leaving the amber card as sole surface (mirrors existing Bash precedent).
- "Still working…" leak: review_gate/interactive_prompt/autonomous_disclosure dispatch `stream_event` but aren't `isTurnActive`, so streamState stays "streaming" while liveNarration nulls. Fix: derived `awaitingUserInput` boolean scoped to `review_gate` + `autonomous_disclosure` (the server's `waiting_for_user` set), turn-scoped via `lastIndexOf("user")`.
- Plan-review narrowed predicate: excluded `interactive_prompt` (its diff/todo_write/notebook_edit kinds stream during genuine work) — avoids suppressing spinner during real work.
- Scope: 2 source files + 3 test files (1 new jsdom render test, 5 cases incl. AC5b/AC5c regression guards). No ADR/IaC/GDPR surface; threshold none.
- Product/UX BLOCKING gate satisfied: .pen wireframe of corrected single-card/no-spinner state committed.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agent: soleur:product:design:ux-design-lead (wireframe — BLOCKING gate)
- Agent: soleur:product:spec-flow-analyzer
- Agent: soleur:engineering:review:code-simplicity-reviewer
