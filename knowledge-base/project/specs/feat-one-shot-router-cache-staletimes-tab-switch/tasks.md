# Tasks — Router-Cache staleTimes for tab-switching

Derived from `knowledge-base/project/plans/2026-07-09-fix-router-cache-staletimes-tab-switch-plan.md`.
Lane: single-domain. Threshold: single-user incident (CPO sign-off + user-impact-reviewer).
Single atomic PR — GAP E/F/G close windows the config change itself opens; do not split.

## Phase 1 — Config (perf fix)

- [ ] 1.1 `apps/web-platform/next.config.ts`: add `staleTimes: { dynamic: 30 }` to the
  existing `experimental` block (leave `static` at default). Comment: RSC-shell reuse +
  isolation-via-hard-nav-boundary-wipe invariant.

## Phase 2 — Isolation fix set (hard-nav every principal boundary)

- [ ] 2.1 GAP C — `components/auth/use-sign-out.ts:104`: `router.push("/login")` →
  `window.location.assign("/login")`; keep awaited `clearSwrCache(mutate)` before it.
- [ ] 2.2 GAP C cleanup — remove unused `useRouter` import, `const router`, and the
  `[router, mutate]`→`[mutate]` dep array at `:109` (tsc will not flag; do manually / eslint).
- [ ] 2.3 GAP C comments — rewrite the docblock (`:10-23`) and inline comments (`:18`, `:94`)
  that narrate the old soft-push, so the AC grep does not match comment text.
- [ ] 2.4 GAP D — `components/auth/use-sign-out.ts:38-52`: extend the
  `onAuthStateChange("SIGNED_OUT")` listener to hard-nav the sibling tab
  (`window.location.assign("/login")`) after `clearSwrCache`.
- [ ] 2.5 GAP E — `components/auth/login-form.tsx:62`: `onVerifySuccess` →
  `window.location.assign(redirectTo ?? "/dashboard")` (OTP sign-in success).
- [ ] 2.6 GAP F — hard-nav the 401/revocation bounces:
  `app/(dashboard)/dashboard/page.tsx:152`, `hooks/use-kb-layout-state.tsx:94`,
  `app/(dashboard)/dashboard/kb/[...path]/page.tsx:92` → `window.location.assign("/login")`.
- [ ] 2.7 GAP G — `lib/security-headers.ts` (or auth-route response wrapper): add
  `Cache-Control: no-store` to authenticated document responses; verify `force-dynamic`
  tabs already carry it; cover non-`force-dynamic` authenticated routes.
- [ ] 2.8 Verify `/invite/<token>` accept-while-authenticated post-accept nav; if it crosses
  a workspace boundary via soft nav, convert to hard nav and add to the boundary table.

## Phase 3 — ADR-067 amendment

- [ ] 3.1 Via `/soleur:architecture`, append `## Amendment (2026-07-09)` to
  `ADR-067-adopt-swr-client-cache.md`: two-cache invariant, full hard-nav boundary set,
  continuous-gate (revocation/T&C/billing) note, bfcache≠Router-Cache note, bounded
  revocation residual + RLS backstop. No new ordinal. No `.c4` edit (no C4 impact).

## Phase 4 — Tests (assert invariants, not proxies)

Harness: `apps/web-platform/e2e/` (`mock-supabase.ts`, `nav-states-shell.e2e.ts`,
`otp-login.e2e.ts`, `oauth.e2e.ts`, `team-membership.e2e.ts`).

- [ ] 4.1 Perf e2e: tab → other tab → back within 30 s asserts `loading.tsx` does NOT
  re-mount (one `force-dynamic` tab + one `"use client"` tab).
- [ ] 4.2 Cross-user e2e (GAP E): A signs out, B OTP-signs-in same browser; B's first paint
  has none of A's RSC.
- [ ] 4.3 Revocation e2e (GAP F): warm two tabs, revoke session, soft-switch within 30 s →
  bounced to `/login`.
- [ ] 4.4 Back/bfcache e2e (GAP C/G): sign out, real browser Back → `/login`, no auth DOM;
  assert authenticated docs carry `no-store`.
- [ ] 4.5 Multi-tab e2e (GAP D): `SIGNED_OUT` in a tab that did not call `handleSignOut`
  triggers hard nav.
- [ ] 4.6 Rewrite `test/swr-cache-clear-on-signout.test.tsx`: re-pin the clear-before-nav
  ordering proof from `useRouter().push` mock to a stubbed `window.location.assign`
  (happy-dom needs `window.location` stubbed); assert clear ran before assign.
- [ ] 4.7 Sign-out failure-branch unit test: signOut throws + local fallback fails → lands on
  `/login`, no loop to `/dashboard`, user-visible failure signal.
- [ ] 4.8 CI-gated build check: `next build` grep for `Unrecognized key` (discoverability).
  NO exact-value config unit test.

## Exit gates

- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] web-platform vitest suite green; Playwright e2e green.
- [ ] All Pre-merge Acceptance Criteria checked.
- [ ] CPO sign-off recorded (threshold single-user incident; expanded isolation scope per
  decision-challenges.md #2); `user-impact-reviewer` at review time.
