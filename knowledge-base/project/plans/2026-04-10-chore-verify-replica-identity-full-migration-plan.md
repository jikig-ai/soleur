---
title: "chore: Verify REPLICA IDENTITY FULL migration applied to production"
type: fix
date: 2026-04-10
---

# Verify REPLICA IDENTITY FULL Migration Applied to Production

Verify that the `REPLICA IDENTITY FULL` migration from PR #1759 (Command Center) was
successfully applied to the `conversations` table in the production Supabase database.
This is a follow-through verification task created by /ship Phase 7 Step 3.5.

## Background

PR #1759 added migration `015_conversations_replica_identity.sql` which sets
`REPLICA IDENTITY FULL` on the `conversations` table. This is required for Supabase
Realtime to include all column values in change payloads, enabling the Command Center's
real-time status badge updates. The migration was committed and merged on 2026-04-07,
but production application was not verified before the session ended.

**Source:** `apps/web-platform/supabase/migrations/015_conversations_replica_identity.sql`

```sql
ALTER TABLE public.conversations REPLICA IDENTITY FULL;
```

## Verification Steps

### Step 1: Retrieve Production Credentials from Doppler

Fetch the Supabase URL and service role key from the `prd` Doppler config:

```text
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain
```

### Step 2: Verify Table Exists and RLS Is Active

Query the `conversations` table via the Supabase REST API. A successful response (even
an empty array) confirms the table exists and RLS permits the service role key to read it:

```text
curl -s "<SUPABASE_URL>/rest/v1/conversations?select=id&limit=1" \
  -H "apikey: <SUPABASE_KEY>" \
  -H "Authorization: Bearer <SUPABASE_KEY>"
```

**Expected:** JSON array (e.g., `[]` or `[{"id":"..."}]`). An error response indicates
the table does not exist or RLS is misconfigured.

### Step 3: Verify REPLICA IDENTITY FULL via SQL

Use the Supabase MCP tool or SQL Editor to run:

```sql
SELECT relreplident FROM pg_class WHERE relname = 'conversations';
```

**Expected:** `f` (FULL). Values: `d` = DEFAULT, `n` = NOTHING, `i` = INDEX, `f` = FULL.

### Step 4: Close Issue if Verified

If both checks pass, close GitHub issue #1766 with a verification comment confirming the
results.

If either check fails, investigate whether the migration was applied. Check:

1. Whether the migration runner (Supabase CLI or dashboard) was triggered after merge
2. Whether an error occurred during migration application
3. Whether the migration needs to be applied manually via the Supabase SQL Editor

## Acceptance Criteria

- [ ] REST API query to `conversations` table returns a valid JSON response (table exists, RLS active)
- [ ] `pg_class.relreplident` for `conversations` is `f` (FULL)
- [ ] GitHub issue #1766 closed with verification comment

## Test Scenarios

- **API verify:** `curl -s "<SUPABASE_URL>/rest/v1/conversations?select=id&limit=1" -H "apikey: <KEY>" -H "Authorization: Bearer <KEY>"` expects valid JSON array
- **SQL verify:** `SELECT relreplident FROM pg_class WHERE relname = 'conversations';` expects `f`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure verification task with no code changes.

## Context

- **Source PR:** #1759 (feat: Command Center replaces dashboard with conversation inbox)
- **Issue:** #1766 (follow-through: Verify REPLICA IDENTITY FULL migration applied to production)
- **Migration file:** `apps/web-platform/supabase/migrations/015_conversations_replica_identity.sql`
- **SLA:** 5 business days from 2026-04-07 (due by 2026-04-14)
- **Priority:** P1-high (follow-through label)
- **No code changes expected** -- this is verification only

## References

- Related PR: #1759
- Related issue: #1766
- [Supabase Realtime docs on REPLICA IDENTITY](https://supabase.com/docs/guides/realtime/postgres-changes)
- Migration: `apps/web-platform/supabase/migrations/015_conversations_replica_identity.sql`
