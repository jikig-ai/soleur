---
title: "Tasks — per-cause tenant-mint fallback for authenticateAndResolveKbPath (#4914)"
plan: knowledge-base/project/plans/2026-06-04-fix-kb-file-route-tenant-mint-fallback-plan.md
issue: 4914
branch: feat-one-shot-4914-kb-tenant-mint-fallback
lane: single-domain
---

# Tasks — fix(kb): per-cause tenant-mint fallback for `authenticateAndResolveKbPath`

Derived from `2026-06-04-fix-kb-file-route-tenant-mint-fallback-plan.md` (post-deepen). Single-file
behavioral change mirroring PR #4913's sibling pattern with a per-cause adjudication.

## Phase 1 — Setup / RED (write failing tests first)

- [ ] 1.1 In `apps/web-platform/test/kb-route-helpers.test.ts`, add a new
  `describe("authenticateAndResolveKbPath — tenant-mint fallback")` block mirroring the
  `resolveUserKbRoot — tenant-mint fallback` block (`:748-870`). Use `setupServiceUserData()` in
  `beforeEach`; reuse `setupHappyPath()`, `mockGetFreshTenantClient.mockRejectedValueOnce(...)`, the
  two-arg mock `RuntimeAuthError(cause, message)`, and the distinct `mockFrom`/`mockServiceFrom`
  non-vacuity assertions.
  - [ ] 1.1.1 Test 1 — `jwt_mint` → service-role fallback resolves `{ ok: true, ctx }` (NOT 503);
    `mockServiceFrom` called with `"users"`, `mockFrom` NOT called.
  - [ ] 1.1.2 Test 2 — `rotation` → same as Test 1.
  - [ ] 1.1.3 Test 3 — `denied_jti` → `{ ok: false, response.status === 403 }`, body
    `{ error: "Access denied" }`, `mockServiceFrom` NOT called, `mockFrom` NOT called.
  - [ ] 1.1.4 Test 4 — `denied_jti` path RESOLVES (does not reject):
    `await expect(authenticateAndResolveKbPath(...)).resolves.toMatchObject({ ok: false })`.
  - [ ] 1.1.5 Test 5 — parametrize `["jwt_mint","rotation","denied_jti"]`; assert exactly one
    `reportSilentFallback(mintErr, { feature: "kb-route-helpers", op:
    "authenticateAndResolveKbPath.tenant-mint", extra: { userId } })` per cause.
  - [ ] 1.1.6 Test 6 — `jwt_mint` + `setupServiceUserData({ workspace_status: "provisioning" })` →
    503 derived from the service read.
  - [ ] 1.1.7 Test 7 — non-`RuntimeAuthError` mint failure re-thrown; `mockServiceFrom` NOT called.
  - [ ] 1.1.8 Test 8 — happy path (mint succeeds) → tenant read, no fallback, no `reportSilentFallback`.
- [ ] 1.2 RED-verify Tests 1, 2, 3, 4 FAIL against pre-fix code
  (`cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts`). The
  current code returns 503 for all causes, so 1/2/3/4 must be red. (`cq-write-failing-tests-before`.)

## Phase 2 — Core implementation (GREEN)

- [ ] 2.1 Edit `apps/web-platform/server/kb-route-helpers.ts` `authenticateAndResolveKbPath`
  mint-failure catch (`:104-113`). Inside `if (mintErr instanceof RuntimeAuthError)`:
  - [ ] 2.1.1 Keep `reportSilentFallback(mintErr, { feature: "kb-route-helpers", op:
    "authenticateAndResolveKbPath.tenant-mint", extra: { userId: user.id } })` firing FIRST, before
    the cause branch (FR3 — fires for all causes incl. `denied_jti`).
  - [ ] 2.1.2 Add `if (mintErr.cause === "jwt_mint" || mintErr.cause === "rotation") { tenant =
    createServiceClient(); }` (FR1 — positive allow-list, NOT `!== "denied_jti"`).
  - [ ] 2.1.3 Add `else { return err(403, "Access denied"); }` (FR2 — `denied_jti` + any future
    unknown cause fail closed; RETURN a Response, never throw).
  - [ ] 2.1.4 Leave the outer `else { throw mintErr; }` for non-`RuntimeAuthError` unchanged (FR4).
  - [ ] 2.1.5 Let the existing `.from("users").select(...).eq("id", user.id).single()` + the
    `workspace_status === "ready"` / installation-id / repo validation run unchanged against the
    (possibly service-role) `tenant`.
- [ ] 2.2 Rewrite the NOTE comment at `:94-99` (FR5): name the new ceiling per
  `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` —
  `jwt_mint`/`rotation` fall back to a self-row service-role read (availability failures, same
  `.eq("id", user.id)` ceiling as `resolveUserKbRoot`); `denied_jti` (and any unknown cause) fail
  closed with 403 because the deny-list IS meant to block the *mutation* here. Mirror the prose style
  of `resolveUserKbRoot`'s ceiling comment (`:251-263`).
- [ ] 2.3 Run vitest GREEN:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts` — all 8 new
  tests + the pre-existing `authenticateAndResolveKbPath` block green.

## Phase 3 — Allowlist rationale + typecheck

- [ ] 3.1 Edit `apps/web-platform/.service-role-allowlist` "#4913" rationale block (FR6): add a
  sentence noting `authenticateAndResolveKbPath` now ALSO uses the service-role client as an
  availability-only fallback (`jwt_mint`/`rotation`) per #4914, and that `denied_jti` fails closed.
  Do NOT add a new path line — the file is already allowlisted (count stays exactly 1).
- [ ] 3.2 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC10).
- [ ] 3.3 Confirm `service-role-allowlist-gate` CI job stays green — no new disallowed service-role
  importer (AC9; no new `createServiceClient` *file* added — already imported in this file).

## Phase 4 — Acceptance verification

- [ ] 4.1 AC1–AC6: the 8 vitest tests green and the new-behavior cases (1,2,3,4) were RED pre-fix.
- [ ] 4.2 AC7: `grep -n "denied_jti" apps/web-platform/server/kb-route-helpers.ts` returns a match
  inside the `authenticateAndResolveKbPath` comment block + the NOTE no longer says "intentionally
  503s … tracked in #4914".
- [ ] 4.3 AC8: `grep -c "apps/web-platform/server/kb-route-helpers.ts"
  apps/web-platform/.service-role-allowlist` returns exactly `1` (unchanged).
- [ ] 4.4 AC10: `tsc --noEmit` clean + full `kb-route-helpers.test.ts` green.

## Notes

- Runner: vitest only (`apps/web-platform/bunfig.toml` blocks bun test). Always
  `cd apps/web-platform && ./node_modules/.bin/vitest …`. Test path `test/kb-route-helpers.test.ts`
  matches the node project `test/**/*.test.ts` include glob (`vitest.config.ts:44`).
- No migration, no infra, no UI surface, no post-merge operator step. Deploys via
  `web-platform-release.yml` on merge.
- PR body: use `Closes #4914`.
- Learning capture at ship time via `/soleur:compound` into
  `knowledge-base/project/learnings/bug-fixes/` — do NOT pre-create a dated filename.
