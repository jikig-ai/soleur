# Migration Checklist — feat-agent-native-outbound-email (#5325)

Migration: `apps/web-platform/supabase/migrations/104_outbound_email.sql`
Verify sentinel: `apps/web-platform/supabase/verify/104_outbound_email.sql`

## Scope

Net-new schema is two tables + their SECURITY DEFINER RPCs:
- `email_suppression` + `suppress_recipient` / `is_recipient_suppressed` /
  `anonymise_email_suppression` (per-founder permanent suppression set).
- `outbound_sends` (WORM cold-send audit) + `record_outbound_send` /
  `anonymise_outbound_sends` + the `outbound_sends_no_mutate` trigger fn.

**ADR-060 substrate decision (CTO).** The plan's deepen P0-1 mandated reusing
`public.action_sends` (migration 051) for the send-audit + body-hash approval and
forbade an `outbound_sends` table. At /work, tracing the actual producer falsified
that premise: `action_sends.message_id` is a `NOT NULL` FK to `public.messages`
with `UNIQUE(message_id)` — built for the founder-clicks-Send-on-a-draft path —
and the agent tool path has NO `messages.id` at tool-exec time (the tool runs
inside the SDK iterator; the assistant message is persisted only at the `result`
event; the tool closure carries `userId` only). `scope_grants` creation is
UI-only. The `soleur:engineering:cto` agent ruled a **dedicated `outbound_sends`
WORM table** (mirroring the proven `action_sends` posture, NOT FK'd to messages),
overturning the plan's "no new table" rule. Body-binding is enforced by the
chokepoint recomputing `per_send_body_sha256` and rejecting on mismatch vs the
gated-review `approved_body_sha256` (the RPC also rejects a mismatch — defense in
depth). Rejected alternatives (action_sends reuse; gate-only no-WORM) are recorded
in ADR-060. No `action_sends`/`scope_grants` alteration; no TS `ActionClass`
union widening (`outbound_sends.action_class` is free text with the enum-ABSENCE
CHECK, defaulting to `marketing.outreach`).

## Security hardening (2026-06-15, automated review #5325)

Background security review flagged `anonymise_outbound_sends` as HIGH
(Authorization / Audit-Trail Tampering) for granting `authenticated` a
self-service erasure path (`auth.uid() = p_user_id`). Valid: `outbound_sends`
is third-party-facing accountability evidence, so a founder self-wiping it is
tampering (distinct from the `action_sends` precedent, which is the founder's own
action log). Fixed BOTH erasure RPCs to **service-role-only** (dropped the
`authenticated` grant + the self-call branch) — `anonymise_email_suppression`
shares the class (wiping the suppression set could re-enable opted-out sends).
The only Art-17 trigger is full account deletion via `service.rpc(...)` in
`server/account-delete.ts` (steps 3.93/3.94, wired this session BEFORE
`auth.admin.deleteUser` so the `owner_id` ON DELETE RESTRICT FK does not block).
`verify/104` checks (19)/(20) assert NOT-executable-by-authenticated.

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

`recipient_hash = HMAC-SHA-256(EMAIL_HASH_PEPPER, normalize(extractAddrSpec(email)))`
is computed in `server/email-triage/outbound-compliance.ts` (Phase 2).
`EMAIL_HASH_PEPPER` must exist in Doppler (all envs) before the chokepoint can
hash; it is NOT a migration concern (the table stores opaque text). Tracked as a
Phase 2 / pre-send precondition, not a schema step.

**EMAIL_HASH_PEPPER is ROTATION-FORBIDDEN (suppression-bypass risk; review #5325).**
Rotating the pepper orphans every existing `email_suppression` + `outbound_sends`
row — the new-pepper hash of a previously-suppressed address no longer matches the
stored hash, so `is_recipient_suppressed` silently returns false and a
previously-opted-out contact is re-mailed (CAN-SPAM/GDPR incident) with no error.
If a rotation is ever genuinely required, it MUST be paired with a re-hash
migration (version-tagged hashes + backfill) — never a bare secret rotation.
Document the pepper as non-rotatable in the Doppler secret description.
