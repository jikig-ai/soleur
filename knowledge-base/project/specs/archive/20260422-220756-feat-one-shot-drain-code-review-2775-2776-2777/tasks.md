# Tasks: Drain web-platform Code-Review Backlog (#2775 + #2776 + #2777)

**Plan:** `knowledge-base/project/plans/2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
**Branch:** `feat-one-shot-drain-code-review-2775-2776-2777`

## 1. Setup

- [ ] 1.1 Verify working directory is the worktree; branch is `feat-one-shot-drain-code-review-2775-2776-2777`
- [ ] 1.2 Confirm `apps/web-platform` is the app root; vitest will run there (`cd apps/web-platform && ./node_modules/.bin/vitest run`)

## 2. Phase 1 — Normalization foundation (#2775)

### 2.1 TDD RED

- [ ] 2.1.1 Create `apps/web-platform/test/repo-url.test.ts` with failing tests for `normalizeRepoUrl`
  - Idempotence (`normalize(normalize(x)) === normalize(x)`)
  - Strip trailing `.git` (case-insensitive, e.g. `.GIT`)
  - Strip trailing `/` (including multiple)
  - Lowercase host only (preserve owner/repo path case)
  - `trim()` leading/trailing whitespace
  - Empty string pass-through
  - Non-GitHub URL pass-through
  - Combined (`HTTPS://GitHub.com/Foo/Bar.git/` → `https://github.com/Foo/Bar`)
