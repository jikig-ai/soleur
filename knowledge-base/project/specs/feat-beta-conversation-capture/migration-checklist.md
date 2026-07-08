# Migration Checklist — feat-beta-conversation-capture (#6165)

## Scope

Migration `apps/web-platform/supabase/migrations/126_beta_crm.sql` (+ `.down.sql`):
3 owner-private tables (`beta_contacts`, `interview_notes`,
`beta_contact_stage_transitions`), owner-only RLS + jti-deny RESTRICTIVE, 4
SECURITY DEFINER RPCs (`crm_contact_upsert`, `crm_note_append`,
`crm_contact_set_stage`, service-role-only `crm_erase_contact`), a BEFORE-UPDATE
`updated_at` trigger, and a 24-month `pg_cron` retention sweep. ADR-102.

## Offline verification (pre-merge, done)

- `test/supabase-migrations/126-beta-crm.test.ts` — file-parse shape gate (RLS
  posture, composite-FK shape, SECURITY-DEFINER pins, PII-safe CHECK design,
  append-only invariant, retention idiom, down-file ordering). GREEN in CI.
- `tsc --noEmit` + full `vitest run` GREEN (976 test files).

## Behavioral verification (DEV-only, gated)

- `test/beta-crm-dsar.integration.test.ts` — cross-tenant deny + positive owner
  control, empty-lens reject, composite-FK privilege boundary, write→read
  round-trip, last_contact advance-only, upsert transition semantics, CASCADE
  erasure. Runs with `SUPABASE_DEV_INTEGRATION=1` on a **dedicated** dev Supabase
  project (`hr-dev-prd-distinct-supabase-projects`) — NEVER the shared dev
  pre-merge.

## dev apply — deferred to PR CI (canonical path; no manual unmerged apply)

The dev apply runs via the canonical CI migration path
(`apps/web-platform/scripts/run-migrations.sh`, which records the tracking row
`public._schema_migrations` in the same transaction). No manual unmerged apply —
CI is the drift-safe apply, and its run exercises the live RLS/RPC surface the
gated integration tests assert.

## prd apply — pending (post-merge, automated)

Applied automatically on merge to `main` by the `migrate` job in
`.github/workflows/web-platform-release.yml` (runs after `await-ci` green, before
`deploy`). No separate operator step (plan AC19). Post-merge, `/ship` Phase 7
Step 3.6 + the release `verify-migrations` job confirm the tables exist in prd;
`mcp__plugin_supabase_supabase__list_migrations` shows `126`.

## No operator prerequisites

No new Doppler secret, vendor account, or env var — the feature runs entirely
against the already-provisioned Supabase + Anthropic boundary (no new
sub-processor). The `crm_erase_contact` third-party Art. 17 path is an
on-request operator runbook
(`knowledge-base/engineering/operations/runbooks/beta-crm-third-party-erasure.md`),
not a deploy prerequisite.
