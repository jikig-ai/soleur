---
title: "PWA service-worker lifecycle traps: first-visit reload, iOS-webview detection, mandated kill switch, aria-live timing"
date: 2026-07-23
branch: feat-one-shot-pwa-offline-install-phase-2
category: ui-bugs
tags: [pwa, service-worker, controllerchange, ios-safari, user-agent, aria-live, brand-survival, user-impact-reviewer]
---

# Learning: four non-obvious PWA/service-worker traps (Phase 2)

## Problem

PWA Phase 2 (offline fallback + update/install UX, ADR-137: extend the handwritten `public/sw.js`) surfaced four traps that unit tests + tsc passed but multi-agent review caught — two of them user-visible regressions.

## Solution / Key Insights

### 1. `clients.claim()` fires `controllerchange` on the FIRST visit — a reload handler must guard on prior-controller

A handwritten SW whose `activate` calls `self.clients.claim()` (needed so the SW controls the first page load) fires a `controllerchange` event on a **brand-new, uncontrolled** visit — that's the *initial claim*, not an update taking over. A naive "reload the page on the first `controllerchange`" (the standard update-took-effect pattern) therefore reloads **100% of new visitors** on first load.

Fix: capture whether a controller already existed when you START watching, and only reload on a genuine update:
```ts
const hadController = Boolean(container.controller); // false on a first, uncontrolled visit
const handler = () => { if (reloaded) return; reloaded = true; if (hadController) reload(); };
```
Test both arms: `controller` present → reloads once; `controller` absent → never reloads.

### 2. iOS in-app WKWebviews carry "Safari" but omit `Version/` — `isIosSafari()` must positively require `Version/`

Detecting iOS Safari (the only iOS browser that can install a PWA via Share → Add to Home Screen) by *excluding* the dedicated third-party browsers (`CriOS|FxiOS|EdgiOS|GSA`) is **insufficient**: iOS in-app WKWebviews (Facebook `FBAN/FBAV`, Instagram, LinkedIn `LinkedInApp`, Line, TikTok, Snapchat) put `Safari` in the UA, lack those tokens, yet have no Share→A2HS affordance — so an "Add to Home Screen" card is a dead end there. Real iOS Safari UAs always carry a `Version/<n>` token; in-app webviews omit it. Gate positively:
```ts
return /Version\/\d/.test(ua) && /Safari/.test(ua) && !/CriOS|FxiOS|EdgiOS|GSA/.test(ua);
```

### 3. A `single-user-incident` plan that MANDATES a mitigation must IMPLEMENT it in the diff

When a plan's `## User-Brand Impact` (brand-survival threshold `single-user incident`) mandates a specific mitigation — here "a self-unregistering recovery worker remains available as a kill switch" — `user-impact-reviewer` treats **"claimed mitigated-in-diff but absent from diff"** as a BLOCKING finding, even if the prose is well-written. The mitigation must ship or the threshold is unmet. The PWA brick-recovery kill switch = a client-side escape hatch (no separate worker needed): `?sw-reset` on any URL → `navigator.serviceWorker.getRegistrations().then(unregister all)` + `caches.keys()→delete all` → reload to the clean URL, wired into the SW-register component so it runs before (re)registration and on every route. It works even when the worker is broken because HTML is served network-only.

### 4. An `aria-live` region must exist BEFORE its content is inserted

A component that returns `null` until an affordance exists, then mounts a wrapper *with* the affordance, cannot announce it — screen readers only announce mutations to a live region that was **already present**. Keep a stable, always-mounted (possibly empty) `aria-live="polite"` wrapper and conditionally render the children inside it. An empty `pointer-events-none` wrapper is inert (does not intercept clicks), so keeping it mounted costs nothing.

## Session Errors

1. **The `aria-live` always-mounted wrapper broke two existing "empty container" test assertions.** — Recovery: updated the tests to assert "no affordances" (`queryByRole("button")` null) instead of `toBeEmptyDOMElement()`. **Prevention:** when a fix changes a component from "returns null" to "always mounts an (empty) region," grep its test file for `toBeEmptyDOMElement`/empty-container assertions in the same edit.
2. **First in-app-webview test UA lacked the `Safari` token entirely**, so it would have passed `isIosSafari()===false` for the wrong reason (not exercising the new `Version/` discriminator). — Recovery: swapped to a `Safari`-but-no-`Version/` UA. **Prevention:** a negative test for a positive-marker gate must fail ONLY on the marker under test — hold every other discriminator constant.
3. **New statechange-cleanup test needed `removeEventListener` on the mock worker, which the mock lacked.** — Recovery: added it. **Prevention:** when adding a cleanup path that calls `removeEventListener`, extend the event-target mock's remover in the same edit.
4. **The `hadController` reload guard broke the existing "reloads once" test** (mock container had no `controller`). — Recovery: parameterized the mock container to set `controller` for the update case. **Prevention:** changing a function to read a new property means updating the shared mock factory's default shape.

## Tags
category: ui-bugs
module: apps/web-platform (public/sw.js, lib/pwa/*, components/pwa/pwa-controls.tsx, app/sw-register.tsx)
