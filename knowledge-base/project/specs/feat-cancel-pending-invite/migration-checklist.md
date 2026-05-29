# Migration checklist — feat-cancel-pending-invite (085)

Migration: `085_revoke_workspace_invitation.sql` (+ `.down.sql`)
Classification: schema-addition (`ADD COLUMN revoked_at/revoked_by`) + `CREATE OR REPLACE`
on 5 existing functions. Additive, rolling-deploy-safe (both columns nullable, no backfill).

## prd apply — pending

The migration is applied automatically on merge to `main` by the `migrate` job in
`.github/workflows/web-platform-release.yml` (the canonical migration path for this repo —
no operator step). The `verify-migrations` job in the same workflow runs the post-apply
sentinels. Pre-merge, the new columns do not yet exist in prd, so preflight Check 1 SKIPs
per Step 1.1b (documented deferral) and re-verifies post-merge.

- dev apply: deferred — integration suite (`TENANT_INTEGRATION_TEST=1`) is opt-in and
  DEV-only; not required for merge.
- prd apply: on merge via `web-platform-release.yml#migrate`.
- post-merge verification: `web-platform-release.yml#verify-migrations` + ship Phase 7
  Step 3.6 REST probe (`revoked_at` column existence).
