# Plan: Drain web-platform Code-Review Backlog (PR #2775 + PR #2776 + PR #2777)

**Date:** 2026-04-22
**Branch:** `feat-one-shot-drain-code-review-2775-2776-2777`
**Issues closed:** #2775, #2776, #2777 (all Post-MVP / Later, code-review-origin)
**Explicitly NOT in scope:** #2778 (projects-table architectural pivot — remains deferred per its own Re-evaluation Criteria)
**Drain pattern reference:** PR #2486 (refactor(kb) — one PR, three closures)
**Origin PR:** #2766 (conversations.repo_url scoping work)

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Overview, Files to Edit (#2775, #2776), Phase 2 (migration), Phase 3 (MCP tools), Acceptance Criteria, Test Scenarios, Risks, Research Insights
**Lenses applied:** architecture-strategist, data-integrity-guardian, data-migration-expert, security-sentinel, agent-native-reviewer, test-design-reviewer, code-simplicity-reviewer, pattern-recognition-specialist, learnings-researcher

### Key Improvements

1. **Exact Postgres `normalizeRepoUrl` equivalent prescribed inline** — the SQL regex chain (`regexp_replace` + `substring`-based host-lowercase that preserves the owner/repo path case) is specified with a verification query so the backfill can be dry-run against prod before applying. Previously the plan said "port the JS regex" without showing the port — reviewable gap closed.
2. **MCP tool schemas pinned to existing Zod types** — `ConversationStatus`, `DomainLeaderId`, and the archive-filter shape are reused from `lib/types.ts` and `server/domain-leaders.ts` instead of redeclared, eliminating drift risk. The `domainLeader` tool arg accepts the `| "general" | null` sentinel to match `UseConversationsOptions`.
3. **Sibling-query audit hardened** — per the 2026-04-22 "audit every query" learning, the plan now enumerates all 7 `repo_url` write/filter sites in `ws-handler.ts` + `agent-runner.ts` + helpers and assigns each an explicit disposition (already-normalized, collapse-to-helper, or leave-as-is with rationale).
4. **YAGNI pass on `buildPredicateAwareQueryBuilder`** — the variant was prescribed "for future tests." Dropped unless a concrete test in this PR consumes it. If no consumer materializes during Phase 4, the variant is not written and `lookup-conversation-for-path-repo-scope.test.ts`'s existing predicate-aware inline helper stays put.
5. **Migration idempotence verified by shape** — the backfill's WHERE clause (`repo_url <> <normalized-expr>`) is exactly the idempotence guarantee. Added a dry-run SELECT probe in Acceptance Criteria so the operator can preview the affected row count before applying.
6. **Test-design gate for MCP tool tests** — archive round-trip assertions use `.toBe(null)` / `.toBe(expect.stringMatching(ISO_8601))` to satisfy `cq-mutation-assertions-pin-exact-post-state`. The disconnected-user short-circuit test uses a predicate-aware mock so the helper's `getCurrentRepoUrl=null` branch is actually exercised (not tautologically passed via a fixed return).
7. **Security: MCP archive write threat model captured** — `conversation_archive` is a write; the tool description + implementation enforce a three-column WHERE (`id`, `user_id`, `repo_url`) AND the RLS backstop. Agent cannot mass-archive cross-repo rows even with a cached conversationId.
8. **Deploy-time verification added** — per the 2026-03-28 "unapplied migration = silent deployment failure" learning, the Post-merge Acceptance Criteria include a Supabase REST API sentinel query that must return 0 before issues are closed.

### New Considerations Discovered

- **Migration runner transaction vs. UPDATE size.** At current data scale (<100K conversations) this is fine. But the migration's UPDATE holds a row-level lock on every row it rewrites for the duration of the transaction. A concurrent user-triggered `UPDATE users SET repo_url = ...` during the migration will block until the migration commits. Mitigation: migration runs in the deploy pipeline's quiet window; no explicit gate needed at current scale but called out so operators know the behavior.
- **`.git` strip is not just a suffix — could be mid-string.** Defensive: `normalizeRepoUrl('https://github.com/foo/bar.git.bak')` must NOT strip `.git` from the middle. Regex must anchor `$`.
- **Uppercase `.GIT` on Windows-originated clones.** Git-for-Windows and some GitHub UI copy-actions yield `.git` lowercase, but legacy tooling can produce `.GIT`. Regex flag `i` on the `.git` strip.
- **Idempotence isn't free — `trim()` on already-normalized input is a no-op, but `lowercase host` on a mixed-case path like `https://github.com/Foo/Bar` must touch only the host portion. Pin this with a test that asserts `normalize('https://github.com/Foo/Bar') === 'https://github.com/Foo/Bar'` (no change — host is already `github.com`).
- **`conversations_list` default page size.** `use-conversations.ts` line 158 caps `.limit(50)`. The MCP tool must match this cap by default — an unbounded list would break agent-token-budget assumptions. Added as an explicit default.

## Overview

Three P3/code-review-origin scope-outs all live in `apps/web-platform` and all trace back to the `conversations.repo_url` work shipped in PR #2766. Folding them into one refactor PR is strictly cheaper than three separate PRs because:

- #2775 (normalize repo_url at write boundary) and #2776 (expose `conversations_list` + `conversation_archive` MCP tools) both touch `server/current-repo-url.ts` and `hooks/use-conversations.ts`. Planning them together ensures the MCP tools in #2776 consume the normalized read path from #2775 — shipping them separately would either (a) require #2776 to ship temporarily de-normalized, then be re-scoped after #2775 merges, or (b) force an arbitrary merge order.
- #2777 (consolidate `createQueryBuilder` test mock) is test-only and independent but lives in the same `apps/web-platform/test/` directory the other two will edit. Folding it keeps test-harness upgrades in one reviewable commit rather than split across three.

All three are `priority/p3-low`, `type/chore` (#2775, #2777) or `type/feature` (#2776), `code-review`, `deferred-scope-out`, and milestone-bound to "Post-MVP / Later".

## Research Reconciliation — Spec vs. Codebase

Spec enumerations from the three issue bodies were verified against `grep` on the current working tree. One divergence:

| Spec claim | Reality | Plan response |
|---|---|---|
| **#2775 — Files to edit include `apps/web-platform/hooks/use-conversations.ts` (client-side read site)** | Client reader exists and does `.from("users").select("repo_url").eq("id", currentUserId).maybeSingle()` inline (line 118-124). | Apply `normalizeRepoUrl` to the value returned from this inline read AND to the payload field in the `users` Realtime callback (line 292). Both sites confirmed. |
| **#2776 — Files to edit: `apps/web-platform/lib/mcp/conversations-tools.ts`** | MCP tools live at `apps/web-platform/server/conversations-tools.ts` — no `lib/mcp/` directory exists. | Edit `server/conversations-tools.ts`. The existing in-file comment (lines 6-7) already documents these two P3 siblings as deferred; the comment must be removed when the tools are added. |
| **#2776 — tool tests live with schema/tests** | Existing test `apps/web-platform/test/conversations-tools.test.ts:71-78` explicitly asserts the two new tool names are NOT exposed. | Invert that assertion: the test now asserts `conversations_list`, `conversation_archive`, `conversation_unarchive` ARE in the name set. |
| **#2777 — 4 duplicate sites including `ws-deferred-creation.test.ts:13`** | `grep -rln 'function createQueryBuilder'` returns **3** files, not 4. `ws-deferred-creation.test.ts` uses a hand-rolled `chain` object with its own recursive `eq: vi.fn(() => chain)` pattern — a different shape, not the same duplicated helper. | Migrate the 3 confirmed sites (`command-center.test.tsx:97`, `start-fresh-onboarding.test.tsx:18`, `update-status.test.tsx:13`). `ws-deferred-creation.test.ts` is NOT migrated — its shape is a predicate-aware recursive chain serving a different test need (predicate inspection inside `start_session`). Noting this explicitly in the plan so reviewers don't re-flag it. |
| **Migration 029 COMMENT on `conversations.repo_url`** | Existing comment (line 21-26 of `029_conversations_repo_url.sql`) explicitly warns: *"any future normalization of users.repo_url MUST also rewrite this column in the same migration, or previously-connected conversations go dark."* | The backfill migration for #2775 MUST rewrite both `users.repo_url` and `conversations.repo_url` in the same file — honoring the coupling invariant the prior migration author already identified. |

## Open Code-Review Overlap

1 overlap detected:

- **#2244** (`refactor(kb): migrate upload route to syncWorkspace (finish PR #2235 scope)`) touches `apps/web-platform/server/kb-route-helpers.ts` and `apps/web-platform/app/api/kb/upload/route.ts`. Both files currently contain an inline `.replace(/\.git$/, "")` call — the same partial-normalization smell this drain addresses. **Disposition: Acknowledge.** #2244's scope is migrating the upload route to `syncWorkspace`, not centralizing URL normalization. Folding the helpers' inline `.replace(/\.git$/, "")` into #2775's new `normalizeRepoUrl` would expand #2775's blast radius beyond the write-boundary fix it was scoped for. Rationale captured here so when #2244 ships, its author will encounter `normalizeRepoUrl` already extracted and can replace the inline calls in the same PR (one-line swap each). **Side effect:** because #2244 is acknowledged not folded, the READ sites in `kb-route-helpers.ts:117` and `app/api/kb/upload/route.ts:137` continue using inline `.replace(/\.git$/, "")` after this PR merges. This is acceptable: after the backfill migration, every `users.repo_url` row is already normalized at rest, so the inline `.replace` becomes a no-op on new data. The consolidation is cosmetic, not correctness-critical.

## Goals

1. **Close #2775** — normalize `repo_url` at the write boundary for both `users` and `conversations` tables, plus apply the same normalization at all read sites, backed by a backfill migration.
2. **Close #2776** — expose `conversations_list` + `conversation_archive` + `conversation_unarchive` as MCP tools, scoped to the authenticated user's normalized `repo_url` for parity with `use-conversations.ts`.
3. **Close #2777** — extract a shared `buildSupabaseQueryBuilder` helper + a predicate-aware variant, migrate the 3 (confirmed) duplicate sites.
4. **Ship #2778 NO-OP** — do not migrate to a `projects` table. The Re-evaluation Criteria on #2778 require demand signal (first-class project concept appearing in Phase ≥3 roadmap). This PR does not satisfy them.

## Non-Goals

- Migrating conversations scoping to a first-class `projects` table (#2778 — intentionally deferred).
- Folding `kb-route-helpers.ts` + `kb/upload/route.ts` inline `.replace(/\.git$/, "")` into the new helper — handled by #2244's future PR (overlap acknowledged above).
- Adding a second MCP tool for message-level reads (deliberately out of scope per the `conversations_lookup` comment in `server/conversations-tools.ts:50-53` — threads are opaque from the agent's perspective).
- Changing any Realtime channel topology (the cross-tab repo-swap channel added in PR #2766 stays as-is).
- Adjusting the `ws-deferred-creation.test.ts` recursive-chain mock — different shape serving predicate inspection; not a duplication.

## Hypotheses

- **H1 (#2775):** The single pattern that will cover every user-facing repo_url variant is: (a) `trim()`, (b) strip trailing `.git`, (c) strip trailing `/`, (d) lowercase host only (NOT path — GitHub owner/repo are case-sensitive for display but case-insensitive at the API — we preserve display case). This matches the strip-set the codebase already does piecemeal in `kb-route-helpers.ts:117` and `api/repo/setup/route.ts:39`.
- **H2 (#2775):** Applying normalization at the write boundary (`/api/repo/setup`) is sufficient for all new rows. Read-site normalization is defense-in-depth for pre-migration rows that the backfill might miss (disconnected users whose `users.repo_url` is NULL, users who never hit the setup endpoint after an unknown past insertion path). If the backfill fully covers the population, the read-site call becomes a cheap no-op.
- **H3 (#2776):** The three new MCP tools' signatures should mirror `use-conversations.ts`'s options surface (`statusFilter`, `domainFilter`, `archiveFilter`) plus optional `repoUrl` override, plus closure-bound `userId`. Passing `repoUrl` explicitly lets the agent scope a read to a specific connected repo (future-proofs for multi-repo agents without requiring a re-architecture). Defaulting to `getCurrentRepoUrl(userId)` gives single-repo parity with the UI.
- **H4 (#2777):** The three `createQueryBuilder` sites are shape-compatible (all return `{ data, error, count }` + chain methods). A single helper with named args (`{ data?, error?, singleRow?, count? }`) covers every call. A predicate-aware variant (captures `.eq(col, val)` calls for assertions) is co-located for future tests that need it but is NOT forced on the migration targets — each site opts in.

## Files to Create

- `apps/web-platform/lib/repo-url.ts` — `normalizeRepoUrl(raw: string): string` helper plus an exported `NormalizedRepoUrl` nominal type for compile-time safety at write sites. **Why lib/ (not server/):** must be importable from both server (`app/api/*`, `server/*`) AND client (`hooks/*`). `lib/` is the existing seam per sibling modules (`lib/routes.ts`, `lib/safe-return-to.ts`).
- `apps/web-platform/supabase/migrations/031_normalize_repo_url.sql` — idempotent `UPDATE` that applies `LOWER(regexp_replace(...))` (or Postgres equivalent of the normalize chain) to both `users.repo_url` and `conversations.repo_url`. Single file — per migration 029's COMMENT coupling invariant, both columns rewrite together. Migration 030 is already taken (`030_processed_stripe_events.sql`); next free slot is 031.
- `apps/web-platform/test/mocks/supabase-query-builder.ts` — shared `buildSupabaseQueryBuilder({ data?, error?, singleRow?, count? })` plus `buildPredicateAwareQueryBuilder(...)` variant.
- `apps/web-platform/test/repo-url.test.ts` — unit tests for `normalizeRepoUrl` (round-trip, idempotence, hostname casing, trailing `.git`, trailing `/`, lowercase preservation of path, non-GitHub URL pass-through, empty/null/undefined guards).
- `apps/web-platform/test/conversations-list-archive-tools.test.ts` — unit tests for the three new MCP tools (filter matrix, repo_url scoping, closure user-binding, archive state transitions).

## Files to Edit

### #2775 — normalization (write + read boundary + backfill)

- `apps/web-platform/app/api/repo/setup/route.ts` — replace the inline partial-normalize (`body.repoUrl.trim().replace(/\/+$/, "")` at line 39) with `normalizeRepoUrl(body.repoUrl)`. Apply BEFORE the format validator so the validator sees the canonical form.
- `apps/web-platform/server/current-repo-url.ts` — apply `normalizeRepoUrl` to the returned value. The helper is the choke point for server-side reads (MCP tools, WS handler, agent-runner, lookup helper) — a single call here covers every server consumer.
- `apps/web-platform/hooks/use-conversations.ts` — apply `normalizeRepoUrl` to:
  1. `setRepoUrl(currentRepoUrl)` at line 125 (initial fetch).
  2. `updated?.repo_url` in the cross-tab users-channel callback at line 292 (Realtime payload).
  3. The `.eq("repo_url", currentRepoUrl)` predicate at line 138 (the predicate value is already-normalized via (1), so this is zero-work — explicit note in a code comment to prevent a future author from double-normalizing).
- **`apps/web-platform/server/ws-handler.ts`** — this was the "silent backdoor" class from PR #2766's post-merge learning. Three sites write or filter by `repo_url`:
  1. `createConversation` INSERT (line 396): `repo_url: repoUrl` — `repoUrl` comes from `getCurrentRepoUrl` which is already normalized, so no change needed. Add a code comment anchoring the contract: `// repoUrl is already normalized — getCurrentRepoUrl applies normalizeRepoUrl at the read boundary (see lib/repo-url.ts)`.
  2. 23505-fallback lookup (line 415): `.eq("repo_url", repoUrl)` — same, no change.
  3. `start_session` inline resumeByContextPath (line 528): `.eq("repo_url", currentRepoUrl)` — same, no change.
  4. `resume_session` cross-check (line 661-671): selects + compares `conv.repo_url` — the comparison is between two already-normalized strings (post-backfill). Add a comment.
- **`apps/web-platform/server/agent-runner.ts`** — line 419 selects `repo_url`; line 589 reads it as `string | null`. Per "audit every query, not just the helper" learning (2026-04-22), this is a sibling read. Route it through `getCurrentRepoUrl` instead of reading `repo_url` inline (collapses a duplicate read site and inherits normalization for free). **Justify in commit:** this is the same collapse pattern the review-response commit did for PR #2766's 4 silent-fallback sites.
- `apps/web-platform/supabase/migrations/031_normalize_repo_url.sql` — backfill `users.repo_url` AND `conversations.repo_url` in the same file. Concrete SQL shape is prescribed in Phase 2. Must be idempotent (a rerun is a no-op).

**Sibling-query audit (deepened per 2026-04-22 "audit every query" learning)** — enumerating every `repo_url` site in production code, with explicit disposition:

| Site | File:Line | Op | Disposition |
|---|---|---|---|
| Auth read (source of truth) | `server/current-repo-url.ts:26` | SELECT | Apply `normalizeRepoUrl` on return (chosen choke point) |
| Setup write | `app/api/repo/setup/route.ts:67` | UPDATE | Apply `normalizeRepoUrl` on input (pre-validator) |
| Sync-conversation insert | `app/api/repo/setup/route.ts:157` | INSERT | `repoUrl` variable is already normalized (local rename for clarity) |
| Disconnect write | `app/api/repo/disconnect/route.ts:74` | UPDATE to NULL | No change — setting to NULL, not a URL |
| Status read | `app/api/repo/status/route.ts:24` | SELECT | No change — reads value as-is for display; post-backfill, already canonical |
| Lookup filter | `server/lookup-conversation-for-path.ts:54` | SELECT filter | No change — `repoUrl` arg is already normalized (callers use `getCurrentRepoUrl`) |
| WS createConversation insert | `server/ws-handler.ts:396` | INSERT | No change — `repoUrl` already normalized; add anchor comment |
| WS 23505 fallback | `server/ws-handler.ts:415` | SELECT filter | No change — same |
| WS start_session resume | `server/ws-handler.ts:528` | SELECT filter | No change — same |
| WS resume_session cross-check | `server/ws-handler.ts:661-671` | SELECT + compare | No change — both sides already normalized; add anchor comment |
| Agent-runner read | `server/agent-runner.ts:419,589` | SELECT | **Collapse** into `getCurrentRepoUrl(userId)` — removes a sibling backdoor |
| KB-route-helpers read | `server/kb-route-helpers.ts:75,83,117,130` | SELECT + parse | **Acknowledge** — #2244's future PR consolidates this; inline `.replace(/\.git$/, "")` becomes a no-op post-backfill |
| KB-upload parse | `app/api/kb/upload/route.ts:58,137` | Read + parse | **Acknowledge** — same as above |
| Client hook read | `hooks/use-conversations.ts:120` | SELECT | Apply `normalizeRepoUrl` on return |
| Client hook Realtime | `hooks/use-conversations.ts:292` | Realtime payload | Apply `normalizeRepoUrl` on payload |
| Client hook filter | `hooks/use-conversations.ts:138,245` | Supabase filter + compare | No change — value is already normalized via the two apply sites above |

**Total:** 16 production sites. **Plan prescribes changes at:** 4 (setup write, current-repo-url, use-conversations initial + Realtime, agent-runner collapse). **Explicitly acknowledged no-change:** 12. This audit closes the class of sibling-backdoor bug PR #2766's review-response commit had to patch retroactively.

### #2776 — MCP tool parity

- `apps/web-platform/server/conversations-tools.ts` — remove the comment at lines 6-7 that documents the two siblings as deferred. Add three `tool(...)` registrations inside `buildConversationsTools`:
  1. `conversations_list({ statusFilter?, domainLeader?, archived? })` — mirrors `UseConversationsOptions`. `domainLeader?: DomainLeaderId | "general" | null`, `archived?: boolean` (maps to `archiveFilter: "archived" | "active"`). Scopes by `getCurrentRepoUrl(userId)` internally — no `repoUrl` arg exposed to the agent. (**Decision note:** the initial prompt asked for an optional `repoUrl?` arg for cross-repo listing. Per H3, this future-proofs multi-repo agents but it also defeats the repo-scope invariant the MCP contract promises. Defer to the repo-is-connected-is-scope contract; revisit if/when #2778 adds a `projects` table with an explicit project-id arg.)
  2. `conversation_archive({ conversationId })` — `UPDATE conversations SET archived_at = NOW() WHERE id = ? AND user_id = ? AND repo_url = ?`. The three-column WHERE enforces repo_url scoping as a backstop to RLS.
  3. `conversation_unarchive({ conversationId })` — `UPDATE conversations SET archived_at = NULL WHERE id = ? AND user_id = ? AND repo_url = ?`.
- `apps/web-platform/test/conversations-tools.test.ts` — invert the negative assertion at lines 71-78. The test must now assert the three new tool names ARE in the name set, and add positive test cases for each tool's happy/error/repo-scope paths. Keep the closure-binding test (different builders with different userIds) and extend it to the new tools.

### #2777 — test mock consolidation

- `apps/web-platform/test/mocks/supabase-query-builder.ts` — new file exporting:
  - `buildSupabaseQueryBuilder({ data?, error?, singleRow?, count? })` — the union shape covering the existing three sites. Default `data = []`, `error = null`, `singleRow = null`, `count = data.length`. Supports `.select().eq().in().is().not().order().limit().single()/maybeSingle().update()` returning `thenable`.
  - `buildPredicateAwareQueryBuilder({ ... })` — **YAGNI-deferred (deepen-pass finding):** the predicate-aware variant was prescribed "for future tests" but no test in this PR consumes it. Per code-simplicity-reviewer lens: don't ship a helper without a consumer. The existing `lookup-conversation-for-path-repo-scope.test.ts` already carries its own inline predicate-aware mock; leave it in place. If the MCP tool tests in Phase 3 need predicate assertions (they might — see Phase 3 test design below), add the variant then with one concrete consumer. Otherwise don't add it. **Keep the door open:** `buildSupabaseQueryBuilder` should be structured so a future `buildPredicateAwareQueryBuilder` is a small extension, not a rewrite.
- `apps/web-platform/test/command-center.test.tsx` — delete inline `createQueryBuilder` (lines 97-114). Import `buildSupabaseQueryBuilder` from `./mocks/supabase-query-builder`. Update call sites (all use `createQueryBuilder(data)` or `createQueryBuilder(data, singleRow)`).
- `apps/web-platform/test/start-fresh-onboarding.test.tsx` — same pattern; delete inline (lines 18-39), import helper, update call sites.
- `apps/web-platform/test/update-status.test.tsx` — same pattern; delete inline (lines 13-37), import helper, update call sites. Note: this file's inline helper uses a different `error` signature — parametrize `buildSupabaseQueryBuilder`'s `error` arg to cover it.

## Implementation Phases

### Phase 1 — Normalization foundation (#2775)

1. **Write failing tests first** (`cq-write-failing-tests-before`):
   - `test/repo-url.test.ts` — covers: `https://github.com/Owner/Repo.git/` → `https://github.com/Owner/Repo`; idempotence; lowercase-host only (path preserved); empty string → empty string; non-GitHub URL pass-through; `.GIT` uppercase extension (strip anyway); `/` only vs trailing multi-`/`.
   - Extend `test/conversations-tools.test.ts` to assert `getCurrentRepoUrl` returns the normalized form (new RED test).
2. Create `lib/repo-url.ts` with `normalizeRepoUrl`.
3. Apply at write site: `/api/repo/setup/route.ts` — replace inline partial-normalize.
4. Apply at server read site: `server/current-repo-url.ts` — wrap return value.
5. Apply at client read sites: `hooks/use-conversations.ts` — two call sites + anchor comment.
6. Collapse `agent-runner.ts` inline read into `getCurrentRepoUrl`.
7. Run `cd apps/web-platform && ./node_modules/.bin/vitest run` — all green.
8. `tsc --noEmit` clean.

### Phase 2 — Backfill migration (#2775)

1. Write `supabase/migrations/031_normalize_repo_url.sql`.
2. **Concrete SQL port** — the WHERE clause gives idempotence; the expression MUST produce the same output as `lib/repo-url.ts::normalizeRepoUrl` for the full fixture set in `test/repo-url.test.ts`. Extract the normalize expression to a SQL-local CTE to avoid repeating it across two UPDATEs:

   ```sql
   -- 031_normalize_repo_url.sql
   -- Backfill users.repo_url AND conversations.repo_url to the canonical form
   -- produced by lib/repo-url.ts::normalizeRepoUrl. Coupling invariant documented
   -- in 029_conversations_repo_url.sql COMMENT -- any normalization of
   -- users.repo_url MUST also rewrite conversations.repo_url in the same file.
   --
   -- Canonical form (must match lib/repo-url.ts byte-for-byte):
   --   1. trim() leading/trailing whitespace
   --   2. Lowercase scheme + host only (preserve owner/repo path case)
   --   3. Strip trailing .git (case-insensitive, anchored)
   --   4. Strip trailing / (one or more)
   --
   -- Idempotent: the WHERE predicate `repo_url <> <normalized-expr>` ensures
   -- already-canonical rows are untouched. Second run is `UPDATE 0`.
   --
   -- CONCURRENTLY is NOT used. Supabase's migration runner wraps each file in
   -- a transaction (SQLSTATE 25001). UPDATE is transaction-safe. Pattern matches
   -- migrations 025, 027, 029 — see
   -- knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md.
   --
   -- No NOT NULL transition. Column stays nullable (consistent with 029).
   -- Disconnected users (repo_url IS NULL) stay NULL — the backfill is
   -- best-effort, not total. See
   -- knowledge-base/project/learnings/2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md.

   UPDATE public.users u
      SET repo_url = regexp_replace(
        regexp_replace(
          LOWER(substring(trim(u.repo_url) from '^([^/]*//[^/]+)'))
          || COALESCE(substring(trim(u.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
          '\.git$', '', 'i'),
        '/+$', '', 'g')
    WHERE u.repo_url IS NOT NULL
      AND u.repo_url <> regexp_replace(
        regexp_replace(
          LOWER(substring(trim(u.repo_url) from '^([^/]*//[^/]+)'))
          || COALESCE(substring(trim(u.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
          '\.git$', '', 'i'),
        '/+$', '', 'g')
      AND substring(trim(u.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL;
      -- Last guard: skip rows whose repo_url doesn't parse as scheme://host.
      -- Those are pre-existing garbage; hands-off is safer than rewriting.

   UPDATE public.conversations c
      SET repo_url = regexp_replace(
        regexp_replace(
          LOWER(substring(trim(c.repo_url) from '^([^/]*//[^/]+)'))
          || COALESCE(substring(trim(c.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
          '\.git$', '', 'i'),
        '/+$', '', 'g')
    WHERE c.repo_url IS NOT NULL
      AND c.repo_url <> regexp_replace(
        regexp_replace(
          LOWER(substring(trim(c.repo_url) from '^([^/]*//[^/]+)'))
          || COALESCE(substring(trim(c.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
          '\.git$', '', 'i'),
        '/+$', '', 'g')
      AND substring(trim(c.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL;
   ```

   **Implementation note:** the implementer MAY extract the repeated normalize expression into a `WITH normalized_users AS (...)` CTE + `UPDATE ... FROM normalized_users` to DRY the SQL, if the CTE form reads cleaner. The constraint that matters is output equality with `lib/repo-url.ts`, not the SQL shape.

3. **Pre-apply dry-run probe** — before applying to prod, run this SELECT on prod via REST API / SQL editor to preview the affected row count:

   ```sql
   SELECT
     count(*) FILTER (WHERE repo_url IS NOT NULL)                  AS total_rows,
     count(*) FILTER (WHERE repo_url ~ '\.git$')                   AS trailing_git,
     count(*) FILTER (WHERE repo_url ~ '\.GIT$')                   AS trailing_git_upper,
     count(*) FILTER (WHERE repo_url ~ '/$')                       AS trailing_slash,
     count(*) FILTER (WHERE repo_url ~ '^https://[^/]*[A-Z]')      AS mixed_case_host
   FROM public.users;
   ```

   Expected: one or more categories > 0 implies the migration will touch rows. If all are 0, the migration is a no-op (still safe to apply — records intent).

4. **CONCURRENTLY forbidden** — per linked learning.
5. **No NOT NULL transition.** Column stays nullable.
6. Post-merge verification per `wg-when-a-pr-includes-database-migrations` runbook.
7. Acceptance Criteria split into `### Pre-merge (PR)` and `### Post-merge (operator)`.

### Phase 3 — MCP tool parity (#2776)

1. **Write failing tests first** (`cq-write-failing-tests-before`):
   - Invert `test/conversations-tools.test.ts:71-78` (assertions now POSITIVE for the three new tool names).
   - Add `test/conversations-list-archive-tools.test.ts` with: filter matrix (status × domain × archive state), closure-bound userId scoping, repo_url scoping via `getCurrentRepoUrl`, error-path (Supabase returns error), disconnected user short-circuit (`getCurrentRepoUrl` returns null → tool returns typed "disconnected" error).
2. **Zod schemas (reuse existing canonical types; no redeclaration)** — the tool schemas MUST reuse `ConversationStatus` from `@/lib/types` and `DomainLeaderId` from `@/server/domain-leaders`, NOT redeclare them inline. Drift would silently diverge MCP tool validation from UI validation.

   ```ts
   // server/conversations-tools.ts (sketch — authoritative shapes, not final code)

   import { z } from "zod/v4";
   import { DOMAIN_LEADERS } from "@/server/domain-leaders";
   import { STATUS_LABELS } from "@/lib/types"; // keys == ConversationStatus values

   // Z enum rebuilt from the same source of truth the UI uses.
   // Using Object.keys(STATUS_LABELS) keeps this coupled to the canonical type.
   const statusValues = Object.keys(STATUS_LABELS) as Array<keyof typeof STATUS_LABELS>;
   const domainLeaderIds = DOMAIN_LEADERS.map((l) => l.id);

   const conversationsListSchema = {
     statusFilter: z.enum(statusValues as [string, ...string[]]).optional(),
     domainLeader: z.union([
       z.enum(domainLeaderIds as [string, ...string[]]),
       z.literal("general"),
     ]).nullable().optional(),
     archived: z.boolean().optional().default(false),
     limit: z.number().int().min(1).max(50).optional().default(50),
   };

   const conversationIdSchema = { conversationId: z.string().uuid() };
   ```

3. **Tool description strings (agent-facing UX)** — each tool's description MUST follow the existing `conversations_lookup` pattern (lines 41-53): describe inputs, outputs, repo-scope semantics, and the disconnected-user short-circuit. Agent-native review gap otherwise.
4. Implement the three tools in `server/conversations-tools.ts`:
   - `conversations_list` — `SELECT id, status, domain_leader, last_active, created_at, archived_at FROM conversations WHERE user_id = ? AND repo_url = ? AND (archived OR archived_at IS NULL)` + optional filters + ORDER BY `last_active` DESC + LIMIT 50.
   - `conversation_archive` — `UPDATE conversations SET archived_at = NOW() WHERE id = ? AND user_id = ? AND repo_url = ? RETURNING id, archived_at`. Returns `isError: true` if 0 rows matched (either conversation doesn't exist, is owned by another user, or is in a different repo — single "not found" error without disclosing which).
   - `conversation_unarchive` — `UPDATE ... SET archived_at = NULL WHERE id = ? AND user_id = ? AND repo_url = ? RETURNING id, archived_at`. Same not-found semantics.
5. **Disconnected-user response** — `{ content: [{ type: "text", text: JSON.stringify({ error: "disconnected", code: "no_repo_connected" }) }], isError: true }`. Exact shape documented in the tool description so agents can parse and retry after reconnection.
6. Update the file-level comment (lines 6-7) to reflect the new reality.
7. `vitest run` — all green. `tsc --noEmit` clean.

### Phase 4 — Test mock consolidation (#2777)

1. Create `test/mocks/supabase-query-builder.ts` — start with the union shape from the three existing helpers (most-general wins).
2. Add a self-test for the helper itself (`test/mocks/supabase-query-builder.test.ts`) — ensures the helper's public surface doesn't regress.
3. Migrate `command-center.test.tsx` — delete inline helper, import shared, update call sites. Run the file's test suite; expect green.
4. Migrate `start-fresh-onboarding.test.tsx` — same pattern.
5. Migrate `update-status.test.tsx` — same pattern; verify the `error` arg path works.
6. Do NOT touch `ws-deferred-creation.test.ts` (predicate-aware chain serves different purpose).
7. Full `vitest run` — all green.

### Phase 5 — Ship

1. `skill: soleur:compound`
2. `skill: soleur:ship`
3. PR body MUST include (GitHub keyword prefix — mid-line use is safe per `cq-prose-issue-ref-line-start`):

   ```
   Closes #2775
   Closes #2776
   Closes #2777
   ```

   Each on its own line — these are GitHub keyword prefixes, not line-leading `#NNNN` prose references.
4. Reference PR #2486 as the drain pattern.
5. Note that #2778 is intentionally NOT closed.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `lib/repo-url.ts` exports `normalizeRepoUrl(raw: string): string`. Handles: `.git` strip (case-insensitive), trailing `/` strip, lowercase host-only, `trim()`. Idempotent.
- [ ] Unit tests for `normalizeRepoUrl` cover the full matrix (≥8 cases — listed in Phase 1).
- [ ] `/api/repo/setup/route.ts` applies normalization before URL-format validation.
- [ ] `getCurrentRepoUrl` returns the normalized value.
- [ ] `use-conversations.ts` normalizes both initial fetch and Realtime `users` payload.
- [ ] `agent-runner.ts` reads `repo_url` via `getCurrentRepoUrl` (not inline SELECT).
- [ ] `server/conversations-tools.ts` exposes `conversations_list`, `conversation_archive`, `conversation_unarchive` — each scoped to the authenticated user's current normalized `repo_url`.
- [ ] `conversations_list` default `limit` matches `use-conversations.ts` line 158 (50). Capped at 50 via Zod schema.
- [ ] `conversations_list` schema reuses `ConversationStatus` (from `@/lib/types`) and `DomainLeaderId` (from `@/server/domain-leaders`) — no inline redeclaration.
- [ ] `conversation_archive` / `conversation_unarchive` UPDATE WHERE clause includes **all three** of `id`, `user_id`, `repo_url` (security backstop — see R3).
- [ ] `conversation_archive` / `conversation_unarchive` return a single "not found" error (no existence-probe leakage) when 0 rows matched.
- [ ] `test/conversations-tools.test.ts` asserts all three new tool names are in the builder's output (inverted from the pre-existing negative assertion).
- [ ] `test/mocks/supabase-query-builder.ts` is the sole helper definition; `rg 'function createQueryBuilder' apps/web-platform/test/` returns 0 hits.
- [ ] All 3 migrated test files import from `./mocks/supabase-query-builder`.
- [ ] `ws-deferred-creation.test.ts` retains its own recursive-chain mock (explicitly not migrated — rationale in the commit).
- [ ] `buildPredicateAwareQueryBuilder` is **not** shipped unless a test in this PR consumes it (YAGNI gate).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` — all green.
- [ ] `cd apps/web-platform && npx tsc --noEmit` — clean.
- [ ] Migration 031 file written, idempotent, no `CONCURRENTLY`, no NOT NULL transition.
- [ ] Migration 031 SQL produces byte-for-byte identical output to `lib/repo-url.ts::normalizeRepoUrl` for every fixture in `test/repo-url.test.ts` (implementer must run a parity probe during Phase 2 — documented in commit).
- [ ] Pre-apply dry-run probe (Phase 2 step 3) run against prod with row counts captured in PR body.
- [ ] PR body contains the three `Closes #NNNN` lines.

### Post-merge (operator)

- [ ] Migration 031 applied to prod Supabase per `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`.
- [ ] **Sentinel query 1 (users):** `SELECT count(*) FROM users WHERE repo_url IS NOT NULL AND (repo_url ~ '\.git$' OR repo_url ~ '\.GIT$' OR repo_url ~ '/$' OR repo_url ~ '^https://[^/]*[A-Z]')` returns **0**.
- [ ] **Sentinel query 2 (conversations):** same shape against `conversations` returns **0**.
- [ ] **Idempotence probe:** re-running the migration produces `UPDATE 0` on both tables (operator runs the UPDATE section of 031 via SQL editor as a check, records the result).
- [ ] **Agent-native parity probe (nice-to-have):** on a throwaway dev account, invoke `conversations_list` and `conversation_archive` via an MCP client and verify the archive state round-trip.
- [ ] Release/deploy workflows succeeded (`wg-after-a-pr-merges-to-main-verify-all`).
- [ ] Verify #2775, #2776, #2777 are CLOSED (`gh issue view <N> --json state`) AND #2778 is still OPEN (regression gate).

## Test Scenarios

1. **normalizeRepoUrl idempotence** — `normalize(normalize(x)) === normalize(x)` for every input in the fixture set.
2. **normalizeRepoUrl preserves path case** — `https://github.com/Anthropic-Labs/Foo.git` → `https://github.com/Anthropic-Labs/Foo` (NOT lowercased to `anthropic-labs/foo`).
3. **normalizeRepoUrl lowercases host** — `https://GitHub.com/foo/bar` → `https://github.com/foo/bar`.
4. **normalizeRepoUrl is suffix-anchored** — `https://github.com/foo/bar.git.bak` → `https://github.com/foo/bar.git.bak` (mid-string `.git` NOT stripped).
5. **normalizeRepoUrl case-insensitive `.git` strip** — `https://github.com/foo/bar.GIT` → `https://github.com/foo/bar`.
6. **normalizeRepoUrl handles multi-trailing-slash** — `https://github.com/foo/bar///` → `https://github.com/foo/bar`.
7. **normalizeRepoUrl pass-through on non-URL** — `''` → `''`; `null`/`undefined` → `''` (safe empty).
8. **Setup route pre-validation normalization** — `https://github.com/foo/bar.git/` POSTed to `/api/repo/setup` → DB row has `repo_url = 'https://github.com/foo/bar'`.
9. **`conversations_list` matrix (8 corners)** — (statusFilter=pending, archived=false) returns only active-pending rows; (archived=true) returns only archived rows; `domainLeader="general"` returns rows with `domain_leader IS NULL`; `domainLeader=null` and no `domainLeader` key both accept all domains; disconnected user (getCurrentRepoUrl=null) returns typed "disconnected" error with `isError: true`.
10. **`conversations_list` honors default `limit=50`** — when the DB has 100 matching rows, the tool returns 50.
11. **`conversation_archive` round-trip** — archive then unarchive returns row to active state. Assertions: `archived_at` `.toBe(expect.stringMatching(ISO_8601))` post-archive; `.toBe(null)` post-unarchive.
12. **`conversation_archive` security — cross-repo cached id fails closed** — conversation belongs to repo A; user is connected to repo B; `conversation_archive({ conversationId })` returns "not found" error (not a success) because the three-column WHERE rejects the UPDATE. Asserts 0 rows updated.
13. **`conversation_archive` security — cross-user id fails closed** — same shape but with another user's conversation id. Same "not found" response.
14. **MCP tool closure binding** — `buildConversationsTools({ userId: "u1" })` and `buildConversationsTools({ userId: "u2" })` return tools that invoke Supabase with their respective userIds, not each other's.
15. **Migration 031 idempotence** — simulated re-run via fixture: apply-then-apply-again leaves `count(*) FILTER (WHERE repo_url <> normalize(repo_url))` at 0 on the second run.
16. **Pre-migration data normalized at rest** — sentinel query returns zero rows for every category (trailing `.git`, trailing `.GIT`, trailing `/`, mixed-case host).

## Risks

- **R1 (low) — Backfill migration changes data under active sessions.** Users whose `users.repo_url` currently has a trailing `/` or `.git` will have their row updated. The subsequent `use-conversations` query filters by the NEW normalized form; Realtime will emit the UPDATE and the user's active browser tabs will refetch via the existing cross-tab channel from PR #2766. Mitigation: the client also normalizes on read (belt-and-suspenders) so any race between the migration and the Realtime propagation lands on the same canonical form.
- **R2 (low) — Non-GitHub URL in prod.** The format validator in `/api/repo/setup/route.ts:40` rejects non-GitHub URLs, so no non-GitHub row should exist at rest. But pre-validation code paths or direct-DB inserts could have bypassed. `normalizeRepoUrl` treats non-GitHub URLs as pass-through (trim + strip trailing `/` + strip trailing `.git`). Safe.
- **R3 (medium) — New MCP tools open a larger agent action surface.** `conversation_archive` is a write. Threat model: an agent-driven archive loop could mass-archive a user's active conversations. Mitigation: repo_url scoping (implicit via `getCurrentRepoUrl`) + user_id scoping (closure-bound) + the UPDATE WHERE clause enforces both. RLS on the `conversations` table provides the final backstop. Same write profile as the existing UI archive button.
- **R4 (low) — Predicate-aware mock variant goes unused.** Deepen-pass YAGNI call: don't ship the variant without a consumer. If Phase 3's MCP archive tests need predicate-aware mocks (to prove the three-column WHERE fires), add the variant with that test as the first consumer. Otherwise don't ship it. `lookup-conversation-for-path-repo-scope.test.ts` keeps its existing inline predicate-aware mock — it's proven load-bearing and fine where it lives.
- **R5 (low) — `ws-deferred-creation.test.ts` not migrated invites reviewer confusion.** Reviewers scanning the PR will see 3 of 4 files migrated and wonder why. Mitigation: explicit code comment in `ws-deferred-creation.test.ts` near the inline mock noting "Not migrated to `buildSupabaseQueryBuilder` — this mock captures `.eq()` predicates recursively for `start_session` predicate inspection; the shared helper serves non-predicate-aware cases. See plan 2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md Non-Goals."
- **R6 (medium) — SQL-JS normalize parity drift.** Two independent implementations of the same normalization (TypeScript `normalizeRepoUrl` + Postgres regex chain) will drift if one evolves without the other. Mitigation: (a) implementer-side parity probe during Phase 2 — construct a table of fixtures from `test/repo-url.test.ts`, run each through the Postgres expression via `psql -c "SELECT <expr>"`, assert output equality; (b) the coupling COMMENT in migration 029 is echoed in migration 031's header (any future normalize change touches both). A future hardening would extract the normalize chain into a SQL function stored in a migration, so the TS and SQL versions reference a shared DB-level source of truth — out of scope for this PR.
- **R7 (low) — Migration row-level lock during UPDATE.** The migration's UPDATE holds row-level locks for the duration of the transaction. Concurrent user writes (`UPDATE users SET repo_url = ...` triggered by `/api/repo/setup` or `/api/repo/disconnect`) block until the migration commits. At current scale (<10K users) this is <1s on a reasonably provisioned DB. Mitigation: apply during a low-traffic window per the standard Supabase migration runbook.
- **R8 (low) — MCP tool description tokens inflate agent prompt.** Adding three tool descriptions to the system prompt costs tokens per agent invocation. `conversations_lookup` is ~250 tokens; three new tools at similar size add ~750. Acceptable for parity but worth noting in the tool-catalog budget discussion (not a gating concern). Mitigation: compact the descriptions during implementation — they don't need to repeat the repo-scope invariant that `conversations_lookup` already explains.

## Alternative Approaches Considered

| Alternative | Tradeoff | Decision |
|---|---|---|
| **Ship as 3 separate PRs** | Smaller, easier-to-review units; longer total merge time; forces arbitrary merge ordering between #2775 and #2776 since they share files. | Rejected. Drain pattern from PR #2486 proves a focused 3-closure PR works. Shared files make ordering a hazard, not a feature. |
| **Fold #2778 (projects table) into this PR** | Eliminates the `repo_url` column entirely; makes #2775 irrelevant. | Rejected. #2778's own Re-evaluation Criteria require demand signal (first-class project concept in roadmap Phase ≥3). Not triggered. |
| **Fold #2244 (kb syncWorkspace migration)** | Would consolidate the inline `.replace(/\.git$/, "")` sites alongside `normalizeRepoUrl` extraction. | Rejected. #2244 is a larger refactor; folding it triples the PR scope. Acknowledged in Open Code-Review Overlap. |
| **Expose MCP tools with `repoUrl` parameter (cross-repo listing)** | Future-proofs multi-repo agents. | Rejected. Breaks the repo-scope invariant the rest of the codebase promises. Revisit after #2778 lands (if ever). |
| **Keep `conversations_unarchive` out of scope** | Smaller surface. | Rejected. `useConversations` UI exposes both archive and unarchive; MCP parity means both. |
| **Move `normalizeRepoUrl` to `server/`** | Colocate with other server helpers. | Rejected. Client hook needs it too. `lib/` is the existing client+server seam. |

## Open Questions

- **Q1:** Should `normalizeRepoUrl` additionally lowercase the owner/repo path? GitHub treats `/Foo/Bar` and `/foo/bar` as the same repo at the API layer (case-insensitive). **Decision:** No. Lowercasing the path would change the display form that users typed in — the Command Center would render `foo/bar` even if the user pasted `Foo/Bar`. Host case is an invisible, safe normalization; path case is a visible, opinionated one. Preserve it.
- **Q2:** Should the migration also `UPDATE` in small batches for large tables? **Decision:** No. Current row count is small (< 10K users, < 100K conversations based on dev-config sampling). If we breach 1M rows we ship a second migration via direct psql per migration 029's comment.

## Domain Review

**Domains relevant:** engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline — single-domain cleanup, no product/UX surface change, no user-visible copy, no new external service).

**Assessment:**

- Pure drain of code-review backlog within `apps/web-platform`. No new user-facing pages, flows, or copy.
- Adds one migration — routine DDL, already follows the 029 coupling pattern documented inline.
- Adds one agent-facing MCP tool cluster — surface change is visible to MCP clients only; documented in the tool descriptions.
- Removes 3 duplicated test helpers.
- No CPO/CMO/CLO/CFO/COO/CRO/CXO signal. Skipping domain leader subagents per `pdr-do-not-route-on-trivial-messages-yes` — the domain signal IS the current task's topic (engineering drain).

No cross-domain implications detected.

## SpecFlow

- **Filter matrix completeness:** `conversations_list`'s three filter fields (`statusFilter`, `domainLeader`, `archived`) × their cardinalities (status: pending/active/failed/paused, leader: 6 domains + "general" + null, archived: boolean) = 64 combinations. Test the 8 "corner" combinations; rely on the implementation's straight-line Supabase query compilation for the rest.
- **Edge: disconnected user.** All three MCP tools must short-circuit cleanly when `getCurrentRepoUrl` returns null. Test the contract: tool returns typed error `{ error: "disconnected", code: "no_repo_connected" }` with `isError: true`. NOT a silent empty-list (would mislead the agent).
- **Edge: concurrent archive + Realtime.** The cross-tab users-channel + conversations-channel already emit when archive-state changes. Adding the MCP `conversation_archive` write creates a third emission path. Verified: all three write sites emit the same UPDATE shape; the Realtime callback's archive-filter check is write-source-agnostic.
- **Edge: migration vs. ongoing writes.** The migration runs in a transaction. New writes during the migration are serialized against it by PG's MVCC — either they see the pre-migration form (then the migration's WHERE clause picks them up) or they see the post-migration form (then the migration is a no-op for their row). No data-loss race.

## Research Insights

- **From `knowledge-base/project/learnings/2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` (today's date):** when scoping by a new column, audit every query — not just the helper. This plan applies the same discipline to normalization: `normalizeRepoUrl` is prescribed at every read site (including `agent-runner.ts`, which the learning directly called out as a sibling-query backdoor). The `Files to edit` list enumerates every read site, not only the helper.
- **From `knowledge-base/project/learnings/2026-04-17-kb-route-helper-extraction-cluster-drain.md`:** the precedent drain (#2486) collapsed 3 code-review scope-outs into one kb-domain PR. Same pattern, different domain, similar review surface.
- **From migration 029's `COMMENT ON COLUMN conversations.repo_url`:** coupling invariant — "any future normalization of users.repo_url MUST also rewrite this column in the same migration, or previously-connected conversations go dark." Migration 031 honors this explicitly.
- **From AGENTS.md rule `cq-silent-fallback-must-mirror-to-sentry`:** `getCurrentRepoUrl` already mirrors DB errors to Sentry via `reportSilentFallback`. Collapsing `agent-runner.ts` inline read into the helper inherits this for free.
- **From AGENTS.md rule `cq-prose-issue-ref-line-start`:** `Closes #2775` etc. are GitHub keyword prefixes (not line-leading `#` prose), so mid-line-or-leading is both safe. The PR body will place them on their own lines with `Closes` prefix.
- **From AGENTS.md rule `cq-in-worktrees-run-vitest-via-node-node`:** vitest must be invoked via `./node_modules/.bin/vitest run` from `apps/web-platform` (not `npx`) to avoid cross-worktree cache poisoning.
- **From AGENTS.md rule `cq-write-failing-tests-before`:** TDD Gate is enforced for Phase 1, 3 (not Phase 4, which is test-refactor — moving code, not implementing new behavior).
- **From AGENTS.md rule `cq-mutation-assertions-pin-exact-post-state`:** Phase 3 migration test (archive → unarchive round-trip) must `.toBe(null)` or `.toBe('<exact-timestamp>')`, not `.toContain` or a range.

## Rollout

1. Merge PR.
2. Verify release workflow succeeds (`wg-after-a-pr-merges-to-main-verify-all`).
3. Operator applies migration 031 to prod per runbook.
4. Black-box: query `SELECT count(*) FROM users WHERE repo_url ~ '\.git$|/$|[A-Z](?=.*github\.com)'` — expect zero.
5. Close #2775, #2776, #2777 via GitHub auto-close (`Closes #NNNN` in PR body). Verify with `gh issue view <N> --json state`.
6. Leave #2778 open with no status change.

## Notes

- This is a one-shot pipeline invocation. Plan review and deepen-plan follow.
- Per `hr-when-a-plan-specifies-relative-paths-e-g`: every path in this plan is worktree-absolute-relative (starts with `apps/web-platform/`). No `../` references.
- Per `cq-code-comments-symbol-anchors-not-line-numbers`: code comments this plan prescribes use symbol anchors (function names, constant names), not the line numbers the plan itself cites for review convenience. Line numbers here are for plan review only — implementation comments MUST use symbol anchors.
