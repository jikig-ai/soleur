# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-cc-chat-stuck-conversation-blocks-concurrency-slot/knowledge-base/project/plans/2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause: `agent-runner.ts` result-branch (lines 1076-1144) places the `active → waiting_for_user` status transition (line 1134) as the LAST step in the success path, after six throw-eligible operations (cost RPC, usage_update emit, syncPush, stream_end emit, status update itself, session_ended emit). Any throw between `saveMessage` and the status update leaves the row stuck at `status='active'`; the WS 30s heartbeat keeps refreshing the slot, so the 120s lazy sweep in `acquire_conversation_slot` and the 1-min pg_cron sweep cannot reclaim it. Cap_hit is the visible symptom.
- Three-layer fix (decreasing user-blast-radius): (1) try/catch wrapping the entire result branch with `assistantPersisted`-aware finalization, (2) periodic `startStuckActiveReaper` running every 60s, (3) self-healing ledger-divergence recovery on `start_session` cap_hit.
- Reaper signal switched at deepen-plan from `last_active` to slot-heartbeat staleness. Code-read confirmed `saveMessage` does NOT update `last_active` (only `updateConversationStatus` does), which would falsely reap long tool-heavy turns. New design joins `conversations LEFT JOIN user_concurrency_slots` and reaps only `status='active'` rows whose slot heartbeat is missing or >120s stale, converging with the existing pg_cron sweep threshold and eliminating the false-positive class.
- No DB-level "release on status leave active" trigger. Rejected per Risk #5 of prior PR: `resume_session` does not call `acquireSlot`, so a status-based release trigger would let resumed conversations bypass the cap.
- Migration 037 added for SECURITY DEFINER RPC `find_stuck_active_conversations` (search_path pinned per `cq-pg-security-definer-search-path-pin-pg-temp`).
- Acknowledge-only on overlapping concerns: #3219 (inactivity-sweep slot leak), #2955 (process-local state ADR), #2961 (repo_url immutability trigger). Same files, different fix shapes — folding in would balloon scope.
- Brand-survival threshold = single-user incident; requires CPO sign-off and `user-impact-reviewer` will run at PR review.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Direct code reads: `agent-runner.ts`, `ws-handler.ts`, `concurrency.ts`, `session-sync.ts`, `cc-dispatcher.ts`, `use-conversations.ts`, `chat-surface.tsx`, `kb-chat-trigger.tsx`, `use-kb-layout-state.tsx`, `lib/types.ts`, migrations 029 & 036, prior plan `2026-05-04-fix-cc-conversation-limit-archive-plan.md`
- Open code-review overlap query via `gh issue list` + `jq`
- Phase 4.6 User-Brand Impact halt-gate check (passed)
- Phase 4.5 Network-Outage gate (skipped — no trigger keywords in plan body)
