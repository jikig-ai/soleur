---
title: "tasks: jti-revoke-rls #3930 + #3932"
date: 2026-05-25
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-25-feat-jti-revoke-rls-3930-3932-plan.md
---

# Tasks — JTI revoke RPC + my_revocation_status reader + PostgREST RLS jti-deny predicate

## Phase 0 — Preconditions

- [ ] 0.1 Verify worktree CWD = `.worktrees/feat-one-shot-jti-revoke-rls-3930-3932`
- [ ] 0.2 Verify mig 037 SHA unchanged since PR-E merge
- [ ] 0.3 Verify `users.role` enum still `{prd, dev}` (no admin role added)
- [ ] 0.4 Verify migration number 068 unclaimed by sibling worktree
- [ ] 0.5 Read sibling precedent `check_my_revocation` in mig 067
- [ ] 0.6 Confirm `is_jti_denied(uuid) TO authenticated` GRANT addition is required

## Phase 1 — Migration 068 (TDD)

- [ ] 1.1 RED — Author `apps/web-platform/test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts` with 5+ scenarios
- [ ] 1.2 GREEN — Author `apps/web-platform/supabase/migrations/068_jti_deny_rls_predicate_and_revoke_rpc.sql`
  - [ ] 1.2.1 `revoke_jti(uuid, uuid, text)` — service-role-only
  - [ ] 1.2.2 `my_revocation_status()` — authenticated, mirrors mig 067 shape
  - [ ] 1.2.3 `is_jti_denied_from_jwt()` — STABLE, authenticated, reads jwt.claims
  - [ ] 1.2.4 19 × RESTRICTIVE policies (`<table>_jti_not_denied`)
  - [ ] 1.2.5 `GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated`
- [ ] 1.3 Verify RED tests now GREEN
- [ ] 1.4 Author `068_jti_deny_rls_predicate_and_revoke_rpc.down.sql`; apply forward+rollback
- [ ] 1.5 REFACTOR — DRY the 19 RESTRICTIVE policies via `DO $$ LOOP $$` if pure-duplicate prose
- [ ] 1.6 Author `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` post-apply CI sentinel (mirror `verify/054_*.sql` shape; UNION-ALL of `check_name + bad::int` rows asserting the 3 functions exist + 19 RESTRICTIVE policies + REVOKE/GRANT matrix)

## Phase 2 — Operator CLI (mirror `byok-revoke.ts` sibling precedent)

- [ ] 2.1 RED — Unit test for `scripts/revoke-jti.ts` at `apps/web-platform/test/scripts/revoke-jti.test.ts`, using `spawnSync("bun", [SCRIPT_PATH, ...args])` per `test/scripts/hash-user-id.test.ts:20-46` precedent
- [ ] 2.2 GREEN — Author `apps/web-platform/scripts/revoke-jti.ts`
  - [ ] `#!/usr/bin/env bun` shebang (NOT `npx tsx`)
  - [ ] Named-flag argv: `--jti --founder-id --reason --yes`
  - [ ] Missing flag → exit 2 with `::error::missing required flag <name>` on stderr (matches `byok-revoke.ts:42`)
  - [ ] UUID-shape gate on `--jti` and `--founder-id` BEFORE any DB write (avoids 22P02)
  - [ ] `createServiceClient()` from `@/lib/supabase/service`
  - [ ] `createChildLogger("revoke-jti")` from `@/server/logger` for structured logs
  - [ ] Print target Supabase URL to STDOUT (not stderr — operator-protection signal) BEFORE write
  - [ ] `createInterface(node:readline/promises)` confirm prompt unless `--yes`
  - [ ] Post-RPC re-read via `from("denied_jti").select(...).eq("jti", args.jti).maybeSingle()`; founder_id mismatch → exit 1
  - [ ] NO Sentry breadcrumb (the `denied_jti` row IS the WORM audit trail; runtime mirror fires when deny HIT happens at PostgREST-deny time)
- [ ] 2.3 Smoke against dev Supabase (NOT prd): `doppler run -p soleur -c dev -- bun run apps/web-platform/scripts/revoke-jti.ts --jti <synth-uuid> --founder-id <dev-founder> --reason "deepen-plan smoke" --yes`

## Phase 3 — Node-side wiring

- [ ] 3.1 RED — Unit test for `getMyRevocationStatus(userId)`
- [ ] 3.2 GREEN — Add helper to `lib/supabase/tenant.ts`
- [ ] 3.3 Grep `denied_jti` + `RuntimeAuthError` catch sites in `server/`
- [ ] 3.4 WS-handler: emit `revocation_notice` WS message variant on revoked sessions
- [ ] 3.5 Widen `WSMessage` discriminated union + test-d exhaustiveness file

## Phase 4 — Compliance + PR body

- [ ] 4.1 Append row to `knowledge-base/legal/compliance-posture.md` Completed Compliance Work
- [ ] 4.2 Compose PR body (Summary, User-Brand Impact, Changelog, Test plan, Reviewer Pipeline) with `Closes #3930` + `Closes #3932`

## Phase 5 — Test execution

- [ ] 5.1 Run `*.tenant-isolation.test.ts` suites under `TENANT_INTEGRATION_TEST=1` (expect 16 suites)
- [ ] 5.2 Run `bash scripts/test-all.sh webplat` — no new regression
- [ ] 5.3 Run `npx tsc --noEmit` clean
- [ ] 5.4 Run `service-role-allowlist-gate.sh` — no new entries
- [ ] 5.5 Run `/soleur:gdpr-gate` against diff — 0 Critical
- [ ] 5.6 EXPLAIN ANALYZE smoke for perf delta < 0.2 ms per RLS-touched query

## Phase 6 — `/soleur:review` with mandatory agents

- [ ] 6.1 Spawn `user-impact-reviewer` (mandatory per `single-user incident` threshold)
- [ ] 6.2 Spawn `data-integrity-guardian` (WORM + RLS + audit surface)
- [ ] 6.3 Spawn `security-sentinel` (JWT mint path + RLS predicate)
- [ ] 6.4 Spawn `gdpr-gate` (auth-domain code change)
- [ ] 6.5 Spawn 6 standard code-review agents
- [ ] 6.6 Spawn `test-design-reviewer` (test files present)
- [ ] 6.7 Spawn `code-simplicity-reviewer` (CONCUR gate)
- [ ] 6.8 Fix all P0/P1 inline; file scope-outs with re-evaluation triggers for any P2

## Phase 7 — `/soleur:ship`

- [ ] 7.1 `/soleur:ship` push + mark ready + auto-merge
- [ ] 7.2 Verify `web-platform-release.yml#migrate` applies mig 068 to prd
- [ ] 7.3 Verify `web-platform-release.yml#post-deploy` runs `gh issue close 3930/3932`
- [ ] 7.4 File "New admin role + admin UI" sub-issue (Tracked Deferral #1)
- [ ] 7.5 Follow-through gate at +24h and +7d: Sentry `is_jti_denied.error` hits = 0
