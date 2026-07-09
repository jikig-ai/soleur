---
title: "Enabling the App Router Router Cache (staleTimes>0) in a multi-tenant app requires hard-nav at EVERY authenticated-principal boundary"
date: 2026-07-09
category: security-issues
module: web-platform
tags: [nextjs, app-router, router-cache, staletimes, tenant-isolation, bfcache, adr-067]
severity: single-user-incident
pr: feat-one-shot-router-cache-staletimes-tab-switch
related:
  - knowledge-base/engineering/architecture/decisions/ADR-067-adopt-swr-client-cache.md
---

## Problem

The dashboard tab-switch skeleton flash persisted after the SWR data cache
(ADR-067) shipped, because the residual cause is the **Next.js App Router Router
Cache** (the client-side RSC-shell cache), not the data layer. Next 15 defaults
`experimental.staleTimes.dynamic = 0`, so a dynamic route's RSC is discarded on
navigate-away and every tab-return refetches + re-shows `loading.tsx`. The fix is
one config knob (`staleTimes: { dynamic: 30 }`) — but that knob has a
**cross-principal isolation side effect** that is easy to miss and is a
single-user-incident-class risk.

## Key Insight

**A Router-Cache HIT serves an RSC payload from client memory with NO server
round-trip, so `middleware.ts` does not run for cached segments.** In a
multi-tenant app this means a warm cache can serve one principal's
server-rendered RSC to another across a *soft* navigation. Enabling any non-zero
`staleTimes` therefore turns "every navigation that crosses an
authenticated-principal boundary" into a security boundary that must **hard-navigate**
(`window.location.assign` / full document load) — the only wipe of the Router
Cache. There is no API to selectively evict it; `router.refresh()` busts only the
*current* route.

The boundary set is larger than intuition suggests. In particular:
- **The default OTP sign-in is a SOFT nav** (client-side verify →
  `router.push("/dashboard")`), not a full page load — so the cross-*user*
  shared-device leak is reachable. Only OAuth/magic-link go through the hard-nav
  server callback.
- **Session-revocation bounces need 302-detection, not just 401.** The #4307
  middleware gate emits `302 → /login`, and `fetch` transparently follows it to
  200 HTML — so a `status === 401`-only guard silently never fires. Detect
  `res.redirected && new URL(res.url).pathname === "/login"` too.

## Two traps the multi-agent review caught (that the implementation missed)

1. **Second-call-site trap (sweep completeness).** When you hard-nav a
   boundary-crossing action, `git grep` for *every* caller of the underlying
   endpoint, not just the one the plan names. `accept-invite` (which calls
   `set_current_workspace_id` → a workspace switch) has **two** front-end call
   sites — `invite/[token]/invite-actions.tsx` AND
   `components/dashboard/pending-invite-banner.tsx`. The plan enumerated only the
   first; the banner stayed a soft `router.push + router.refresh` and would have
   served the prior workspace's RSC in sibling tabs for ≤`dynamic`s. Mechanical
   guard: for the endpoint that crosses the boundary, `git grep -l
   '/api/workspace/accept-invite'` and convert *all* callers.

2. **`router.refresh()` is paint-then-correct — wrong for sensitive RSC.** For a
   route that bakes sensitive data into the RSC (here `admin/analytics` bakes
   ALL-tenant data — every user's email + all conversations — behind only an
   `ADMIN_USER_IDS` env check), a mount-time `router.refresh()` re-validates authz
   but only AFTER the cached RSC paints — a sub-second flash of the stale
   payload to a de-provisioned admin. The robust fix is to **move the sensitive
   read off the RSC** onto an authz-gated API route consumed via SWR, so a fresh
   403 is returned and nothing sensitive is ever in a cacheable RSC. (Bonus: also
   removes the per-visit double-render of the heavy query.)

## Also

- **Router Cache ≠ bfcache.** A hard nav wipes the Router Cache but not the
  browser back/forward cache. Defeat bfcache with `Cache-Control: no-store` on
  authenticated **document** responses, set in `middleware.ts` (route groups are
  URL-stripped, so a global `security-headers.ts` `source:"/(.*)"` matcher cannot
  select authenticated routes). Scope by `Sec-Fetch-Dest` but **fail-closed**:
  treat an ABSENT header (legacy Safari < 16.4) as a document and apply no-store,
  or those browsers keep bfcache-restoring the authenticated shell after Back.
- **The data backstop for service-client tabs is the membership probe, not RLS.**
  Cached tabs that fetch via the RLS-bypassing `createServiceClient()` are scoped
  by `resolveActiveWorkspace()`'s `workspace_members` probe (returns own/empty at
  HTTP 200 after removal — empty ≠ leak), not by RLS. Enumerate every
  service-client SWR route; RLS backstops only session-client routes.

## Session Errors

- **Nested-heredoc commit message → `parse error near '\n'`.** Recovery: write
  the message with the Write tool, then `git commit -F <file>`. Prevention: never
  build a multi-line commit body via a nested `<<EOF` fallback in one Bash call.
- **Stray placeholder file created at the wrong path.** Recovery: `rm -rf` the
  directory before it was staged. One-off.
- **QA `nav-states` Playwright webServer exited 1 locally.** Cause: the public
  webServer points at an unreachable `test.supabase.co`; a background agent fetch
  → `unhandledRejection` → the app's crash-handler exits the process → Playwright
  aborts the whole run (including the independent `authenticated` project).
  Recovery: verified the app boots with the diff (manual dev start), confirmed the
  diff has zero structural-UI surface in nav-states-covered routes, deferred to
  CI's containerized `e2e`. Prevention: already documented in
  `2026-06-08-nav-states-structural-ui-gate-flakes-on-throttled-local.md` — CI is
  the authoritative structural-UI gate.
- **`sleep 30 && <check>` blocked by the harness.** Prevention: use
  `run_in_background` or a Monitor until-loop; never chain a sleep to poll.
</content>
