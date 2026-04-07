---
title: "fix: health check returns supabase: connected"
type: fix
date: 2026-04-07
---

# fix: health check returns supabase: connected

## Overview

The `/health` endpoint always reports `supabase: "error"` in production because `checkSupabase()` pings `/rest/v1/` (the PostgREST schema listing endpoint) with the anon key. Supabase returns 401 for schema listing without the service role key. This is a pre-existing issue -- the health check has never returned `connected` in production.

## Problem Statement

In `apps/web-platform/server/health.ts`, the `checkSupabase()` function fetches `${serverUrl()}/rest/v1/` with the `NEXT_PUBLIC_SUPABASE_ANON_KEY`. The `/rest/v1/` root endpoint lists available schemas, which requires the service role key. The anon key only has access to query specific tables (via RLS policies).

Verified via curl:

- `GET /rest/v1/` with anon key returns **401**
- `GET /rest/v1/users?select=id&limit=1` with anon key returns **200** (empty array due to RLS, but HTTP status is 200)

## Proposed Solution

Change `checkSupabase()` to query a specific table (`users`) with `select=id&limit=1` instead of the schema listing endpoint. This approach:

1. Uses the existing anon key (no need to add the service role key to the health check)
2. Validates end-to-end connectivity: DNS resolution, TLS, PostgREST routing, and database availability
3. Returns 200 even with RLS (PostgREST returns 200 with an empty set when RLS filters all rows)
4. Avoids exposing privileged credentials in a public endpoint

### Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Use service role key for `/rest/v1/` | Validates schema listing | Leaks privileged key scope into health check; unnecessary privilege escalation | Rejected |
| Query specific table with anon key | Minimal change; validates connectivity; uses existing credentials | Tests one table, not schema availability | **Chosen** |
| Use `createServiceClient()` from Supabase JS SDK | Higher-level API; auto-handles auth | Heavier dependency for a connectivity probe; service role key overkill | Rejected |

## Acceptance Criteria

- [ ] `/health` returns `supabase: "connected"` when Supabase is reachable (update `checkSupabase()` in `apps/web-platform/server/health.ts`)
- [ ] `/health` returns `supabase: "error"` when Supabase is unreachable (timeout/network error)
- [ ] Existing unit tests in `apps/web-platform/test/server/health.test.ts` continue to pass
- [ ] Production verification: `curl https://app.soleur.ai/health | jq .supabase` returns `"connected"` after deploy

## Test Scenarios

- Given Supabase is reachable, when `/health` is called, then `supabase` field is `"connected"`
- Given Supabase is unreachable (network error), when `/health` is called, then `supabase` field is `"error"`
- Given Supabase returns a non-200 status for the table query, when `/health` is called, then `supabase` field is `"error"`
- **API verify:** `curl -s https://app.soleur.ai/health | jq '.supabase'` expects `"connected"`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- **Source issue:** [#1685](https://github.com/jikig-ai/soleur/issues/1685)
- **Source PR:** [#1680](https://github.com/jikig-ai/soleur/pull/1680)
- **File to modify:** `apps/web-platform/server/health.ts` (lines 3-16, `checkSupabase()` function)
- **Test file:** `apps/web-platform/test/server/health.test.ts`

## Implementation

### `apps/web-platform/server/health.ts`

Change the fetch URL from `/rest/v1/` to `/rest/v1/users?select=id&limit=1`:

```typescript
async function checkSupabase(): Promise<boolean> {
  try {
    const response = await fetch(
      `${serverUrl()}/rest/v1/users?select=id&limit=1`,
      {
        headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "" },
        signal: AbortSignal.timeout(2000),
      },
    );
    return response.ok;
  } catch {
    return false;
  }
}
```

No other files need changes. The `HealthResponse` interface, `buildHealthResponse()`, Dockerfile `HEALTHCHECK`, and E2E smoke test all remain valid.

## References

- Related issue: #1685
- Source PR: #1680
- Supabase PostgREST docs: anon key can query tables with RLS but cannot list schemas
