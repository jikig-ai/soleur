# Tasks: fix Command Center stale conversations after repo swap

**Plan:** `knowledge-base/project/plans/2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md`
**Branch:** `feat-one-shot-command-center-stale-conversations-after-repo-swap`

## 1. Preflight

- [x] 1.1 Confirm next migration number is 029: `cd apps/web-platform && ls supabase/migrations/ | tail -5`.
- [x] 1.2 Enumerate every `conversations` INSERT site: `cd apps/web-platform && grep -rn "from(\"conversations\").insert" . --include="*.ts" --include="*.tsx"`.
- [x] 1.3 Enumerate every `lookupConversationForPath` caller: `cd apps/web-platform && grep -rn "lookupConversationForPath" . --include="*.ts" --include="*.tsx"`.
- [x] 1.4 Baseline-green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/command-center.test.tsx` passes against HEAD.

## 2. RED tests (TDD gate — must fail first)

- [x] 2.1 Create `apps/web-platform/test/command-center-repo-scope.test.tsx` — two conversations, two different `repo_url`; assert only the current one renders. Run, confirm fail.
- [x] 2.2 Create `apps/web-platform/test/lookup-conversation-for-path-repo-scope.test.ts` — same context_path, different repo_url; assert current-repo row is returned. Run, confirm fail.
- [x] 2.3 Create `apps/web-platform/test/disconnect-hides-conversations.test.ts` — user.repo_url = null returns empty. Run, confirm fail.

## 3. Schema & type

- [x] 3.1 Create `apps/web-platform/supabase/migrations/029_conversations_repo_url.sql` (content from plan Phase 1.1).
- [ ] 3.2 Apply migration locally; verify every pre-existing row has non-null `repo_url` matching its user's `users.repo_url`; verify disconnected-user rows stay NULL.
- [x] 3.3 Update `apps/web-platform/lib/types.ts` — add `repo_url: string | null` to `Conversation`.

## 4. Producer side (stamp repo_url on insert)

- [x] 4.1 `server/ws-handler.ts`: stamp `repo_url` on the conversation INSERT (~L283) and include in the 23505-fallback lookup (~L300).
- [x] 4.2 `app/api/repo/setup/route.ts`: stamp `repo_url` on the auto-sync conversation INSERT (~L151-158) — `repoUrl` already in scope from request body.
- [x] 4.3 Sweep every INSERT site from task 1.2 and stamp `repo_url` identically.

## 5. Consumer side (scope queries)

- [x] 5.1 `hooks/use-conversations.ts`: fetch `users.repo_url` after `getUser()`; short-circuit to `[]` when null; add `.eq("repo_url", repoUrl)` to the list query; drop Realtime payloads whose `repo_url !== currentRepoUrl` in the channel callback.
- [x] 5.1b `hooks/use-conversations.ts`: add a second Realtime channel subscribed to `users` UPDATE on `id = currentUserId`. On payload, if `new.repo_url !== currentRepoUrl`, update local `repoUrl` state and call `fetchConversations()`. Covers race R-C (other tab switched repos). Add corresponding scenario 7 test to `test/command-center-repo-scope.test.tsx`.
- [x] 5.2 `server/lookup-conversation-for-path.ts`: add `repoUrl` parameter; add `.eq("repo_url", repoUrl)` to the query; return `{ ok: true, row: null }` when repoUrl is null/empty.
- [x] 5.3 Update every caller from task 1.3 (`app/api/chat/thread-info/route.ts`, `app/api/conversations/route.ts`, `server/conversations-tools.ts`, and the ws-handler 23505 fallback) to read `users.repo_url` and pass it.

## 6. UX nuance — "previous conversations are tied to your disconnected repository"

- [x] 6.1 `app/(dashboard)/dashboard/page.tsx`: when user.repo_status === "not_connected" AND a cheap `count=exact head=true` query on conversations shows pre-existing rows, render a hint line below the first-run CTA explaining that reconnecting the prior URL restores them.

## 7. Verify GREEN

- [x] 7.1 Tests from task 2 now pass.
- [x] 7.2 Existing tests still pass: `test/command-center.test.tsx`, `test/chat-surface-sidebar.test.tsx`, `test/dashboard-sidebar-collapse.test.tsx`.
- [x] 7.3 `./node_modules/.bin/tsc --noEmit` is clean in `apps/web-platform/`.
- [x] 7.4 Full vitest run in `apps/web-platform/` is green.

## 8. QA via Playwright MCP

- [ ] 8.1 Log in as test account with pre-seeded conversations.
- [ ] 8.2 Disconnect repo via Settings.
- [ ] 8.3 Create + connect new (different) repo via Connect Repo flow.
- [ ] 8.4 Command Center: assert zero pre-swap conversations visible; screenshot.
- [ ] 8.5 Start a new conversation in the new repo; verify it appears; screenshot.
- [ ] 8.6 Disconnect again → Command Center shows empty state.
- [ ] 8.7 Reconnect the exact same URL from step 8.3 → new conversation from 8.5 reappears; screenshot.

## 9. Ship artifacts

- [ ] 9.1 Commit plan + tasks.md together with migration + test + code changes.
- [ ] 9.2 Open PR with `Closes #<issue-number>` in the body.
- [ ] 9.3 Post-merge operator: verify migration applied to prod Supabase per runbook `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`.
- [ ] 9.4 Post-merge operator: smoke-test the disconnect+reconnect cycle on a throwaway prod account.

## 10. Deferral issues (file in same PR)

- [ ] 10.1 Issue: `projects` table + project_id on conversations — future multi-repo-per-user model. Milestone: Post-MVP / Later.
- [ ] 10.2 Issue: billing-page conversation count — product question: lifetime vs current-project. Milestone: Post-MVP / Later.
