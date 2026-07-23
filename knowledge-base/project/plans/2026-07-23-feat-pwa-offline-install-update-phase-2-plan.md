---
title: "feat: PWA Phase 2 — offline fallback + update/install UX (apps/web-platform)"
date: 2026-07-23
status: ready
type: enhancement
branch: feat-one-shot-pwa-offline-install-phase-2
lane: cross-domain
milestone: "Phase 1: Close the Loop (Mobile-First, PWA)"
adr: ADR-137
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ✨ PWA Phase 2 — offline fallback + update/install UX

## Enhancement Summary

**Deepened on:** 2026-07-23
**Sections enhanced:** Architecture rationale, SW fetch handler, client update/install, offline page, Risks.
**Gates run (all pass):** 4.6 User-Brand Impact (threshold `single-user incident`, valid); 4.7 Observability (5 fields, non-placeholder, no-ssh); 4.8 PAT-shaped halt (no match); 4.4 precedent-diff (no offline-fallback precedent — novel branch, flagged); 4.45 verify-the-negative (all negative claims confirmed against `public/sw.js`).

### Key improvements

1. **Verified the network-only-HTML claim against the live worker** — today `public/sw.js` has exactly one `respondWith` (line 63, the static-asset branch); HTML has none, so network-only HTML is confirmed, and the new `navigate` branch is the *only* HTML interception (passthrough + catch-only). `skipWaiting` is at line 21 (install chain, to remove); `clients.claim` is at line 36 (activate, to keep).
2. **Confirmed CSP shape makes the offline page constraint concrete** — `script-src … 'strict-dynamic'` means a cache-served page cannot run inline scripts (stale/absent nonce); `style-src 'self' 'unsafe-inline'` allows inline `<style>`. Offline page = zero `<script>`, inline styles, `<a href>` retry.
3. **Confirmed `/offline.html` reaches middleware** — matcher (`middleware.ts:424`) excludes `sw\.js` and image extensions but NOT `.html`, so the PUBLIC_PATHS entry is load-bearing for correct precache (else `cache.addAll` captures a 307→/login).

### New considerations discovered

- **Sticky-SW recovery is the top risk** — added a kill-switch (self-unregistering recovery worker) note; the `navigate` branch must be catch-only so an online fetch that *resolves with a 4xx/5xx* still returns the network response (only a thrown/rejected fetch → offline shell). Do NOT branch on `response.ok`.
- **`beforeinstallprompt` requires `preventDefault()` synchronously** or Chromium shows its own mini-infobar; the deferred event is single-use (re-fires only on a later eligibility change).

## Overview

