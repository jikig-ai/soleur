# Tasks — feat-one-shot-10096-deleteuser-teardown-gaps

Plan: `knowledge-base/project/plans/2026-10-13-fix-deleteuser-teardown-gaps-plan.md`
Issue: #10096 (closes) · umbrella: #9993 (stays open) · related: #9994 (merged
PR #10090), #9995 (mu1 owner, untouched), #3934 (deferred sweeper)

## 1. Phase 1 — Helper prefix allowlist

- [ ] 1.1 Append `"workspace-backfill-parity-"` to `SYNTHETIC_PREFIXES` in
  `apps/web-platform/test/helpers/tenant-isolation-teardown.ts` (+ docblock note). (AC3)
- [ ] 1.2 Append the same literal to `EXPECTED_PREFIXES` in
  `apps/web-platform/test/helpers/tenant-isolation-teardown.test.ts` — the
  set-equality census pins the two lists. (AC3)
- [ ] 1.3 Confirm the `[a-f0-9]{16}@soleur.test` suffix pin is unchanged
  (fail-closed boundary; PR #2597 class).

## 2. Phase 2 — Migrate the 15 drain files to `tearDownTenantUser`

Uniform edit: add
`import { tearDownTenantUser } from "@/test/helpers/tenant-isolation-teardown";`,
keep each suite's own `assertSynthetic`, replace the raw `deleteUser` call with
`await tearDownTenantUser(service, user)` — LOUD, no `try/catch`/`.catch`
wrapper. (AC2)

`.catch(() => {})` swallow suites (afterAll loops, straight swap):
- [ ] 2.1 `server/attachment-pipeline.tenant-isolation.test.ts` (call ~184; keep
  storage `.remove()` of `victimPath`)
- [ ] 2.2 `server/cc-dispatcher.tenant-isolation.test.ts` (call ~121)
- [ ] 2.3 `server/conversations-tools.tenant-isolation.test.ts` (call ~123)
- [ ] 2.4 `server/current-repo-url.tenant-isolation.test.ts` (call ~101)
- [ ] 2.5 `server/kb-document-resolver.tenant-isolation.test.ts` (call ~114)
- [ ] 2.6 `server/kb-route-helpers.tenant-isolation.test.ts` (call ~115)
- [ ] 2.7 `server/lookup-conversation-for-path.tenant-isolation.test.ts` (call ~112)
- [ ] 2.8 `server/ws-handler.tenant-isolation.test.ts` (call ~117)

Unchecked / try-catch-swallow suites:
- [ ] 2.9 `server/action-sends-worm.test.ts` — afterAll loop (~204): drop the
  `anonymise_action_sends` + `anonymise_scope_grants` try/catch pair AND the
  deleteUser try/catch → one helper call per user; in-test throwaway site (~451):
  same swap.
- [ ] 2.10 `server/email-triage-worm.test.ts` — afterAll (~194) and in-test
  throwaway user (~579); leave the `workspace_members` row-delete in the (j)
  `finally` untouched.
- [ ] 2.11 `server/template-authorizations-worm.test.ts` — afterAll (~195): the
  three manual anonymise RPCs + deleteUser → one helper call per user.
- [ ] 2.12 `server/tenant-jwt-deny.tenant-isolation.test.ts` — TWO afterAlls
  (~102, ~248): keep the `denied_jti` row delete, swap `deleteUser` → helper.
- [ ] 2.13 `server/scope-grants/lifecycle.test.ts` — afterAll (~111): replace
  bare `deleteUser(userA.id)`; delete now succeeds even when the suite fails
  before its step-7 anonymise.
- [ ] 2.14 `server/workspace-member-revocation.tenant-isolation.test.ts` —
  in-test (~360): replace `workspace_members.delete().eq("user_id", dId)` +
  `deleteUser(dId)` with `tearDownTenantUser(service, {id: dId, email: dEmail})`
  (D's email is `workspace-fixture-` — already allowlisted).
- [ ] 2.15 `server/workspace-backfill-trigger-parity.test.ts` — afterAll
  (~105–125): replace the 4-step try/catch manual FK-reverse (members →
  workspaces → organizations → deleteUser) with one helper call; requires the
  Phase-1 prefix.
- [ ] 2.16 Timeout sweep: any `afterAll` looping ≥2 users under `30_000` → bump
  to `60_000` (helper ≈ 24 sequential round-trips/user).

## 3. Phase 3 — Drain the sentinel ratchet

- [ ] 3.1 In `server/teardown-deleteuser-sentinel.test.ts`: remove all 15 entries
  from `KNOWN_LEGACY_CARRIERS` AND `EXPECTED_CALL_COUNTS` (same commit as §2 —
  stale-entry/count-pin tests force it). Keep the empty set + a "drained by
  #10096" comment as the standing mechanism. (AC1)
- [ ] 3.2 Update the sentinel docblock: `test/server/**` "tracked for drain by
  #10096" → drained; enumerated set = 6 (1 canonical + 5 manual allowlist). (AC1)

## 4. Phase 4 — Verification

- [ ] 4.1 `npx vitest run test/server/teardown-deleteuser-sentinel.test.ts
  test/helpers/tenant-isolation-teardown.test.ts --project unit` → green. (AC1, AC3)
- [ ] 4.2 Mutation self-check: add a scratch raw `deleteUser(` in a
  non-enumerated file → sentinel offender test RED; revert. (AC1)
- [ ] 4.3 Confirm `tenant-integration` job runs on the PR (helpers/ is anchored
  in the detect-changes filter) and goes green — real dev teardown proof;
  zero `Database error deleting user` in output. (AC4)
- [ ] 4.4 Optional local corroboration (needs doppler):
  `doppler run -p soleur -c dev_scheduled -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/ --project unit --project repo-wide` → exit 0. (AC4)
- [ ] 4.5 Boundary diff check: `git diff origin/main -- apps/web-platform/server
  apps/web-platform/supabase .github` is empty. (AC5)

## 5. Phase 5 — Bookkeeping

- [ ] 5.1 Comment on #10096: true census (15 files/18 call sites vs "~18"),
  sentinel-scope premise update (already recursive via KNOWN_LEGACY_CARRIERS
  ratchet), third-shape finding (3 byok suites' deliberate-leak comments are
  stale pre-helper — #3934 territory). (AC6)
- [ ] 5.2 Reference #9993; verify it remains OPEN. (AC6)
- [ ] 5.3 PR body carries `Closes #10096`. (AC6)
