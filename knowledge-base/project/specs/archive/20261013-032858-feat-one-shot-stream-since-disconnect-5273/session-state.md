# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-14-feat-stream-since-disconnect-replay-buffer-plan.md
- Status: complete

### Errors
None. CWD verified, branch verified (`feat-one-shot-stream-since-disconnect-5273`), premise validated (v1 PR #5256 MERGED 2026-06-14; umbrella #5240 correctly stays open). All deepen-plan halt gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped var, 4.9 UI-wireframe) passed. All 9 learning citations resolve; all 3 prescribed GitHub labels exist.

### Decisions
- Replay attaches at the non-destructive reattach seam (`ws-handler.ts:2500`), NOT `resume_session` (which aborts the live agent at `:1588` and would kill the in-flight turn the feature exists to preserve). Acceptance criterion phrased as the invariant (a frame from the still-running agent after reconnect is rendered), not the proxy (replayFrom returned frames).
- In-memory per-conversation buffer is NOT novel — extends AP-013 → ADR-027 and mirrors `TtlDedupMap` (`observability.ts:413-458`); ADR-059 cites these. Removed mis-cited ADR-042/046.
- Buffer keyed on the frame's `conversationId`, not `session.conversationId` (`sendToClient` is `userId`-keyed, so blind `session.conversationId` causes same-user cross-conversation contamination). Added a global Map-cardinality cap + byte cap.
- Cost double-count fix located at `ws-client.ts:901` (unconditionally additive); `nextSeq` counter moved to a separate map that survives `clear` (prevents replaying already-rendered frames on resume).
- Simplified: dropped `stream_replay{begin/end}` (per-`seq` dedup suffices); `stream_replay` is a per-status discriminated sub-union; Phase 5 (MCP parity) demoted to a post-merge tracking issue.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Research agents: `repo-research-analyst`, `learnings-researcher`, `Explore`
- Review agents (deepen-plan fan-out): `architecture-strategist`, `data-integrity-guardian`, `security-sentinel`, `code-simplicity-reviewer`, `spec-flow-analyzer`, `observability-coverage-reviewer`, `type-design-analyzer`
