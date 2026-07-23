---
title: "Tasks — PWA Phase 2 (offline + update/install UX)"
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-23-feat-pwa-offline-install-update-phase-2-plan.md
adr: ADR-137
---

# Tasks — PWA Phase 2

> Derived from the plan. Lane defaulted to `cross-domain` (no spec.md on branch;
> TR2 fail-closed).

## Phase 0 — Preconditions (verify only)

- 0.1 Read `apps/web-platform/middleware.ts:424` matcher; confirm `.html` reaches middleware (→ needs PUBLIC_PATHS).
- 0.2 Confirm CSP: inline styles allowed (`style-src 'unsafe-inline'`), non-nonce inline scripts blocked (`strict-dynamic`).
- 0.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean baseline.

## Phase 1 — Offline page + allowlist

- 1.1 Create `apps/web-platform/public/offline.html` — static, script-free, inline-styled, theme-aware, `<a href>` retry.
- 1.2 Edit `apps/web-platform/lib/routes.ts` — add `/offline.html` to `PUBLIC_PATHS` with rationale comment.

## Phase 2 — Service worker (`public/sw.js`)

- 2.1 Bump `CACHE_NAME` → `soleur-app-shell-v10`.
- 2.2 Add `/offline.html` to `SHELL_ASSETS`.
- 2.3 Remove `self.skipWaiting()` from `install` (keep `clients.claim()` in `activate`).
- 2.4 Add `message` listener: `SKIP_WAITING` → `self.skipWaiting()`.
- 2.5 Add `navigate`-mode fetch branch: `fetch(req).catch(() => caches.match("/offline.html"))`.
- 2.6 Fold in #3002: `cache.put` try/catch + top-level `error`/`unhandledrejection` handler. `Closes #3002`.
- 2.7 Leave `push`/`notificationclick` byte-identical.

## Phase 3 — Client update + install UX

- 3.1 Create `apps/web-platform/lib/pwa/sw-update.ts` (waiting detection, SKIP_WAITING post, guarded controllerchange reload).
- 3.2 Create `apps/web-platform/lib/pwa/install.ts` (beforeinstallprompt capture, standalone + iOS detection).
- 3.3 Create `apps/web-platform/components/pwa/pwa-controls.tsx` (`"use client"`) — update pill + install button + iOS guidance; `null` in standalone.
- 3.4 Mount `<PwaControls/>` in `apps/web-platform/app/(dashboard)/layout.tsx`.
- 3.5 GATE: operator reviews the `.pen` wireframe / chrome before implementing Phase 3 UI.

## Phase 4 — Tests + verification

- 4.1 `test/pwa/sw-update.test.ts`, `test/pwa/install.test.ts` (node, mocked SW/beforeinstallprompt).
- 4.2 `test/components/pwa/pwa-controls.test.tsx` (jsdom).
- 4.3 Middleware: `isPublicPath("/offline.html")` true / `"/offline.htmlx"` false.
- 4.4 Precache-list test: `SHELL_ASSETS` includes `/offline.html`.
- 4.5 `./node_modules/.bin/tsc --noEmit` + `./node_modules/.bin/vitest run test/pwa test/components/pwa` green.
