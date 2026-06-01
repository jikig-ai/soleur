---
title: "Tasks — fix pending-invite recovery banner (raw_user_meta_data on public.users)"
plan: knowledge-base/project/plans/2026-06-01-fix-pending-invite-recovery-banner-public-users-column-plan.md
branch: feat-one-shot-multi-user-workspace-invites-pending
issue: 4715
prior_pr: 4713
lane: single-domain
---

# Tasks

Derived from `2026-06-01-fix-pending-invite-recovery-banner-public-users-column-plan.md`. Single-file surgical bug fix + one regression test. Test runner is **vitest** (`apps/web-platform`); run with `./node_modules/.bin/vitest run <path>` from `apps/web-platform/`. `bun test` is blocked by `bunfig.toml pathIgnorePatterns=["**"]`.

## Phase 1 — RED: regression test

- [ ] 1.1 Create `apps/web-platform/test/server/workspace-invitations-pending-select.test.ts` (matches `vitest.config.ts` node-project glob `test/**/*.test.ts`).
  - [ ] 1.1.1 Use shared helper `mockQueryChain` from `../helpers/mock-supabase`; wire `vi.hoisted()` + `vi.mock("@/lib/supabase/service", ...)` per the helper docstring / `workspace-resolver.test.ts` precedent.
  - [ ] 1.1.2 Mock `@/server/observability` (`reportSilentFallback: vi.fn()`) and `@/server/logger` (`createChildLogger`) — both imported at SUT module scope.
  - [ ] 1.1.3 Test A (select-string gate): call `getPendingInvitesForUser(uuid, "alice@example.com")`; capture `mockFrom.mock.results[0].value.select.mock.calls[0][0]`; assert it does NOT match `/\b(raw_user_meta_data|raw_app_meta_data|encrypted_password|email_confirmed_at|last_sign_in_at)\b/`; assert it DOES match `/inviter:users!workspace_invitations_inviter_user_id_fkey/` and `/email/`; assert `mockFrom` called with `"workspace_invitations"`.
  - [ ] 1.1.4 Test B (output-shape): feed one well-formed row (`inviter: { email: "boss@acme.com" }`) → assert mapped `inviter_name === "boss@acme.com"`; feed `inviter: { email: null }` → assert `inviter_name === "A team member"`.
- [ ] 1.2 Run `./node_modules/.bin/vitest run test/server/workspace-invitations-pending-select.test.ts` from `apps/web-platform/`; confirm Test A **FAILS** against current (broken) code. (RED proof.)

## Phase 2 — GREEN: single-file fix

- [ ] 2.1 Edit `apps/web-platform/server/workspace-invitations.ts` ONLY:
  - [ ] 2.1.1 Embedded select (L72-75): remove `raw_user_meta_data`, keep `email`.
  - [ ] 2.1.2 Inviter type (L126-129): drop `raw_user_meta_data` field, leave `{ email: string | null }`.
  - [ ] 2.1.3 Derivation (L135-136): `inviter_name: inviter?.email ?? "A team member"`.
- [ ] 2.2 Re-run the Phase 1 test → must now **PASS** (both Test A and Test B).

## Phase 3 — Regression-proof

- [ ] 3.1 `./node_modules/.bin/vitest run test/server/` (from `apps/web-platform/`) — existing invitation tests still pass: `workspace-invitations-revoke.test.ts`, `workspace-invitations-revoke.integration.test.ts`, `cancel-invite-route.test.ts`, `workspace-invitation-identity.test.ts`, `test/app/invite-page.test.tsx`.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (no cross-consumer type breakage from the `inviter` type removal; `inviter_name: string` interface unchanged).
- [ ] 3.3 `npm run -w apps/web-platform test:ci` (= `vitest run`) — full package green.

## Phase 4 — Verification & PR

- [ ] 4.1 `grep -c raw_user_meta_data apps/web-platform/server/workspace-invitations.ts` → 0; `grep -rn raw_user_meta_data apps/web-platform --include=*.ts --include=*.tsx` → no matches.
- [ ] 4.2 PR body uses `Ref #4715` (NOT `Closes` — issue already CLOSED by #4713).
- [ ] 4.3 QA per plan Test Scenarios (Supabase MCP read-only on DEV for invite-row existence; Playwright MCP for banner render on `/dashboard` + no double-render on `/dashboard/chat`). Never create synthetic users against prod.
- [ ] 4.4 Post-merge: container restart is automatic via `web-platform-release.yml` (path-filtered on `apps/web-platform/**`); no migration, no operator step.
