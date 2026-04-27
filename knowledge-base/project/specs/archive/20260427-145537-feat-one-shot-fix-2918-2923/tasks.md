# Tasks — cc-soleur-go cleanup #2918-#2923

Plan: `knowledge-base/project/plans/2026-04-27-fix-cc-soleur-go-cleanup-2918-2923-plan.md`

## Phase 1 — `#2918` workspace-permission lock + atomic write

- [x] 1.1 (RED) Write `apps/web-platform/test/workspace-permission-lock.test.ts` with T1-T4
  - 1.1.1 T1: same-path serialization
  - 1.1.2 T2: different-path concurrent
  - 1.1.3 T3: atomic rename, no partial file on throw
  - 1.1.4 T4: lock release on `fn` throw
- [x] 1.2 (GREEN) Implement `apps/web-platform/server/workspace-permission-lock.ts`
  - 1.2.1 `withWorkspacePermissionLock(path, fn)` Map-of-Promise mutex
  - 1.2.2 `atomicWriteJson(path, obj)` write-tmp + rename + cleanup-on-throw
- [x] 1.3 (REFACTOR) Wrap `patchWorkspacePermissions` body in `withWorkspacePermissionLock`; replace `writeFileSync` with `atomicWriteJson`
- [x] 1.4 Verify `cc-dispatcher-real-factory.test.ts` T10 still passes (one fire per cold factory)

## Phase 2 — `#2922` extract `buildAgentQueryOptions`

- [x] 2.1 (RED) Write `apps/web-platform/test/agent-runner-query-options.test.ts` with T1-T4 (canonical shape, args wiring, drift snapshot)
- [x] 2.2 (GREEN) Implement `apps/web-platform/server/agent-runner-query-options.ts`
  - 2.2.1 `AgentQueryOptionsArgs` interface
  - 2.2.2 `buildAgentQueryOptions(args)` returns canonical SDKOptions; calls `buildAgentSandboxConfig` and `buildAgentEnv`
- [x] 2.3 (REFACTOR) Replace `query({ options: {...} })` literal in `agent-runner.ts startAgentSession` (lines 814-893)
- [x] 2.4 (REFACTOR) Replace `sdkQuery({ options: {...} })` literal in `cc-dispatcher.ts realSdkQueryFactory` (lines 401-477)
- [x] 2.5 Add drift-guard test in `agent-runner-helpers.test.ts`: shared fields deep-equal between legacy + cc
- [x] 2.6 Update `cc-dispatcher-real-factory.test.ts` T4/T17 to assert through helper

## Phase 3 — `#2919` BYOK migration RPC

- [x] 3.1 (RED) Write `apps/web-platform/test/agent-runner-byok-migration.test.ts` with T1-T3 (RPC called once on v1, rows_affected=0 path, v2 skipped)
- [x] 3.2 (GREEN) Write migration `apps/web-platform/supabase/migrations/033_migrate_api_key_to_v2_rpc.sql`
  - 3.2.1 `migrate_api_key_to_v2(...)` function with predicate-locked UPDATE
  - 3.2.2 RETURNS rows_affected
  - 3.2.3 SECURITY INVOKER (RLS preserved)
- [x] 3.3 Replace inline UPDATE in `agent-runner.ts getUserApiKey` (lines 188-198) with RPC
- [x] 3.4 Replace inline UPDATE in `agent-runner.ts getUserServiceTokens` (lines 248-259) with RPC (same race, fold in)
- [x] 3.5 Verify migration applies clean to dev Supabase project

## Phase 4 — `#2920` cc dispatcher status writes

- [x] 4.1 (RED) Extend `cc-dispatcher-real-factory.test.ts`
  - 4.1.1 T-AC4a: `waiting_for_user` write on AskUserQuestion gate
  - 4.1.2 T-AC4b: `active` write on gate resolve
  - 4.1.3 T-AC4c: `.eq("user_id", args.userId)` present on every update
  - 4.1.4 T-AC4d: error path → `reportSilentFallback`
