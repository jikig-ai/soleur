# Tasks — feat-one-shot-9994-deleteuser-500s

Derived from `knowledge-base/project/plans/2026-10-12-fix-integration-deleteuser-500s-teardown-plan.md`.
Issue: #9994 · tracker: #9993 (reference only, never close).

## Phase 1 — Setup / evidence re-check

- [x] 1.1 Live probe on dev (DONE at plan time): `admin.createUser` → `admin.deleteUser` →
  `500 unexpected_failure`; direct `DELETE FROM public.users` →
  `23503 workspace_members_user_id_fkey`. Hypothesis 1 confirmed; hypothesis 2 refuted
  (`audit_byok_use_no_mutate` prosrc has the founder_id carve-out); drift filed as #10095.
- [x] 1.2 Re-read `test/helpers/tenant-isolation-teardown.ts` docblock + `ANONYMISE_SEQUENCE`
  before editing; confirm the six synthetic prefixes needed:
  `tenant-isolation-`, `byok-isolation-`, `beta-crm-`, `cc-cross-tenant-`,
  `conv-rail-cross-tenant-`, `dsar-cross-tenant-`.

## Phase 2 — Helper generalization

- [x] 2.1 `test/helpers/tenant-isolation-teardown.ts`: replace single-prefix
  `SYNTHETIC_EMAIL_PATTERN` with an exported prefix allowlist (`SYNTHETIC_PREFIXES` → regex),
  keeping the `[a-f0-9]{16}@soleur.test` suffix and the fail-closed refusal for any
  non-allowlisted email. Update docblock (helper serves all synthetic-suite teardowns).
- [x] 2.2 `test/helpers/tenant-isolation-teardown.test.ts`: positive case per new prefix;
  negative cases for non-allowlisted prefix and non-`soleur.test` domain; keep existing
  throw assertions.

## Phase 3 — Suite adoption (nightly-leg defect sites)

- [x] 3.1 `test/beta-crm-dsar.integration.test.ts`: `afterAll` → `tearDownTenantUser(service, u)`
  for userA/userB; AC10 → `tearDownTenantUser(service, userA)` then keep the
  all-three-beta-tables-empty assertion + `userA.id = ""`.
- [x] 3.2 `test/byok.integration.test.ts`: `afterAll` → helper after the existing
  `getUserById` email round-trip check.
- [x] 3.3 `test/cc-dispatcher-cross-tenant.integration.test.ts`: `afterAll` → helper (keep
  round-trip check).
- [x] 3.4 `test/conversations-rail-cross-tenant.integration.test.ts`: `afterAll` → helper
  (keep round-trip check).
- [x] 3.5 `test/dsar-export-cross-tenant.integration.test.ts`: `afterAll` → helper (replaces
  the best-effort swallow — teardown becomes fail-loud by design).

## Phase 4 — workspace_id insert repair (fold-in, same leg)

- [x] 4.1 `test/cc-dispatcher-cross-tenant.integration.test.ts`: every `from("conversations")`
  and `from("messages")` insert sets `workspace_id` (= the owning user's id, the
  trigger-created solo workspace per ADR-038 N2). `assistantRowFor` extended with a
  `workspaceId` arg; all 6 call sites pass the owning user's id; the T-RLS3 direct
  insert and the T-W3 reseed set it inline.
- [x] 4.1a `test/cc-dispatcher-cross-tenant.integration.test.ts` (discovered at work
  time): `assistantRowFor` also omitted `template_id` — NOT NULL, no default
  (`public.messages`, confirmed via information_schema scoped to `public`; the
  earlier probe's `extension`/`topic` rows belong to a non-public `messages`
  table). Set `template_id: "default_legacy"` — mirrors production's
  `server/cc-dispatcher.ts` `buildRow`.
- [x] 4.2 `test/conversations-rail-cross-tenant.integration.test.ts`: same sweep for
  `conversations` inserts (~lines 209, 269, and any site the Phase 4 grep surfaces).
- [x] 4.3 Run the plan's Phase 4 verification command → every insert site covered.

## Phase 5 — Recurrence sentinel

- [x] 5.1 Create `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts` per the
  plan's `## Guard Contract` (census over `test/*.integration.test.ts` + `test/helpers/*.ts`
  for `\.admin\.deleteUser\(`; allowlist = 2 helpers + 4 manual-FK-reverse suites + mu1 with a
  `#9995`-revisit comment; anti-vacuity floor ≥1). Post-fix census: 7 carriers.
