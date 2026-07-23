---
title: Extend the handwritten service worker over adopting Serwist for PWA Phase 2
status: active
date: 2026-07-23
---

# ADR-137: Extend the handwritten service worker over adopting Serwist

## Context

PWA Phase 2 (offline fallback, update UX, install UX) needs service-worker
changes on top of the Phase 1 baseline (PR #6849, merged 2026-07-23). The
baseline ships a **handwritten** service worker at
`apps/web-platform/public/sw.js` (`CACHE_NAME = "soleur-app-shell-v9"`),
registered by `apps/web-platform/app/sw-register.tsx`. Its current shape:

- **Network-only HTML** — the fetch handler never `respondWith`s HTML; HTML
  always comes from the network so every document carries a fresh per-request
  CSP nonce (`middleware.ts` mints `nonce` per request; `lib/csp.ts` emits
  `script-src … 'nonce-…' 'strict-dynamic'`). A cached HTML document would
  carry a stale nonce and its framework scripts would be CSP-blocked.
- **Cache-first `_next/static/**`** + precached icons/favicon under
  `CACHE_NAME`; the version suffix is the cache-purge lever (bump → `activate`
  deletes stale caches keyed to an old project ref).
- **Push notifications** — `push` / `notificationclick` handlers with
  per-variant tag namespacing and open-redirect origin validation
  (security-sensitive; see learning 2026-04-13-web-push-notification-…).
- **Silent update** — `skipWaiting()` in `install` + `clients.claim()` in
  `activate`, so a new worker swaps assets mid-session with no prompt.

The decision to record: **adopt Serwist (the Next.js `@serwist/next` SW
toolchain) OR extend the existing handwritten `public/sw.js`?**

Constraints that must not regress:

1. **Network-only HTML / CSP nonce.** HTML must keep coming from the network;
   the SW must never serve cached authenticated HTML.
2. **ADR-067 Router-Cache hard-nav invariant.** `feat-tab-content-cache`
   relies on hard navigations (`window.location.assign`) at every
   auth-principal boundary so middleware re-runs. The SW must let online
   navigations reach the network (and thus middleware) untouched.
3. **`CACHE_NAME` / versioning + project-ref purge** must be preserved.
4. **The deploy pipeline is broken repo-wide** (PR #6852 / decision-challenge
   #6860). Phase 2 will merge green but not deploy until that clears. Adding a
   build-time toolchain that reshapes `next.config.ts` raises the blast radius
   of the already-fragile build.

## Decision

**Extend the existing handwritten `public/sw.js`.** Do not adopt Serwist.

The Phase 2 deltas are each small, surgical edits to the handwritten worker
and its registrant:

- **Offline fallback** — precache a static, script-free `public/offline.html`
  and serve it from a new `navigate`-mode branch of the fetch handler *only on
  network failure* (`fetch(req).catch(() => caches.match("/offline.html"))`).
- **Update UX** — remove `skipWaiting()` from `install` (new workers go to
  `waiting`), add a `message` listener that calls `skipWaiting()` on
  `{type:"SKIP_WAITING"}`, and surface an "Update available — Reload"
  affordance client-side that posts the message and reloads on
  `controllerchange`.
- **Install UX** — a client component captures `beforeinstallprompt`
  (Chromium) and renders iOS Add-to-Home-Screen guidance where it is absent.

None of these require a build-time precache manifest, a `next.config.ts`
wrapper, or touching the push handlers.

## Rationale (why not Serwist)

- **New build-toolchain dependency during a broken deploy pipeline.** Serwist
  wraps `next.config.ts` (`withSerwist`) and injects a precache manifest at
  build time. With PR #6852 already breaking the build repo-wide, adding a
  build-graph dependency is exactly the wrong risk to take this cycle.
- **Forced rewrite of security-sensitive push handlers.** Serwist wants to own
  the worker entry; migrating the `push`/`notificationclick` handlers (with
  their per-variant tag namespacing and open-redirect validation) into a
  Serwist source SW is a rewrite of working, review-hardened, security-relevant
  code for zero Phase 2 benefit.
- **Build-time precache model fights the deliberate design.** The current
  worker's `CACHE_NAME` project-ref purge and network-only-HTML posture are
  intentional. Serwist's default `NavigationRoute` + precached app-shell model
  would need careful de-configuration to avoid caching HTML — re-deriving the
  exact invariant we already have.
- **The delta is genuinely small.** Offline fallback ≈ one fetch branch + one
  static file; update UX ≈ delete one line + add a message listener + a client
  toast; install UX ≈ one client component. A toolchain is not warranted.
- **Zero new dependency** keeps `bunfig.toml` `minimumReleaseAge` and the
  supply-chain surface untouched.

## Consequences

- **Positive:** no new dep, no `next.config.ts` change, push handlers
  untouched, all four invariants preserved by construction, reviewable diff.
- **Negative / accepted:** we keep hand-maintaining precache lists (add
  `/offline.html` to `SHELL_ASSETS`) and the update lifecycle by hand. If the
  precache surface ever grows to need build-time revisioning of many hashed
  assets, revisit Serwist (the `_next/static/**` cache-first-on-fetch strategy
  already avoids that need today).
- **Sticky-SW risk** (see plan Risks): a bad fetch handler can brick the
  installed app until storage is cleared. Mitigations: keep the `navigate`
  branch a transparent network passthrough with a catch-only fallback; retain
  the ability to ship a self-unregistering recovery worker as a kill switch.

## Alternatives considered

| Option | Verdict | Why |
| --- | --- | --- |
| Adopt `@serwist/next` | Rejected | Build-toolchain dep amid broken deploy pipeline; forces push-handler rewrite; precache model re-derives invariants we already hold. |
| Extend handwritten `public/sw.js` | **Chosen** | Lowest risk; preserves CACHE_NAME/versioning, network-only HTML, ADR-067 hard-nav, push handlers; zero new dep. |
| Raw Workbox (no Next wrapper) | Rejected | Same rewrite cost as Serwist without the Next integration; still a new dep. |
