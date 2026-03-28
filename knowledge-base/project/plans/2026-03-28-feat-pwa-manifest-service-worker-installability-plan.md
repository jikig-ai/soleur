---
title: "feat: PWA manifest + service worker + installability"
type: feat
date: 2026-03-28
issue: "#1042"
milestone: "Phase 1: Close the Loop"
semver: minor
---

## Enhancement Summary

**Deepened on:** 2026-03-28
**Sections enhanced:** 5 (Technical Considerations, Service Worker Strategy, Acceptance Criteria, Test Scenarios, Implementation Notes)
**Research sources:** Next.js PWA guide, web.dev caching strategies, MDN PWA docs, 5 institutional learnings (CSP nonce, Docker build, WebSocket CSP, strict-dynamic rendering)

### Key Improvements

1. Refined caching strategy from cache-first to stale-while-revalidate for non-hashed assets, with cache-first for content-hashed `_next/static/` bundles
2. Added concrete service worker code with complete install/activate/fetch handlers
3. Added service worker + HTTP caching interaction analysis (avoiding double-caching overhead)
4. Integrated institutional learnings about CSP nonce dynamic rendering and Docker public/ directory handling
5. Added edge cases for SW registration timing, update lifecycle, and standalone mode detection

### Institutional Learnings Applied

- `2026-03-20-multistage-docker-build-esbuild-server-compilation.md` -- Docker COPY fails when source path missing; Dockerfile already has defensive comment for `public/`
- `2026-03-20-nonce-based-csp-nextjs-middleware.md` -- CSP nonce extraction requires dynamic rendering; layout.tsx already forces this via `await headers()`
- `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` -- Confirmed: `'strict-dynamic'` blocks all scripts without dynamic rendering; no risk here since layout is already dynamic
- `2026-03-28-csp-connect-src-websocket-scheme-mismatch.md` -- SW fetch handler must not intercept WebSocket upgrade requests; `wss://` is in connect-src
- `2026-03-20-nextjs-static-csp-security-headers.md` -- `worker-src 'self'` was included from the initial security headers implementation

---

# feat: PWA manifest + service worker + installability

## Overview

Add Progressive Web App support so the Soleur web platform is installable on iOS, Android, and desktop. This implements app shell caching only -- no offline mode, since agents require network connectivity. This is Phase 1, item 1.6 from the product roadmap.

## Problem Statement / Motivation

The roadmap mandates a PWA-first architecture: one Next.js codebase covers web browsers, mobile (installable PWA), and desktop (installable PWA). Native apps are deferred unless PWA hits real limits. Currently, the web platform has no manifest, no service worker, and no installability. Users cannot "Add to Home Screen" on any surface. Without PWA installability, the platform feels like a website rather than an app -- no standalone window, no app icon, no app shell caching for faster repeat visits.

## Proposed Solution

Use Next.js App Router's built-in PWA support (no external dependencies like `next-pwa` or `@serwist/next`):

1. **`app/manifest.ts`** -- Next.js generates `/manifest.webmanifest` from a typed TypeScript function
2. **`public/sw.js`** -- Hand-written service worker for app shell caching (static assets only)
3. **Service worker registration** -- Client-side registration in the root layout
4. **App icons** -- 192x192 and 512x512 PNG icons in `public/icons/`
5. **Dockerfile update** -- Copy `public/` directory into the production image
6. **Viewport metadata** -- `theme_color` via Next.js `generateViewport`

### Why hand-written SW over Serwist/next-pwa

- The scope is app shell caching only (CSS, JS, fonts) -- no precache manifest injection needed
- No offline fallback page (agents require network)
- Zero new dependencies
- Easier to audit for security (CSP compliance, cache behavior)
- Serwist/next-pwa add build complexity (webpack plugin, `swSrc`/`swDest` config) that is disproportionate for cache-only behavior

### Why not offline mode

The issue and roadmap explicitly scope this to app shell caching only. Agent conversations require WebSocket connections to the server. Offline mode would require local state management, queueing, and reconciliation -- that is a different feature entirely.

## Technical Considerations

### CSP Compatibility

The existing CSP in `lib/csp.ts` already includes:

- `worker-src 'self'` -- allows service worker registration from same origin
- `script-src` includes `'self'` -- allows loading `/sw.js`

No CSP changes needed.

#### Research Insight: CSP and Dynamic Rendering

