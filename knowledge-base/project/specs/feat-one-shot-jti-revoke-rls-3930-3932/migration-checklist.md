# Migration Checklist — feat-one-shot-jti-revoke-rls-3930-3932

Migration: `apps/web-platform/supabase/migrations/068_jti_deny_rls_predicate_and_revoke_rpc.sql`

## dev apply — done

Applied 2026-05-25 via `bun supabase-migrate.ts --env dev --apply 068` (Doppler+pg
pooler, transaction-wrapped). content_sha tracked in `_schema_migrations`.

verify-068 sentinel: 31/31 rows return `bad=0` against dev.

## prd apply — pending

Will be applied automatically by `.github/workflows/web-platform-release.yml#migrate`
on merge of PR #4418 (job: `migrate-apply-web-platform`). The release workflow's
`verify-migrations` job runs `verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql`
post-apply against prd as the canonical sentinel.

Operator does NOT apply manually. Preflight Check 1 SKIPs against prd until
release CI has run, per Step 1.1b documented-deferral signal in this checklist.
