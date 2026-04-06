---
title: "fix: disconnect repository fails due to NOT NULL constraint violation"
type: fix
date: 2026-04-06
---

# fix: disconnect repository fails due to NOT NULL constraint violation

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

- [ ] `DELETE /api/repo/disconnect` sets `workspace_path` to `''` (empty string) instead of `null`
- [ ] `DELETE /api/repo/disconnect` sets `workspace_status` to `'provisioning'` instead of `null`
- [ ] Existing unit test assertions are updated to match the new values
- [ ] Disconnecting a repository on the Settings page succeeds (returns `{ ok: true }`)
- [ ] After disconnect, the user record shows `workspace_path = ''` and `workspace_status = 'provisioning'`

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
