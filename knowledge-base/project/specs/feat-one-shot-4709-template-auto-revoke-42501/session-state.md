# Session State — #4709 template auto-revoke 42501 fix

## Status: PAUSED for clean-session restart (2026-05-31)

Tool output in the originating session was delayed/batched and intermittently
contaminated (node-deprecation warnings prepended to Read results). This caused
two false intermediate conclusions that were later caught and corrected:
- "migration 089 applied to DEV / GREEN 20/20" — FALSE. `psql` and `pg` are both
  ABSENT; the apply exited 127 and the rewritten test failed to import `pg`.
  **DEV was never modified.**
- A destructive edit: the comprehensive existing integration test
  `apps/web-platform/test/server/template-authorizations-worm.test.ts`
  (PR-I #4078, supabase-js + `TENANT_INTEGRATION_TEST=1` harness) was overwritten
  with a `pg`-based rewrite, because the initial Read returned contaminated content.
  **RECOVERED**: restored verbatim from git HEAD (`git diff HEAD` on that file is
  now empty). Do not re-overwrite it — extend it in place.

## What IS done and trustworthy
- **Design decision: Approach 2** (narrow RPC carve-out; re-derive expiry/quota
  server-side). **CTO + CPO both signed off** (recorded in the plan, Implementation
  Step 2). Approach 1 (service-role) rejected: under service role the RPC's
  `WHERE founder_id = COALESCE(v_founder_id, founder_id)` degrades to always-true
  → cross-tenant over-reach.
- **Migration written** (NOT applied): `089_template_auto_revoke_carveout.sql` +
  `.down.sql`. Adds the carve-out: authed founder may revoke own row with
  `expired`/`quota_exhausted` ONLY when the RPC re-derives the dead state; every
  other authed non-`founder_revoked` reason still 42501; service-role path
  unchanged; WORM bracket + `search_path` + grants mirror 088; same `(text,text)`
  signature (CREATE OR REPLACE, no DROP).
- **No TS change** — `is-template-authorized.ts` keeps the authenticated client
  (correct for Approach 2). Confirmed `git diff HEAD` empty for that file.
- Plan updated; draft PR #4711 open.

## What REMAINS (do in clean session)
1. Apply migration 089 to DEV (no psql/pg on PATH): use Supabase MCP
   `apply_migration` (needs `mcp__plugin_supabase_supabase__authenticate` first),
   OR `npm i -D pg` then node-pg via Doppler `DATABASE_URL_POOLER` rewritten
   `:6543`→`:5432` (session mode), wrapping `BEGIN; <089>; INSERT INTO
   public._schema_migrations(filename,content_sha) VALUES(...); COMMIT;`.
2. RED→GREEN: EXTEND the existing `template-authorizations-worm.test.ts`
   (supabase-js harness; gated `TENANT_INTEGRATION_TEST=1`, run via
   `doppler run -p soleur -c dev`). Add carve-out cases:
   - authed `expired` on genuinely-expired self-owned row → persists (RED pre-089: 42501).
   - authed `quota_exhausted` genuinely over-quota → persists.
   - anti-spoof: authed `expired` on non-expired row → 42501.
   - anti-spoof: authed `quota_exhausted` under-quota → 42501.
   - gate preserved: authed `policy_violation` → 42501.
   - cross-tenant: A cannot revoke B's row.
   Seeding an expired/over-quota row in this harness is the tricky part (WORM
   blocks direct UPDATE of expires_at; `authorize_template` sets bounds). Confirm
   `authorize_template`'s default `max_sends` and whether a low-max path exists
   before writing the quota RED; for the expired case a service-role+worm_bypass
   seed path or a test-helper RPC may be required.
3. Run the existing parity/WORM tests green:
   `revocation-reason-exhaustive.test.ts`, the 088 migration test.
4. gdpr-gate (Phase 2 exit), full review, qa, compound, ship.

## Restart command
`/soleur:work knowledge-base/project/plans/2026-05-31-fix-template-auto-revoke-42501-founder-gate-plan.md`
(from inside this worktree). DEV is clean; no migration rollback needed.
