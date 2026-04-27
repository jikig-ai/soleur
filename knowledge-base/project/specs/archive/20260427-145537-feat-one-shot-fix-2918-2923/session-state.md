# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-2918-2923/knowledge-base/project/plans/2026-04-27-fix-cc-soleur-go-cleanup-2918-2923-plan.md
- Status: complete

### Errors
None.

### Decisions
- Bundled all 6 issues into one cleanup PR — same code area (agent-runner.ts, cc-dispatcher.ts, soleur-go-runner.ts, permission-callback.ts, agent-runner-sandbox-config.ts). Scope-locked: did NOT expand to broader code-review backlog.
- #2918 lock pattern: in-process Map mutex (zero-dep) — sibling precedent in pending-prompt-registry.ts. Multi-process coordination deferred (single Next.js worker per container).
- #2919 fix pattern: Postgres function via supabase.rpc() — predicate-locked UPDATE (WHERE key_version = 1) so second concurrent caller no-ops. LANGUAGE sql, SECURITY DEFINER, REVOKE from authenticated/anon, GRANT TO service_role.
- #2920 ownership: dispatcher writes status (synthesizes AgentSession, owns BYOK fetches). Added last_active for parity with legacy agent-runner.ts:303.
- #2922 helper name: agent-runner-query-options.ts — matches sibling agent-runner-sandbox-config.ts. Drift-guard test asserts shared fields are deep-equal between legacy + cc paths.
- Closes #2918–#2923 in PR body. Migration applies dev-then-prd post-merge per wg-when-a-pr-includes-database-migrations.
- Deepen pass surfaced 7 corrections: RPC permissioning (DEFINER not INVOKER), atomic-write needs fdatasync, last_active parity, AbortSignal scope, SubagentStart payload divergence intentional, plaintext correctness for second concurrent BYOK caller (HKDF determinism), LANGUAGE sql over plpgsql.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- gh issue view (#2918–#2923 verified open)
- gh issue list --label code-review (overlap check)
- File reads: agent-runner.ts, cc-dispatcher.ts, soleur-go-runner.ts, permission-callback.ts, agent-runner-sandbox-config.ts, supabase/migrations/027, 032
- Artifacts: plan (885 lines), tasks.md (102 lines)
