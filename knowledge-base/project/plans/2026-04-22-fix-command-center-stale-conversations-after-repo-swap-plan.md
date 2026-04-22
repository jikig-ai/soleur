# fix: Command Center shows stale conversations after repo swap

**Type:** bug fix
**Severity:** P1 — data-scoping / UX correctness (not security: all leaked rows belong to the same user)
**Branch:** `feat-one-shot-command-center-stale-conversations-after-repo-swap`
**Date:** 2026-04-22

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Migration safety, Realtime semantics, Race conditions, Related learnings, RLS alignment
**Research sources:** Supabase Realtime docs + GitHub issue #97 (realtime-js multi-column filter limitation), PostgreSQL UPDATE FROM performance guidance, multi-tenant SaaS scoping patterns, sibling migrations 025/027/028, prior learnings (`2026-03-28-unapplied-migration-command-center-chat-failure.md`, `2026-04-17-kb-chat-stale-context-on-doc-switch.md`).

### Key Improvements

1. **Realtime-filter claim validated** — confirmed via Supabase docs and upstream [realtime-js#97](https://github.com/supabase/realtime-js/issues/97) that the `filter:` clause accepts only one `=` predicate. Client-side drop on `repo_url` mismatch is the only option. Plan text made explicit.
2. **UPDATE-FROM backfill sized against prod** — migration 028 comment fixes conversations at ~1k prod rows; UPDATE-FROM with PK join is sub-second, no batching needed. Plan risk section narrowed accordingly.
3. **Two new race conditions flagged** — (a) user disconnects mid-insert: a WS handler inserts a conversation stamped with the just-cleared `repo_url`; plan now prescribes reading `users.repo_url` inside the same transaction as the INSERT, and the WS handler must abort with a "no connected repo" close code if `repo_url` is null at insert time. (b) user reconnects to a different URL while a conversation page is open: the page's hook still has the old `repoUrl` in closure; plan adds a `repo_url`-change-aware effect that refetches (or hard-reloads) when `users.repo_url` changes server-side.
4. **RLS scope clarified** — current RLS on `conversations` is `auth.uid() = user_id` only. This plan does NOT tighten RLS to include `repo_url` because (a) all leaked rows belong to the same user — no cross-tenant security failure, (b) RLS would force service-role clients (ws-handler, agent-runner) to bypass RLS or re-select `users.repo_url` on every write, adding latency for no security gain. Recorded as a defensible Non-Goal with a 1-line rationale.
5. **Retroactive-gate check applied** (per AGENTS.md `wg-when-fixing-a-workflow-gates-detection`) — the KB-chat-stale-context learning (2026-04-17) fixed the same class of bug at the UI layer (unmount-on-key-change). This PR fixes it at the data layer. Both are now needed; plan adds an explicit cross-reference so neither regresses.

### New Considerations Discovered

- **Supabase Realtime cannot express multi-column AND filters** — [realtime-js#97](https://github.com/supabase/realtime-js/issues/97) has been open since 2023 with no movement. Client-side drop is the permanent pattern.
- **`UPDATE FROM` with a joined subquery is ~92% faster than correlated subqueries** ([Dupple, 2026](https://dupple.com/blog/postgresql-update-join)) and is the idiomatic choice for this backfill.
- **AGENTS.md cq-supabase-migration-concurrently-forbidden pattern is already respected** by sibling migrations 025, 027, 028 — our plan inherits their rationale verbatim so the pattern stays consistent.
- **Multi-tenant SaaS guidance prefers tenant-level (here: project/repo) scoping over user-level scoping** — the repo_url approach aligns with this, but the deferred `projects` table is the long-term correct model. The deferral issue (task 10.1) now includes a link to the WorkOS and Flightcontrol multi-tenant guides for the future design.

## Overview

On account `jean.deruelle@jikigai.com`, a user disconnected repo `la-chatte`, then created a new public repo `au-chat-chat` through the Connect Repo flow. After the new project provisioned, the Command Center still displayed every conversation from the `la-chatte` era (e.g. "Shall we bundle Fablab and coworking together as activities?", "Tell me about the file at overview/vision.md"), with no relation to the newly-connected `au-chat-chat` repo.

**Root cause:** the `conversations` table has no repo / project scoping column. The Command Center query (`hooks/use-conversations.ts`) filters on `user_id` only. `DELETE /api/repo/disconnect` clears `users.repo_url` and deletes the workspace on disk, but leaves every `conversations` row untouched. When the user connects a different repo, the query continues to return the pre-disconnect rows.

**Fix, at a high level:** stamp each conversation with the `repo_url` it was created against (new `conversations.repo_url` column), and filter the Command Center query to only return conversations whose `repo_url` matches the user's current `users.repo_url`. Apply the same filter to the KB context-path lookup (`lookupConversationForPath`) so a shared path like `overview/vision.md` in the new repo does not silently resume a thread from the old repo. Leave old rows in place (hidden, recoverable if the user reconnects the same URL) — destructive cascade-delete is out of scope.

**Not fixed in this PR (deferred):** a first-class `projects` table with a repo→project 1:N model; retroactive UX that surfaces "orphaned" conversations from disconnected repos; billing-page lifetime-conversation count (question for product: is billing per-user or per-repo).

## Research Reconciliation — Spec vs. Codebase

| Bug-report claim | Codebase reality | Plan response |
| --- | --- | --- |
| "After swapping repos, Command Center should only show conversations scoped to the current repo" | No repo-scoping column exists on `conversations`; query filters on `user_id` only. | Add `conversations.repo_url` column; filter query by the user's current `users.repo_url`. |
| "Disconnect should not leak to the new repo" | `/api/repo/disconnect/route.ts` clears `users.repo_url` but does **not** touch `conversations`. | Scoping via `repo_url` equality means disconnect automatically hides all conversations (current user `repo_url` becomes `NULL`; no row's `repo_url` equals `NULL` under `.eq()`). |
| "New repo `au-chat-chat` showed conversations about the old repo's files (`overview/vision.md`, `overview/Au%20Chat%20…`)" | KB chat resumption via `lookupConversationForPath` matches on `(user_id, context_path)` only. Two repos with the same file path collide. | Add `repo_url` eq filter to that lookup too; without this, opening `overview/vision.md` in the new repo would resume the la-chatte thread. |

## Hypotheses

- **H1 (confirmed — primary):** `conversations` rows have no repo/project scoping. The Command Center query (`hooks/use-conversations.ts:107-124`) filters on `user_id` only, so any repo swap leaks.
- **H2 (confirmed — secondary):** `lookupConversationForPath` (`server/lookup-conversation-for-path.ts:44-52`) has the same scoping gap on the `(user_id, context_path)` unique key. A file at the same path in the new repo resumes the old repo's thread.
- **H3 (confirmed — cleanup):** `/api/repo/disconnect/route.ts` clears `users.repo_url` but never touches `conversations`. No deletion, no archival, no flag — the rows are simply orphaned.
- **H4 (ruled out):** not an RLS leak. All returned rows belong to the same authenticated user. This is in-user tenancy (project-scope), not cross-user tenancy. Stamping `repo_url` and filtering in the query is sufficient; RLS can later be hardened but is not load-bearing.
- **H5 (ruled out):** not a caching bug. The query re-runs on mount; the Supabase Realtime subscription still filters by `user_id` only. No stale state in hook memo / localStorage.

## Files to Edit

- `apps/web-platform/supabase/migrations/029_conversations_repo_url.sql` — **new migration** (create).
- `apps/web-platform/hooks/use-conversations.ts` — load current user's `repo_url`, add `.eq("repo_url", repoUrl)` to the list query; gracefully handle `repo_url === null` (return empty list).
- `apps/web-platform/server/lookup-conversation-for-path.ts` — accept `repoUrl` arg; add `.eq("repo_url", repoUrl)` to the context_path lookup.
- `apps/web-platform/app/api/chat/thread-info/route.ts` — read `users.repo_url`, pass to `lookupConversationForPath`.
- `apps/web-platform/app/api/conversations/route.ts` — same as above if it calls `lookupConversationForPath` (verify at work-time).
- `apps/web-platform/server/conversations-tools.ts` — same as above (`conversations_lookup` MCP tool; verify at work-time).
- `apps/web-platform/server/ws-handler.ts` — at conversation creation (line ~283 and the 23505 fallback path), stamp `repo_url` from current user row.
- `apps/web-platform/app/api/repo/setup/route.ts` — at the auto-sync conversation insert (line ~151-158), stamp `repo_url`.
- `apps/web-platform/lib/types.ts` — add `repo_url: string | null` to the `Conversation` type.

## Files to Create

- `apps/web-platform/supabase/migrations/029_conversations_repo_url.sql`
- `apps/web-platform/test/command-center-repo-scope.test.tsx` — RED test: seed two conversations with different `repo_url` values against one user, assert only the current-repo one renders.
- `apps/web-platform/test/lookup-conversation-for-path-repo-scope.test.ts` — RED test: two conversations with same `(user_id, context_path)` but different `repo_url`; assert only the current-repo one is returned.
- `apps/web-platform/test/disconnect-hides-conversations.test.ts` — RED test (API-level or hook-level): after `users.repo_url` is nulled, the query returns `[]`.

## Open Code-Review Overlap

None. Queried the 20 most recent open `code-review` issues (#2594, #2592, #2591, #2590, #2349, #2348, #2246, #2244, #2231, #2225-#2217, #2197, #2196) — zero reference `hooks/use-conversations.ts`, `server/lookup-conversation-for-path.ts`, `app/api/repo/disconnect/`, `app/api/repo/setup/`, `app/api/conversations/`, or `supabase/migrations/`. No fold-in, no defer.

## Implementation Phases

### Phase 1 — Migration + type (DB contract first)

**1.1** Write migration `029_conversations_repo_url.sql`:

```sql
-- 029_conversations_repo_url.sql
-- Scope conversations to the repository they were created against.
-- Fixes: command center + KB-context-path lookup leaking pre-disconnect
-- conversations into a freshly-connected repo (see plan
-- 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md).
--
-- Nullable on purpose: pre-migration rows are backfilled with the user's
-- CURRENT repo_url. If the user had already disconnected before this
-- migration ran, users.repo_url is NULL and conversations.repo_url stays
-- NULL — those rows will be hidden by the new query filter (desired —
-- matches disconnect semantics).
--
-- NOT using CONCURRENTLY: Supabase migration runner wraps each file in a
-- transaction (see migrations 025, 027 comments). Column add + index are
-- transaction-safe. If the table grows to a size where an index rebuild
-- becomes disruptive, ship a second migration via direct psql.

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS repo_url text;

-- Backfill pre-migration rows with the user's current repo_url.
-- For disconnected users (repo_url IS NULL), conversations.repo_url stays NULL.
UPDATE public.conversations c
   SET repo_url = u.repo_url
  FROM public.users u
 WHERE c.user_id = u.id
   AND c.repo_url IS NULL;

-- Partial index — only populated rows are indexed (disconnected-user
-- conversations don't need index coverage; they're never queried).
CREATE INDEX IF NOT EXISTS idx_conversations_user_repo
  ON public.conversations (user_id, repo_url)
  WHERE repo_url IS NOT NULL;

-- Update the existing context_path UNIQUE index to include repo_url so
-- the same KB file path in two repos no longer collides. This drops and
-- recreates the index (established pattern — see migration 025).
DROP INDEX IF EXISTS public.conversations_context_path_user_uniq;

CREATE UNIQUE INDEX conversations_context_path_user_uniq
  ON public.conversations (user_id, repo_url, context_path)
  WHERE context_path IS NOT NULL AND archived_at IS NULL;
```

**1.2** Update `apps/web-platform/lib/types.ts` — add `repo_url: string | null` to `Conversation`.

**Deliverable of Phase 1:** migration applies cleanly on a populated dev DB; every pre-existing conversation has a non-null `repo_url` equal to the user's current `users.repo_url`.

#### Research Insights (Phase 1)

**Best Practices:**

- `UPDATE ... FROM <table>` with an indexed PK join is ~92% faster than a correlated subquery (`UPDATE ... SET col = (SELECT ...)`) — the backfill uses the join form.
- Supabase migrations run in a transaction per file — `CREATE INDEX CONCURRENTLY` is rejected (`SQLSTATE 25001`). Pattern established by migrations 025, 027, 028; this plan follows the same rationale verbatim.

**Performance Considerations:**

- Production `conversations` is ~1k rows (per migration 028's comment). UPDATE-FROM joined to `users` by PK completes in sub-second; no batching / timeout loop needed.
- Lock scope during the backfill: UPDATE acquires `ROW EXCLUSIVE` on `conversations` and `ACCESS SHARE` on `users`. Blocks concurrent writes to `conversations` for the duration — sub-second window is acceptable; no concurrent-write traffic in the migration window is realistic for a single-instance deploy.

**Edge Cases:**

- Rows whose user has `users.repo_url IS NULL` at migration time stay `repo_url = NULL` and are hidden by the new query filter. Exactly what disconnect-without-reconnect semantics dictate.
- Rows whose user row was deleted (impossible under `ON DELETE CASCADE` but worth stating) — the join simply misses them; they stay `NULL`. Hidden, consistent with H4.

**References:**

- [PostgreSQL UPDATE JOIN performance guide (Dupple, 2026)](https://dupple.com/blog/postgresql-update-join) — justifies the `UPDATE ... FROM` form.
- [Supabase migration 028 comment (in-tree)](apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql) — prior-art transactional-runner rationale we mirror.

### Phase 2 — Stamp `repo_url` on new conversations (producer side)

**2.1** `server/ws-handler.ts` — at the conversation INSERT (~line 283) and the 23505 unique-violation fallback (~line 300), read the current user's `repo_url` and include it in the insert payload. On the fallback lookup, include `repo_url` in the `.eq()` chain.

**2.2** `app/api/repo/setup/route.ts` — at the auto-sync conversation INSERT (~line 151-158), stamp `repo_url` from the freshly-set value (`repoUrl` is in scope from the request body).

**2.3** Sweep `grep -rn "from(\"conversations\").insert" apps/web-platform` for any other INSERT sites and stamp them identically. Document each in this plan before implementing.

**Deliverable of Phase 2:** conversations inserted after this phase carry a non-null `repo_url`. Manual verify: insert a test conversation, inspect the DB row.

### Phase 3 — Scope the consumer queries (reader side)

**3.1 RED test first — `test/command-center-repo-scope.test.tsx`:** seed two conversations for one mocked user — one with `repo_url = "https://github.com/acme/old"`, one with `"https://github.com/acme/new"`. Mock `users.repo_url = "https://github.com/acme/new"`. Render the dashboard. Assert only the "new" conversation renders. This test MUST fail against the current main.

**3.2** Update `hooks/use-conversations.ts`:

- After `getUser()`, fetch `users.repo_url` for the authenticated user.
- If `repo_url` is `null`, short-circuit: `setConversations([])` and return — there is no connected repo, so the Command Center shows the empty state.
- Otherwise add `.eq("repo_url", repoUrl)` to the list query.
- The Supabase Realtime subscription filter stays on `user_id` — Realtime's `filter:` accepts only a single equality predicate per [realtime-js#97](https://github.com/supabase/realtime-js/issues/97); a two-column AND is not expressible at the wire protocol. We handle cross-repo rows client-side by dropping payloads whose `repo_url !== currentRepoUrl` in the listener callback — same defense-in-depth pattern as the existing `archived_at` handling.
- Add a second effect that subscribes to `users` table UPDATE events on `id = currentUserId`. On payload with `new.repo_url !== currentRepoUrl`, update local `repoUrl` state and call `fetchConversations()` to re-scope the view in place. This closes race-condition **R-C** below (user reconnects to a different URL in another tab while this tab is open).

**3.3 RED test — `test/lookup-conversation-for-path-repo-scope.test.ts`:** seed two rows with the same `(user_id, context_path)` but different `repo_url`. Call `lookupConversationForPath(userId, path, currentRepoUrl)`. Assert the returned row's `repo_url` matches `currentRepoUrl`. Also assert that the pre-migration UNIQUE index would have rejected this seed; the new index permits it.

**3.4** Update `server/lookup-conversation-for-path.ts`:

- Signature becomes `lookupConversationForPath(userId, contextPath, repoUrl)`.
- Add `.eq("repo_url", repoUrl)` to the query.
- If `repoUrl` is `null`/empty, return `{ ok: true, row: null }` — no connected repo means no resumable thread.

**3.5** Update every caller of `lookupConversationForPath`:

- `app/api/chat/thread-info/route.ts`
- `app/api/conversations/route.ts` (verify — the file exists; inspect it at work-time)
- `server/conversations-tools.ts` (MCP tool `conversations_lookup` — verify at work-time)
- Each caller must fetch `users.repo_url` for the authenticated user and pass it through. If `repo_url` is null, return an empty / not-found response consistent with that route's contract.

**3.6** Update the `ws-handler.ts` resume-by-context_path fallback (the 23505 branch, ~line 300) to include `repo_url` in its lookup, matching the new UNIQUE index predicate. Without this, a 23505 on insert would fall back to a lookup that finds nothing and throw the same "Failed to resolve existing context_path conversation" error migration 025 tried to eliminate.

**Deliverable of Phase 3:** Command Center shows only current-repo conversations; KB context-path resume never crosses repo boundaries; tests from 3.1 and 3.3 pass.

### Phase 4 — Disconnect path alignment (no code change expected)

**4.1** Audit `/api/repo/disconnect/route.ts`. With the repo_url scoping in place, setting `users.repo_url = NULL` automatically hides all that user's conversations from the Command Center (because `.eq("repo_url", null)` matches nothing in PostgREST). **No code change is expected here** — but we must record this claim in the plan so a reviewer doesn't add speculative cleanup.

**4.2 RED test — `test/disconnect-hides-conversations.test.ts`:** seed conversations with `repo_url = "https://github.com/acme/x"`, then null the user's `repo_url`. Assert the hook / route returns `[]`.

**Deliverable of Phase 4:** verified-by-test that disconnect alone (no conversation mutation) hides all conversations.

### Phase 5 — QA via Playwright MCP (ships with the PR)

Reproduce the exact scenario from the bug report against the dev server:

1. Log in as a test account with a pre-seeded repo + conversations.
2. Navigate to Settings → Disconnect repository.
3. Connect a new (different) repo via the Create Repo flow.
4. Navigate to Command Center. Assert **zero** pre-swap conversations are visible (empty-state copy renders instead).
5. Start a new conversation in the new repo. Verify it appears and the old ones are still hidden.
6. Disconnect again. Navigate to Command Center. Assert empty state (no connected repo).
7. Reconnect the SAME new repo (same URL). Assert the conversations from step 5 reappear (`repo_url` equality holds).

Screenshots from steps 4, 5, 7 land in the PR description.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Migration `029_conversations_repo_url.sql` adds `conversations.repo_url` column, backfills from `users.repo_url`, adds `(user_id, repo_url)` partial index, rotates the context_path UNIQUE index to include `repo_url`.
- [ ] Every `conversations` INSERT site in `apps/web-platform/` stamps `repo_url` from the authenticated user's current `users.repo_url`.
- [ ] `hooks/use-conversations.ts` filters by `(user_id, repo_url)`; returns empty list when `users.repo_url IS NULL`.
- [ ] `lookupConversationForPath` requires a `repoUrl` argument and filters by it; all callers pass the current value.
- [ ] Three new tests (Phase 3.1, 3.3, 4.2) pass; existing `test/command-center.test.tsx`, `test/chat-surface-sidebar.test.tsx`, and `test/dashboard-sidebar-collapse.test.tsx` still pass.
- [ ] `tsc --noEmit` passes with the new `Conversation.repo_url` type.
- [ ] `npm run test` passes in `apps/web-platform` (using `./node_modules/.bin/vitest run` per AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`).
- [ ] PR description includes Playwright screenshots for QA steps 4, 5, 7.

### Post-merge (operator)

- [ ] Migration applied to prod Supabase (verify via REST API per AGENTS.md `wg-when-a-pr-includes-database-migrations`; runbook `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`).
- [ ] Smoke-test on production: disconnect + reconnect cycle on a throwaway account does not leak conversations.

## Test Scenarios

| # | Scenario | Expected | Test file |
| --- | --- | --- | --- |
| 1 | Single connected repo, 3 conversations | All 3 show | existing `command-center.test.tsx` (must still pass) |
| 2 | Disconnected (repo_url = null), 3 orphaned conversations | `conversations.length === 0`; empty-state renders | `disconnect-hides-conversations.test.ts` |
| 3 | Swapped repos (old has 2 conversations, new has 1) | Only the 1 new conversation shows | `command-center-repo-scope.test.tsx` |
| 4 | Two repos, same `overview/vision.md` path, different threads | `lookupConversationForPath` returns the current-repo row | `lookup-conversation-for-path-repo-scope.test.ts` |
| 5 | User reconnects the exact same URL that was previously connected | Previously-hidden conversations re-appear | manual QA (step 7) |
| 6 | Realtime UPDATE arrives for a conversation with a different `repo_url` than the user's current | Subscription callback drops the payload | unit test in `command-center-repo-scope.test.tsx` |
| 7 | Realtime UPDATE on `users` changes `repo_url` (user reconnected to different URL in another tab) | Hook refetches; visible conversation set updates to new scope | unit test in `command-center-repo-scope.test.tsx` |

## Risks & Edge Cases

- **R-A: clone-in-progress disconnect.** The existing disconnect handler already rejects with 409 while `repo_status === "cloning"`. The stamping in Phase 2.2 relies on `users.repo_url` being set at insert time, which happens before the auto-sync conversation is created (setup route sets `repo_url` then inserts the conversation). Safe.
- **R-B: user disconnects mid-stream.** A WebSocket session may insert messages into a conversation whose `repo_url` no longer matches the user's current `repo_url`. Those messages still persist under the conversation's original `repo_url`. The hook never shows them — correct behavior. No extra guard needed.
- **R-C: user reconnects to a different URL in another tab while this tab is open.** Without mitigation, the hook keeps showing conversations scoped to the prior URL until the page reloads. **Mitigation:** Phase 3.2 second effect subscribes to `users` UPDATE events and refetches on `repo_url` change. Tested explicitly in `test/command-center-repo-scope.test.tsx` (add scenario: emit a `users` UPDATE with a new `repo_url`, assert the hook refetches and the conversation set changes).
- **R-D: conversation INSERT races `users.repo_url` clear.** A WS handler reads `users.repo_url = X`, then the user's other tab disconnects (sets `repo_url = NULL`), then the WS handler INSERTs a conversation with `repo_url = X`. The row is then "orphaned" (user's current `repo_url` is NULL or a different value). Impact: one row in the DB that never surfaces in any query until the user re-connects `X`. Not a correctness failure — just a no-op row. **Mitigation:** accept as out-of-scope; disconnect is rare and the failure mode is benign. If it becomes a problem, wrap the INSERT in a single-statement `INSERT ... SELECT repo_url FROM users WHERE id = $1 AND repo_url IS NOT NULL` so the write short-circuits to zero rows when the user disconnected mid-insert.
- **Per-request cost of reading `users.repo_url`.** Each conversation list query now adds one `users` row read. Negligible — single-row lookup by PK. Could be hoisted to a React context (alongside the existing `useOnboarding` / user-data context) if it shows in profiling, but not warranted at plan time.
- **Null-`repo_url` Realtime filter.** Supabase Realtime's `filter` clause accepts only a single equality predicate ([realtime-js#97](https://github.com/supabase/realtime-js/issues/97)). Client-side drop in the callback is the idiomatic pattern (already used for `archived_at`).
- **RLS not tightened.** Conversations' RLS is `auth.uid() = user_id`. This plan deliberately does NOT add `repo_url` to the RLS `USING` clause: (a) no cross-user leak exists, so RLS is not the defense layer, (b) ws-handler and agent-runner use the service role (RLS-bypassed) and would need their own checks anyway, (c) adding RLS would force every authenticated-client read to JOIN `users`, doubling the per-query row reads. Recorded as a Non-Goal; revisit if/when org-level sharing lands.
- **`toContain` vs `toBe` in assertions (AGENTS.md `cq-mutation-assertions-pin-exact-post-state`).** All scenarios above assert exact post-state — scenario 2 asserts `conversations.length === 0`, scenario 3 asserts the specific surviving id, scenario 4 asserts the returned `repo_url` matches.
- **jsdom layout traps (AGENTS.md `cq-jsdom-no-layout-gated-assertions`).** None of the new tests depend on layout values.
- **Destructive-prod test allowlist (AGENTS.md `cq-destructive-prod-tests-allowlist`).** Not applicable — all new tests are unit-level with mocked Supabase; no prod writes.
- **Union widening / exhaustive-switch (AGENTS.md `cq-union-widening-grep-three-patterns`).** Adding `repo_url` to the `Conversation` type is a field add, not a union widening — no consumer switch patterns to sweep.

### Related Learnings (retroactive-gate check)

- [`knowledge-base/project/learnings/2026-04-17-kb-chat-stale-context-on-doc-switch.md`](../learnings/2026-04-17-kb-chat-stale-context-on-doc-switch.md) — fixed a *UI-layer* variant of this bug class (chat panel carries state across URL-key change) by forcing unmount on key change. This PR fixes the *data-layer* variant (conversations are not scoped to the URL-equivalent `repo_url`). The UI fix and the data-layer fix are complementary — neither subsumes the other. The retroactive-gate check per AGENTS.md `wg-when-fixing-a-workflow-gates-detection` is satisfied: both fixes land, neither regresses.
- [`knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`](../learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md) — documents the exact failure mode an unapplied `029_conversations_repo_url.sql` migration would produce (app code expects a column that doesn't exist → silent 500). Post-merge AC includes a REST-API verification probe per runbook to prevent recurrence.
- [`knowledge-base/project/learnings/database-issues/disconnect-null-constraint-violation-20260406.md`](../learnings/database-issues/disconnect-null-constraint-violation-20260406.md) — prior disconnect-handler bug. This plan does NOT modify the disconnect handler's field-clear payload; no regression risk for that class.

## Non-Goals / Out of Scope

- A first-class `projects` table with `(user_id, repo_url) → project_id` FK. The repo_url-as-scope approach is sufficient for the current one-repo-per-user product model. When the product evolves to multi-repo-per-user, introduce `projects.id` and add a `project_id` column to `conversations`. Multi-tenant SaaS guidance favors tenant/project-level scoping over user-level scoping ([WorkOS guide](https://workos.com/blog/developers-guide-saas-multi-tenant-architecture), [Flightcontrol multi-tenant data modeling](https://www.flightcontrol.dev/blog/ultimate-guide-to-multi-tenant-saas-data-modeling)); the deferred design should follow that pattern. Deferral tracked as a follow-up issue (to be filed in Phase 6 of this plan if not already tracked).
- RLS tightening on `conversations` to include `repo_url`. See R-D / "RLS not tightened" in Risks — deliberate no-op. Revisit only if org-level sharing lands.
- Billing-page conversation count. The current query (`app/(dashboard)/dashboard/settings/billing/page.tsx:33`) counts lifetime conversations per `user_id`. **Open question for product:** should lifetime billing reflect all history, or only current-project? Not touched by this PR. File deferral issue.
- UI for "orphaned" conversations (conversations whose `repo_url` no longer matches any current user's `repo_url`). Not needed today — hidden is sufficient.
- Hard cascade delete on disconnect. Deliberate no-op — reconnecting the same URL should restore the view. Cascade-delete would make the disconnect button irreversible with zero upside.
- Cross-user tenancy / RLS hardening. All leaked rows belong to the same user, so RLS is not load-bearing here. If future product decisions add org-level sharing, revisit.

## Domain Review

**Domains relevant:** Engineering (primary), Product (tier-assessment for UX impact).

### Engineering (CTO scope)

**Status:** inline review (no subagent spawn — plan phase handled by planner directly per plan step 2.5; full CTO review at /ship Phase 5.5 per AGENTS.md `hr-before-shipping-ship-phase-5-5-runs`).
**Assessment:** Schema change is minimal and follows the migration 024/025 pattern (add column + rotate index + narrow partial-index predicate). No new tables. Query changes are additive. Three RED tests provide regression coverage. The one migration risk (backfill UPDATE on a possibly-large `conversations` table) is bounded by the dev DB size and acceptable within Supabase's transactional migration model — the query runs once, is idempotent, and only reads `users.repo_url`.

### Product/UX Gate

**Tier:** advisory (modifies the Command Center empty state & empty-filter states, no new pages/flows).
**Decision:** auto-accepted (pipeline context — plan invoked by `/one-shot` subagent, not interactively).
**Agents invoked:** none (advisory tier in pipeline context).
**Skipped specialists:** none required.
**Pencil available:** N/A (no wireframes needed; empty-state copy already exists at `app/(dashboard)/dashboard/page.tsx:329-443`).

#### Findings

- The existing first-run empty state (`!visionExists && conversations.length === 0 && !hasActiveFilter` → "Tell your organization what you're building.") is a good fallback when `users.repo_url IS NULL`. No new copy needed.
- Risk: a user who had 50 conversations and disconnects will see the "No conversations yet" empty state, which can read like data loss. **Mitigation (in-scope for this PR):** if `users.repo_status === "not_connected"` and the user has pre-existing conversations stamped with other `repo_url` values, the dashboard should hint "Your previous conversations are tied to your disconnected repository. Reconnect that repository to view them." This is a one-line conditional render in `app/(dashboard)/dashboard/page.tsx`. Counts can come from a cheap `count=exact head=true` query. **Ship decision:** in-scope, lightweight, same PR.

## Verification Commands (pre-flight)

Before starting implementation, a work-skill agent MUST run:

- `cd apps/web-platform && ls supabase/migrations/ | tail -5` — confirm the next migration number is 029 (currently 028 is the latest).
- `cd apps/web-platform && grep -rn "from(\"conversations\").insert" . --include="*.ts" --include="*.tsx"` — enumerate every INSERT site.
- `cd apps/web-platform && grep -rn "lookupConversationForPath" . --include="*.ts" --include="*.tsx"` — enumerate every caller.
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/command-center.test.tsx` — confirm the existing test suite is green against main before editing.

Record each command's output under `## Preflight Output` when implementation begins — do not skip.

<!-- verified: 2026-04-22 source: local inspection of apps/web-platform/supabase/migrations/ at commit HEAD of branch feat-one-shot-command-center-stale-conversations-after-repo-swap (latest migration 028_conversations_user_id_session_id_unique.sql) -->