The root layout already calls `await headers()` which forces dynamic rendering. This is critical because `'strict-dynamic'` in the CSP only works when Next.js injects nonces during dynamic rendering (see learning `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`). The SW registration script tag will automatically receive the nonce from the framework. No special handling needed for the `<script>` tag that registers the service worker -- Next.js handles nonce injection for all framework-rendered scripts.

### Cross-Origin-Opener-Policy (COOP)

The current COOP header is `same-origin` in `lib/security-headers.ts`. The issue flags this as a concern for OAuth popups, but the auth flow uses redirect-based magic links (`signInWithOtp` with `emailRedirectTo`), not popup-based OAuth. COOP `same-origin` is safe. No changes needed.

### Middleware Matcher

The middleware matcher in `middleware.ts` already excludes static assets:

```typescript
"/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"
```

The service worker at `/sw.js` is **not excluded** by this pattern (it does not match the static extensions). However, Next.js serves files from `public/` directly, before middleware runs. The manifest at `/manifest.webmanifest` is generated by the App Router route at `app/manifest.ts`, which also bypasses the matcher (it matches `manifest.webmanifest` but the route handler runs without middleware intervention since it returns JSON, not HTML).

**Action needed:** Add `sw.js` to the middleware matcher exclusion pattern to ensure the service worker file is never intercepted by the auth middleware. While Next.js serves `public/` files directly in development, the production custom server (`server/index.ts`) routes all non-health, non-API requests through `handle(req, res, parsedUrl)` which invokes Next.js middleware.

#### Research Insight: Middleware Pattern

The updated matcher should be:

```typescript
"/((?!_next/static|_next/image|favicon.ico|sw\\.js|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"
```

Note: `manifest.webmanifest` is generated by the App Router at `app/manifest.ts`, not served from `public/`. It is a route handler, not a static file. The middleware matcher check is irrelevant for it -- Next.js routes it as an API-like response. However, verify that the middleware does not interfere by checking that `/manifest.webmanifest` returns JSON without auth redirects (it should, since the path does not match any auth-required pattern).

### Dockerfile Changes

The Dockerfile already has a comment at line 49: "add COPY --from=builder /app/public ./public when public/ exists". This PR activates that line.

#### Research Insight: Docker Build Verification

From learning `2026-03-20-multistage-docker-build-esbuild-server-compilation.md`: Docker COPY fails when the source path does not exist. Since this PR creates `public/`, the COPY will succeed. But verify with an actual Docker build in the PR -- do not rely on inference. The Dockerfile comment was placed defensively for exactly this scenario.

The `public/` directory is needed in the **builder** stage (so `next build` can reference icons for the manifest) AND in the **runner** stage (so the production server can serve static files). The COPY line should be:

```dockerfile
COPY --from=builder /app/public ./public
```

This goes in the runner stage alongside the existing `.next` copy.

### Icon Generation

PWA installability requires at minimum:

- 192x192 icon (for Android home screen)
- 512x512 icon (for Android splash screen)
- `apple-touch-icon` (180x180 for iOS)
- `favicon.ico` (for browser tab)

Icons should use the Soleur brand colors (dark neutral bg, white/light elements). For MVP, generate simple placeholder icons with the Soleur "S" lettermark.

### iOS Limitations (documented in roadmap)

- Push notifications require iOS 16.4+ AND home-screen installation (deferred to P3, item 3.7)
- iOS kills service worker within seconds of backgrounding
- iOS evicts SW caches after ~14 days of non-use
- No background sync/fetch on iOS
- iOS has no `beforeinstallprompt` event -- users must manually use Share > Add to Home Screen

These are known and accepted for P1. The onboarding walkthrough with iOS install guidance is deferred to P2 (item 2.11).

## Acceptance Criteria

### Functional Requirements

- [ ] `app/manifest.ts` generates a valid web app manifest at `/manifest.webmanifest`
- [ ] Manifest includes: `name`, `short_name`, `description`, `start_url: /`, `display: standalone`, `background_color`, `theme_color`, `icons` (192x192, 512x512)
- [ ] `public/sw.js` implements app shell caching (static assets: CSS, JS, fonts, images)
- [ ] Service worker uses `skipWaiting()` + `clientsClaim()` so deployed updates activate immediately without requiring all tabs to close
- [ ] Service worker registered on page load via client component
- [ ] Root layout includes `<link rel="manifest">` (automatic via `app/manifest.ts`)
- [ ] Root layout exports `viewport` with `themeColor`
- [ ] `public/icons/` contains 192x192 and 512x512 PNG icons
- [ ] `public/icons/apple-touch-icon.png` at 180x180 for iOS
- [ ] Apple-touch-icon `<link>` tag in root layout metadata
- [ ] Middleware matcher updated to exclude `/sw.js`
- [ ] Dockerfile copies `public/` directory into production image
- [ ] PWA installable on Chrome desktop (install prompt appears)
- [ ] PWA installable on Android Chrome (install banner appears)
- [ ] PWA installable on iOS Safari (Add to Home Screen works)
- [ ] App shell loads from cache on repeat visits (verify in DevTools > Application > Cache Storage)
- [ ] Lighthouse PWA audit passes (installable, has manifest, registers SW)

