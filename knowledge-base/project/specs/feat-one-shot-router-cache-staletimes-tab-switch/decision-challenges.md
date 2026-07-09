# Decision Challenges — feat-one-shot-router-cache-staletimes-tab-switch

Surfaced during plan + plan-review (headless one-shot). `ship` Phase 6 renders these
into the PR body and files an `action-required` issue for operator visibility.

## 1. Dropped `static: 180` from the operator's suggested config (Taste)

The fix brief suggested `experimental.staleTimes = { dynamic: 30, static: 180 }`
and delegated tuning ("tune in the plan"). Both simplification reviewers
(DHH + code-simplicity) and the architecture reviewer independently flagged
`static: 180` as unmotivated and mildly counterproductive: the reported bug is
caused solely by `staleTimes.dynamic = 0`; `static` already defaults to a
non-zero window (300 s in Next 15), and lowering it to 180 adds revalidation
churn on prefetched routes for no described benefit. **Plan ships
`{ dynamic: 30 }` only.** Reversible one-line change if a static-route problem
later appears. Operator: flag if you specifically wanted the `static` override.

## 2. Isolation surface is larger than "one config line + GAP C" (User-Challenge / scope)

The 5-agent plan-review + 4-agent deepen pass (single-user-incident threshold)
established that a non-zero `staleTimes.dynamic` makes the client Router Cache
retain per-principal server-rendered RSC across **soft** navigations, and
middleware does not re-run on cache hits. The default OTP sign-in, the onboarding
funnel's terminal `→/dashboard` hops, account deletion, and the in-session
401/302 revocation bounces are all **soft**, so the perf change opens real
cross-principal windows that require converting ~9 nav sites to hard navs (GAP
C/D/E-incl-funnel/F-incl-delete+302) plus a bfcache defense in `middleware.ts`
(GAP G) plus a dedicated guard for the `admin/analytics` route, which bakes
**all-tenant** data into an RLS-bypassing cacheable RSC (GAP H). deepen also
corrected that the data backstop is `resolveActiveWorkspace()`'s membership probe,
not RLS.

The perf win (no skeleton flash on tab switch) is operator-requested and each
mitigation is small/precedented (mirrors `org-switcher-container.tsx:131`), so the
plan keeps the feature and expands the isolation deliverables. **The scope is now
materially larger than "one config line."** Operator/CPO: confirm the expanded
isolation scope is acceptable; the cheapest descope lever is a smaller `dynamic`
(e.g. 5-10 s) which shrinks every window, or (strongest) also refactor
`admin/analytics` off the RSC-baked all-tenant read. CPO sign-off is required
(`requires_cpo_signoff: true`); `user-impact-reviewer` runs at review time.

**Operator decision (2026-07-09): "Ship full safe scope"** — proceed with
`dynamic: 30` + all hard-nav conversions (GAP C/D/E incl. funnel /F incl.
delete-account + 302-detection /G /H) + ADR-067 amendment. GAP H shipped as the
mount-time `router.refresh()` guard (not the API+SWR refactor).

## 3. Isolation invariants covered by deterministic unit tests, not Playwright e2e (Test-strategy / Taste)

The plan's Phase 4 prescribed a Playwright e2e matrix (perf skeleton, cross-user
OTP, revocation 302, real-Back/bfcache, multi-tab SIGNED_OUT, admin-deprovision).
Implemented instead as **deterministic unit tests**, all green:

- **GAP C** (sign-out hard-nav + clear-before-nav ordering + teardown-failure
  branch): `test/swr-cache-clear-on-signout.test.tsx` (rewritten, re-pinned to
  `window.location.assign`) + `test/dashboard-layout-signout.test.tsx`.
- **GAP D** (sibling-tab `SIGNED_OUT` hard-nav + same-tab guard):
  `test/use-sign-out-signed-out-listener.test.tsx`.
- **GAP E** (OTP sign-in + signup + setup-key skip hard-nav, open-redirect-safe):
  `test/login-redirect-cooldown.test.tsx`, `test/signup-redirect-cooldown.test.tsx`,
  `test/components/setup-key-skip.test.tsx`.
- **GAP G** (`no-store` on authenticated documents only, via `Sec-Fetch-Dest`;
  public paths + non-document fetches untouched): `test/middleware.no-store.test.ts`
  (invokes the real `middleware()`).
- **GAP H** (admin-analytics `router.refresh()` on every mount):
  `test/components/analytics/admin-analytics-authz-refresh.test.tsx`.
- **Config recognition**: the plan's `next build | grep 'Unrecognized key'` is
  CI-gated (multi-minute full build), not a vitest.

**Rationale:** the headless one-shot pipeline cannot start the dev server +
Playwright browsers to *verify* new e2e specs. Authoring them blind risks either
(a) vacuous assertions — asserting the ABSENCE of a transient `loading.tsx`
skeleton is exactly the "proxy, not invariant" trap the plan warns against, and
mocked-instant API routes may never show the skeleton with OR without the fix —
or (b) red CI on the required `e2e` check, stalling the autonomous merge. The
unit tests assert the same observable contracts deterministically at the
navigation-mechanism boundary (`window.location.assign` fired, `no-store` header
present, `router.refresh()` called). **Follow-up:** a live-server Playwright pass
(cross-user paint + real-Back bfcache + revocation 302) is a fast-follow once the
change is on a preview deploy; `user-impact-reviewer` cross-checks the diff at
review time.
