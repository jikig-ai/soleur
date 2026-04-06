---
title: "fix: disconnect repository fails due to NOT NULL constraint violation"
type: fix
date: 2026-04-06
deepened: 2026-04-06
---

# fix: disconnect repository fails due to NOT NULL constraint violation

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 3 (Root Cause, Implementation, Test Scenarios)

### Key Improvements

1. Identified this as the same class of schema-code mismatch bug that caused the Command Center chat failure (learning: `2026-03-28-unapplied-migration-command-center-chat-failure.md`) -- both involve NOT NULL constraint violations where application code assumes nullable columns
2. The TypeScript types already disallow `null` for both fields (`workspace_path: string`, `workspace_status: "provisioning" | "ready"`) -- the bug only exists in the runtime update payload, meaning `tsc --noEmit` could not have caught it because the Supabase client accepts `Record<string, unknown>` for update payloads
3. Added a defensive test scenario to verify the update payload matches schema defaults, preventing recurrence if new columns with NOT NULL constraints are added to the disconnect handler

### Relevant Learnings Applied

- `2026-03-28-unapplied-migration-command-center-chat-failure.md` -- same root cause pattern (NOT NULL violation from schema-code mismatch)
- `2026-03-18-postgresql-set-not-null-self-validating.md` -- PostgreSQL constraint enforcement is strict; no workaround for NOT NULL violations
- `integration-issues/silent-setup-failure-no-error-capture-20260403.md` -- the `repo_error` column and error capture patterns were added after this disconnect feature was implemented, confirming the disconnect route was written before the schema was fully stabilized
- `test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` -- the existing test file already uses `vi.hoisted()` correctly (fixed in prior session)

## Problem

The "Disconnect repository" action on the Settings page fails with "Failed to disconnect repository". The `DELETE /api/repo/disconnect` endpoint attempts to set `workspace_path` and `workspace_status` to `null`, but both columns have `NOT NULL` constraints in the database schema (`001_initial_schema.sql`). Additionally, `workspace_status` has a CHECK constraint restricting values to `('provisioning', 'ready')` -- `null` violates both constraints.

The Supabase update returns an error, the handler catches it at line 83, and returns the generic "Failed to disconnect repository" error to the client.

## Root Cause

In `apps/web-platform/app/api/repo/disconnect/route.ts` lines 78-79:

```typescript
workspace_path: null,
workspace_status: null,
```

The database schema (`001_initial_schema.sql` lines 9-11):

```sql
workspace_path text not null default '',
workspace_status text not null default 'provisioning'
  check (workspace_status in ('provisioning', 'ready')),
```

Setting either column to `null` violates the `NOT NULL` constraint. Setting `workspace_status` to `null` also violates the CHECK constraint.

The unit test (`disconnect-route.test.ts`) did not catch this because it mocks the Supabase client -- the mock always returns `{ error: null }` for the update call, bypassing the real database constraint check.

## Acceptance Criteria

- [x] `DELETE /api/repo/disconnect` sets `workspace_path` to `''` (empty string) instead of `null`
- [x] `DELETE /api/repo/disconnect` sets `workspace_status` to `'provisioning'` instead of `null`
- [x] Existing unit test assertions are updated to match the new values
- [x] Disconnecting a repository on the Settings page succeeds (returns `{ ok: true }`)
- [x] After disconnect, the user record shows `workspace_path = ''` and `workspace_status = 'provisioning'`

## Implementation

### Phase 1: Fix the route handler

**File:** `apps/web-platform/app/api/repo/disconnect/route.ts`

Change the update payload (lines 70-81) from:

```typescript
workspace_path: null,
workspace_status: null,
```

to:

```typescript
workspace_path: "",
workspace_status: "provisioning",
```

These are the default values from the schema. Setting `workspace_status` to `'provisioning'` (the default) is semantically correct -- a disconnected user's workspace is in the same state as a freshly created account before workspace provisioning. Empty string for `workspace_path` matches the column default.

#### Research Insights

**Why `null` was used in the first place:** The disconnect feature (plan archived at `20260406-113432`) was modeled after `DELETE /api/account/delete` which deletes the entire user row. The disconnect plan specified "clear all repo-related fields" and used `null` as the universal "clear" value. This works for columns added by migration `011_repo_connection.sql` (which are nullable: `repo_url text`, `github_installation_id bigint`, etc.) but fails for the original `001_initial_schema.sql` columns which have NOT NULL constraints.