### Non-Functional Requirements

- [ ] No new npm dependencies added
- [ ] Service worker does not cache API responses or HTML pages (network-only for those)
- [ ] Service worker uses cache-first for static assets, network-first for navigation
- [ ] CSP headers remain unchanged and service worker registration succeeds
- [ ] No regression in existing auth flow (magic link, callback, session cookies)

## Test Scenarios

- Given a desktop Chrome browser, when navigating to app.soleur.ai, then the browser install icon appears in the address bar
- Given the PWA is installed on Android, when opening from the home screen, then it launches in standalone mode without browser chrome
- Given iOS Safari, when using Share > Add to Home Screen, then the app installs with the correct icon and name
- Given a repeat visit with warm cache, when the page loads, then static assets (CSS, JS) are served from the service worker cache (verify via Network tab: "(from ServiceWorker)")
- Given the service worker is registered, when navigating to `/dashboard`, then the HTML response comes from the network (not cache)
- Given the service worker is registered, when an API request is made (`/api/*`, `/ws`), then it bypasses the cache entirely
- Given the `manifest.webmanifest` URL, when fetching it, then it returns valid JSON with all required fields
- Given the CSP headers, when registering the service worker, then no CSP violations are logged in the console

### Edge Cases (from research)

- Given the browser is in private/incognito mode, when registering the service worker, then registration fails gracefully (console.warn, no error thrown, app works normally)
- Given a deploy with new static assets, when a returning user visits, then the new service worker activates via skipWaiting and serves fresh assets
- Given the PWA is installed in standalone mode, when clicking an external link, then the browser opens (not the standalone window) -- verify `scope` does not trap external navigation
- Given the service worker is active, when a WebSocket connection is initiated to `/ws`, then the SW fetch handler does not intercept it (method/URL guard)
- Given a slow network, when the service worker is installing, then cached shell assets load on second visit even if first visit was interrupted

### Integration Verification

- **Browser:** Navigate to `https://app.soleur.ai`, open DevTools > Application > Manifest, verify all fields populated and "Installable" status
- **Browser:** Navigate to `https://app.soleur.ai`, open DevTools > Application > Service Workers, verify registered and active
- **Browser:** Open Lighthouse, run PWA audit, verify "Installable" badge passes
- **Docker:** Build production image (`docker build`), run container, verify `/sw.js` is served with correct MIME type (`application/javascript`)
- **Docker:** Verify `/manifest.webmanifest` returns valid JSON from the containerized app

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Icons look unprofessional | Low -- MVP placeholder | Generate clean lettermark; replace with designed icons before beta (P4) |
| Service worker caches stale assets after deploy | Medium | Use cache-busting via Next.js hashed filenames (`_next/static/`) |
| iOS Safari does not show install prompt | Expected | Known iOS limitation; deferred to P2 onboarding walkthrough (2.11) |
| SW registration fails due to custom server routing | Medium | Add `/sw.js` to middleware exclusion; verify in production-like Docker build |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/engineering change with no new vendors, legal obligations, marketing surface, or user-facing pages.

## Implementation Notes

### File Structure

```text
apps/web-platform/
  app/
    manifest.ts          # NEW - generates /manifest.webmanifest
    layout.tsx           # MODIFIED - add viewport themeColor, apple-touch-icon
    sw-register.tsx      # NEW - client component for SW registration
  public/
    sw.js                # NEW - service worker (plain JS, not TypeScript)
    icons/
      icon-192x192.png   # NEW
      icon-512x512.png   # NEW
      apple-touch-icon.png # NEW (180x180)
      favicon.ico        # NEW (32x32)
  middleware.ts          # MODIFIED - add sw.js to exclusion pattern
  Dockerfile             # MODIFIED - uncomment public/ COPY line
```

### Service Worker Caching Strategy

#### Research Insights

