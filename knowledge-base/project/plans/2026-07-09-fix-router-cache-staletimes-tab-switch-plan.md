---
title: "fix: Add experimental.staleTimes so dashboard tab-switching reuses the Router Cache (RSC shell) instead of re-showing the skeleton"
type: fix
date: 2026-07-09
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
issue: TBD
---

## Enhancement Summary

**Deepened on:** 2026-07-09 (post 5-agent plan-review + 4-agent deepen pass:
security-sentinel, data-integrity-guardian, framework-docs-researcher, verify-the-negative).

### Key corrections folded in
1. **RLS is NOT the data backstop for the cached tabs** — they fetch via
   `createServiceClient()` (RLS-bypassing); workspace scoping is enforced by
   `resolveActiveWorkspace()`'s explicit membership probe
   (`server/workspace-resolver.ts:413-445`). The ADR/plan now cite that probe, and
   RLS `is_workspace_member` only for session-client routes.
2. **Isolation gap set expanded** — GAP E generalized to the whole principal-ENTRY
   funnel (`setup-key:54`, `connect-repo:129/217/616`, `signup:59`, `accept-terms:47`),
   GAP F gains `delete-account-dialog.tsx:41`, and a new **GAP H** special-cases
   `admin/analytics` (bakes all-tenant data into the RSC via service-client, no SWR,
   only `isAdmin` env + cache-wipe protect it).
3. **GAP F must detect the 302 revocation redirect**, not only `401` (the #4307 gate
   emits `clearSessionAndRedirect` = 302→/login; `fetch` follows to 200 HTML).
4. **GAP G relocated to `middleware.ts`** — route groups can't be selected by the
   global `security-headers.ts` `source:"/(.*)"` matcher; middleware has the auth +
   per-path signal to scope `no-store` to authenticated documents only.
5. **Tests assert mount-driven revalidation** (`revalidateOnMount`) — SWR
   `revalidateOnFocus` does not fire on in-app tab switches (same document).

### New considerations discovered
- Middleware has **no inverse auth redirect** (`/login`,`/signup` are PUBLIC_PATHS),
  so a soft delete→/login→signup-funnel→/dashboard chain is reachable — both ends
  must hard-nav.
- `ws-client.ts:178` already hard-navigates its 4 revocation close-codes (safe);
  the service worker is network-only for HTML/RSC (safe); token-refresh never
  changes the acting principal without a nav (safe).

---

# fix: Router-Cache `staleTimes` for instant dashboard tab-switching

