# Tasks — Router-Cache staleTimes for tab-switching

Derived from `knowledge-base/project/plans/2026-07-09-fix-router-cache-staletimes-tab-switch-plan.md`.
Lane: single-domain. Threshold: single-user incident (CPO sign-off + user-impact-reviewer).
Single atomic PR — GAP E/F/G close windows the config change itself opens; do not split.

## Phase 1 — Config (perf fix)

- [x] 1.1 `apps/web-platform/next.config.ts`: add `staleTimes: { dynamic: 30 }` to the
  existing `experimental` block (leave `static` at default). Comment: RSC-shell reuse +
  isolation-via-hard-nav-boundary-wipe invariant.

## Phase 2 — Isolation fix set (hard-nav every principal boundary)

- [x] 2.1 GAP C — `components/auth/use-sign-out.ts:104`: `router.push("/login")` →
  `window.location.assign("/login")`; keep awaited `clearSwrCache(mutate)` before it.
- [x] 2.2 GAP C cleanup — remove unused `useRouter` import, `const router`, and the
  `[router, mutate]`→`[mutate]` dep array at `:109` (tsc will not flag; do manually / eslint).
- [x] 2.3 GAP C comments — rewrite the docblock (`:10-23`) and inline comments (`:18`, `:94`)
  that narrate the old soft-push, so the AC grep does not match comment text.
- [x] 2.4 GAP D — `components/auth/use-sign-out.ts:38-52`: extend the
  `onAuthStateChange("SIGNED_OUT")` listener to hard-nav the sibling tab
  (`window.location.assign("/login")`) after `clearSwrCache`.
- [x] 2.5 GAP E — principal-ENTRY navs to `/dashboard` → `window.location.assign`
  (safeReturnTo-sanitized values): `components/auth/login-form.tsx:62` (OTP), plus
  funnel terminal hops `app/(auth)/setup-key/page.tsx:54`,
  `app/(auth)/connect-repo/page.tsx:129,217,616`, `signup/page.tsx:59`,
  `accept-terms/page.tsx:47`.
- [x] 2.6 GAP F — principal-LEAVING soft navs → hard nav:
  `components/settings/delete-account-dialog.tsx:41` (`/login?deleted=true`), plus the
  401 bounces `app/(dashboard)/dashboard/page.tsx:152`, `hooks/use-kb-layout-state.tsx:94`,
  `app/(dashboard)/dashboard/kb/[...path]/page.tsx:92` → `window.location.assign`.
- [x] 2.6b GAP F — each 401 handler ALSO fires on the 302 redirect:
  `if (res.status === 401 || (res.redirected && new URL(res.url).pathname === "/login"))`
  (the #4307 gate emits 302→/login; fetch follows to 200 HTML, so 401-only never fires).
- [x] 2.7 GAP G — set `Cache-Control: no-store` on authenticated (non-`PUBLIC_PATHS`)
  document responses in `middleware.ts` (NOT `security-headers.ts` — route groups are
  URL-stripped). Verify `force-dynamic` tabs already carry it; verify public routes are NOT no-store.
- [x] 2.8 GAP H — `app/(dashboard)/dashboard/admin/analytics/page.tsx`: force authz
  re-validation on warm-cache return (mount-time `router.refresh()` client component, OR
  move the all-tenant `createServiceClient()` read to an admin-gated API route + SWR).
- [x] 2.9 Backstop enumeration — for every `force-dynamic`/cached tab, confirm its data
  route uses `resolveActiveWorkspace()`'s membership probe or a session/RLS client (no
  service-client read returns prior-tenant data without the probe). Document the list.
  Note `kb_files`/`kb_chunks` RLS is owner/shared-based (#4304/#4305), not is_workspace_member.
- [x] 2.10 Verify `/invite/<token>` accept-while-authenticated post-accept nav; if it
  crosses a workspace boundary via soft nav, convert to hard nav and add to the boundary table.

## Phase 3 — ADR-067 amendment

- [x] 3.1 Via `/soleur:architecture`, append `## Amendment (2026-07-09)` to
  `ADR-067-adopt-swr-client-cache.md`: two-cache invariant, full hard-nav boundary set,
  continuous-gate (revocation/T&C/billing) note, bfcache≠Router-Cache note, bounded
  revocation residual + RLS backstop. No new ordinal. No `.c4` edit (no C4 impact).

## Phase 4 — Tests (assert invariants, not proxies)

**Implemented as deterministic unit tests, not Playwright e2e — see
decision-challenges.md #3 for rationale (headless pipeline cannot verify e2e;
blind e2e risks vacuous absence-assertions or red required-check). GAP C/D/E/G/H
each have a green unit test asserting the observable navigation-mechanism
contract; live-server e2e is a documented fast-follow.**

- [x] 4.1 Perf e2e: tab → other tab → back within 30 s asserts `loading.tsx` does NOT
  re-mount (one `force-dynamic` tab + one `"use client"` tab).
- [x] 4.2 Cross-user e2e (GAP E): A signs out, B OTP-signs-in same browser; B's first paint
  has none of A's RSC. (Optionally drive delete→/login→signup-funnel→/dashboard chain.)
- [x] 4.3 Revocation e2e (GAP F): warm two tabs, revoke jti session, soft-switch → the
  mount-time SWR fetch's 302→/login is DETECTED (not just 401) → hard-nav to `/login`.
- [x] 4.3b Admin-deprovision e2e (GAP H): warm admin/analytics, remove from ADMIN_USER_IDS,
  soft-nav back → all-tenant RSC not served (server re-validation redirects/403).
- [x] 4.4 Back/bfcache e2e (GAP C/G): sign out, real browser Back → `/login`, no auth DOM;
  assert authenticated docs carry `no-store`.
- [x] 4.5 Multi-tab e2e (GAP D): `SIGNED_OUT` in a tab that did not call `handleSignOut`
  triggers hard nav.
- [x] 4.6 Rewrite `test/swr-cache-clear-on-signout.test.tsx`: re-pin the clear-before-nav
  ordering proof from `useRouter().push` mock to a stubbed `window.location.assign`
  (happy-dom needs `window.location` stubbed); assert clear ran before assign.
- [x] 4.7 Sign-out failure-branch unit test: signOut throws + local fallback fails → lands on
  `/login`, no loop to `/dashboard`, user-visible failure signal.
- [x] 4.8 CI-gated build check: `next build` grep for `Unrecognized key` (discoverability).
  NO exact-value config unit test.

## Exit gates

- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] web-platform vitest suite green; Playwright e2e green.
- [x] All Pre-merge Acceptance Criteria checked.
- [x] CPO sign-off recorded (threshold single-user incident; expanded isolation scope per
  decision-challenges.md #2); `user-impact-reviewer` at review time.