**HTTP Caching Interaction:** Next.js serves `/_next/static/**` with `Cache-Control: public, max-age=31536000, immutable` because filenames contain content hashes. The browser HTTP cache already handles these optimally. The SW cache provides a second layer that survives HTTP cache eviction (browser storage pressure, user clearing cache). For content-hashed assets, cache-first is correct because the URL changes when content changes.

**Non-Hashed Assets:** Icons (`/icons/**`) and `favicon.ico` do not have content hashes. Use stale-while-revalidate for these so updates propagate on next visit without requiring a SW version bump.

**Navigation Requests:** Always network-only. The server renders fresh HTML with the current CSP nonce (see learning `2026-03-20-nonce-based-csp-nextjs-middleware.md`). Caching HTML would serve stale nonces, breaking `'strict-dynamic'`.

**WebSocket/API:** Must bypass the service worker entirely. The fetch event handler must check `request.mode === 'websocket'` or URL patterns and fall through to the network. (See learning `2026-03-28-csp-connect-src-websocket-scheme-mismatch.md` -- CSP already allows `wss://`, but SW must not intercept the upgrade request.)

#### Concrete Implementation

```javascript
// public/sw.js -- hand-written service worker for app shell caching

const CACHE_NAME = "soleur-app-shell-v1";

// Static shell assets cached on install (non-hashed assets only).
// _next/static/** are cached on fetch via cache-first strategy.
const SHELL_ASSETS = [
  "/icons/icon-192x192.png",
  "/icons/icon-512x512.png",
  "/icons/apple-touch-icon.png",
  "/favicon.ico",
];

// Install: pre-cache shell assets, activate immediately
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

// Activate: clean old caches, claim clients immediately
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      )
    )
  );
  self.clients.claim();
});

// Fetch: route by URL pattern
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Skip non-GET requests (POST, WebSocket upgrade, etc.)
  if (event.request.method !== "GET") return;

  // Skip API routes, WebSocket, and health check
  if (
    url.pathname.startsWith("/api/") ||
    url.pathname === "/ws" ||
    url.pathname === "/health"
  ) {
    return;
  }

  // Cache-first for content-hashed Next.js bundles
  if (url.pathname.startsWith("/_next/static/")) {
    event.respondWith(
      caches.match(event.request).then(
        (cached) =>
          cached ||
          fetch(event.request).then((response) => {
            if (response.ok) {
              const clone = response.clone();
              caches.open(CACHE_NAME).then((cache) =>
                cache.put(event.request, clone)
              );
            }
            return response;
          })
      )
    );
    return;
  }

  // Stale-while-revalidate for non-hashed shell assets (icons, favicon)
  if (
    url.pathname.startsWith("/icons/") ||
    url.pathname === "/favicon.ico"
  ) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        const fetchPromise = fetch(event.request).then((response) => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) =>
              cache.put(event.request, clone)
            );
          }
          return response;
        });
        return cached || fetchPromise;
      })
    );
    return;
  }

  // Network-only for everything else (HTML, manifest, etc.)
  // HTML must come from network to get fresh CSP nonce
});
```

#### Edge Cases

- **SW fetch and WebSocket:** The `method !== "GET"` guard handles most cases, but WebSocket upgrades technically start as GET. The URL pattern guard (`/ws`) provides defense-in-depth.
- **Opaque responses:** Cross-origin requests (if any) may return opaque responses that cannot be inspected. The `response.ok` check prevents caching error responses.
- **Cache storage quota:** Mobile browsers limit SW cache to ~50MB. Content-hashed bundles accumulate over deploys. Old versions are evicted by the activate handler, but runtime-cached `_next/static/` entries persist. Consider periodic cache cleanup if bundle sizes grow significantly.
- **SW registration timing:** Register the SW after the page load event (or in `useEffect`) to avoid competing with critical resource loading on first visit.

### `app/manifest.ts` Complete Implementation

```typescript
import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Soleur — One Command Center, 8 Departments",
    short_name: "Soleur",
    description:
      "One command center for your entire business. AI agents across 8 departments plan, execute, and compound knowledge.",
    start_url: "/",
    display: "standalone",
    background_color: "#0a0a0a",
    theme_color: "#0a0a0a",
    icons: [
      {
        src: "/icons/icon-192x192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/icons/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any maskable",
      },
    ],
  };
}
```

#### Research Insights

