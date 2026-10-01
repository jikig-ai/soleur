# Migration 141 — Dev apply + verification checklist

**Migration:** `141_users_cohort_key.sql` (+ `141_users_cohort_key.down.sql`)
**Scope:** adds `public.users.cohort_key` (`text`, CHECK `^[a-z0-9-]+$`,
nullable, no default — no table rewrite, no downtime). Paired `.down.sql`
drops the column.
**Ledger note:** the file was edited in the review-fix commit
(`/api/admin/cohort` → `/api/internal/cohort` in comments only, blob
`f7790b4f…` → `22e6d7ac…`) after the runner had applied the first body; the
dev-ledger row was discarded via `dev-ledger-reconcile.yml` (execute,
`allow_later_rows` — the two later rows are conversation-engine migrations
unrelated to `users.cohort_key`) and re-applied by the tenant-integration
job at the corrected body.

## Dev apply — done

- Applied by the PR-triggered `tenant-integration` job (workflow
  `tenant-integration.yml`, run for head `a2ef5fb7f1`), which applies
  unmerged migrations under the dev-suite mutex and writes the
  `_schema_migrations` tracking row itself.
- **content_sha (git hash-object):** `22e6d7ac1ab3c209f0afc30305fa924739d2827a`
- Verified green: `tenant-integration` + `tenant-integration-required` both
  PASS on the pushed head.

## prd apply — pending (deferred to release pipeline)

Not applied to prd: feature-branch migrations land on prd at merge via the
release flow, not before. Nothing in this diff reads `cohort_key` on the
unscoped path — admin analytics filters by it only under `?cohort=`, and the
writer is the Bearer-gated internal route; a missing column on prd degrades
the scoped endpoints only.

## Post-merge verification

After merge, the release `verify-migrations` job re-asserts the column on
prd. Manual spot-check equivalent:

```bash
curl -sf "$SUPABASE_URL/rest/v1/users?select=cohort_key&limit=1" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY"
# 200 => applied; 400 => not applied
```
