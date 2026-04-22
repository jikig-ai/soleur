---
title: When Scoping by a New Column, Audit Every Query — Not Just the Helper
date: 2026-04-22
category: integration-issues
tags:
  - multi-tenant-scoping
  - plan-gap
  - code-review
  - websocket-handler
  - supabase
  - repo-scoping
  - test-mock-drift
module: apps/web-platform/server
problem_type: logic_error
component: supabase_query
severity: high
symptoms:
  - "Command Center lists conversations from previously-connected repo after disconnect/reconnect"
  - "KB-path chat resume picks up thread from prior repo when same context_path exists in both"
  - "WS cached conversationId resumes across repo swap"
root_cause: missing_scope_column
synced_to: [plan]
---

# Learning: When Scoping by a New Column, Audit Every Query — Not Just the Helper

## Problem

PR #2766 added `conversations.repo_url` scoping to fix a user-reported bug:
after disconnecting repo `la-chatte` and connecting a new repo `au-chat-chat`,
the Command Center still showed every conversation from `la-chatte`. The plan
correctly identified the data-scoping gap and prescribed:

- Add `repo_url` column to `conversations`.
- Scope `hooks/use-conversations.ts` list query by `repo_url`.
- Accept a `repoUrl` arg in `lookupConversationForPath` + short-circuit on null.
- Thread `repoUrl` through 3 callers of that helper.
- Stamp `repo_url` on 2 INSERT sites.

The work-phase implementation followed the plan verbatim and all 2172 tests
passed. Green CI, clean `tsc`, test file per acceptance criterion.

**Multi-agent review then found two P1 plan gaps the plan author missed and
no test caught:**

1. **`start_session` inline resume-by-context_path lookup was unscoped.** The
   handler at `server/ws-handler.ts:426-435` runs a direct Supabase query
   against `conversations` (user_id + context_path + archived_at) BEFORE
   reaching the `lookupConversationForPath` helper. The plan scoped the
   helper and the 23505 fallback — it missed this third sibling query. A
   user opening `overview/vision.md` in the new repo would silently resume
   the la-chatte thread via this path.

2. **`resume_session` lookup verified only `id` + `user_id`, not `repo_url`.**
   A client holding a cached conversationId from the prior repo (browser
   history, deep link, agent-memory of a prior `conversations_lookup` call,
   mobile client) could resume across a repo swap. The Command Center hid
   these ids, the MCP tool refused to surface them, but this WS path was
   a backdoor.

Both bugs would have shipped to production with green CI if multi-agent
review hadn't caught them.

## Solution

Fixed both paths in a single review-response commit:

1. Extracted `getCurrentRepoUrl(userId)` helper (`server/current-repo-url.ts`)
   that reads `users.repo_url` with `reportSilentFallback` on DB error
   (rule `cq-silent-fallback-must-mirror-to-sentry`).
2. `start_session` reads `currentRepoUrl` once, short-circuits resume when
   disconnected (falls through to deferred creation — which aborts when
   still null), and adds `.eq("repo_url", currentRepoUrl)` to the inline
   lookup.
3. `resume_session` reads `currentRepoUrl`, SELECTs `conv.repo_url`
   alongside `id, status`, and rejects with "Conversation not found" when
   `conv.repo_url !== currentRepoUrl` — indistinguishable response from
   a genuine miss to avoid existence-probe leakage.
4. Collapsed 4 duplicated inline `users.repo_url` reads into the helper.
5. Migration 029: added `COMMENT ON COLUMN` documenting coupling with
   `users.repo_url`; added `archived_at` marker on pre-migration rows
   whose user is currently disconnected so they remain discoverable via
   the Archived filter.
6. Test infra: rewrote `lookup-conversation-for-path-repo-scope.test.ts`
   test 2 with a predicate-aware mock (was tautologically passing — fixed
   return regardless of `.eq("repo_url", ...)`). Added RED test for the
   `createConversation` disconnect-abort path.

## Key Insight

**When a plan prescribes scoping a helper function, grep the codebase for
every other inline query that references the same table + columns before
implementing.** Plan authors think in helpers; codebases have sibling
inline queries. The helper-based scoping checklist is necessary but
insufficient — any query that bypasses the helper (for performance, for
historical reasons, or because the helper didn't exist when it was
written) becomes a silent backdoor.

**Concrete checklist when scoping by a new column:**

- `rg '\.from\("<table>"\)' --type ts` — every site, not just the helper.
- For each hit, ask: does this query need the new scope column? If it
  handles user-identifiable data (including by id), the answer is
  usually yes — an id can be cached across scope changes.