- [ ] 2.1.2 Run `./node_modules/.bin/vitest run test/repo-url.test.ts` — expect RED (file doesn't exist yet)

### 2.2 TDD GREEN

- [ ] 2.2.1 Create `apps/web-platform/lib/repo-url.ts` exporting `normalizeRepoUrl(raw: string): string`
- [ ] 2.2.2 Re-run the test — expect GREEN

### 2.3 Apply at write boundary

- [ ] 2.3.1 Edit `apps/web-platform/app/api/repo/setup/route.ts` — replace inline `body.repoUrl.trim().replace(/\/+$/, "")` with `normalizeRepoUrl(body.repoUrl)`. Apply BEFORE the format validator.

### 2.4 Apply at server read boundary

- [ ] 2.4.1 Edit `apps/web-platform/server/current-repo-url.ts` — wrap the returned value in `normalizeRepoUrl(...)`. Import from `@/lib/repo-url`.

### 2.5 Apply at client read boundary

- [ ] 2.5.1 Edit `apps/web-platform/hooks/use-conversations.ts`:
  - Normalize `currentRepoUrl` (around line 123-125)
  - Normalize `updated?.repo_url` in the users-channel Realtime callback (around line 292)
  - Add a code comment anchoring the "already normalized" contract on the `.eq("repo_url", currentRepoUrl)` line

### 2.6 Collapse sibling read (audit every query)

- [ ] 2.6.1 Edit `apps/web-platform/server/agent-runner.ts` — replace the inline `SELECT ... repo_url ...` at line 419 + the read at line 589 with a call to `getCurrentRepoUrl(userId)`. Justify in commit.

### 2.7 Verify Phase 1

- [ ] 2.7.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` — all green (regression-free)
- [ ] 2.7.2 `cd apps/web-platform && npx tsc --noEmit` — clean

## 3. Phase 2 — Backfill migration (#2775)

- [ ] 3.1 Create `apps/web-platform/supabase/migrations/031_normalize_repo_url.sql`:
  - Idempotent `UPDATE` on `users.repo_url` (regexp-based normalize matching `lib/repo-url.ts`)
  - Same `UPDATE` on `conversations.repo_url` (coupling invariant from 029)
  - WHERE `repo_url IS NOT NULL AND repo_url <> <normalized-expression>` on each
  - No `CONCURRENTLY` (transaction-wrapped)
  - Inline COMMENT explaining the regex chain maps to `normalizeRepoUrl`
- [ ] 3.2 Self-test locally: read the SQL in a Supabase SQL console, dry-run the SELECT variant, verify idempotence
- [ ] 3.3 Document post-merge operator steps in the PR body per `wg-when-a-pr-includes-database-migrations`

## 4. Phase 3 — MCP tool parity (#2776)

### 4.1 TDD RED

- [ ] 4.1.1 Invert `apps/web-platform/test/conversations-tools.test.ts` lines 71-78: assert the three new tool names ARE in the builder's output
- [ ] 4.1.2 Create `apps/web-platform/test/conversations-list-archive-tools.test.ts` covering:
  - `conversations_list` filter matrix (8 corner cases)
  - `conversations_list` disconnected-user short-circuit (`{ error: "disconnected", code: "no_repo_connected" }`, isError: true)
  - `conversation_archive` sets `archived_at` to a timestamp; `conversation_unarchive` sets it to `null` (exact `.toBe(null)` — per `cq-mutation-assertions-pin-exact-post-state`)
  - Closure user-binding: two builders with different userIds invoke Supabase with their respective userIds
  - Repo-scope: a conversation from repo A is invisible while user is connected to repo B
- [ ] 4.1.3 Run tests — expect RED

### 4.2 TDD GREEN

- [ ] 4.2.1 Edit `apps/web-platform/server/conversations-tools.ts`:
  - Remove lines 6-7 (defer comment)
  - Add `conversations_list({ statusFilter?, domainLeader?, archived? })` tool
  - Add `conversation_archive({ conversationId })` tool
  - Add `conversation_unarchive({ conversationId })` tool
  - Each tool: resolve `repoUrl = await getCurrentRepoUrl(userId)`; short-circuit if null
  - Each mutation tool: `UPDATE ... WHERE id = ? AND user_id = ? AND repo_url = ?` (three-column backstop)
- [ ] 4.2.2 Run tests — expect GREEN
- [ ] 4.2.3 `npx tsc --noEmit` — clean

## 5. Phase 4 — Test mock consolidation (#2777)

### 5.1 Extract shared helpers

- [ ] 5.1.1 Create `apps/web-platform/test/mocks/supabase-query-builder.ts`:
  - Export `buildSupabaseQueryBuilder({ data?, error?, singleRow?, count? })` — union shape from the three existing helpers
  - Export `buildPredicateAwareQueryBuilder(...)` — same surface + `predicates` capture array on `.eq()`
- [ ] 5.1.2 Create `apps/web-platform/test/mocks/supabase-query-builder.test.ts` — self-test for the helper's public surface

### 5.2 Migrate 3 confirmed sites

- [ ] 5.2.1 `apps/web-platform/test/command-center.test.tsx`:
  - Delete inline `createQueryBuilder` (lines 97-114)
  - `import { buildSupabaseQueryBuilder } from "./mocks/supabase-query-builder"`
  - Rename all call sites (`createQueryBuilder(data)` → `buildSupabaseQueryBuilder({ data })`)
  - Run the file's test suite; expect green
- [ ] 5.2.2 `apps/web-platform/test/start-fresh-onboarding.test.tsx` — same pattern
- [ ] 5.2.3 `apps/web-platform/test/update-status.test.tsx` — same pattern; verify `error` arg path covered
- [ ] 5.2.4 Confirm `rg 'function createQueryBuilder' apps/web-platform/test/` returns 0 hits

### 5.3 Document the deliberate non-migration

- [ ] 5.3.1 Add a code comment near the inline mock in `apps/web-platform/test/ws-deferred-creation.test.ts` explaining why it's not migrated (cites this plan file by name)

### 5.4 Full test sweep

- [ ] 5.4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` — all green
- [ ] 5.4.2 `npx tsc --noEmit` — clean

## 6. Phase 5 — Ship

- [ ] 6.1 Run `skill: soleur:compound` to capture learnings
- [ ] 6.2 Run `skill: soleur:ship` to drive commit + PR
- [ ] 6.3 PR body must include (each on its own line):

  ```
  Closes #2775
  Closes #2776
  Closes #2777
  ```

- [ ] 6.4 PR body must reference PR #2486 as the drain pattern
- [ ] 6.5 PR body must note #2778 is intentionally NOT closed

## 7. Post-merge (operator)

- [ ] 7.1 Apply migration 031 to prod Supabase per `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
- [ ] 7.2 Sentinel query: `SELECT count(*) FROM users WHERE repo_url ~ '\.git$|/$|[A-Z](?=.*github\.com)'` returns 0
- [ ] 7.3 Verify #2775, #2776, #2777 auto-closed (`gh issue view <N> --json state`)
- [ ] 7.4 Verify #2778 is still OPEN (regression gate)
- [ ] 7.5 Verify release/deploy workflows succeeded
- [ ] 7.6 Optional black-box: MCP tool probe on a throwaway account (list + archive + unarchive round-trip)
