# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-15-feat-workspace-reprovision-on-reconnect-plan.md
- Sub-issue: #5340 (Refs #5240, not Closes)
- Draft PR: #5339
- Status: complete

### Errors
None.

### Decisions
- Epic #5240 OPEN; design item #2 confirmed 🔴 Outstanding, deferred by v1. Sub-issue #5340 filed with Refs #5240.
- Architecture split: cc-dispatcher (Concierge) already calls `ensureWorkspaceRepoCloned`; agent-runner (leader) does NOT. Add recovery to leader path; add post-recovery-failure honest message to cc path. Re-clone reused/extended, never duplicated.
- Honest "reclaimed" message sits AFTER recovery (load-bearing placement learning) — verified by negative test. `worktree_enter_failed` routes through `type:"error"` branch (cc-dispatcher.ts:2787-2792), not `session_ended`.
- Load-bearing deepen finding: `realSdkQueryFactory` runs ONLY on cold conversations; warm-query reconnect needs per-dispatch fire-and-forget re-resolve (mirror `setBashAutonomous` at :2348) or feature is a no-op for reconnect.
- Scope guard honored: no change to `/workspaces` denyRead isolation boundary. Threshold = single-user incident; requires_cpo_signoff: true.

### Components Invoked
- soleur:plan, soleur:deepen-plan
- Agents: general-purpose (×2), learnings-researcher, kieran-rails-reviewer, code-simplicity-reviewer, dhh-rails-reviewer
- gh issue create (#5340), git commit/push