Switching between dashboard tabs and returning to a previously-visited one still
re-shows a too-long loading skeleton, even for tabs whose content has not
changed. The residual cause is the **Next.js App Router Router Cache**, not the
data layer: the SWR client cache (ADR-067, PR #5639) already fixed the
client-side *data* fetches, but the *RSC shell* (the server-component payload for
each tab route, gated by its `loading.tsx`) is still refetched on every return
because `apps/web-platform/next.config.ts` sets no `experimental.staleTimes`
override — so Next.js 15's default `staleTimes.dynamic = 0` means the client
Router Cache never reuses a tab's RSC payload. Every return refetches from the
server and re-triggers the route-segment Suspense skeleton.

The performance fix is one config knob: `experimental.staleTimes = { dynamic: 30 }`.
But that knob has a **security side effect** that the 5-agent plan-review proved
is real and load-bearing at this threshold: a non-zero `dynamic` makes the client
Router Cache **retain a principal's server-rendered RSC across soft navigations**,
and middleware does **not** re-run on a Router-Cache hit (the RSC is served from
client memory with no server round-trip). So the same knob that fixes the
skeleton also opens a cross-principal window — unless every navigation that
crosses an authenticated-principal boundary hard-navigates (the only mechanism
that wipes the Router Cache). This plan ships the config change **and** the
enumerated set of hard-nav conversions that keep the isolation invariant intact,
and amends ADR-067 to record the complete two-cache invariant.

> **Premise correction (plan-review P0, Kieran + arch-strategist + spec-flow).**
> An earlier draft claimed "every sign-in path is a full document load, so only
> the sign-out button needs a fix." **That is false.** The *default* login UI is
> email-OTP, verified **client-side** (`lib/auth/useOtpFlow.ts:190` →
> `components/auth/login-form.tsx:62` `router.push(redirectTo ?? "/dashboard")` —
> a soft nav). Only OAuth and clicked-magic-link go through the hard-nav
> `(auth)/callback/route.ts`. The in-session 401/revocation bounces are soft too.
> The cross-*user* leak is therefore reachable, and the fix set is larger than
> one line. See the corrected boundary table below.

## Overview

Two client caches cooperate to make tab-switching instant; **both** must respect
the principal-boundary isolation invariant:

| Layer | Mechanism | Fixed by | Cleared/wiped at principal boundary by |
|---|---|---|---|
| **Data** | SWR in-memory cache | ADR-067 / PR #5639 | `clearSwrCache(mutate)` on sign-out + workspace-switch (FR4) |
| **RSC shell** | App Router Router Cache | **this plan** | **hard navigation** (`window.location.assign` / full document load) — the only Router-Cache wipe |

`staleTimes.dynamic = 30` makes the Router Cache reuse a dynamic route's RSC
payload for 30 s after the last visit — instant tab-return, background
revalidation, no re-shown skeleton. The SWR data layer revalidates independently
on mount/focus, so cached-shell + fresh-data compose correctly.

**Load-bearing isolation invariant (brand_survival_threshold = single-user
incident, inherited from ADR-067):** a warm Router Cache must never serve one
principal's server-rendered RSC to another, and must never survive the loss of a
principal's authorization. Because a Router-Cache hit bypasses middleware, this is
enforced **only** by wiping the cache (via hard navigation) at every navigation
that enters or leaves an authenticated principal context — in **any** tab.

## Problem Statement / Motivation

- Dashboard tabs are separate App Router route segments. The `force-dynamic`
  server tabs (**Inbox, Routines, Workstream, Releases, Audit, Audit/GitHub, Admin
  Analytics, Settings/Privacy, Settings/Scope-grants**) and the segments carrying
  a `loading.tsx` (**`dashboard/`, `dashboard/kb/`, `dashboard/chat/`,
  `dashboard/settings/`, `dashboard/admin/analytics/`**) show a route-segment
  Suspense skeleton whenever their RSC payload is refetched.
- With `staleTimes.dynamic = 0` (Next 15 default; was `30` in Next 14) the Router
  Cache discards the RSC the instant you navigate away, so returning always
  refetches and re-shows the skeleton. This is the residual gap SWR did not, and
  structurally cannot, cover (SWR caches `fetch` results, not the RSC shell).

## Proposed Solution

1. **Config (the perf fix)** — add `experimental.staleTimes = { dynamic: 30 }` to
   `apps/web-platform/next.config.ts`. `static` is left at its Next 15 default
   (300 s); it is irrelevant to the dynamic tab bug and lowering it was dropped as
   unmotivated (see decision-challenges.md #1).
2. **Hard-navigate every authenticated-principal boundary** (the isolation fix
   set — GAP C/D/E/F). The Router Cache is wiped by a full document load; convert
   the soft navs that cross a principal boundary to `window.location.assign`,
   mirroring the existing `org-switcher-container.tsx:131` precedent.
3. **bfcache defense (GAP G)** — ensure authenticated documents are `no-store` so
   browser Back cannot restore a rendered authenticated document (a mechanism
   *separate* from the Router Cache that hard-nav does not defeat).
4. **Amend ADR-067** to record the complete two-cache invariant and the full
   hard-nav boundary set (not just three transitions).
5. **Tests assert the invariants themselves** (cross-user, revocation, Back,
   multi-tab, and the skeleton-not-re-shown perf behavior) via the existing
   Playwright e2e harness — not source/response-shape proxies.

### The corrected principal-boundary set (the isolation deliverables)

"Principal boundary" = entering an authenticated context (sign-in success) OR
leaving/losing one (sign-out, session revocation/expiry bounce), in any tab.

| Transition | Site | Today | Deliverable |
|---|---|---|---|
| OAuth / clicked magic-link sign-in | `app/(auth)/callback/route.ts` (server `NextResponse.redirect`, `no-store`) | **hard** (full load) | none — safe |
| dev-signin | `app/api/auth/dev-signin/route.ts` (303) | **hard** | none — safe |
| Workspace switch | `components/dashboard/org-switcher-container.tsx:131` `window.location.assign` | **hard** | none — safe (precedent) |
| **OTP sign-in success (default UI)** | `components/auth/login-form.tsx:62` `router.push(redirectTo ?? "/dashboard")` | **soft** | **GAP E** → `window.location.assign(redirectTo ?? "/dashboard")` (redirectTo already `safeReturnTo`-sanitized at `:24`) |
| **Onboarding funnel terminal entry to `/dashboard`** | `app/(auth)/setup-key/page.tsx:54`, `app/(auth)/connect-repo/page.tsx:129,217,616`, `signup/page.tsx:59`, `accept-terms/page.tsx:47` | **soft** | **GAP E (funnel)** → hard-nav the terminal `→ /dashboard`/`/dashboard/kb` hops (middleware has no inverse auth redirect, so an authenticated user is never bounced out of this soft funnel) |
| **Sign-out button** | `components/auth/use-sign-out.ts:104` `router.push("/login")` | **soft** | **GAP C** → `window.location.assign("/login")` |
| **Sign-out observed in a sibling tab** | `components/auth/use-sign-out.ts:38-52` `onAuthStateChange("SIGNED_OUT")` — clears SWR only | **soft/none** | **GAP D** → also hard-nav the sibling tab to `/login` |
| **Account deletion** | `components/settings/delete-account-dialog.tsx:41` `router.push("/login?deleted=true")` | **soft** | **GAP F** → `window.location.assign("/login?deleted=true")` (strongest principal-leaving boundary) |
| **401/302 session-revocation bounce** | `app/(dashboard)/dashboard/page.tsx:152`, `hooks/use-kb-layout-state.tsx:94`, `app/(dashboard)/dashboard/kb/[...path]/page.tsx:92` | **soft** (`router.push`/`replace("/login")`) | **GAP F** → hard-nav to `/login`, and also **detect the 302** (the #4307 gate emits `clearSessionAndRedirect`=302→/login which `fetch` follows to 200 HTML — a `status===401`-only guard never fires; add `res.redirected && new URL(res.url).pathname==="/login"`) |
| **WS auth/revocation close** (MEMBERSHIP_REVOKED 4012, AUTH_TIMEOUT, AUTH_REQUIRED, TC_NOT_ACCEPTED) | `lib/ws-client.ts:178-181` `window.location.href = <static map>` | **hard** | none — already hard-nav (static close-code→path map; open-redirect-safe) |
| **Admin analytics warm-cache (env-deprovision)** | `app/(dashboard)/dashboard/admin/analytics/page.tsx:24-70` bakes all-tenant data via `createServiceClient()` (RLS-bypass), no SWR, only `isAdmin` env check | **cached RSC** | **GAP H** → force server re-validation of authz on return (mount-time `router.refresh()`, or move the all-tenant read to an admin-gated API + SWR so a de-provisioned admin gets a fresh 403) |
| **bfcache** (browser Back restores rendered document) | authenticated docs lack `Cache-Control: no-store` (`lib/security-headers.ts`) | eligible on non-`force-dynamic` auth routes | **GAP G** → set `no-store` on authenticated (non-public) document responses **in `middleware.ts`** (route groups can't be selected by the global `security-headers.ts` `source:"/(.*)"`; middleware has the auth + per-path signal) |

## Research Reconciliation — Spec vs. Codebase

| Claim (brief / draft) | Reality (verified at plan + plan-review) | Plan response |
|---|---|---|
| Tabs are App Router routes with `loading.tsx`; dynamic server components | Confirmed for `force-dynamic` server tabs (Inbox/Routines/Workstream/Audit/Releases/Admin-Analytics/Settings-Privacy/Scope-grants). `loading.tsx` at `dashboard/`, `kb/`, `chat/`, `settings/`, `admin/analytics/`. **Dashboard + KB pages are `"use client"`** (KB `page.tsx` is an empty fragment; UI in layout sidebar). | Global config covers all classes. KB inert to staleTimes (empty RSC). |
| `next.config.ts` has NO `staleTimes`; correct location | Confirmed — `experimental` = `serverActions` + `middlewareClientMaxBodySize` (`next.config.ts:55-72`). `withSentryConfig` preserves `experimental.staleTimes`. Next 15.5.18 supports it. | Add `{ dynamic: 30 }` to that block. |
| Workspace switch hard-navigates — safe | Confirmed `org-switcher-container.tsx:131`, explicit "NOT a soft router.push … STALE prior-tenant data" comment. | Cited as the GAP-C/D/E/F precedent. |
| **Every sign-in path full-loads → cache wiped** | **FALSE.** Default OTP verifies client-side → `login-form.tsx:62` soft `router.push`. Only OAuth/magic-link hard-nav via `callback`. | **GAP E.** Corrected everywhere; the cross-user leak is reachable. |
| Only sign-out needs the fix (GAP C) | Incomplete. In-session 401 bounces (`dashboard/page.tsx:152`, `use-kb-layout-state.tsx:94`, `kb/[...path]/page.tsx:92`) and the sibling-tab `SIGNED_OUT` listener are soft. | **GAP D + F.** |
| Back-after-signout closed by hard sign-out | Partial. Hard-nav wipes the **Router Cache** but not **bfcache**; authenticated docs lack `no-store` (`security-headers.ts`). | **GAP G** + real-Back e2e. |
| Middleware re-gates every nav | Only server-reaching navs. Router-Cache hits bypass middleware, deferring the **continuous** per-request gates (revocation #4307 at `middleware.ts:197`, T&C consent, billing) by up to `dynamic` s. | Documented as the continuous-gate boundary; bounded by `dynamic:30` + GAP F + RLS data backstop. |
| KB (`"use client"`) + realtime unaffected | Confirmed. KB RSC empty. Conversations rail (`hooks/use-conversations.ts`) is a persistent realtime client hook in `(dashboard)/layout.tsx`, outside any route RSC. | Documented in Sanity Checks. |

## Technical Considerations

### Why hard navigation is the only wipe, and why middleware is not enough

A Router-Cache hit serves an RSC payload from client memory with **no server
round-trip**, so `middleware.ts` (auth gate, #4307 revocation gate at `:197`, T&C
consent gate, billing) does not run for cached segments. There is no public API to
selectively evict the App Router Router Cache; `router.refresh()` busts only the
*current* route's RSC (learning
`2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md`).
A **hard navigation (full document load) is the canonical full wipe.** Therefore
the isolation invariant reduces to: *every navigation that crosses an
authenticated-principal boundary must hard-navigate.* The boundary set above is
the complete, enumerated realization of that rule.

### The continuous-gate / revocation boundary (arch-strategist P0, spec-flow P0-1)

Middleware enforces authorization **continuously**, per request — not only at
transitions. With `dynamic:30`, a member removed from a workspace / role-changed /
newly-unconsented (JWT still valid ~1 h) can soft-navigate warm RSC shells for up
to 30 s without the revocation/consent gate running. Two revocation sub-cases,
verified distinct (data-integrity-guardian):

- **jti session-revocation** (`revoked=true`): every SWR data fetch hits `/api/*`
  → middleware (matcher covers all non-static, `middleware.ts:380`) → the #4307
  gate (`:197`) → `clearSessionAndRedirect` **302→/login**. This is the *fast*
  backstop — the principal is ejected on the first mount-time fetch, well inside
  30 s, via **middleware, not RLS**. **GAP F must detect this 302** (fetch follows
  it to 200 HTML, so a `status===401`-only guard silently never fires; add
  `res.redirected && new URL(res.url).pathname==="/login"` → `window.location.assign`).
- **workspace-membership removal** (session still valid): does **not** 401/302.
  The cached tabs' data routes fetch via `createServiceClient()` (RLS-bypassing —
  e.g. `app/api/dashboard/foundation-status/route.ts:20`); workspace scoping is
  enforced by **`resolveActiveWorkspace()`'s membership probe**
  (`server/workspace-resolver.ts:413-445`: explicit `workspace_members` query +
  solo shortcut), which returns own/empty scope after removal at **HTTP 200**.
  So the shell background-revalidates (on **mount**, see below) to empty/own-scoped
  data within ≤ `dynamic` s — **empty ≠ leak**. RLS `is_workspace_member`
  (migrations 053/059/075) is the backstop only for **session-client** routes.

- **The real backstop is `resolveActiveWorkspace()`, not RLS** — the plan/ADR must
  cite the membership probe for the (majority) service-client routes. **Phase 2
  adds a verification task**: enumerate every `force-dynamic`/cached tab's data
  route and confirm it routes through `resolveActiveWorkspace()` (or a session
  client), so none returns prior-tenant data during the window.
- **`admin/analytics` is the one exception with NO membership/RLS backstop**
  (`page.tsx:24-70`): it bakes **all-tenant** data (every user's email + all
  conversations) into the RSC via `createServiceClient()`, has **no SWR fetch**,
  and is protected only by an `isAdmin`/`ADMIN_USER_IDS` env check + cache-wipe. A
  user removed from `ADMIN_USER_IDS` (env-deprovision, redeploy-gated) with a warm
  cache could soft-navigate the stale all-tenant RSC for ≤ `dynamic` s — not
  covered by RLS, the #4307 jti gate, or GAP F. **GAP H** closes it (mount-time
  `router.refresh()` re-runs the server authz on return; or move the read to an
  admin-gated API + SWR). The cross-*user* variant (non-admin B OTP-signs-in on
  A's browser) is already closed by GAP E.
- **Residual, accepted:** RSC-only tabs with no mount-time SWR fetch (Audit,
  Audit/GitHub, Privacy, Scope-grants) bake **own** user-scoped rows
  (`.eq(founder_id/user_id, user.id)`), so a stale shell there is the user's own
  data — no cross-principal exposure; bounded to ≤ `dynamic` s. `dynamic:30` is the
  deliberate bound.

> **Revalidation fires on MOUNT, not focus.** An in-app tab switch is a client
> route change within the same document — the OS window does not blur/refocus, so
> SWR `revalidateOnFocus` does **not** fire; `revalidateOnMount` (component mount
> on tab entry) is the load-bearing revalidation. Phase 4 tests assert
> mount-driven revalidation.

### Router Cache vs. bfcache (arch-strategist P1, spec-flow P0-2)

Browser back/forward cache (bfcache) is a **whole-document** snapshot, separate
from the in-memory Router Cache; `window.location.assign` does not clear it. It is
reliably defeated only by `Cache-Control: no-store` on the document response.
`force-dynamic` content tabs emit `no-store` (bfcache-ineligible; confirmed —
Next maps `revalidate=0` → `private, no-cache, no-store, max-age=0, must-revalidate`),
but non-`force-dynamic` authenticated routes (`settings/billing/page.tsx`, the
`"use client"` `dashboard/` and `kb/` pages) do not, so Back could restore a
rendered authenticated document. **GAP G** adds `Cache-Control: no-store` to
authenticated **non-public** document responses. **Location: `middleware.ts`, NOT
`lib/security-headers.ts`** — security-headers is applied globally via
`next.config.ts` `headers()` with `source:"/(.*)"`, and Next route groups
(`(dashboard)`) are stripped from the URL, so no `source` matcher can select
authenticated routes; a global `no-store` would also disable bfcache for public
pages (a perf regression). `middleware.ts` already computes `user` + `PUBLIC_PATHS`
(`:134-139`), so it is the only place with the auth signal and per-path control.
The Back test must exercise a **real** browser Back, not a source assertion. GAP G
is partly orthogonal to staleTimes (bfcache exists at `dynamic:0` too); scoping to
authenticated documents keeps public-page bfcache intact.

### staleTimes value

`dynamic: 30` restores Next 14's default reuse window — long enough for instant
return-nav, short enough that the revocation residual is bounded to 30 s and
background revalidation keeps content fresh. `static` left at default (see
decision-challenges.md #1). The value is a UX/freshness-vs-revocation-latency
tradeoff; deepen-plan may tune.

### Global blast radius (arch-strategist P2, spec-flow P2-8) — public routes

`staleTimes` is app-wide. Public `PUBLIC_PATHS` (`lib/routes.ts`) are covered:
`/shared/[token]` and `/invite/[token]` are token-keyed and principal-neutral —
distinct tokens are distinct route-cache keys, and content is public-by-design (no
cross-token leak within a tab). A `<Link>` prefetch from a public page to an
authenticated route is a real network request through middleware, so an
unauthenticated prefetch caches the `/login` redirect, not authenticated content.
No public-route leak; documented so the ADR reflects the app-wide scope.

### Sanity checks (unaffected / must-verify surfaces)

- **KB tab**: `kb/page.tsx` is an empty `"use client"` fragment; RSC trivial; UI in
  layout sidebar via SWR. staleTimes neither helps nor harms it.
- **Realtime rail**: `use-conversations.ts` subscribes from a persistent layout
  client hook, outside route RSC; unaffected by RSC reuse.
- **`force-dynamic` ≠ Router-Cache opt-out**: `export const dynamic = "force-dynamic"`
  governs *server* rendering only; those routes' RSC is still client-cached (the
  fix relies on this). `router.refresh()` is the per-route freshness escape hatch.
- **Cloudflare/CDN**: no interaction — Router Cache is in-browser-memory and never
  changes response headers; the `no-store` redirects remain the edge guard.
- **Admin impersonation**: no user-facing "view-as-tenant" soft-nav flow exists
  (grepped; `session-proxy.ts`/`agent-runner.ts` hits are internal service-role,
  not a UI nav) — stated as a checked item so a future one is caught.
- **Service worker** (`public/sw.js:44-83`): network-only for HTML/RSC (cache-firsts
  only content-hashed `/_next/static/`, icons; early-returns on `/api`,`/ws`), so it
  retains no per-principal content and hard-nav's non-interaction with it is
  harmless — stated so a future SW change that caches documents is caught.
- **Token refresh**: `TOKEN_REFRESHED` re-mints the same `auth.uid()` — the acting
  principal never changes without a nav (workspace switch, already hard-nav). No
  principal-swap-without-nav vector. Session hijack is unchanged by the 30 s window
  (JWT already valid ~1 h) — not introduced here.
- **Unauthenticated prefetch of authenticated RSC**: middleware redirects
  unauthenticated `/dashboard/*` to `/login` (`middleware.ts:319`), so a `<Link>`
  prefetch caches the login redirect, not authenticated content.
- **Invite-accept while already authenticated** (spec-flow P2-6): the post-accept
  navigation of `/invite/<token>` must be verified; if it soft-navigates into a
  new/switched workspace it needs a hard-nav (like workspace-switch). Verification
  task in Phase 2; not yet resolved at plan time.

## User-Brand Impact

- **If this lands broken, the user experiences:** the returning-to-a-tab skeleton
  flash persists (no perf win); or, if the isolation fix set is incomplete, a
  cross-principal exposure below.
- **If this leaks, the user's workspace/inbox/KB content is exposed via** a warm
  Router Cache serving server-rendered RSC across a principal boundary — the
  single-user trust breach ADR-067 guards. Concrete vectors, each mapped to a
  deliverable (`user-impact-reviewer`: cross-check against the diff):
  - **Cross-user at OTP sign-in / onboarding funnel** — A's warm `/dashboard` RSC
    served to B who OTP-signs-in (or completes the soft funnel) on the same document
    → **GAP E (+ funnel hops)**. The delete→/login→signup-funnel→/dashboard chain is
    reachable because middleware has no inverse auth redirect.
  - **All-tenant leak via `admin/analytics`** — a user removed from `ADMIN_USER_IDS`
    with a warm cache soft-navigates the RSC-baked all-tenant analytics (every user's
    email + all conversations) → **GAP H** (the highest-blast-radius vector).
  - **Account-deletion / same-user-after-signout, browser Back** — Router Cache
    (**GAP C/D/F** incl. `delete-account-dialog.tsx:41`) and bfcache (**GAP G**) closed.
  - **Sign-out in one tab, sibling tab stays warm** → **GAP D**.
  - **Revoked/role-changed member rides warm cache** → jti-revocation ejected by
    middleware 302 (**GAP F** 302-detection); membership-removal returns empty via
    `resolveActiveWorkspace()` probe (own/empty ≠ leak); bounded `dynamic`.
- **Brand-survival threshold:** `single-user incident`. CPO sign-off required at
  plan time before `/work` (also acknowledging the expanded isolation scope, see
  decision-challenges.md #2); `user-impact-reviewer` at review time; deepen-plan
  adds `security-sentinel` + `data-integrity-guardian`.

## Observability

```yaml
liveness_signal:
  what:            "Next.js config recognized: dev/build startup emits NO 'Unrecognized key(s) in ... experimental' warning for staleTimes (silent-ignore is the perf-no-op failure mode)"
  cadence:         "per CI build"
  alert_target:    "CI build log"
  configured_in:   "apps/web-platform/next.config.ts (experimental.staleTimes)"

error_reporting:
  destination:     "Sentry web-platform via SENTRY_DSN (existing)"
  fail_loud:       "Sign-out teardown failures already mirror to Sentry via reportSilentFallback (feature:'auth', op:'signOut') in components/auth/use-sign-out.ts; GAP C/D keep this path"

failure_modes:
  - mode:          "staleTimes key silently ignored (wrong nesting / unsupported) — perf fix is a no-op"
    detection:     "CI build-log grep for 'Unrecognized key' (discoverability_test)"
    alert_route:   "CI build step (blocking)"
  - mode:          "cross-principal RSC served from warm cache (OTP sign-in, Back, sibling tab, or revoked member)"
    detection:     "Playwright e2e per vector (cross-user OTP, real-Back, multi-tab SIGNED_OUT, revoked-session soft-switch) asserting the observable invariant"
    alert_route:   "CI e2e failure (pre-merge, blocking)"
  - mode:          "sign-out teardown fails, still-valid cookies re-hydrate the user to /dashboard after hard-nav (silent sign-out failure)"
    detection:     "unit test of the signOut-throws + local-fallback-fails branch: lands on /login and stays; a user-visible failure signal exists (not only Sentry)"
    alert_route:   "CI test failure + Sentry op:signOut event"

logs:
  where:           "web-platform Docker stdout (pino) + Sentry (existing)"
  retention:       "per existing web-platform retention (unchanged)"

discoverability_test:
  # The config-recognition check (no 'Unrecognized key' for staleTimes) is a
  # BUILD-TIME gate — it lives in `liveness_signal` above and the `next build`
  # CI step (blocking), because it is multi-minute and not a single live probe.
  # This runtime discoverability_test is a no-ssh, no-shell-operator liveness
  # probe an operator can run locally to confirm the deploy target is reachable
  # and serving (the surface this client-side caching change ships to).
  command:         curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/login
  expected_output: "200"
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-067** (`knowledge-base/engineering/architecture/decisions/ADR-067-adopt-swr-client-cache.md`)
— do NOT mint a new ordinal; the tab-switch decision belongs with its origin
record. Add `## Amendment (2026-07-09): Router-Cache staleTimes (RSC-shell half)`
recording, **completely** (arch-strategist: an incomplete invariant is the reject
condition):

- The tab-switch story now has two cooperating client caches: SWR (data) + the
  App Router Router Cache (RSC shell), the latter enabled by
  `experimental.staleTimes = { dynamic: 30 }`.
- A Router-Cache hit **bypasses middleware**, so a warm cache defers not just
  transition-time isolation but the **continuous** per-request gates — #4307
  revocation, T&C consent, billing — by up to `dynamic` s. The invariant is
  therefore "the Router Cache is wiped by hard navigation at **every** navigation
  that crosses an authenticated-principal boundary, in any tab" — enumerate the
  full set: principal-ENTRY (OTP sign-in `login-form.tsx:62` + the onboarding
  funnel's terminal `→/dashboard` hops), principal-LEAVING (sign-out + sibling-tab
  `SIGNED_OUT` + account-deletion + the 401/**302** revocation bounces), and
  workspace switch. Not three transitions.
- **The data backstop is `resolveActiveWorkspace()`'s membership probe, NOT RLS.**
  The cached tabs fetch via `createServiceClient()` (RLS-bypassing); scoping comes
  from the probe (`server/workspace-resolver.ts:413-445`). RLS `is_workspace_member`
  backstops only session-client routes; `kb_files`/`kb_chunks` are owner/shared-keyed.
  Distinguish the two revocation sub-cases: **jti session-revocation** →
  middleware 302→/login on the next fetch (fast, GAP F must detect the 302);
  **membership-removal** → probe returns own/empty at HTTP 200 (no 401, shell stale
  ≤ `dynamic` s, empty ≠ leak).
- **`admin/analytics` is the RSC-baked all-tenant exception** with no probe/RLS
  backstop — GAP H (mount `router.refresh()` / admin-gated API) is its guard.
- Router-Cache wipe ≠ bfcache defeat; authenticated documents get `no-store` in
  `middleware.ts` (GAP G).
- The bounded residual (own-scoped RSC-only tabs, `≤ dynamic` s) is a known,
  accepted bound.
- Route through `/soleur:architecture` so ordinal/index checks run.

### C4 views

**No C4 impact** — verified by reading all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`).
Enumeration: no external human actor added (no new correspondent/recipient); no
external system/vendor (`staleTimes` is an in-process Next.js flag — same basis
ADR-067 recorded for SWR); no container/data-store (Router Cache is in-memory in
the existing `dashboard` React container leaf); no access-relationship change
(`founder → dashboard → api → supabase` topology and per-principal isolation
preserved — caching changes fetch *timing*, and the boundary-wipe invariant keeps
isolation identical). No `.c4` edit; no C4 validation-test run needed.

### Sequencing

Single atomic PR: config + GAP C/D/E/F/G + ADR-067 amendment + tests. GAP E/F/G
close windows the config change itself opens; they must not be split from it.

## Implementation Phases

### Phase 1 — Config (perf fix)
- `apps/web-platform/next.config.ts`: add `staleTimes: { dynamic: 30 }` to the
  existing `experimental` block, with a comment explaining RSC-shell reuse + the
  "isolation via hard-nav boundary wipe" invariant.

### Phase 2 — Isolation fix set (hard-nav conversions)
- **GAP C** `components/auth/use-sign-out.ts:104`: `router.push("/login")` →
  `window.location.assign("/login")`. Keep the awaited `clearSwrCache(mutate)`
  before it. **Remove** the now-unused `useRouter` import, the `const router`, and
  the `[router, mutate]` → `[mutate]` dep-array entry at `:109` (tsc will NOT flag
  these — `noUnusedLocals` is off; remove manually / run eslint). **Rewrite the
  docblock (lines 10-23) and both inline comments (`:18`, `:94`)** that narrate the
  old soft-push teardown, else the AC grep matches them (Kieran P1-1).
- **GAP D** `components/auth/use-sign-out.ts:38-52`: extend the
  `onAuthStateChange("SIGNED_OUT")` listener to also hard-nav the sibling tab
  (`window.location.assign("/login")`) after `clearSwrCache`, so a sign-out in tab
  A wipes tab B's Router Cache too.
- **GAP E** principal-ENTRY navigations into `/dashboard` → `window.location.assign`
  (all use `safeReturnTo`-sanitized values, so `assign` is open-redirect-safe):
  `components/auth/login-form.tsx:62` (OTP success), and the onboarding funnel's
  terminal hops `app/(auth)/setup-key/page.tsx:54`,
  `app/(auth)/connect-repo/page.tsx:129,217,616`, `signup/page.tsx:59`,
  `accept-terms/page.tsx:47`. (Middleware has no inverse auth redirect for these
  PUBLIC_PATHS, so the soft funnel is a live re-entry into a warm prior-principal
  cache — see security-sentinel P1.)
- **GAP F** principal-LEAVING soft navs → hard nav:
  `components/settings/delete-account-dialog.tsx:41`
  (`router.push("/login?deleted=true")` → `window.location.assign(...)`), and the
  in-session 401/302 bounces `app/(dashboard)/dashboard/page.tsx:152`,
  `hooks/use-kb-layout-state.tsx:94`, `app/(dashboard)/dashboard/kb/[...path]/page.tsx:92`.
  **Each 401 handler must ALSO detect the 302** the #4307 gate emits: change
  `if (res.status === 401)` to also fire on
  `res.redirected && new URL(res.url).pathname === "/login"`, then
  `window.location.assign("/login")` (a `status===401`-only guard never fires
  because `fetch` follows the 302 to 200 HTML — security-sentinel P2).
- **GAP G** `middleware.ts` (NOT `security-headers.ts` — route groups are
  URL-stripped): set `Cache-Control: no-store` on authenticated (non-`PUBLIC_PATHS`)
  document responses so browser Back cannot restore a rendered authenticated
  document. Confirm `force-dynamic` tabs already carry it; the target is the
  non-`force-dynamic` authenticated routes.
- **GAP H** `app/(dashboard)/dashboard/admin/analytics/page.tsx`: force server
  re-validation of authz on warm-cache return — either a small mount-time client
  component calling `router.refresh()`, or (stronger, preferred if in budget) move
  the all-tenant `createServiceClient()` read to an admin-gated API route consumed
  via SWR, so a de-provisioned admin gets a fresh 403 instead of a cached
  all-tenant RSC.
- **Verify (backstop enumeration):** for every `force-dynamic`/cached tab, confirm
  its data route routes through `resolveActiveWorkspace()`'s membership probe (or a
  session/RLS client) — none may return prior-tenant data on a service-client read
  without the probe. Note `kb_files`/`kb_chunks` RLS is owner/shared-based (not
  `is_workspace_member`; #4304/#4305).
- **Verify** the `/invite/<token>` accept-while-authenticated post-accept nav; if
  soft into a new/switched workspace, convert to hard nav and add to the boundary
  table.

### Phase 3 — ADR-067 amendment
- Append the complete `## Amendment (2026-07-09)` section (above) via
  `/soleur:architecture`.

### Phase 4 — Tests (assert invariants, not proxies — spec-flow theme)
Use the existing Playwright e2e harness (`apps/web-platform/e2e/`: `mock-supabase.ts`,
`nav-states-shell.e2e.ts`, `otp-login.e2e.ts`, `oauth.e2e.ts`, `team-membership.e2e.ts`).
- **Perf (the fix works):** navigate tab → other tab → back within 30 s and assert
  the `loading.tsx` skeleton does **not** re-mount (one `force-dynamic` server tab
  and one `"use client"` tab, documenting which classes benefit).
- **Cross-user (GAP E):** User A signs out, User B OTP-signs-in in the same browser
  context; assert B's first dashboard paint contains **none** of A's RSC content.
  (Optionally also drive the delete→/login→signup-funnel→/dashboard chain.)
- **Admin-deprovision (GAP H):** warm `admin/analytics` as an admin, remove the user
  from `ADMIN_USER_IDS`, soft-navigate back; assert the all-tenant RSC is not served
  (server re-validation redirects / 403).
- **Revocation (GAP F):** authenticate, warm two tabs, revoke the session
  server-side (jti), soft-switch tabs; assert the mount-time SWR fetch's **302→/login**
  is detected and the tab hard-navs to `/login` (not a stale shell). Assert the
  handler fires on the 302 redirect, not only a literal 401.
- **Back / bfcache (GAP C/G):** sign out, press **real** browser Back; assert
  `url === /login` and no authenticated shell in the DOM; assert authenticated docs
  carry `no-store`.
- **Multi-tab (GAP D):** a `SIGNED_OUT` event in a tab that did **not** call
  `handleSignOut` triggers a hard nav (not just `clearSwrCache`).
- **Sign-out unit (rewrite `test/swr-cache-clear-on-signout.test.tsx`):** the
  FR4 "clear-before-nav" ordering proof must be re-pinned from the `useRouter().push`
  mock to a stubbed `window.location.assign` (happy-dom does not make
  `window.location` spy-able by default — stub it); assert `clearSwrCache` ran
  before the assign. Also cover the signOut-throws + local-fallback-fails branch:
  lands on `/login`, stays there (not looped to `/dashboard` by `login-form.tsx`),
  user-visible failure signal exists.
- **Build recognition:** CI-gated `next build` grep for `Unrecognized key`
  (discoverability_test). No exact-value config unit test (change-detector; the
  value is tunable and silent-ignore is caught by the build grep).

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Config only, rely on "sign-in full-loads" | False premise (OTP is soft) — leaves a live cross-user leak. |
| Keep sign-out soft; hard-nav sign-in only | Misses GAP D/F and the revocation window; sign-out Back resurrects the shell. |
| `router.refresh()` instead of hard-nav | Busts only the current route; sibling/other segments stay warm. Does not wipe the cache. |
| Per-route `staleTimes` | `staleTimes` itself is global; per-route freshness exists only via `cacheLife()` on `"use cache"` boundaries (not adopted — the tabs don't use `use cache`). Boundary-wipe covers all routes uniformly. GAP H uses a mount-time `router.refresh()` for the one route (admin/analytics) that needs per-route re-validation. |
| Set `dynamic` very low (e.g. 5) to shrink the revocation window | Erodes the perf win it exists to deliver; the window is already RLS-backstopped and GAP-F-bounded. deepen-plan may tune. |
| New ADR instead of amending ADR-067 | Fragments the tab-switch story; arch-strategist: amend, but the invariant must be complete (done). |

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `next.config.ts` `experimental` contains `staleTimes: { dynamic: 30 }`;
      CI `next build` emits no `Unrecognized key` for it.
- [ ] All principal-boundary soft navs are converted (GAP C/E/F). The grep must use
      a **query-string-tolerant** regex (the account-delete nav is `"/login?deleted=true"`):
      `git grep -nE '\.(push|replace)\((["\x60])/(login|dashboard)'` over
      `components/auth/login-form.tsx`, `components/auth/use-sign-out.ts`,
      `components/settings/delete-account-dialog.tsx`, `app/(auth)/setup-key/page.tsx`,
      `app/(auth)/connect-repo/page.tsx`, `app/(auth)/signup/page.tsx`,
      `app/(auth)/accept-terms/page.tsx`, `app/(dashboard)/dashboard/page.tsx`,
      `hooks/use-kb-layout-state.tsx`, `app/(dashboard)/dashboard/kb/[...path]/page.tsx`
      returns **0 executable-line matches for principal-boundary hops** (now
      `window.location.assign`); comment mentions in `use-sign-out.ts` are rewritten.
- [ ] GAP F 401 handlers also fire on `res.redirected && pathname==="/login"` (the
      302 revocation path), not `status===401` alone.
- [ ] `use-sign-out.ts` sibling-tab `SIGNED_OUT` listener hard-navigates (GAP D),
      not just `clearSwrCache`; `useRouter` import + `const router` + dep-array
      entry removed.
- [ ] GAP G: authenticated (non-`PUBLIC_PATHS`) document responses carry
      `Cache-Control: no-store`, set in `middleware.ts` (not `security-headers.ts`);
      verified for at least one non-`force-dynamic` authenticated route AND that a
      public route (`/login`, `/shared/*`) is NOT `no-store`.
- [ ] GAP H: `admin/analytics` re-validates authz on warm-cache return (mount
      `router.refresh()` or admin-gated API+SWR); a de-provisioned admin does not see
      a cached all-tenant RSC (e2e).
- [ ] Backstop enumeration: every `force-dynamic`/cached tab's data route routes
      through `resolveActiveWorkspace()`'s membership probe or a session/RLS client
      (documented list); no service-client read returns prior-tenant data sans probe.
- [ ] `clearSwrCache(mutate)` still runs before the sign-out navigation (FR4),
      proven by the rewritten ordering test pinned to `window.location.assign`.
- [ ] Playwright e2e assert the observable invariants (mount-driven, not focus):
      perf (no skeleton re-mount), cross-user OTP, revocation soft-switch, real-Back,
      multi-tab SIGNED_OUT, admin-deprovision warm-cache.
- [ ] Sign-out teardown-failure branch test: lands on `/login`, no loop to
      `/dashboard`, user-visible failure signal.
- [ ] ADR-067 has the complete `## Amendment (2026-07-09)` (full boundary set +
      continuous-gate note + bfcache note + revocation residual/bound).
- [ ] `/invite/<token>` accept-while-authenticated nav verified (hard-nav if it
      crosses a workspace boundary).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; web-platform
      test suite green (vitest per `package.json`); e2e green.

## Test Scenarios

### Regression (the reported bug)
- Given a user on `/dashboard/inbox`, when they switch to `/dashboard/routines` and
  back within 30 s, then inbox renders instantly from the Router Cache with **no**
  re-shown `loading.tsx`, revalidating in the background.

### Isolation (single-user-incident guards — each asserts the invariant, not a proxy)
- Given User A warmed `/dashboard`, when A signs out and User B OTP-signs-in in the
  same browser within 30 s, then B's first dashboard paint shows none of A's RSC
  (GAP E).
- Given an authenticated user with two warm tabs, when their session is revoked
  server-side and they soft-switch tabs within 30 s, then they are bounced to
  `/login`, not shown a stale shell (GAP F + RLS backstop).
- Given a signed-out user, when they press browser Back, then they land on `/login`
  with no authenticated shell in the DOM (Router Cache GAP C/D + bfcache GAP G).
- Given a sign-out in tab A, when tab B receives `SIGNED_OUT`, then tab B hard-navs
  to `/login` (GAP D).
- Given a workspace switch, when `set_current_workspace_id` commits, then the
  existing `window.location.assign("/dashboard")` wipes the cache (unchanged).

### Edge
- Given sign-out teardown fails with still-valid cookies, when the hard-nav loads
  `/login`, then the user stays on `/login` (not re-hydrated to `/dashboard`) and
  sees a failure signal (spec-flow P1-5).
- Given a `force-dynamic` tab whose content is RSC-only, when returned to within
  `dynamic` s, then the cached shell shows briefly and background revalidation /
  next 401 refreshes it (accepted residual; `router.refresh()` escape hatch).

## Success Metrics
- No `loading.tsx` skeleton on return-nav to a tab visited within 30 s.
- Zero cross-principal / Back / multi-tab / revoked-member Router-Cache exposures
  (asserted by the e2e suite).

## Dependencies & Risks

- **Expanded isolation surface** (decision-challenges.md #2): the perf change
  requires GAP C/D/E (incl. funnel) /F (incl. delete-account + 302-detection) /G
  /H — ~9 nav sites + middleware `no-store` + the admin-analytics guard. Each is
  small/precedented, but the set is materially larger than "one config line" —
  CPO sign-off acknowledges it (a smaller `dynamic` is the descope lever).
- **`admin/analytics` all-tenant RSC** (highest blast radius): no probe/RLS
  backstop; GAP H is load-bearing. Prefer the admin-gated-API+SWR form if in budget
  (it also fixes the underlying "all-tenant baked into a cacheable RSC" smell).
- **Continuous-gate revocation residual**: jti-revocation ejected fast by the
  middleware 302 (GAP F must detect it — not `401`-only); membership-removal returns
  own/empty via `resolveActiveWorkspace()` probe (empty ≠ leak); RSC-only own-scoped
  tabs stale ≤ `dynamic` s. RLS is NOT the backstop for the service-client tabs.
- **GAP G location**: must be `middleware.ts`, not `security-headers.ts` (route
  groups are URL-stripped; a global `no-store` regresses public-page bfcache).
- **bfcache is partly orthogonal/pre-existing**: GAP G is the correct fix; scope it
  to authenticated documents to avoid disabling bfcache globally (a perf regression
  on public pages).
- **Hard-nav sign-out dead-end**: teardown failure + valid cookies can re-hydrate
  to `/dashboard`; covered by the failure-branch test + a user-visible signal.
- **Stale RSC shell for RSC-content `force-dynamic` tabs**: ≤ `dynamic` s on
  soft-nav return; background revalidation + `router.refresh()` mitigate.
- **Silent config-ignore**: CI build-grep for `Unrecognized key`.
- Next 15.5.18 confirmed — `experimental.staleTimes` supported; `withSentryConfig`
  preserves the key.

## Domain Review

**Domains relevant:** none (engineering / config + client-auth-navigation change;
no cross-domain business implications). Product/UX Gate: the touched files include
`.tsx` paths (`components/auth/login-form.tsx`, `app/(dashboard)/dashboard/page.tsx`,
`app/(dashboard)/dashboard/kb/[...path]/page.tsx`) that match the mechanical
UI-surface glob, **but every `.tsx` edit is non-visual** — a navigation-mechanism
swap (`router.push`→`window.location.assign`, GAP E/F) and an HTTP header (GAP G),
with **byte-identical rendered output** before/after. Per the ui-surface-terms.md
"no structural/layout change" / "backend-only logic" exclusions, there is no new or
changed page, flow, or visual surface, so `wg-ui-feature-requires-pen-wireframe`
has **no wireframe deliverable** and `ux-design-lead` is not triggered. Product
= NONE. (deepen-plan Phase 4.9's mechanical glob will match these paths; this is
the documented false-positive class — a non-visual edit to a `.tsx` file.)

The `single-user incident` threshold routes this to the escalated eng plan-review
panel (DHH + Kieran + Code-Simplicity + architecture-strategist + spec-flow — all
run; findings consolidated and applied) and, at review time, `user-impact-reviewer`
+ deepen-plan's `security-sentinel` + `data-integrity-guardian`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies reference none of
`next.config.ts`, `use-sign-out`, `login-form`, `staleTimes`, or
`org-switcher-container`.

## References & Research

### Internal
- `knowledge-base/engineering/architecture/decisions/ADR-067-adopt-swr-client-cache.md` (amended; FR4 invariant)
- `apps/web-platform/next.config.ts:55-72` (experimental block)
- `apps/web-platform/components/auth/use-sign-out.ts:104,38-52` (GAP C/D)
- `apps/web-platform/components/auth/login-form.tsx:62` + `lib/auth/useOtpFlow.ts:190` (GAP E — soft OTP sign-in)
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx:152`, `hooks/use-kb-layout-state.tsx:94`, `app/(dashboard)/dashboard/kb/[...path]/page.tsx:92` (GAP F — soft 401 bounces)
- `apps/web-platform/middleware.ts:197` (#4307 revocation gate — the continuous gate deferred by cache hits)
- `apps/web-platform/lib/security-headers.ts` (GAP G — add `no-store`)
- `apps/web-platform/components/dashboard/org-switcher-container.tsx:131` (hard-nav precedent)
- `apps/web-platform/app/(auth)/callback/route.ts` (hard sign-in for OAuth/magic-link only)
- `apps/web-platform/e2e/` (`mock-supabase.ts`, `nav-states-shell.e2e.ts`, `otp-login.e2e.ts`, `oauth.e2e.ts`, `team-membership.e2e.ts`) + `test/swr-cache-clear-on-signout.test.tsx`
- `knowledge-base/project/learnings/best-practices/2026-06-23-swr-adoption-test-isolation-and-shared-key-discipline.md`
- `knowledge-base/project/learnings/ui-bugs/2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md`
- `knowledge-base/project/specs/feat-one-shot-router-cache-staletimes-tab-switch/decision-challenges.md`

### External
- Next.js `experimental.staleTimes` (Router Cache), Next 15 — `dynamic` default `0` (was `30` in 14.x), `static` default `300`.
- Next.js bfcache / `Cache-Control: no-store` on authenticated document responses.

### Related
- PR #5639 / issue #5640 (ADR-067 SWR adoption); follow-up #5644 (conversations rail TR3).
