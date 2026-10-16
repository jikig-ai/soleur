# Tasks — feat-one-shot-10254-action-sends-message-id

Plan: `knowledge-base/project/plans/2026-10-15-fix-action-sends-message-id-erasure-plan.md`
Issue: #10254 (ruled option (b) — migration 162, mirroring 161). Do NOT
expand scope to `action_sends.grant_id` (#10379 covers the audit).

## Phase 1 — Migration 162 (forward + down + verify)

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/162_action_sends_message_id_cascade_null_carveout.sql`
  - `to_regclass` precondition block for `public.action_sends` AND `public.messages` (lint-migration-fk-preconditions.sh)
  - `ALTER TABLE public.action_sends ALTER COLUMN message_id DROP NOT NULL`
  - `DROP CONSTRAINT action_sends_message_id_fkey` + re-add `FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL NOT VALID` + `VALIDATE CONSTRAINT action_sends_message_id_fkey` (zero-downtime form — see plan `## Downtime & Cutover`)
  - `DROP TRIGGER IF EXISTS action_sends_no_update` + recreate `BEFORE UPDATE OF` the 11 non-message_id pre-064 columns `FOR EACH STATEMENT`
  - `CREATE TRIGGER action_sends_message_id_guard BEFORE UPDATE OF message_id FOR EACH ROW EXECUTE FUNCTION public.action_sends_no_mutate()`
  - `CREATE OR REPLACE FUNCTION action_sends_no_mutate()` — 087 bypass first; `TG_OP='DELETE'` P0001; carve-out branch gated `TG_OP='UPDATE' AND TG_LEVEL='ROW'` (REQUIRED — the same function serves the statement triggers where OLD/NEW are unassigned); carve-out = `OLD.message_id IS NOT NULL AND NEW.message_id IS NULL AND (to_jsonb(NEW)-'message_id')=(to_jsonb(OLD)-'message_id') AND NOT EXISTS (SELECT 1 FROM public.messages WHERE id = OLD.message_id)`; final raise P0001
  - `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated, service_role`
  - `COMMENT ON FUNCTION` + `COMMENT ON COLUMN message_id` (NULL = de-linked state)
  - `CREATE OR REPLACE FUNCTION anonymise_action_sends` — add `message_id = NULL` to the UPDATE's SET list inside the existing `app.worm_bypass` window; auth checks + re-arm unchanged
- [ ] 1.2 Create `162_*.down.sql` — restore 087 function body, 064 12-column trigger, `SET NOT NULL` + NO ACTION FK, drop `action_sends_message_id_guard`, restore pre-162 `anonymise_action_sends`; carry the reinstatement WARNING (161 style); note `SET NOT NULL` fails while NULL rows exist
- [ ] 1.3 Create `supabase/verify/162_action_sends_message_id_cascade_null_carveout.sql` — one `(check_name, bad)` row per check using `CASE WHEN EXISTS(...) AND <cond> THEN 0 ELSE 1 END` (always emits; missing object = bad=1, never absent row): FK `confdeltype='n'`; `message_id` is_nullable; row-level trigger present; carve-out + `NOT EXISTS`/`public.messages` in `action_sends_no_mutate` prosrc; `app.worm_bypass` preserved; `message_id = NULL` in `anonymise_action_sends` prosrc
- [ ] 1.4 `bash apps/web-platform/scripts/lint-migration-fk-preconditions.sh <162 file>` → rc 0 (command verified at plan time)

## Phase 2 — Offline shape test

- [ ] 2.1 Create `apps/web-platform/test/supabase-migrations/162-action-sends-message-id-cascade-null-carveout.test.ts` mirroring the 161 test; pins per Guard-2 assembly (DEFINER+search_path, bypass-before-raise, DELETE raise, four conjuncts, `TG_LEVEL='ROW'` gate, statement trigger's 11-col list excludes message_id, row-level trigger exists, RPC sets `message_id = NULL`, COMMENTs, down restores 087 body + 12-col trigger)
- [ ] 2.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/162-action-sends-message-id-cascade-null-carveout.test.ts` → green (deps permitting — npm registry unreachable on planning host)

## Phase 3 — Tolerance removal + integration coverage

- [ ] 3.1 `test/helpers/tenant-isolation-teardown.ts`: delete `hasUndeletableActionSendsAnchor` + its #10254 doc block (~lines 309-339); KEEP the generic `tolerate:` option (other callers + unit test)
- [ ] 3.2 `test/server/action-sends-worm.test.ts`: remove `tolerate:` block (~197-205); add — (a) direct `UPDATE ... SET message_id=NULL` while parent message lives → P0001; (b) anonymise clears `message_id` too; (c) DELETE still P0001
- [ ] 3.3 `test/server/template-authorizations-worm.test.ts`: remove `tolerate:` block (~185-188)
- [ ] 3.4 (REQUIRED per CTO ruling 2026-10-15) `test/server/account-delete.cascade.integration.test.ts`: extend fixture with one seeded `action_sends` row — ancestors first: `scope_grants` row (`grant_id NOT NULL`), fresh `messages` row owned by the test user (`action_sends_message_unique` forbids shared messages), then the send row (service-role INSERTs or `write-action-send` path); post-delete assertion mirrors `audit_byok_use`: row survives, `message_id IS NULL`

## Phase 4 — Legal-doc parity

- [ ] 4.1 `docs/legal/data-protection-disclosure.md` §2.3(r): trigger no longer "pure-reject" on UPDATE (Art-17 cascade carve-out); retention sentence gains `message_id = NULL`
- [ ] 4.2 `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`: mirror 4.1 (legal-doc-consistency parity)
- [ ] 4.3 `knowledge-base/legal/article-30-register.md`: update action_sends TOM/retention rows (~lines 344, 421) — record the carve-out; fix stale `session_replication_role` mention → `app.worm_bypass`; preserve the "carve-out is transition-bound, not role-bound" distinction (service_role does NOT gain a privilege surface)

## Phase 5 — Verification

- [ ] 5.1 Local: lint (1.4), shape test (2.2), `markdownlint` on edited docs
- [ ] 5.2 Deployed surface (CI/release pipeline): dev apply → `run-verify.sh` all `bad=0`; `TENANT_INTEGRATION_TEST=1` worm suites green sans tolerances; cascade integration test green
