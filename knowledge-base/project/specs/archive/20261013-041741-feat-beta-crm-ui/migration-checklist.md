# Migration checklist — feat-beta-crm-ui (migration 127)

Migration: `apps/web-platform/supabase/migrations/127_beta_crm_access_log.sql` (+ `.down.sql`)
Adds: `beta_contact_access_log` table + `crm_get_contact_detail(uuid)` VOLATILE SECURITY DEFINER RPC.

## dev apply — deferred (shared-dev pre-merge exclusion)

Not applied to shared dev pre-merge per `hr-dev-prd-distinct-supabase-projects` (behavioral
proofs belong on a dedicated dev project, never the shared pre-merge dev). Shape verified by
`test/supabase-migrations/127-beta-crm-access-log.test.ts` (26 assertions) + multi-agent
data-integrity review (RPC body, composite-FK CASCADE, jsonb aggregation, RLS posture).

## prd apply — pending

Applies automatically on merge-to-main via `web-platform-release.yml#migrate` (plan AC17 —
pipeline-automated, no SSH, no dashboard). `/soleur:ship` Phase 7 Step 3.6 verifies
`beta_contact_access_log` exists in prd post-merge via the Supabase REST probe, and CI's
`verify-migrations` job runs on deploy. Preflight Check 1 SKIPs pre-merge on this documented
deferral.

## Verification (post-apply)

- `beta_contact_access_log` table exists (REST `select=accessed_at&limit=1` → 200).
- `crm_get_contact_detail(uuid)` RPC exists + is SECURITY DEFINER (MCP `list_migrations` / `execute_sql` read-only probe).
