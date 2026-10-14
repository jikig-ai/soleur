# Tasks: PWA Manifest + Service Worker + Installability

Issue: [#1042](https://github.com/jikig-ai/soleur/issues/1042)
Plan: `knowledge-base/project/plans/2026-03-28-feat-pwa-manifest-service-worker-installability-plan.md`

## Phase 1: Setup (public directory + icons)

- [x] 1.1 Create `apps/web-platform/public/` directory
- [x] 1.2 Generate PWA icons: `public/icons/icon-192x192.png` (192x192), `public/icons/icon-512x512.png` (512x512), `public/icons/apple-touch-icon.png` (180x180), `public/favicon.ico` (32x32)
  - Use Soleur brand colors (neutral-950 background `#0a0a0a`, white "S" lettermark)
  - Placeholder quality is acceptable for P1; design-quality icons before beta (P4)

## Phase 2: Core Implementation

- [x] 2.1 Create `apps/web-platform/app/manifest.ts`
  - Export typed `MetadataRoute.Manifest` function
  - Fields: `name`, `short_name`, `description`, `start_url: "/"`, `display: "standalone"`, `background_color: "#0a0a0a"`, `theme_color: "#0a0a0a"`, `icons` array (512x512 with `purpose: "any maskable"` for Android adaptive icons)
- [x] 2.2 Create `apps/web-platform/public/sw.js` (see plan for complete code)
  - Install event: pre-cache shell assets (icons, favicon), call `self.skipWaiting()`
  - Fetch event: cache-first for `/_next/static/**` (content-hashed); stale-while-revalidate for `/icons/**` and `/favicon.ico` (non-hashed); network-only for HTML, API, WebSocket
  - Activate event: delete old caches via `caches.keys()` filter, call `self.clients.claim()`
  - Skip non-GET requests (guard against WebSocket intercept)
  - Skip `/api/`, `/ws`, `/health` explicitly
  - HTML must always come from network (CSP nonce is per-request)
- [x] 2.3 Create `apps/web-platform/app/sw-register.tsx` (see plan for complete code)
  - Client component that returns `null`, registers SW in `useEffect`
  - Register `/sw.js` with `scope: "/"` and `updateViaCache: "none"`
  - Only register if `"serviceWorker" in navigator`
  - Use `console.warn` not `console.error` for registration failures (non-fatal)
  - No push notification logic (deferred to P3)
- [x] 2.4 Update `apps/web-platform/app/layout.tsx`
  - Import and render `<SwRegister />` component inside `<body>`
  - Add `apple-touch-icon` link to metadata `icons` field
  - Export `viewport` with `themeColor: "#0a0a0a"`
- [x] 2.5 Update `apps/web-platform/middleware.ts`
  - Add `sw.js` to the middleware matcher exclusion pattern
  - Pattern: `"/((?!_next/static|_next/image|favicon.ico|sw\\.js|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"`

## Phase 3: Docker + Deployment

- [x] 3.1 Update `apps/web-platform/Dockerfile`
  - Uncomment/add `COPY --from=builder /app/public ./public` in the runner stage (line 49 area)

## Phase 4: Verification

- [ ] 4.1 Run Lighthouse PWA audit locally (dev mode)
  - Verify "Installable" passes
  - Verify manifest detected with all fields
  - Verify service worker registered and active
- [ ] 4.2 Verify no CSP violations in browser console
- [ ] 4.3 Verify app shell cache populated in DevTools > Application > Cache Storage
- [ ] 4.4 Verify static assets served from SW cache on repeat navigation (Network tab shows "ServiceWorker")
- [ ] 4.5 Verify HTML pages and API requests bypass cache (Network tab shows network fetch)
- [ ] 4.6 Verify auth flow still works (magic link login, callback, session cookies)
- [ ] 4.7 Verify Docker build succeeds with `public/` directory (COPY line active)
- [ ] 4.8 Verify SW registration fails gracefully in private/incognito mode (no errors thrown)
- [ ] 4.9 Verify `/manifest.webmanifest` returns valid JSON without auth redirect
