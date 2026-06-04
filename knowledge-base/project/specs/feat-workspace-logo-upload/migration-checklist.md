# Migration 098 — workspace_logos — DEV apply + verification

**Applied:** 2026-06-04 to DEV (Supabase ref `mlwiodleouzwniehynfz`) via Doppler
`DATABASE_URL_POOLER` session-mode (`:5432`), wrapped `BEGIN … COMMIT` with the
canonical `_schema_migrations` tracking row (`content_sha
fcdbc325cd8ba7c7bcc98c877750f5cfef4fd276`). MCP not used — Doppler-pooler path
per the work-skill Supabase fallback chain.

prd apply is automatic on merge via `web-platform-release.yml#migrate` (no
operator action).

## Pre-apply collision check
`098` is collision-free on `origin/main` (only `095`–`097` present). No renumber needed.

## Catalog verification (post-apply, live) — AC1 / AC2
- `workspaces.logo_path` text, **nullable**, no backfill. ✅
- `workspace-logos` bucket: `public=false`, `file_size_limit=1048576`,
  `allowed_mime_types=['image/webp']`. ✅
- `is_workspace_owner(uuid,uuid)`: `prosecdef=true` (SECURITY DEFINER),
  `search_path=public, pg_temp`, `EXECUTE` granted to `authenticated` only
  (`anon`/`service_role` revoked). ✅
- 4 policies on `storage.objects` (no `FOR ALL`): SELECT→`is_workspace_member`;
  INSERT (WITH CHECK only), UPDATE (USING **and** WITH CHECK), DELETE (USING only)
  →`is_workspace_owner`; every policy AND-guards `^[0-9a-f-]{36}$` before the
  `::uuid` cast. ✅

## Behavioral RLS verification (live, `SET LOCAL ROLE authenticated` + jwt claims, savepoint-isolated, ROLLBACK-wrapped) — AC3
Seeded two synthetic tenants (ownerA + memberA in workspace A; ownerB in workspace B):
- owner writes own workspace logo object → **allowed** ✅
- non-owner member writes/overwrites → **denied** (RLS) ✅
- non-member reads another workspace's logo object → **0 rows** (RLS filters) ✅
- co-member reads workspace logo object → **visible** ✅
- owner-of-A UPDATE/move object into B's prefix → **denied** (WITH CHECK) ✅
- malformed (non-UUID) path → **clean-deny, no 22P02 abort** ✅

## down.sql — corrected during verification (plan precondition falsified)
The plan's down (`DELETE FROM storage.objects` → `DELETE FROM storage.buckets`)
is **infeasible**: Supabase installs a platform trigger `protect_objects_delete`
(`storage.protect_delete`) that blocks direct DELETE on both `storage.objects`
and `storage.buckets` ("Direct deletion from storage tables is not allowed. Use
the Storage API instead." — verified live). Bucket-creating migrations 019/042
ship **no** SQL bucket teardown for this reason; 071's `DELETE FROM
storage.buckets` is a dormant bug that would fail if ever run.

**Corrected down.sql** reverts only SQL-droppable objects: 4 policies →
`is_workspace_owner` → `logo_path` column. Verified live (ROLLBACK-wrapped):
column + function + policies all removed cleanly. Bucket + objects teardown is a
Storage-API/operator concern (rare rollback path; an empty orphan bucket is
harmless). data-integrity P2's "delete objects in down" intent is preserved at
runtime by the route's orphan-cleanup arms + the account-delete purge helper.

## AC5b — column-takeover DB-enforced (live, DEV)
The plan claimed `public.workspaces` has "ONLY `workspaces_select_for_members`".
Live verification falsified the literal claim — there is ALSO a
`workspaces_jti_not_denied` policy — but the **security property holds**:
- `workspaces_jti_not_denied` is **RESTRICTIVE** (`permissive=false`), `FOR ALL`,
  `USING/WITH CHECK = NOT is_jti_denied_from_jwt()` — a session-revocation guard
  that can only *further deny*, never *grant*.
- The only **PERMISSIVE** policy is `workspaces_select_for_members` (SELECT only,
  `is_workspace_member(id, auth.uid())`).
- PostgreSQL RLS requires a passing PERMISSIVE policy for a command; there is NO
  permissive INSERT/UPDATE/DELETE policy → authenticated client writes are denied.

**Verified:** static (no permissive write policy) + behavioral (an authenticated
owner's `UPDATE workspaces SET logo_path` affects **0 rows**). So no client SDK
path can set `logo_path` to another workspace's key — the read proxy can safely
trust `logo_path`. The route writes via service-role only. ✅

**Result: 34/34 live checks PASS** (32 migration + 2 AC5b).

## prd apply — pending

prd apply is **deferred to merge** by design: `web-platform-release.yml#migrate`
runs the migration runner against prd automatically on merge touching
`apps/web-platform/**` (no operator action — the merge IS the apply, per plan
AC10 post-merge note). At pre-merge preflight time the `logo_path` column does
not yet exist in prd; this is expected. Post-merge, `/ship` Phase 7 Step 3.6 +
the release `verify-migrations` job confirm the column is live. Preflight Check 1
treats this documented deferral as SKIP (auditable paper trail per Step 1.1b).
