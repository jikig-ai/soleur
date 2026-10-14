# Migration checklist — feat-one-shot-concierge-perms-gh-auth

Migration: `apps/web-platform/supabase/migrations/097_workspace_bash_autonomous.sql`
(+ `.down.sql`, + `verify/097_workspace_bash_autonomous.sql` runtime grant sentinel).

Adds `workspaces.bash_autonomous boolean NOT NULL DEFAULT false` + the
member-read / owner-write SECURITY DEFINER RPCs. `ADD COLUMN ... NOT NULL
DEFAULT false` is metadata-only on PG11+ (no table rewrite, in-transaction safe).

## dev apply — pending

Applied by the standard `run-migrations.sh` path on the next dev deploy.

## prd apply — pending

Deferred to the release pipeline: `web-platform-release.yml#migrate` runs
`run-migrations.sh` on merge to main, applying 097 + recording the
`_schema_migrations` tracking row in the same transaction. The PR uses `Ref`
(not auto-`Closes`) semantics for the migration per plan AC20. CI's
`verify-migrations` job then runs `verify/097_*.sql` (anon-revoked /
authenticated-granted grant-hygiene sentinels) and fails the deploy on drift.

Post-merge verification (automated, no operator step): `/soleur:postmerge` +
the release pipeline's REST probe confirm `workspaces.bash_autonomous` exists
in prd. No manual `terraform apply` or dashboard SQL step.
