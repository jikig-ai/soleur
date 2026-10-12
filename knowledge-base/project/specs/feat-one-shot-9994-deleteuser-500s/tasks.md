# Tasks — feat-one-shot-9994-deleteuser-500s

Derived from `knowledge-base/project/plans/2026-10-12-fix-integration-deleteuser-500s-teardown-plan.md`.
Issue: #9994 · tracker: #9993 (reference only, never close).

## Phase 1 — Setup / evidence re-check

- [x] 1.1 Live probe on dev (DONE at plan time): `admin.createUser` → `admin.deleteUser` →
  `500 unexpected_failure`; direct `DELETE FROM public.users` →
  `23503 workspace_members_user_id_fkey`. Hypothesis 1 confirmed; hypothesis 2 refuted
  (`audit_byok_use_no_mutate` prosrc has the founder_id carve-out); drift filed as #10095.
- [ ] 1.2 Re-read `test/helpers/tenant-isolation-teardown.ts` docblock + `ANONYMISE_SEQUENCE`
  before editing; confirm the six synthetic prefixes needed:
  `tenant-isolation-`, `byok-isolation-`, `beta-crm-`, `cc-cross-tenant-`,
  `conv-rail-cross-tenant-`, `dsar-cross-tenant-`.

## Phase 2 — Helper generalization

- [ ] 2.1 `test/helpers/tenant-isolation-teardown.ts`: replace single-prefix
  `SYNTHETIC_EMAIL_PATTERN` with an exported prefix allowlist (`SYNTHETIC_PREFIXES` → regex),
  keeping the `[a-f0-9]{16}@soleur.test` suffix and the fail-closed refusal for any
  non-allowlisted email. Update docblock (helper serves all synthetic-suite teardowns).
- [ ] 2.2 `test/helpers/tenant-isolation-teardown.test.ts`: positive case per new prefix;
  negative cases for non-allowlisted prefix and non-`soleur.test` domain; keep existing
  throw assertions.

## Phase 3 — Suite adoption (nightly-leg defect sites)

- [ ] 3.1 `test/beta-crm-dsar.integration.test.ts`: `afterAll` → `tearDownTenantUser(service, u)`
  for userA/userB; AC10 → `tearDownTenantUser(service, userA)` then keep the
  all-three-beta-tables-empty assertion + `userA.id = ""`.
- [ ] 3.2 `test/byok.integration.test.ts`: `afterAll` → helper after the existing
  `getUserById` email round-trip check.
- [ ] 3.3 `test/cc-dispatcher-cross-tenant.integration.test.ts`: `afterAll` → helper (keep
  round-trip check).
- [ ] 3.4 `test/conversations-rail-cross-tenant.integration.test.ts`: `afterAll` → helper
  (keep round-trip check).
- [ ] 3.5 `test/dsar-export-cross-tenant.integration.test.ts`: `afterAll` → helper (replaces
  the best-effort swallow — teardown becomes fail-loud by design).

## Phase 4 — workspace_id insert repair (fold-in, same leg)

- [ ] 4.1 `test/cc-dispatcher-cross-tenant.integration.test.ts`: every `from("conversations")`
  and `from("messages")` insert sets `workspace_id` (= the owning user's id, the
  trigger-created solo workspace per ADR-038 N2). Extend `assistantRowFor` to carry
  `workspace_id`, or set it per call site.
- [ ] 4.2 `test/conversations-rail-cross-tenant.integration.test.ts`: same sweep for
  `conversations` inserts (~lines 209, 269, and any site the Phase 4 grep surfaces).
- [ ] 4.3 Run the plan's Phase 4 verification command → every insert site covered.

## Phase 5 — Recurrence sentinel

- [ ] 5.1 Create `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts` per the
  plan's `## Guard Contract` (census over `test/*.integration.test.ts` + `test/helpers/*.ts`
  for `\.admin\.deleteUser\(`; allowlist = 2 helpers + 4 manual-FK-reverse suites + mu1 with a
  `#9995`-revisit comment; anti-vacuity floor ≥1).
- [ ] 5.2 Exercise the mutation matrix: ≥1 RED-driving mutation demonstrated (e.g., scratch
  file with raw `deleteUser` → suite red; emptied allowlist → red; zero-match regex → red).

## Phase 6 — Verification

- [ ] 6.1 Local leg run (AC1): `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env SUPABASE_DEV_INTEGRATION=1 npm run test:ci -- test/beta-crm-dsar.integration.test.ts test/cc-dispatcher-cross-tenant.integration.test.ts test/conversations-rail-cross-tenant.integration.test.ts test/dsar-author-redaction.integration.test.ts test/dsar-export-cross-tenant.integration.test.ts test/server/conversation-visibility.tenant-isolation.test.ts --project unit --reporter=verbose` → exit 0.
- [ ] 6.2 Local leg run (AC2): `doppler run -p soleur -c dev_scheduled -- env BYOK_INTEGRATION_TEST=1 npm run test:ci -- test/byok.integration.test.ts --project unit` → exit 0.
- [ ] 6.3 `npx vitest run test/server/teardown-deleteuser-sentinel.test.ts test/helpers/tenant-isolation-teardown.test.ts test/server/teardown-anonymise-parity.test.ts --project unit` → green.
- [ ] 6.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.

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
