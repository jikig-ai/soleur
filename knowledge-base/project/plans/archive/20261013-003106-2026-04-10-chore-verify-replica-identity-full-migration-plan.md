---
title: "chore: Verify REPLICA IDENTITY FULL migration applied to production"
type: fix
date: 2026-04-10
---

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 3 (Verification Steps, Test Scenarios, Context)
**Research agents used:** Doppler secret discovery, Supabase Management API probe, learnings review

### Key Improvements

1. Discovered fully automated SQL verification path via Supabase Management API (`SUPABASE_ACCESS_TOKEN` in Doppler `prd`) -- eliminates need for MCP OAuth or manual SQL Editor
2. Pre-verified both checks pass: REST API returns data, `relreplident = 'f'` confirmed
3. Added concrete Doppler secret names and API endpoints for copy-paste execution

### New Considerations Discovered

- `SUPABASE_ACCESS_TOKEN` in Doppler `prd` config enables Management API access (project ref: `ifsccnjhymdmidffkzhl`)
- The Supabase MCP tool requires OAuth authentication and is unnecessary for this task
- Doppler personal tokens (used locally) support `-c prd` flag; service tokens do not (see learning: 2026-03-29-doppler-service-token-config-scope-mismatch)

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

Fetch three secrets from the `prd` Doppler config:

```text
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain
doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain
```

### Research Insights

**Available Doppler secrets (prd config):**

| Secret Name | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | REST API base URL (`https://api.soleur.ai`) |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key for REST API (bypasses RLS) |
| `SUPABASE_ACCESS_TOKEN` | Personal access token for Supabase Management API |
| `SUPABASE_URL` | Raw Supabase URL (contains project ref `ifsccnjhymdmidffkzhl`) |

**Doppler usage note:** These commands use the local Doppler personal token, which
supports the `-c prd` flag. CI workflows use service tokens where `-c` is ignored
(see learning: `2026-03-29-doppler-service-token-config-scope-mismatch.md`).

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

**Pre-verification result (2026-04-10):** Returns
`[{"id":"df546f57-008d-44fa-962a-362c31659dde"}]` -- table exists, RLS active, data present.

### Step 3: Verify REPLICA IDENTITY FULL via SQL

Use the Supabase Management API (fully automated, no browser required):

```text
curl -s "https://api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query" \
  -X POST \
  -H "Authorization: Bearer <SUPABASE_ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT relreplident FROM pg_class WHERE relname = '\''conversations'\''"}'
```

**Expected:** `[{"relreplident":"f"}]` where `f` = FULL.

Values: `d` = DEFAULT, `n` = NOTHING, `i` = INDEX, `f` = FULL.

**Pre-verification result (2026-04-10):** Returns `[{"relreplident":"f"}]` -- REPLICA
IDENTITY FULL is confirmed applied.

### Research Insights

**Automation path discovery:** The original issue suggested the Supabase SQL Editor
(browser) for Step 3. During deepening, we discovered:

1. `SUPABASE_ACCESS_TOKEN` exists in Doppler `prd` config
2. The Supabase Management API endpoint
   `POST /v1/projects/{ref}/database/query` accepts raw SQL
3. This eliminates the need for Supabase MCP OAuth or manual SQL Editor access
4. The project ref (`ifsccnjhymdmidffkzhl`) is extractable from `SUPABASE_URL`

**Fallback paths (if Management API is unavailable):**

1. Supabase CLI: `supabase db query "SELECT ..." --project-ref ifsccnjhymdmidffkzhl`
   (requires `supabase login` -- CLI v2.84.2 is installed)
2. Supabase MCP tool: requires OAuth authentication flow (interactive)
3. Supabase Dashboard SQL Editor: manual browser access (last resort)

### Step 4: Close Issue if Verified

If both checks pass, close GitHub issue #1766 with a verification comment containing
the actual API responses:

```text
gh issue close 1766 --comment "Verified on 2026-04-10:

1. REST API: conversations table exists, RLS active (returned data)
2. REPLICA IDENTITY: relreplident = 'f' (FULL) confirmed via Management API SQL query

Migration 015_conversations_replica_identity.sql is applied to production."
```

If either check fails, investigate whether the migration was applied. Check:

1. Whether the migration runner (Supabase CLI or dashboard) was triggered after merge
2. Whether an error occurred during migration application
3. Whether the migration needs to be applied manually via the Supabase SQL Editor

## Acceptance Criteria

- [x] REST API query to `conversations` table returns a valid JSON response (table exists, RLS active)
- [x] `pg_class.relreplident` for `conversations` is `f` (FULL)
- [x] GitHub issue #1766 closed with verification comment

## Test Scenarios

- **API verify:** `curl -s "<SUPABASE_URL>/rest/v1/conversations?select=id&limit=1" -H "apikey: <KEY>" -H "Authorization: Bearer <KEY>"` expects valid JSON array
- **SQL verify:** `curl -s "https://api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query" -X POST -H "Authorization: Bearer <TOKEN>" -H "Content-Type: application/json" -d '{"query": "SELECT relreplident FROM pg_class WHERE relname = '\''conversations'\''"}'` expects `[{"relreplident":"f"}]`

### Edge Cases

- **Empty conversations table:** REST API returns `[]` (still valid -- confirms table exists and RLS is active)
- **Management API token expired:** Falls back to Supabase CLI (`supabase db query`) or manual SQL Editor
- **relreplident = 'd' (DEFAULT):** Migration was NOT applied -- investigate whether the migration file was included in the deployment pipeline

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
