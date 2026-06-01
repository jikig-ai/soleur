---
title: "An untyped Supabase embedded select can reference a non-existent column and ship green — mocks that discard the select arg never catch it"
date: 2026-06-01
category: integration-issues
module: apps/web-platform/server/workspace-invitations.ts
issue: 4715
prior_pr: 4713
fix_pr: 4738
tags: [supabase, postgrest, 42703, schema-drift, test-mocks, regression-test, invite, multi-user]
---

# Learning: untyped Supabase select referencing a column that only exists on `auth.users` ships green

## Problem

The keyless-invitee membership deadlock (#4715) was "fixed, merged, and deployed" via PR #4713 — yet reproduced in production the next day: an invited user (a keyless invitee, e.g. `invitee@example.com`) stayed stuck in their own empty solo workspace, the owner's invite stayed `Pending`, and there was no in-app path to accept.

PR #4713 added a `PendingInviteBannerRecovery` banner (the in-app accept path for an invitee who abandoned the `/invite` link). The banner self-fetches `GET /api/workspace/pending-invites`, which calls `getPendingInvitesForUser()` in `apps/web-platform/server/workspace-invitations.ts`. That function's embedded select was:

```ts
inviter:users!workspace_invitations_inviter_user_id_fkey(
  email,
  raw_user_meta_data   // ← only exists on auth.users, NOT public.users
)
```

PostgREST/supabase-js resolves the `users` FK target to **`public.users`**, which has no `raw_user_meta_data` column (it exists only on `auth.users`). Both `Promise.all` query branches failed with Postgres **42703** `column users_1.raw_user_meta_data does not exist`, `allRows` came back empty, the function returned `[]`, the API returned `{invites: []}`, and the banner rendered `null` **every time**. The recovery path was dead on arrival.

## Root cause

A read query referenced a column that does not exist on the resolved relation, and **nothing caught it before production**:

1. **The service client is untyped.** `createServiceClient` calls `createClient(...)` with no `Database` generic, so `.select("…raw_user_meta_data…")` is a free string — `tsc` cannot know the column is invalid.
2. **Unit tests mock the client and discard the select argument.** The existing `chainableMock` (`workspace-invitation-identity.test.ts`) sets `.select = vi.fn(() => chain)` — canned data is returned regardless of column names, so the broken column was never exercised.
3. **The opt-in integration harness (`*.integration.test.ts`, `TENANT_INTEGRATION_TEST=1`) existed but never covered this read path** — only the revoke RPC — and it does not run in CI.
4. **The error WAS mirrored to Sentry** (`reportSilentFallback op=get-pending-by-userid/by-email`) but degraded to a graceful empty array; "feature 100% broken" looked identical to "no pending invites," so no alert fired.
5. **No post-merge verification** — #4715's own body notes "#4641's post-merge verification box was never checked"; #4713 repeated it.

## Solution

`apps/web-platform/server/workspace-invitations.ts` (3-line removal): drop `raw_user_meta_data` from the embedded select, remove it from the inviter TS type, and derive `inviter_name` from `inviter?.email ?? "A team member"` (`public.users` exposes `email`, not `full_name`). Confirmed against the live prod DB: re-running the identical query without the column returns the invitee's real pending invite.

Two regression tests added:
- **Unit** (`workspace-invitations-pending-select.test.ts`): captures the actual `.select()` string via an arg-capturing mock (`mockQueryChain` from `test/helpers/mock-supabase.ts`) and asserts it excludes auth.users-only columns and still embeds the inviter email — on BOTH `Promise.all` branches — plus asserts the `.toLowerCase()` normalization. Proven RED on the broken column.
- **Opt-in integration** (`workspace-invitations-pending.integration.test.ts`, `TENANT_INTEGRATION_TEST=1` vs DEV): runs the real query against the real schema; proven to fail (`expected undefined to be defined`) when the column is reintroduced.

## Key Insight

When a Supabase client is **untyped**, an embedded-select column name is just a string the compiler cannot validate; a unit test that **mocks the client and ignores the select argument** validates nothing about column correctness either. The cheapest deterministic CI guard for this class is an **arg-capturing select-string assertion** (does the select reference any column that does not exist on the resolved `public.*` table?). The strongest guard is an **opt-in integration test against the real dev schema** — the harness already existed; it just never covered the read path. The durable structural fix is to **type the client with a generated `Database` schema** so the whole class becomes a `tsc` error.

A green CI on a Supabase data-layer change does NOT mean the query runs against the real schema. Treat any new/changed `.from(X).select(\`…\`)` embed as needing either (a) an arg-capturing select-string test or (b) an integration test against dev.

## Prevention / ranked improvements

| Improvement | Leverage | Status |
|---|---|---|
| Type the Supabase client (`supabase gen types typescript` → `createClient<Database>`) — makes this a tsc error | Highest (structural) | follow-up candidate |
| Run the `*.integration.test.ts` shard in CI against dev/ephemeral Supabase | High | follow-up candidate |
| Sentry alert (threshold=1) on `get-pending-by-*` silent-fallback ops | Medium | follow-up candidate |
| Arg-capturing select-string unit test for Supabase embeds | Medium | DONE this PR |
| `/qa` must exercise the changed user flow end-to-end before ship | High (process) | partial — integration test covers the query layer |

## Session Errors

1. **`gh run list --json databaseName` → `Unknown JSON field`.** Recovery: used the documented field set (`databaseId`, `workflowName`, …). Prevention: when a `gh --json` call errors, it prints the valid field list — read it before re-scripting; do not guess field names.
2. **Bash `UID` reused as a script variable** — `UID` is a readonly shell builtin, so the assignment silently kept `1001` and the query filtered on the wrong id. Recovery: renamed to `INVITEE_UID`. Prevention: never assign shell-reserved names (`UID`, `EUID`, `PWD`, `PPID`, `GROUPS`) in scripts; pick a domain-prefixed name.
3. **Full web-platform vitest reported 3 failed tests (inngest ×2, pdf-text-extract)** — all ~16s **timeouts** under full-suite parallel load on a CPU-throttled machine, not assertion failures; all green in isolation (35/35). Prevention: per the work-skill Doppler/contention caveat, re-run suspected failures in isolation before treating a full-suite timeout as a regression; these are documented cold-start flakes (#3687).

## Tags
category: integration-issues
module: apps/web-platform/server/workspace-invitations.ts

## Related
- [[2026-05-12-type-widening-cascades-and-write-boundary-sentinels]] — same "tsc can't see across the boundary" class for jsonb/unknown payloads
- Prior partial fixes: PR #4713 (#4715), PR #4641
