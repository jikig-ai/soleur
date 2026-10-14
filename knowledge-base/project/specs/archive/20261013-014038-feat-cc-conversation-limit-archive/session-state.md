# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-04-fix-cc-conversation-limit-archive-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause: archive paths (hook + MCP tool) update `archived_at` directly without calling `release_conversation_slot` RPC; lazy 120s sweep doesn't fire while WS is heartbeating other conversations. Slot leaks until pg_cron 1-min tick after full WS disconnect.
- Fix at DB layer with new migration 036: AFTER UPDATE OF archived_at trigger on `public.conversations` calls existing SECURITY DEFINER `release_conversation_slot` RPC. Closes the gap for all current and future writers.
- Trigger fires on `archived_at` transitions ONLY, NOT on `status='completed'`. Reason: `resume_session` does not call `acquireSlot`, so releasing on completed-only would let a resumed conversation bypass the cap.
- Second slot-leak source identified in `agent-runner.ts:442-464` (`startInactivityTimer` bulk-flip). Deferred to a follow-on issue; out of scope for this PR.
- User-Brand impact threshold: `single-user incident`; CPO + user-impact-reviewer required at PR review (rule `hr-weigh-every-decision-against-target-user-impact`).

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Codebase research: plan-limits.ts, ws-client.ts, server/concurrency.ts, server/ws-handler.ts, server/conversations-tools.ts, server/agent-runner.ts, hooks/use-conversations.ts, supabase/migrations/029
- gh issue list --label code-review (reconciled against #2961, #2962, #2191 — acknowledge/defer)
