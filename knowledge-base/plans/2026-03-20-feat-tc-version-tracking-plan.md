---
title: "feat: add T&C version tracking to tc_accepted_at"
type: feat
date: 2026-03-20
semver: patch
---

# feat: add T&C version tracking to tc_accepted_at

## Overview

The current T&C enforcement system gates on `tc_accepted_at IS NOT NULL` without recording which version of the Terms & Conditions the user accepted. When T&C are updated, there is no mechanism to determine which version a user consented to or to require re-acceptance of new terms. This creates a legal defensibility gap: in a dispute, the system cannot prove which exact terms a user agreed to.

This plan adds a `tc_accepted_version` column to the `public.users` table, a `TC_VERSION` constant in the application, and version-aware enforcement logic in middleware and the acceptance API route.

## Problem Statement / Motivation

**Legal defensibility:** GDPR Article 7 requires demonstrable consent. If T&C change but the system only records a timestamp, the controller cannot prove which version the user consented to. A regulator or court asking "show me the terms this user agreed to" has no answer beyond "they clicked something at some point."

**Re-acceptance on update:** When T&C are updated (e.g., the upcoming Section 5 subscription/cancellation clauses from #893), existing users should be required to accept the new version. Without version tracking, the only option is a blanket re-acceptance for all users, including those who already accepted the current version.

**Audit trail integrity:** The combination of `tc_accepted_at` (when) and `tc_accepted_version` (what) creates a complete consent record per GDPR Article 7(1).

## Proposed Solution

### 1. Database: New migration `007_add_tc_accepted_version.sql`

Add a `tc_accepted_version` column to `public.users`:

```sql
-- apps/web-platform/supabase/migrations/007_add_tc_accepted_version.sql
ALTER TABLE public.users
  ADD COLUMN tc_accepted_version text;

COMMENT ON COLUMN public.users.tc_accepted_version IS
  'Semantic version of T&C the user accepted (e.g., "1.0.0"). NULL = pre-version-tracking user or no T&C accepted.';
```

The column is nullable (existing users have `NULL` until they re-accept). It is NOT added to the column-level GRANT in migration 006 -- it remains server-write-only, same protection as `tc_accepted_at`.

Update `handle_new_user()` trigger to record the version from signup metadata:

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, workspace_path, tc_accepted_at, tc_accepted_version)
  VALUES (
    new.id,
    new.email,
    '/workspaces/' || new.id::text,
    CASE
      WHEN (new.raw_user_meta_data->>'tc_accepted') = 'true'
      THEN now()
      ELSE null
    END,
    CASE
      WHEN (new.raw_user_meta_data->>'tc_accepted') = 'true'
      THEN new.raw_user_meta_data->>'tc_version'
      ELSE null
    END
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2. Application: T&C version constant

Create a single source of truth for the current T&C version:

```typescript
// apps/web-platform/lib/legal/tc-version.ts
export const TC_VERSION = "1.0.0";
```

This is bumped manually when T&C content changes. The version string should match the `Last updated` date/version in the T&C document header.

### 3. Auth callback: Record version on acceptance

Update `ensureWorkspaceProvisioned` in `apps/web-platform/app/(auth)/callback/route.ts` to pass and store `tc_accepted_version` alongside `tc_accepted_at`:

- Extract `tc_version` from `user.user_metadata` (set by signup form)
- Pass it through to the upsert in the fallback path
- Mirror the trigger logic: only set when `tc_accepted` is true

### 4. Middleware: Version-aware enforcement

Update `apps/web-platform/middleware.ts` to check version staleness after confirming the user is authenticated:

- Query `tc_accepted_version` from `public.users` for the authenticated user
- Compare against `TC_VERSION` constant
- If `tc_accepted_version` is NULL or < `TC_VERSION`: redirect to `/accept-terms`
- If equal: proceed normally

This extends the existing auth check (redirect to `/login` if no user) with a version gate.

### 5. Accept-terms API: Stamp version on re-acceptance

Update `POST /api/accept-terms` (from PR #940) to write both `tc_accepted_at` and `tc_accepted_version` when the user accepts:

```typescript
await serviceClient
  .from("users")
  .update({
    tc_accepted_at: new Date().toISOString(),
    tc_accepted_version: TC_VERSION,
  })
  .eq("id", user.id);
```

### 6. Signup form: Include version in metadata

Update the signup flow to include `tc_version: TC_VERSION` in the user metadata passed to `supabase.auth.signUp()`, so the trigger can record it.

## Technical Considerations

### Dependency on PR #940

PR #940 (enforce `tc_accepted_at` -- middleware, WebSocket, acceptance page) is still open. This feature builds on top of it:

- The `/accept-terms` page and `POST /api/accept-terms` route are introduced by #940
- The middleware T&C enforcement (redirect to `/accept-terms` if not accepted) is introduced by #940

**Approach:** This PR should target main and merge after #940. If #940 is not yet merged at implementation time, branch from main and handle conflicts at merge time -- the touchpoints are well-defined (middleware.ts, callback/route.ts).

### Version format

Use semantic versioning (`1.0.0`) for T&C versions. This is human-readable, sortable, and allows distinguishing major rewrites (2.0.0) from clause additions (1.1.0) from typo fixes (1.0.1). The comparison logic uses simple string equality (`!== TC_VERSION`), not semver comparison -- any version mismatch triggers re-acceptance.

### Migration safety

- The new column is nullable with no default, so the `ALTER TABLE` is a metadata-only operation (no table rewrite)
- Existing users get `NULL` for `tc_accepted_version`, which the middleware treats as "stale" and redirects to re-accept
- The column is protected by the existing column-level GRANT in migration 006 (only `email` is user-writable)

### Trigger-fallback parity (learning from #925)

Per the learning in `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md`, the database trigger and the TypeScript fallback in `callback/route.ts` must use identical conditional logic for `tc_accepted_version`. Both must:
- Only set `tc_accepted_version` when `tc_accepted` is true
- Read the version from the same metadata key (`tc_version`)

### WebSocket enforcement

The WebSocket handler (from PR #940) rejects connections with close code 4004 if T&C not accepted. Consider whether it should also check version staleness. For this initial implementation, WebSocket enforcement of version is a non-goal -- the middleware redirect handles it for all HTTP routes, and users must pass through an HTTP route before establishing a WebSocket connection.

## Non-goals

- **Automatic version detection from T&C document content** (e.g., hashing the document). Manual version bumps are simpler and give legal control over what constitutes a "new version."
- **Version history table** (tracking every version a user has ever accepted). A single `tc_accepted_version` column is sufficient for the current requirement. A history table can be added later if needed for audit.
- **Differential T&C display** (showing users what changed between versions). Out of scope -- the `/accept-terms` page shows the full current T&C.
- **WebSocket version enforcement.** Users must pass through HTTP middleware before WebSocket, so HTTP enforcement is sufficient.
- **Grace period for version transitions.** When T&C are updated, users are immediately redirected on their next request. No "you have N days to accept" logic.

## Acceptance Criteria

- [ ] New migration `007_add_tc_accepted_version.sql` adds `tc_accepted_version text` column to `public.users`
- [ ] `handle_new_user()` trigger records `tc_accepted_version` from signup metadata when `tc_accepted` is true
- [ ] `TC_VERSION` constant exists in `apps/web-platform/lib/legal/tc-version.ts`
- [ ] Auth callback fallback path records `tc_accepted_version` with trigger-fallback parity
- [ ] Middleware redirects to `/accept-terms` when `tc_accepted_version !== TC_VERSION` (including NULL)
- [ ] `POST /api/accept-terms` writes both `tc_accepted_at` and `tc_accepted_version`
- [ ] Signup form includes `tc_version` in user metadata
- [ ] `tc_accepted_version` column is NOT in the column-level GRANT (remains server-write-only)
- [ ] All existing tests pass; new tests cover version check logic

## Test Scenarios

### Acceptance Tests

- Given a new user signs up with T&C checkbox checked, when their profile is created, then `tc_accepted_version` equals `TC_VERSION` and `tc_accepted_at` is set
- Given a new user signs up without checking T&C, when their profile is created, then `tc_accepted_version` is NULL and `tc_accepted_at` is NULL
- Given an existing user with `tc_accepted_version = "1.0.0"` and `TC_VERSION = "1.0.0"`, when they access a protected route, then they proceed normally
- Given an existing user with `tc_accepted_version = NULL`, when they access a protected route, then they are redirected to `/accept-terms`
- Given an existing user with `tc_accepted_version = "0.9.0"` and `TC_VERSION = "1.0.0"`, when they access a protected route, then they are redirected to `/accept-terms`
- Given a user on `/accept-terms` clicks accept, when the API processes their acceptance, then `tc_accepted_version` is updated to `TC_VERSION` and `tc_accepted_at` is refreshed

### Edge Cases

- Given the Supabase query for `tc_accepted_version` fails in middleware, when a user accesses a protected route, then the middleware fails open (user proceeds) -- consistent with existing fail-open behavior for auth queries
- Given the database trigger fires but the metadata does not contain `tc_version`, when a new user is created, then `tc_accepted_version` is NULL (not a stale string)

### Regression Tests

- Given the trigger-fallback parity fix from #925, when the fallback path creates a user row, then `tc_accepted_version` mirrors the trigger logic exactly (conditional on `tc_accepted`, reads from `tc_version` metadata key)

## Dependencies & Risks

| Dependency | Status | Risk |
|---|---|---|
| PR #940 (T&C enforcement middleware, `/accept-terms` page) | Open | Must merge first; touchpoints are well-defined |
| Issue #933 (no downstream enforcement) | Open, addressed by #940 | Resolved when #940 merges |
| Migration 006 (column-level GRANT) | Merged | New column auto-protected; no GRANT change needed |

**Risk: Middleware performance.** Adding a `users` table query to middleware for every request adds latency. Mitigation: the query is a single-row lookup by primary key (`id`), which is O(1) on the index. If this becomes a concern, the version can be cached in the session cookie or JWT claims.

**Risk: Grandfathered users flood.** When this ships, all existing users have `tc_accepted_version = NULL` and will be redirected to `/accept-terms` on their next visit. This is the intended behavior -- it is the "require re-acceptance" mechanism described in the issue.

## References & Research

### Internal References

- `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql` -- existing T&C timestamp migration
- `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql` -- column-level GRANT restriction
- `apps/web-platform/app/(auth)/callback/route.ts` -- auth callback with trigger-fallback pattern
- `apps/web-platform/middleware.ts` -- current auth middleware (no T&C enforcement yet)
- `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md` -- trigger/fallback parity learning
- `knowledge-base/learnings/2026-03-20-supabase-column-level-grant-override.md` -- column-level GRANT learning

### Related Issues & PRs

- #947 -- this issue (T&C version tracking)
- #933 -- no downstream enforcement of `tc_accepted_at`
- #940 -- PR enforcing `tc_accepted_at` (dependency)
- #925 -- unconditional `tc_accepted_at` fallback bug
- #889 -- original T&C acceptance mechanism
- #893 -- T&C cancellation/subscription clauses (will trigger a version bump)

### External References

- GDPR Article 7 -- Conditions for consent (demonstrable, specific, informed)
- GDPR Article 7(1) -- Controller must demonstrate consent was given