- **`display: "standalone"`** removes browser chrome (address bar, tabs). This is the correct mode for an app-like experience. `"fullscreen"` is for games/kiosks; `"minimal-ui"` retains a minimal bar.
- **`background_color`** is shown during the app splash screen on Android before the first paint. Match it to the body background (`neutral-950 = #0a0a0a`) for a seamless launch.
- **`theme_color`** sets the OS-level tint (Android status bar, desktop title bar). Dark theme matches the app's aesthetic.
- **`purpose: "any maskable"`** on the 512x512 icon enables Android adaptive icon support (the OS crops the icon to circles, squircles, etc.). The icon design must have sufficient padding (safe zone is the inner 80%) to avoid content clipping.
- **`id` field** (optional, not included): sets a canonical identity for the PWA. If omitted, browsers use `start_url`. Fine for a single-domain app.
- **`scope` field** (optional, not included): restricts which URLs the PWA navigates to in standalone mode. If omitted, defaults to the manifest's directory. Since manifest is at root (`/`), all paths are in scope.

### `app/sw-register.tsx` Complete Implementation

```tsx
"use client";

import { useEffect } from "react";

export function SwRegister() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker
        .register("/sw.js", { scope: "/", updateViaCache: "none" })
        .catch((err) => {
          // Non-fatal: app works without SW, just no caching
          console.warn("SW registration failed:", err);
        });
    }
  }, []);

  return null;
}
```

#### Research Insights

- **`updateViaCache: "none"`** ensures the browser always checks for a fresh `sw.js` file, bypassing HTTP cache. Critical for deploying SW updates.
- **Register in `useEffect`** (not at module scope) to defer registration until after hydration. This prevents the SW install fetch from competing with critical page resources on first load.
- **Error handling:** `console.warn` not `console.error` -- SW failure is non-fatal. The app works fully without caching. Sentry should not be flooded with expected failures (e.g., private browsing mode blocks SW registration).
- **No `navigator.serviceWorker.ready` await** -- registration is fire-and-forget. The SW activates asynchronously. No UI depends on SW readiness.

## References and Research

### External Documentation

- [Next.js PWA Guide](https://nextjs.org/docs/app/guides/progressive-web-apps) -- official App Router PWA documentation (manifest.ts, SW registration, install prompt)
- [Web App Manifest spec](https://developer.mozilla.org/en-US/docs/Web/Manifest) -- W3C manifest fields
- [web.dev: Service Worker Caching Strategies](https://web.dev/learn/pwa/serving) -- cache-first, stale-while-revalidate, network-first patterns
- [Chrome DevDocs: Workbox Caching Strategies](https://developer.chrome.com/docs/workbox/caching-strategies-overview) -- strategy selection guidance
- [web.dev: Service Worker and HTTP Caching](https://web.dev/articles/service-worker-caching-and-http-caching) -- interaction between SW cache and browser HTTP cache
- [MDN: PWA Caching Guide](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Caching) -- cache storage API, quota, eviction
- [web.dev: PWA Update Lifecycle](https://web.dev/learn/pwa/update) -- skipWaiting, clients.claim, update flow

### Codebase References

- Existing CSP: `apps/web-platform/lib/csp.ts` (line 59: `worker-src 'self'`)
- Existing security headers: `apps/web-platform/lib/security-headers.ts` (COOP: same-origin)
- Existing middleware: `apps/web-platform/middleware.ts` (matcher pattern)
- Existing Dockerfile: `apps/web-platform/Dockerfile` (line 49: public/ comment)
- Existing layout: `apps/web-platform/app/layout.tsx` (metadata, viewport, `await headers()`)
- Roadmap: `knowledge-base/product/roadmap.md` (Phase 1 item 1.6, iOS limitations)

### Institutional Learnings Applied

- `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md` -- CSP nonce injection via middleware; `worker-src 'self'` already present
- `knowledge-base/project/learnings/2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` -- `await headers()` in layout forces dynamic rendering; SW scripts get nonces
- `knowledge-base/project/learnings/2026-03-28-csp-connect-src-websocket-scheme-mismatch.md` -- SW must not intercept WebSocket connections
- `knowledge-base/project/learnings/2026-03-20-multistage-docker-build-esbuild-server-compilation.md` -- Docker COPY fails on missing source; `public/` comment is defensive
- `knowledge-base/project/learnings/2026-03-20-nextjs-static-csp-security-headers.md` -- Initial security headers implementation that included `worker-src 'self'`

### Issue Tracking

- Related issue: [#1042](https://github.com/jikig-ai/soleur/issues/1042)
- Deferred: Install guidance in onboarding (P2, #674 item 2.11)
- Deferred: Push notifications (P3, #1049 item 3.7)