**Supabase client error behavior:** When a Postgres constraint violation occurs, the Supabase JS client returns `{ error: { message: '...violates check constraint...', code: '23514' } }` for CHECK violations or `{ error: { message: '...violates not-null constraint...', code: '23502' } }` for NOT NULL violations. The handler at line 83 catches this correctly but logs it as a generic error. The fix should also improve the log message to include the constraint violation details from `updateError.message` so future constraint issues are diagnosable from logs without needing to reproduce.

**No migration needed:** PostgreSQL NOT NULL and CHECK constraints are enforced at write time (not read time). The fix changes the write payload to comply with existing constraints -- no schema changes required.

### Phase 2: Update tests

**File:** `apps/web-platform/test/disconnect-route.test.ts`

Update the assertion on lines 171-173:

```typescript
// Before
workspace_path: null,
workspace_status: null,

// After
workspace_path: "",
workspace_status: "provisioning",
```

### Phase 3: Update TypeScript types (if needed)

**File:** `apps/web-platform/lib/types.ts`

Check if the `workspace_status` type needs updating. Currently (lines 54-55):

```typescript
workspace_path: string;
workspace_status: "provisioning" | "ready";
```

This type already does not accept `null`, so the code was already inconsistent with its own types. The fix aligns runtime behavior with the TypeScript type.

## Alternative Considered

**Add a database migration to make columns nullable:** This would fix the symptom but change the schema contract. Other code paths (`callback/route.ts`, `workspace/route.ts`, `agent-runner.ts`) depend on `workspace_path` being non-null. Making these columns nullable would require auditing all consumers and adding null checks. The simpler fix is to use the schema defaults, which preserves the existing contract.

## Test Scenarios

- Given an authenticated user with a connected repo (`repo_status: 'ready'`), when `DELETE /api/repo/disconnect` is called, then the response is `{ ok: true }` and `workspace_path` is set to `''` and `workspace_status` is set to `'provisioning'`
- Given the Settings page showing a connected repo, when the user clicks "Confirm Disconnect", then the repo is disconnected and the user is redirected to `/connect-repo`
- Given the update payload in the disconnect handler, verify no field is set to `null` for columns that have NOT NULL constraints in the schema (defensive regression test)

### Research Insights

**Why the unit test did not catch this:** The test mocks `createServiceClient` and its `.update().eq()` chain resolves to `{ error: null }` unconditionally (line 84 in `disconnect-route.test.ts`). This is typical for unit-level route tests -- they verify the handler logic (auth checks, rate limiting, response codes) but not database constraint compliance. An integration test against a real Supabase instance (or at minimum, a mock that enforces column constraints) would have caught this.

**Preventing recurrence:** The existing test already asserts the exact update payload values (lines 166-174). Changing the assertion from `null` to the correct schema defaults is sufficient -- if someone reintroduces `null` for these fields, the test will catch it at the assertion level (though it still would not catch a real constraint violation). True prevention requires either schema-aware mocks or integration tests, both of which are out of scope for this fix.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a bug fix for an existing feature with no product, legal, or marketing impact.

## Context

### Files to modify

- `apps/web-platform/app/api/repo/disconnect/route.ts` (2-line change)
- `apps/web-platform/test/disconnect-route.test.ts` (2-line change)

### Related artifacts

- Original feature plan: `knowledge-base/project/plans/archive/20260406-113432-2026-04-06-feat-disconnect-github-repo-plan.md`
- Original issue: #1492 (CLOSED)
- Schema: `apps/web-platform/supabase/migrations/001_initial_schema.sql`
- Learning: `knowledge-base/project/learnings/2026-03-29-repo-connection-implementation.md`

### Why the test missed it

The unit test mocks `createServiceClient` to return a fake Supabase client. The mock's `.update().eq()` chain returns `{ error: null }` unconditionally, so it never exercises the real database constraint. This is a known limitation of unit tests with mocked databases -- an integration test against a real Supabase instance would have caught this. No change to the test infrastructure is proposed here (integration testing is a separate concern tracked elsewhere).
