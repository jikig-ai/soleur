# Learning: changing a DB-default invariant must grep TENANT_INTEGRATION_TEST tests for the old contract

## Problem

PR #4762 changed `handle_new_user()` + the backfill so `organizations.name` defaults to
`'My Workspace'` instead of NULL (migration 091). The full local `vitest run` passed
(7884) and the PR merged. Then main's `Tenant integration (dev-Supabase)` job went RED
on two assertions that still encoded the OLD contract:

- `workspace-backfill-trigger-parity.test.ts:158` — `expect(organizations![0].name).toBeNull()`
- `dsar-export-workspace-tables.integration.test.ts:159` — `expect(data![0].name).toBeNull()`

Both are gated behind `TENANT_INTEGRATION_TEST=1` and run against **live dev Supabase**,
so the local `vitest run` (no env flag, no live creds) **skipped** them. The behavioral
change to the signup trigger surfaced only post-merge, in the CI job that exercises the
real DB.

## Solution

Fix-forward PR #4766: update both assertions to `expect(...name).toBe(DEFAULT_ORG_NAME)`
via the shared `@/lib/workspace-name` constant.

## Key Insight

When a migration changes a **default-value or nullability invariant** on a column
(`NULL → default`, `default → NULL`, enum-value change), the unit suite is blind to it
two ways: (1) migration-shape tests only regex the SQL source, and (2) the
behavioral tests that would catch it are `TENANT_INTEGRATION_TEST`-gated and skipped by
the default `vitest run`. The cheap forward gate at /work time is a grep of the WHOLE
test tree for assertions on the changed column, **before** committing the migration:

```bash
grep -rnE '<table>|<column>' test/ | grep -iE '<column>.*(toBeNull|=== null|: null|toBe\()'
```

For this change: `grep -rn 'organizations' test/ | grep -iE 'name.*toBeNull'` would have
surfaced both files at /work time. This is the integration-test analog of the existing
"sweep-class fixes use grep-enumerated work-lists" rule — extend the grep to
integration tests whose live-DB behavior depends on the invariant, not just the unit
mocks.

## Tags
category: test-failures
module: apps/web-platform/supabase/migrations