- [x] 4.2 (GREEN) Replace no-op `ccDeps.updateConversationStatus` in `cc-dispatcher.ts` (lines 394-397) with real supabase update
- [x] 4.3 Verify Bash gate write path also works (`permission-callback.ts` lines 307/317)

## Phase 5 — `#2921` Bash batching

- [x] 5.1 (RED) Write `apps/web-platform/test/permission-callback-bash-batch.test.ts` T1-T7
  - 5.1.1 T1: prefix grant + allow exact match
  - 5.1.2 T2: prefix allow with extra args
  - 5.1.3 T3: different prefix denied
  - 5.1.4 T4: revoke clears
  - 5.1.5 T5: cross-conversation isolation
  - 5.1.6 T6: cross-user isolation
  - 5.1.7 T7: TTL expiry (60min)
- [x] 5.2 (GREEN) Implement `apps/web-platform/server/permission-callback-bash-batch.ts`
  - 5.2.1 `getBashApprovalCache(userId, conversationId)` factory
  - 5.2.2 `deriveBashCommandPrefix(command)` helper (git/npm/bun/npx-aware)
- [x] 5.3 Wire batching into `permission-callback.ts` Bash branch
  - 5.3.1 Pre-gate cache check
  - 5.3.2 Augment options to `["Approve", "Approve all <prefix>", "Reject"]` when cache wired
  - 5.3.3 On batched-option select, call `cache.grant(prefix)`
- [x] 5.4 Inject cache via `ccDeps.bashApprovalCache` in `cc-dispatcher.ts realSdkQueryFactory`
- [x] 5.5 Wire revocation into `cleanupCcBashGatesForConversation`
- [x] 5.6 (RED→GREEN) Add multi-Bash batching test in `cc-dispatcher-bash-gate.test.ts`
  - 5.6.1 5x `git status` after batch grant → 0 additional gates
  - 5.6.2 `git status` grant ≠ `git push` allow

## Phase 6 — `#2923` cc system-prompt parity

- [x] 6.1 (RED) Extend `apps/web-platform/test/soleur-go-runner.test.ts`
  - 6.1.1 T1: default-args preserves baseline 5-line prompt
  - 6.1.2 T2: artifact-path injects artifact sentence
  - 6.1.3 T3: activeWorkflow injects sticky-workflow sentence
  - 6.1.4 T4: both args together
- [x] 6.2 (GREEN) Widen `buildSoleurGoSystemPrompt(args?)` signature in `apps/web-platform/server/soleur-go-runner.ts`
- [x] 6.3 Add `artifactPath`/`activeWorkflow` to `QueryFactoryArgs` and `DispatchArgs`
- [x] 6.4 Thread args through `dispatch` → `queryFactory` → `realSdkQueryFactory` → `buildSoleurGoSystemPrompt`

## Phase 7 — Verification

- [x] 7.1 Run targeted vitest files (8 listed in plan §Phase 7)
- [x] 7.2 Run full app-level vitest (`apps/web-platform`)
- [ ] 7.3 Apply migration `033_migrate_api_key_to_v2_rpc.sql` to dev Supabase
- [ ] 7.4 Verify RPC exists via Supabase REST sentinel call

## Phase 8 — Ship

- [ ] 8.1 PR body uses `Closes #2918`, `Closes #2919`, `Closes #2920`, `Closes #2921`, `Closes #2922`, `Closes #2923`
- [ ] 8.2 No version-file edits (plugin.json, marketplace.json)
- [ ] 8.3 Run `/soleur:review` before mark-ready
- [ ] 8.4 Run `/soleur:qa` (no UI changes — minimal scope)
- [ ] 8.5 Auto-merge after CI green
- [ ] 8.6 (Post-merge) Apply migration to prd Supabase
- [ ] 8.7 (Post-merge) Verify migration prd via REST sentinel
- [ ] 8.8 (Post-merge) Close #2919 with deploy-run link
- [ ] 8.9 (Post-merge) Note in #2853 that Stage 6 #2920 + #2923 gates satisfied
- [ ] 8.10 (Post-merge) Verify all release/deploy workflows green
