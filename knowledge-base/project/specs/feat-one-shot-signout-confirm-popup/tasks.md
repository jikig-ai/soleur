---
title: "tasks: feat-one-shot-signout-confirm-popup"
date: 2026-05-11
plan: knowledge-base/project/plans/2026-05-11-feat-signout-confirmation-modal-plan.md
---

# Tasks: Sign-out Confirmation Modal

Derived from `knowledge-base/project/plans/2026-05-11-feat-signout-confirmation-modal-plan.md`.

## Phase 1 — Modal component (RED)

- [ ] 1.1 Create `apps/web-platform/test/sign-out-confirm-modal.test.tsx` with failing tests:
  - [ ] 1.1.1 `renders nothing when open=false`
  - [ ] 1.1.2 `renders dialog with role="dialog" + aria-modal="true" + aria-labelledby`
  - [ ] 1.1.3 `initial focus is on Cancel button`
  - [ ] 1.1.4 `ESC key calls onClose (when not isSigningOut)`
  - [ ] 1.1.5 `backdrop click calls onClose (when not isSigningOut)`
  - [ ] 1.1.6 `Cancel button click calls onClose`
  - [ ] 1.1.7 `Sign out button click calls onConfirm`
  - [ ] 1.1.8 `isSigningOut=true disables both buttons and primary shows "Signing out…"`
  - [ ] 1.1.9 `focus returns to trigger element on close`
  - [ ] 1.1.10 `Tab cycles focus inside dialog; Shift+Tab wraps`
- [ ] 1.2 Confirm all tests fail (component not yet implemented).

## Phase 2 — Modal component (GREEN)

- [ ] 2.1 Create `apps/web-platform/components/auth/sign-out-confirm-modal.tsx` per plan Phase 2 snippet.
- [ ] 2.2 Reuse focus-trap implementation from `components/settings/cancel-retention-modal.tsx`.
- [ ] 2.3 Use `z-[60]` to render above the mobile drawer (drawer aside `z-50`).
- [ ] 2.4 Disable backdrop dismissal and ESC dismissal while `isSigningOut` is true.
- [ ] 2.5 Run `bun test apps/web-platform/test/sign-out-confirm-modal.test.tsx`; all tests pass.

## Phase 3 — Layout wiring (RED → GREEN)

- [ ] 3.1 Create `apps/web-platform/test/dashboard-layout-signout.test.tsx` with failing tests:
  - [ ] 3.1.1 `sidebar Sign out button click opens the modal`
  - [ ] 3.1.2 `Cancel closes modal without calling supabase.auth.signOut`
  - [ ] 3.1.3 `Confirm calls supabase.auth.signOut and router.push("/login")`
  - [ ] 3.1.4 `Confirm shows "Signing out…" + disables both buttons during teardown`
  - [ ] 3.1.5 `removeAllChannels rejection: signOut + redirect STILL run AND reportSilentFallback fires with feature:"auth" op:"signOut"`
  - [ ] 3.1.6 `signOut rejection: redirect STILL runs AND reportSilentFallback fires with feature:"auth" op:"signOut"`
- [ ] 3.2 Edit `apps/web-platform/app/(dashboard)/layout.tsx`:
  - [ ] 3.2.1 Import `SignOutConfirmModal` and `reportSilentFallback`.
  - [ ] 3.2.2 Add `signOutModalOpen` and `isSigningOut` useState hooks.
  - [ ] 3.2.3 Change sidebar Sign out button `onClick` to `() => setSignOutModalOpen(true)`.
  - [ ] 3.2.4 Rewrite `handleSignOut` per plan Phase 3 snippet: nested try/catch around `removeAllChannels` and `signOut`, each with `reportSilentFallback`; outer `finally` still runs `router.push("/login")`.
  - [ ] 3.2.5 Set `setIsSigningOut(true)` at the start of `handleSignOut`; do NOT reset on completion (route push unmounts).
  - [ ] 3.2.6 Render `<SignOutConfirmModal open={signOutModalOpen} onClose={() => setSignOutModalOpen(false)} onConfirm={handleSignOut} isSigningOut={isSigningOut} />` at the layout root, alongside the drawer overlay.
- [ ] 3.3 Run `bun test apps/web-platform/test/dashboard-layout-signout.test.tsx`; all tests pass.
- [ ] 3.4 Run existing sidebar tests (`dashboard-sidebar-collapse.test.tsx`, `dashboard-layout-banner.test.tsx`, `dashboard-layout-drawer-rail.test.tsx`); confirm no regressions.

## Phase 4 — Drift-guard extension (closes #3039)

- [ ] 4.1 Edit `apps/web-platform/test/auth/sentry-tag-coverage.test.ts`:
  - [ ] 4.1.1 Add `"signOut"` to `AUTH_VERBS` array.
- [ ] 4.2 Run `bun test apps/web-platform/test/auth/sentry-tag-coverage.test.ts`; confirm the test passes (the new mirror added in Phase 3 satisfies it).
- [ ] 4.3 Run `rg "\.signOut\b" apps/web-platform/{app,components,lib,server,hooks} -t ts -t tsx`; verify the only call site is `app/(dashboard)/layout.tsx`. If a second call site surfaces, mirror it inline.

## Phase 5 — Verification

- [ ] 5.1 `cd apps/web-platform && bun typecheck` — clean.
- [ ] 5.2 `cd apps/web-platform && bun test` — full suite passes.
- [ ] 5.3 Manual QA — desktop expanded sidebar: click Sign out; modal opens; ESC closes; backdrop closes; Cancel closes; Confirm signs out and lands on `/login`.
- [ ] 5.4 Manual QA — desktop collapsed sidebar: same flow, verify focus returns to the icon-only button.
- [ ] 5.5 Manual QA — mobile drawer open (viewport `<md`): tap Sign out; verify modal renders centered above the drawer overlay.
- [ ] 5.6 Inspect Sentry locally (or instrument via `console.log` shim if Sentry DSN not wired in dev) and confirm a synthetic `removeAllChannels` failure produces a captured event with `feature: "auth", op: "signOut"`.

## Phase 6 — Ship

- [ ] 6.1 Compound capture (per AGENTS.md `wg-before-every-commit-run-compound-skill`).
- [ ] 6.2 Commit: `feat(web-platform): add sign-out confirmation modal + Sentry mirror (Closes #3039)`.
- [ ] 6.3 Open PR with body referencing this plan, Closes #3039.
- [ ] 6.4 `/soleur:review` → `/soleur:qa` → `/soleur:ship`.