- `rg '\.eq\("id"' --type ts` scoped to the table — id-based lookups are
  the most common backdoor.
- Diff the set of sites against the set the plan prescribes. Every
  unexplained delta needs either a scope addition or a written
  justification.

## Session Errors

- **Added `users.repo_url` reads broke 4 existing test-file mocks** —
  `createQueryBuilder` helpers in `command-center.test.tsx`,
  `update-status.test.tsx`, `start-fresh-onboarding.test.tsx`,
  `ws-deferred-creation.test.ts` lacked `.maybeSingle()` (my new code
  called it on the `users` table). Recovery: added `maybeSingle` + a
  `singleRow` param to each helper. **Prevention:** when adding a new
  fluent-chain call (`.maybeSingle`, `.single`, `.rpc`) to production
  code, `rg 'createQueryBuilder'` and verify each test mock supports
  the new call before committing.

- **`ws-resume-by-context-path.test.ts` broke with 3 failures** when I
  added a 3rd `.eq()` predicate to the `start_session` inline query. The
  existing mock used a fixed-depth chain (`eq().eq().is()`) that silently
  dropped the new predicate. Recovery: rewrote the mock's eq chain as
  recursive (`eq: () => chain`) and mocked `@/server/current-repo-url`
  directly. **Prevention:** when writing Supabase test mocks, use
  recursive `eq: () => chain` + `is: () => chain` instead of fixed-depth
  chains. A test mock that only supports N predicates silently drops
  predicate N+1 when production code adds one.

- **Doubled path segment** — called Read on
  `apps/web-platform/apps/web-platform/server/ws-handler.ts` when I was
  already `cd`'d into `apps/web-platform`. Recovery: corrected the path
  on next attempt. **Prevention:** prefer worktree-absolute paths rooted
  at the worktree directory, not compound-prefixed ones — the Bash tool
  doesn't persist CWD across calls so "current directory" reasoning is
  unreliable.

- **Plan gap: `start_session` inline resumeByContextPath lookup missed
  repo_url scoping.** The plan correctly scoped `lookupConversationForPath`
  and the 23505 fallback but missed this third inline query. Caught by
  architecture + agent-native review. Recovery: added
  `.eq("repo_url", currentRepoUrl)` and null-short-circuit. **Prevention:**
  when a plan prescribes scoping a helper, `rg` the codebase for every
  other inline query on the same table+columns that bypass the helper —
  they need the same scoping change (see "Key Insight" above).

- **Plan gap: `resume_session` lookup was unscoped by repo_url.** Only
  verified `id` + `user_id`, allowing cached-id cross-repo resumption.
  Caught by agent-native review. Recovery: added `repo_url` match check
  with deliberately indistinguishable "not found" response. **Prevention:**
  when adding tenant/scope columns, audit every id-based query — ids can
  be cached across scope swaps and bypass new column filters (see
  `cq-ref-removal-sweep-cleanup-closures` for the general "sweep all
  usages" class).

- **Tautologically-passing test in
  `lookup-conversation-for-path-repo-scope.test.ts` test 2.** Used
  `mockSingleChain({ data: fixedRow })` — mock returned the fixed row
  regardless of `.eq("repo_url", ...)` predicate. Test passed even if
  the helper omitted the new predicate entirely. Caught by test-design
  review. Recovery: rewrote with predicate-aware mock
  (`eq: () => { predicates.push([col, val]); return chain }` + data
  filtered by captured predicate). **Prevention:** when a test claims
  "the filter is applied", the mock MUST inspect `.eq()` predicates.
  A mock that returns the same data regardless of input can only
  verify non-filtering contracts — per AGENTS.md TDD Gate:
  "distinguish gate-absent from gate-present".

## Related Learnings

- [`2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`](2026-04-15-multi-agent-review-catches-bugs-tests-miss.md) — same class: parallel review catches defects invisible to green-CI test suites. This session confirms the pattern for plan-level gaps (not just code-level smells).
- [`2026-04-10-multi-agent-review-catches-info-disclosure.md`](2026-04-10-multi-agent-review-catches-info-disclosure.md) — related agent-native gap class.
- [`2026-04-17-kb-chat-stale-context-on-doc-switch.md`](2026-04-17-kb-chat-stale-context-on-doc-switch.md) — same data-scoping problem at the UI layer (unmount-on-key-change). The current fix lands at the data layer; both are complementary.

## Tags

category: integration-issues
module: apps/web-platform/server
