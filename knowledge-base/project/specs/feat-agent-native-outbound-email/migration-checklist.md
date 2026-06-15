# Migration Checklist — feat-agent-native-outbound-email (#5325)

Migration: `apps/web-platform/supabase/migrations/104_outbound_email.sql`
Verify sentinel: `apps/web-platform/supabase/verify/104_outbound_email.sql`

## Scope

Net-new schema is ONLY `email_suppression` + its three SECURITY DEFINER RPCs
(`suppress_recipient`, `is_recipient_suppressed`, `anonymise_email_suppression`).
The send-audit + body-hash approval binding **reuses** `public.action_sends`
(migration 051) unchanged — no `outbound_sends` table, no enum widening,
no `action_sends`/`scope_grants` alteration. `action_sends.action_class` admits
`marketing.outreach` via its enum-ABSENCE CHECK (`!~ '^(payment|legal|auth)\.'`),
verified against `051_action_class_widening_and_action_sends.sql:104-106`.

## Resume verification (2026-06-15)

Migration 104 was authored + committed in a prior session but NOT applied.
On resume, re-derived against the contract and the existing lint:

- **Defect found + fixed:** all three RPCs originally `REVOKE ALL … FROM PUBLIC, anon`
  (missing `authenticated`). The generalised `test/migration-rpc-grants.test.ts`
  requires the union of revoked roles to contain `{public, anon, authenticated}`
  (Supabase's `ALTER DEFAULT PRIVILEGES` grants EXECUTE to `authenticated` by
  default, so the named-role REVOKE is load-bearing —
  `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`). As
  committed, 104 would have failed that existing test. Fixed to
  `FROM PUBLIC, anon, authenticated` then re-GRANT, matching mig 051
  `grant_action_class`/`anonymise_action_sends`.
- Contract pinned by `test/supabase-migrations/104-outbound-email.test.ts`
  (18 file-parse assertions: table shape, UNIQUE index, owner-SELECT RLS,
  REVOKE writes, ON CONFLICT DO NOTHING, auth.uid() pin, Art-17 tombstone,
  HMAC determinism comment, no-un-suppress negative-space, down-migration).
- `test/migration-rpc-grants.test.ts`: PASS (439/439) including 104's RPCs.

## dev apply — deferred to PR CI (canonical path; no manual unmerged apply)

The dev apply runs in `.github/workflows/tenant-integration.yml`
("Apply migrations to dev" step) on every `pull_request` to main: it invokes
`apps/web-platform/scripts/run-migrations.sh` against the `dev_scheduled`
Doppler config (environment=dev) with `ALLOW_UNMERGED_DEV_APPLY=1` — the
documented legitimate apply path for a PR's own in-flight migration.

Manual hand-rolled `psql`/pg apply was deliberately NOT performed: applying an
unmerged migration to the shared dev project creates dev-vs-main drift that must
be reverted before push (`2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`,
#4241). CI is the drift-safe apply, and its run exercises the live RLS /
auth.uid() / upsert-idempotency behavior against real Postgres that file-parse
tests cannot.

## prd apply — pending (post-merge, automated)

Applied automatically by `.github/workflows/web-platform-release.yml` (job:
`migrate-apply-web-platform`) on merge of PR #5326. The release workflow's
`verify-migrations` job then runs `verify/104_outbound_email.sql` post-apply
against prd as the canonical runtime sentinel (10 checks, all must return
`bad=0`). Operator does NOT apply manually.

## EMAIL_HASH_PEPPER (Doppler) — required before first send

`recipient_hash = HMAC-SHA-256(EMAIL_HASH_PEPPER, normalize(email))` is computed
in `server/email-triage/outbound-compliance.ts` (Phase 2). `EMAIL_HASH_PEPPER`
must exist in Doppler (all envs) before the chokepoint can hash; it is NOT a
migration concern (the table stores opaque text). Tracked as a Phase 2 / pre-send
precondition, not a schema step.
