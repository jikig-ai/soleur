# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-14-feat-reconnect-state-machine-hardening-plan.md
- Status: complete

### Errors
None. Two P0 plan defects surfaced by deepen-plan review agents and corrected in-place before finalizing.

### Decisions
- Connection-state input is a `chatReducer` `ChatAction` (`connection_change`), NOT a `StreamEvent`/`WSMessage` variant — keeps pure `applyStreamEvent` untouched, avoids widening the wire protocol.
- P0 corrected — AC11 escape hatch: replaced `clear_streams` connection reset (fires on every reconnect) with dedicated `reset_connection` action dispatched only from user-new-turn `sendMessage` path.
- P0 corrected — duplicate banner: State 1 reframed as a rewire of the existing `chat-surface.tsx:567-580` banner through the precedence selector, not a greenfield component.
- Simplicity: collapsed 4-value `ConnectionPhase` to 3 values (`live|reconnecting|unrecoverable`); State 4 derived render affordance; `ReconnectView` shrunk 5→3 variants.
- Scope: pure client-side TS — no GDPR/schema/auth/API/IaC surface. Threshold = single-user incident; `requires_cpo_signoff: true`. Wireframe `.pen` already committed (4 states).

### Components Invoked
soleur:plan, soleur:deepen-plan; agents: Explore, learnings-researcher, repo-research-analyst, architecture-strategist, code-simplicity-reviewer, general-purpose; deepen-plan gates 4.6/4.7/4.8/4.9 all passed.
