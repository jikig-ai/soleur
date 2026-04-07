# Learning: Supabase PostgREST anon key returns 401 for schema listing but 200 for table queries

## Problem

The `/health` endpoint's `checkSupabase()` function fetched `${supabaseUrl}/rest/v1/` (the PostgREST schema listing endpoint) with the anon key. This always returned 401 because schema listing requires the service role key. The health check never reported `supabase: "connected"` in production.

## Solution

Changed the health check URL from `/rest/v1/` to `/rest/v1/users?select=id&limit=1`. The anon key can query specific tables — PostgREST returns HTTP 200 with an empty JSON array (`[]`) when RLS filters all rows, not 401. This validates DNS resolution, TLS, PostgREST routing, and database availability without requiring elevated credentials.

## Key Insight

PostgREST treats schema listing and table queries differently for authorization. Schema listing (`/rest/v1/`) requires the service role key (returns 401 with anon key). Table queries (`/rest/v1/<table>?...`) work with the anon key — RLS filters rows at the database level, but the HTTP response is always 200 (with empty results if no rows pass RLS). This makes table queries a reliable connectivity probe even without authentication.

## Tags

category: integration-issues
module: web-platform/server/health