- [x] 5.2 Exercise the mutation matrix: scratch carriers in BOTH scope dirs
  (`test/*.integration.test.ts`, `test/helpers/*.ts`) drove the offender assertion
  RED with the correct named file; files removed after the run.

## Phase 5b — Scope expansion discovered at work time (operator-approved)

The dsar-export leg surfaced two defects invisible at plan time:

- [x] 5b.1 **Dev drift (second #10095-class instance):** `dsar_export_jobs.user_id` and
  `dsar_export_audit_pii.user_id` carried `NO ACTION` FKs + `NOT NULL` on dev, while
  main (mig 041) and prd declare `ON DELETE SET NULL` + nullable. Operator approved a
  class-C reconcile (exact ALTERs shown before running): mutex + ledger backup
  (`/var/tmp/dev-9994/`) + single transaction → both FKs now `SET NULL`, columns
  nullable. Evidence: `constraints-before.txt`, post-verify census.
- [x] 5b.2 **Latent prod bug — WORM trigger vs. the FK's own cascade:**
  `dsar_export_audit_pii_no_mutate` raised P0001 on the `SET NULL` cascade's internal
  `UPDATE ... SET user_id = NULL` (GoTrue's transaction can't set `app.worm_bypass`).
  True on main + prd: `auth.admin.deleteUser` 500s for every user with an
  export-audit row — a latent Art. 17 erasure defect never exercised because the
  suites were dormant until #9855.
  Fix: migration `160_dsar_export_audit_pii_cascade_null_carveout.sql` +
  `.down.sql` — `CREATE OR REPLACE FUNCTION` adding the `user_id` NOT-NULL→NULL
  carve-out mirroring `audit_byok_use_no_mutate`'s `founder_id` gate (mig 087);
  DELETE still universally blocked; `app.worm_bypass` exemption preserved;
  SECURITY DEFINER + `SET search_path = public, pg_temp`. Applied to dev (no
  ledger row — the runner owns ledger writes on merge; CREATE OR REPLACE is
  idempotent). Issue-filing gate ruled it inline-sized (≤100 lines).
- [x] 5b.3 End-to-end proof on real rows: the two users leaked by the pre-fix
  failures (each holding jobs + audit_pii rows) deleted via
  `auth.admin.deleteUser` after the carve-out — the exact path that 500'd.

## Phase 6 — Verification

- [x] 6.1 Local leg run (AC1): `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env SUPABASE_DEV_INTEGRATION=1 npm run test:ci -- test/beta-crm-dsar.integration.test.ts test/cc-dispatcher-cross-tenant.integration.test.ts test/conversations-rail-cross-tenant.integration.test.ts test/dsar-author-redaction.integration.test.ts test/dsar-export-cross-tenant.integration.test.ts test/server/conversation-visibility.tenant-isolation.test.ts --project unit --reporter=verbose` → exit 0.
- [x] 6.2 Local leg run (AC2): `doppler run -p soleur -c dev_scheduled -- env BYOK_INTEGRATION_TEST=1 npm run test:ci -- test/byok.integration.test.ts --project unit` → exit 0.
- [x] 6.3 `npx vitest run test/server/teardown-deleteuser-sentinel.test.ts test/helpers/tenant-isolation-teardown.test.ts test/server/teardown-anonymise-parity.test.ts --project unit` → green.
- [x] 6.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.

## Phase 7 — Issue bookkeeping

- [ ] 7.1 Comment on #9994: probe evidence (named constraint `workspace_members_user_id_fkey`,
  census summary, hypothesis 2 refuted, fix shape).
- [ ] 7.2 Comment on #9995: mu1's raw `deleteUser` (~line 183) will hit the same RESTRICT once
  its 401 is fixed; point at #9994's fix shape + #10095 (mu1-relevant drift).
- [ ] 7.3 PR body: `Closes #9994`, `Ref #9993`, `Ref #10094`, `Ref #10095`, `Ref #10096` —
  never `Closes #9993`.

## Already done at plan time

- [x] Filed #10094 (slot-trigger `cap_hit` + worktree-lease `acquire` failures — separate legs,
  separate root cause).
- [x] Filed #10095 (`audit_github_token_use.founder_id` RESTRICT-on-dev drift reconcile).
- [x] Filed #10096 (latent `test/server/**` deleteUser teardown gap).
- [x] Live probe: constraint named, hypothesis 2 refuted, no second minimal-path blocker.