Builds on PWA Phase 1 (PR #6849, merged 2026-07-23), which shipped a correct
manifest (`start_url:/dashboard`, `scope:/`, shortcuts, `appleWebApp`,
`viewportFit:cover`) and a handwritten service worker at
`apps/web-platform/public/sw.js` (`CACHE_NAME "soleur-app-shell-v9"`,
network-only HTML, cache-first `_next/static`, silent `skipWaiting`, push
handlers), registered by `apps/web-platform/app/sw-register.tsx`.

Phase 2 adds three capabilities, all by **extending the handwritten worker**
(architecture decision recorded in **ADR-137** — Serwist rejected as a
build-toolchain dependency during a broken deploy pipeline that would force a
rewrite of the security-sensitive push handlers):

1. **Offline fallback** — precache a static, script-free `public/offline.html`
   and serve it *only when a navigation's network fetch fails*. Online
   navigations stay network-only (fresh CSP nonce; ADR-067 hard-nav preserved).
2. **Update UX** — stop silently swapping assets mid-session. New worker
   versions go to `waiting`; a non-intrusive "Update available — Reload"
   affordance lets the user opt in, which posts `SKIP_WAITING` and reloads.
3. **Install UX** — capture `beforeinstallprompt` (Chromium) → "Install app"
   button; where it is absent (iOS Safari) show Add-to-Home-Screen guidance.
   Suppress all install chrome when already running standalone.

**Out of scope (do NOT touch):** the deploy pipeline break (PR #6852 /
decision-challenge #6860) — Phase 2 merges green but will not deploy until that
clears; Phase 3 (per-surface mobile UX incl. kanban mobile layout).

## Research Reconciliation — Spec vs. Codebase

Premise validation (checked at plan time against `origin/main` + live `gh`):

| Spec / description claim | Reality (verified) | Plan response |
| --- | --- | --- |
| SW at `public/sw.js`, `CACHE_NAME "soleur-app-shell-v9"`, network-only HTML, skipWaiting+claim, no prompt | Confirmed verbatim (read the file) | Extend in place; bump `CACHE_NAME` → `v10`. |
| Registered via `<SwRegister/>` in `app/layout.tsx` | Confirmed; `sw-register.tsx` also chains push subscription; registered with `updateViaCache:"none"` | Leave SwRegister registration+push untouched; add a separate `<PwaControls/>` for update/install chrome. |
| CSP nonce / network-only HTML constraint | Confirmed: `middleware.ts` mints per-request nonce; `lib/csp.ts` `script-src … 'nonce-…' 'strict-dynamic'` (non-nonce inline scripts blocked); `style-src 'self' 'unsafe-inline'` (inline styles allowed) | Offline page = **script-free** static HTML with inline `<style>` and an `<a href>` retry (no JS). |
| ADR-067 "Router-Cache hard-nav invariants" | ADR-067 is *SWR client cache*; the Router-Cache `staleTimes` hard-nav (`window.location.assign` at auth boundaries) is the same feat-tab-content-cache line (PR #6252). Invariant holds. | `navigate` branch is a transparent network passthrough — online navigations reach middleware unchanged. |
| Serwist not currently a dependency | Confirmed: no `serwist`/`workbox`/`next-pwa` in `apps/web-platform/package.json` | Adopting it = new dep + `next.config.ts` wrapper → rejected (ADR-137). |
| PR #6852 broke deploy; tracked in #6860 | #6860 OPEN ("decision-challenge: inline-vs-import strip.ts …") | Merge green only; no deploy, no pipeline edits. |
| Highest ADR = 136 | Confirmed (`ADR-136`) | New decision = **ADR-137**. |
| No toast/sonner library | Confirmed: app uses bespoke `setToast` state (workstream-board) | Update/install affordances are bespoke components — no new dep. |

## Architecture Decision (ADR-137)

**Extend the handwritten `public/sw.js`; do not adopt Serwist.** Full rationale,
constraints, and alternatives table:
`knowledge-base/engineering/architecture/decisions/ADR-137-extend-handwritten-service-worker-over-serwist.md`.

## User-Brand Impact

**If this lands broken, the user experiences:** a bricked installed PWA — a
malformed `navigate`-mode `respondWith` (or a bad `activate`) can make every
navigation fail or serve the offline shell while online, and a service worker
is *sticky* (survives reloads; recovery needs clearing site data). Secondary:
an update prompt that reload-loops, or an "Install"/"Add to Home Screen"
affordance that errors or shows after install.

**If this leaks, the user's data is exposed via:** n/a for confidentiality —
`public/offline.html` is static, public-by-design, carries no session or PII,
and the SW never serves cached authenticated HTML (network-only HTML
preserved). The threshold below is driven by **availability**, not data
exposure.

**Brand-survival threshold:** `single-user incident` — a sticky bad worker can
render the installed app unusable for a user until they clear storage, and
per-user recovery is hard. This mandates: the `navigate` branch stays a
transparent network passthrough with catch-only fallback; a self-unregistering
recovery worker remains available as a kill switch; `user-impact-reviewer` runs
at review time; CPO sign-off before `/work` (see frontmatter
`requires_cpo_signoff: true`).

## Implementation Phases

Phase order is load-bearing: the offline page + PUBLIC_PATHS entry must exist
before the SW precaches it; the SW `message` contract must exist before the
client posts to it.

### Phase 0 — Preconditions (verify, do not code)

- Read `apps/web-platform/middleware.ts:424` matcher — confirms `sw\.js` is
  excluded but `.html` is **not**, so `/offline.html` reaches middleware and
  **must** be added to `PUBLIC_PATHS` (else `cache.addAll("/offline.html")`
  precaches a `307 → /login`). This is the
  `2026-05-29-nextjs-metadata-routes-need-public-paths-allowlist` class.
- Confirm CSP: `style-src 'self' 'unsafe-inline'` (inline styles OK),
  `script-src … 'strict-dynamic'` (non-nonce inline scripts blocked → offline
  page must be script-free).
- Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` to capture a
  clean baseline (Phase 1 learning: treat "this compiles" as a precondition to
  verify, not a fact).

### Phase 1 — Static offline page + route allowlist

- **Create `apps/web-platform/public/offline.html`** — self-contained, static,
  **script-free**: branded "You're offline" message, inline `<style>`
  (theme-aware via `prefers-color-scheme`, mirrors `#0a0a0a` forge-dark), and a
  script-free retry `<a href="/dashboard">Try again</a>`. No `<script>`, no
  nonce dependency.
- **Edit `apps/web-platform/lib/routes.ts`** — add `"/offline.html"` to
  `PUBLIC_PATHS`, adjacent to `/manifest.webmanifest`/`/robots.txt`, with a
  rationale comment (public-by-design; precached by the SW; must bypass
  Supabase auth or the precache captures the login redirect). Keeps CSP (public
  branch still runs `withCspHeaders`).

### Phase 2 — Service worker: offline fallback + update contract (`public/sw.js`)

- Bump `CACHE_NAME` `"soleur-app-shell-v9"` → `"soleur-app-shell-v10"`.
- Add `"/offline.html"` to `SHELL_ASSETS` (precached on install).
- **Remove `self.skipWaiting()`** from the `install` handler (new workers now
  go to `waiting` instead of activating mid-session). Keep `clients.claim()` in
  `activate` (first-install control is unaffected — with no existing controller
  a worker still activates immediately).
- **Add a `message` listener:**
  `self.addEventListener("message", (e) => { if (e.data?.type === "SKIP_WAITING") self.skipWaiting(); });`
- **Add a `navigate` branch** to the fetch handler, after the API/ws/health
  early-return and before/around the static-asset branch:
  ```js
  // Navigation: network-first; fall back to the precached static offline
  // shell ONLY on network failure. Online navigations reach the network
  // (and middleware) untouched — preserves network-only HTML (fresh CSP
  // nonce) and the ADR-067 hard-nav boundary.
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match("/offline.html"))
    );
    return;
  }
  ```
  Verify `fetch(event.request)` preserves redirect/credential semantics for
  navigations (pass the original `Request`).
- **Fold in #3002** (code-review overlap): wrap `cache.put` in the static-asset
  branch in try/catch (quota-exceeded is non-fatal) and add a top-level
  `self.addEventListener("error", …)` / `"unhandledrejection"` handler that
  `console.warn`s without breaking fetch handling. `Closes #3002`.
- **Do NOT touch** the `push` / `notificationclick` handlers.

### Phase 3 — Client update affordance (`components/pwa/` + `lib/pwa/`)

- **Create `apps/web-platform/lib/pwa/sw-update.ts`** (testable, no JSX):
  helpers to (a) detect a `waiting` worker on an existing registration and via
  `updatefound` → new worker `statechange === "installed"` while
  `navigator.serviceWorker.controller` exists; (b) `postMessage({type:"SKIP_WAITING"})`
  to the waiting worker; (c) a `controllerchange` one-shot reload guarded by a
  module-level `reloading` flag (no reload loop).
- **Create `apps/web-platform/lib/pwa/install.ts`** (testable): `beforeinstallprompt`
  capture/defer, `appinstalled` handling, and standalone detection
  (`matchMedia('(display-mode: standalone)').matches || navigator.standalone`),
  plus iOS-Safari detection (no `beforeinstallprompt`).
- **Create `apps/web-platform/components/pwa/pwa-controls.tsx`** (`"use client"`):
  uses the two lib modules. Renders (i) a non-intrusive "Update available —
  Reload" toast/pill when a worker is waiting; (ii) an "Install app" button when
  a `beforeinstallprompt` is captured; (iii) an iOS "Add to Home Screen"
  guidance card (share → Add to Home Screen) when on iOS Safari and not
  standalone. Renders `null` when standalone / nothing to show. Does **not**
  register the SW — it reads the existing registration via
  `navigator.serviceWorker.getRegistration()`.
- **Mount `<PwaControls/>`** in `apps/web-platform/app/(dashboard)/layout.tsx`
  (authenticated surface — install/update chrome stays inside the app, not on
  `/login`).

### Phase 4 — Tests + verification

- Vitest unit tests for `lib/pwa/sw-update.ts` and `lib/pwa/install.ts` under
  `test/pwa/*.test.ts` (node) with mocked `navigator.serviceWorker` /
  `beforeinstallprompt` (vitest include glob is `test/**/*.test.ts`; **not**
  co-located — `bunfig.toml` blocks bun test).
- Component test for `pwa-controls.tsx` under `test/components/pwa/*.test.tsx`
  (jsdom/happy-dom; include glob `test/**/*.test.tsx`).
- Middleware test: `isPublicPath("/offline.html") === true` and prefix-collision
  negative `isPublicPath("/offline.htmlx") === false` (mirror the robots.txt
  regression tests).
- A precache-list assertion test: `SHELL_ASSETS` in `public/sw.js` includes
  `"/offline.html"` (guards the precache-drift class).
- Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and
  `./node_modules/.bin/vitest run test/pwa test/components/pwa` at this phase.

## Files to Edit

- `apps/web-platform/public/sw.js` — CACHE_NAME v10, precache offline.html,
  drop `skipWaiting` from install, add `message` listener + `navigate` branch,
  fold in #3002 (cache.put guard + global error handler).
- `apps/web-platform/lib/routes.ts` — add `/offline.html` to `PUBLIC_PATHS`.
- `apps/web-platform/app/(dashboard)/layout.tsx` — mount `<PwaControls/>`.

## Files to Create

- `apps/web-platform/public/offline.html` — static, script-free offline shell.
- `apps/web-platform/lib/pwa/sw-update.ts` — update-lifecycle helpers.
- `apps/web-platform/lib/pwa/install.ts` — install/standalone/iOS helpers.
- `apps/web-platform/components/pwa/pwa-controls.tsx` — update + install chrome.
- `apps/web-platform/test/pwa/sw-update.test.ts`
- `apps/web-platform/test/pwa/install.test.ts`
- `apps/web-platform/test/components/pwa/pwa-controls.test.tsx`
- (middleware/offline allowlist assertions fold into the existing
  `test/middleware*.test.ts`; add if no suitable file exists.)

## Open Code-Review Overlap

2 open code-review issues touch files this plan edits:

- **#3002** — "add service-worker global error handler for cache.put quota
  failures" (touches `public/sw.js`). **Fold in** — we are already rewriting
  the fetch handler; add the `cache.put` try/catch + global error/rejection
  handler in the same PR. `Closes #3002` in the PR body.
- **#3564** — "establish Core Web Vitals infrastructure for apps/web-platform"
  (touches `app/layout.tsx`). **Acknowledge** — a separate perf-instrumentation
  concern, orthogonal to PWA offline/install/update; leave open, no change here.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `public/offline.html` exists, contains **no** `<script>` element, and
      renders a branded offline message + a script-free `<a href>` retry.
- [ ] `isPublicPath("/offline.html") === true`; `isPublicPath("/offline.htmlx")
      === false` (regression tests pass).
- [ ] `public/sw.js`: `CACHE_NAME === "soleur-app-shell-v10"`; `SHELL_ASSETS`
      includes `"/offline.html"`; the `install` handler contains **no**
      `skipWaiting`; a `message` listener calls `skipWaiting()` on
      `{type:"SKIP_WAITING"}`; a `navigate`-mode branch does
      `fetch(...).catch(() => caches.match("/offline.html"))`; `push` /
      `notificationclick` handlers are byte-identical to Phase 1.
- [ ] `lib/pwa/sw-update.ts` reload path is guarded against a `controllerchange`
      reload loop (unit test asserts a single reload).
- [ ] `pwa-controls.tsx` renders `null` when
      `matchMedia('(display-mode: standalone)').matches` (unit/component test).
- [ ] `beforeinstallprompt` is captured (`preventDefault` called) and drives the
      "Install app" affordance; iOS-Safari path shows guidance instead
      (component test).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] `./node_modules/.bin/vitest run test/pwa test/components/pwa` green.
- [ ] PR body: `Closes #3002`. `Ref #6849` (Phase 1). Do **not** reference
      #6852/#6860 as closing.

### Post-merge (operator / post-deploy — blocked on #6852)

- [ ] After the deploy pipeline clears (#6852/#6860) and this deploys:
      `curl -sI https://app.soleur.ai/offline.html` returns `HTTP 200` with
      `content-type: text/html` (NO ssh). Automation: single `curl`, run by the
      shipping agent once deploy is unblocked — not operator-manual.
- [ ] Manual QA (Chromium): install the app, ship a trivial SW change, confirm
      the "Update available — Reload" affordance appears (not a silent swap) and
      accepting it reloads once. Automation: not feasible pre-deploy (requires a
      real second SW version on a deployed origin); e2e navigate-smoke covers
      the online path pre-merge.

## Domain Review

**Domains relevant:** Product/UX. (Engineering/security carried as plan Risks;
no Legal/Finance/Growth surface — static public page, no PII, no vendor, no
schema.)

### Product/UX Gate

**Tier:** blocking — mechanical escalation fires: this plan creates
`components/pwa/pwa-controls.tsx` (matches `components/**/*.tsx`).
**Decision:** reviewed (partial) — pipeline subagent has no Task tool, so the
`ux-design-lead` / `spec-flow-analyzer` / `cpo` agent pipeline could not be
spawned inline.
**Agents invoked:** none (Task unavailable in this pipeline planning subagent).
**Skipped specialists:** ux-design-lead (Task/Pencil unavailable in pipeline —
see wireframe gate below), spec-flow-analyzer (Task unavailable), cpo (Task
unavailable; `requires_cpo_signoff` recorded for the operator).
**Pencil available:** no.

#### Wireframe gate (`wg-ui-feature-requires-pen-wireframe`)

The install/update UI is minor chrome (toast/pill + button + iOS guidance
card). Per the ARGUMENTS, a wireframe is acceptable but minimal and **the
operator reviews it before implementation**. A textual wireframe spec is below;
a `.pen` wireframe + operator sign-off is a **pre-`/work` gate** (do not
implement Phase 3 UI before the operator approves the chrome).

Textual wireframe (non-intrusive, bottom-anchored, respects safe-area insets):

- **Update pill** — small rounded pill, bottom-center above the composer safe
  area: `⟳ Update available` + `Reload` text button. Dismissible. Appears only
  when a worker is `waiting`.
- **Install button** — subtle secondary button (settings/header overflow or a
  one-time bottom banner): `⤓ Install app`. Appears only when
  `beforeinstallprompt` was captured; hidden after `appinstalled`.
- **iOS guidance card** — small dismissible card: "Install Soleur: tap the
  Share icon, then *Add to Home Screen*." Appears only on iOS Safari, not
  standalone, once per session/dismissal.
- All three render `null` in standalone mode and never overlap the composer
  (anchor to the composer box per the Phase 1 floating-pill learning, not a
  fixed offset).

#### Findings

Non-intrusiveness and standalone-suppression are the load-bearing UX
requirements; both are encoded as ACs. No new user-facing *page* or multi-step
flow — these are progressive-enhancement affordances.

## Observability

```yaml
liveness_signal:
  what: SW-registered + offline-fallback-served breadcrumbs (client-side, best-effort progressive enhancement — no server liveness applies to a client SW)
  cadence: per client session
  alert_target: none (client-side best-effort; app works without the SW)
  configured_in: apps/web-platform/app/sw-register.tsx (registration) + apps/web-platform/components/pwa/pwa-controls.tsx (update/install)
error_reporting:
  destination: browser console.warn (existing) + Sentry.captureException on SW registration failure (non-fatal)
  fail_loud: warn-level, non-fatal — registration failure already falls through to "app works without SW"
failure_modes:
  - mode: SW registration fails
    detection: catch in sw-register.tsx
    alert_route: console.warn + Sentry breadcrumb
  - mode: offline.html precached as a login redirect (missing PUBLIC_PATHS entry)
    detection: post-deploy curl 200 + vitest isPublicPath test + SHELL_ASSETS precache-list test
    alert_route: CI red (pre-merge) / curl (post-deploy)
  - mode: update prompt reload loop
    detection: controllerchange reload-guard flag + unit test asserting single reload
    alert_route: CI red
  - mode: SW bricks navigation (serves offline while online / respondWith throws)
    detection: vitest navigate-branch unit test (fetch resolves → passthrough; rejects → offline.html) + manual Chromium QA
    alert_route: CI red / QA
logs:
  where: browser console (client-side only; no server log surface for the SW)
  retention: n/a (client)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/pwa test/components/pwa   # plus, post-deploy: curl -sI https://app.soleur.ai/offline.html"
  expected_output: "vitest: all pass; curl: HTTP 200, content-type: text/html"
```

## Test Scenarios

1. **Offline navigation** — with `fetch` mocked to reject, the SW `navigate`
   branch resolves to the cached `/offline.html`.
2. **Online navigation** — `fetch` resolves; the SW returns the network
   response untouched (no cached HTML served; nonce/middleware path intact).
3. **PUBLIC_PATHS** — `isPublicPath("/offline.html")` true; `"/offline.htmlx"`
   false.
4. **Update lifecycle** — a `waiting` worker surfaces the affordance; clicking
   Reload posts `SKIP_WAITING` and triggers exactly one `controllerchange`
   reload.
5. **Install capture** — `beforeinstallprompt` `preventDefault`ed and stored;
   button click calls `prompt()`; `appinstalled` hides the button.
6. **Standalone suppression** — `display-mode: standalone` → `PwaControls`
   renders `null`.
7. **iOS path** — iOS-Safari UA, not standalone → guidance card, no install
   button (no `beforeinstallprompt`).

## Research Insights

**Precedent-diff (Phase 4.4):** the only in-repo SW precedent is the existing
handwritten `public/sw.js` (push/notification handlers + cache-first static).
There is **no offline-fallback precedent** — the `navigate`-mode
`respondWith(fetch().catch(...))` branch is **novel** for this codebase;
reviewers should scrutinize its redirect/credential handling and the
catch-only (never `response.ok`) semantics. The update-lifecycle
(`skipWaiting` via `postMessage` + `controllerchange` reload) and
`beforeinstallprompt` capture are standard web-platform patterns (MDN /
web.dev "app-update-notification" and "customize-install"); they are new to
this repo but not novel to the platform.

**Best practices (grounded):**
- Update prompt: keep the new worker in `waiting`; only `skipWaiting()` on
  explicit user action, then reload once on `controllerchange` (guard the
  reload with a module flag to avoid a loop). This is exactly the mid-session
  asset-swap fix the ARGUMENTS ask for.
- Offline navigation: branch on `event.request.mode === "navigate"` (not on
  `Accept: text/html` sniffing) — it is the canonical navigation predicate and
  avoids matching `fetch()`/XHR HTML sub-requests.
- iOS: `beforeinstallprompt` never fires on iOS Safari; detect
  `display-mode: standalone` / `navigator.standalone` to suppress, and gate the
  Add-to-Home-Screen card on iOS-Safari UA. Do not show install chrome in an
  in-app browser (no A2HS support).
- Offline page a11y: `<html lang="en">`, a visible heading, sufficient
  contrast in both `prefers-color-scheme` modes, and a real focusable
  `<a href>` retry (keyboard-reachable, no JS).

**Edge cases:**
- A navigation that resolves with an HTTP error (500/maintenance page) must
  return that network response, NOT the offline shell — catch only rejects.
- First install (no existing controller): a worker with no `skipWaiting` still
  activates immediately (waiting only occurs when a controller exists), so the
  update affordance never shows on first install — correct.
- `CACHE_NAME` bump to `v10` purges old caches on `activate`; with the waiting
  model that purge now runs only after the user accepts the update — acceptable
  and safer than mid-session purge.

**References:**
- <https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Offline_and_background_operation>
- <https://web.dev/articles/app-update-notification>
- <https://web.dev/articles/customize-install>
- <https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent>

## Risks & Mitigations / Sharp Edges

- **Sticky-SW brick (highest risk).** A bad `navigate` `respondWith` can make
  the installed app fail every navigation, and a SW persists across reloads.
  *Mitigation:* keep the branch a transparent network passthrough with
  **catch-only** fallback; unit-test both arms; retain a self-unregistering
  recovery worker as a kill switch; `updateViaCache:"none"` already ensures the
  SW script is re-fetched fresh so a fixed worker can supersede a bad one.
- **Offline page must be script-free** — `script-src … 'strict-dynamic'` blocks
  non-nonce inline scripts, and a cache-served page cannot rely on a fresh
  nonce. Use inline `<style>` (allowed by `style-src 'unsafe-inline'`) and an
  `<a href>` retry. No `<script>`.
- **PUBLIC_PATHS is load-bearing for precache** — without `/offline.html` in
  `PUBLIC_PATHS`, `cache.addAll` captures a `307 → /login`
  (`2026-05-29-nextjs-metadata-routes-need-public-paths-allowlist` class).
- **ADR-067 hard-nav** — the `navigate` branch must never serve cached HTML
  online; online navigations must reach middleware. Passthrough-then-catch
  preserves this.
- **Do not remove `clients.claim()`** — first-install control depends on it;
  only `skipWaiting` is removed (that is the mid-session-swap fix).
- **tsc is a precondition, not an afterthought** (Phase 1 learning): run
  `./node_modules/.bin/tsc --noEmit` at the phase that lands code; a plan's
  "this compiles" is a claim to verify.
- **Bash CWD persists** across tool calls (Phase 1 learning): prefix
  path-relative commands with `cd apps/web-platform &&` after any `cd <root>`.
- **Test file paths must match vitest globs** — `test/**/*.test.ts` (node) /
  `test/**/*.test.tsx` (jsdom); co-located component tests are silently skipped
  and `bunfig.toml` blocks bun test entirely.
- **A plan whose `## User-Brand Impact` section is empty, placeholder, or omits
  the threshold fails `deepen-plan` Phase 4.6.** It is filled above.

## Non-Goals / Out of Scope

- **Deploy pipeline fix** (PR #6852 / #6860) — tracked; do not touch. Phase 2
  merges green, deploys later.
- **Phase 3** — per-surface mobile UX incl. kanban mobile layout — separate.
- **Full offline data mode** — agents require network; only the app-shell
  fallback + static offline page are in scope (no offline reads/writes).
- **Serwist adoption** — rejected in ADR-137; the ADR is the tracking record
  (revisit only if the precache surface grows to need build-time revisioning).
- **Background sync / periodic sync / push changes** — not in Phase 2.
