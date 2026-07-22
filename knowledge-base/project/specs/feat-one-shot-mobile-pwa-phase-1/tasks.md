---
feature: feat-one-shot-mobile-pwa-phase-1
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-22-feat-mobile-pwa-phase-1-hardening-plan.md
---

# Tasks — Mobile + PWA Phase 1 (installable dashboard + mobile hardening)

> Note: spec.md absent for this branch → `lane` defaulted to `cross-domain` (fail-closed).
> CODE-ONLY. No new image assets / service worker / install prompt (Phase 2).
> Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
> Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run`.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `/dashboard/inbox` and `/dashboard/workstream` routes exist under `app/(dashboard)/dashboard/` (manifest shortcut deep-links must be real).
- [ ] 0.2 Confirm the `<main>` height chain (`flex h-dvh flex-col` ancestor → `<main flex-1>` → `ChatSurface` direct child) so `h-full` resolves (already verified in review; re-confirm no refactor since).

## Phase 1 — Viewport, metadata, skip-link

- [ ] 1.1 `app/layout.tsx` `viewport`: add `viewportFit: "cover"` + `interactiveWidget: "resizes-content"`; keep `themeColor: "#0a0a0a"`.
- [ ] 1.2 `app/layout.tsx` `metadata`: add `appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "Soleur" }`; keep existing `icons`.
- [ ] 1.3 `app/(dashboard)/layout.tsx` `<main>`: add `id="main-content"`, `tabIndex={-1}`, `ref={mainRef}`; keep className + `inert`.
- [ ] 1.4 `app/(dashboard)/layout.tsx`: add the scoped skip-to-content link as the first focusable child, rendered only when `!drawerOpen`, `sr-only focus:not-sr-only …` brand-token styled, with `onClick={() => mainRef.current?.focus()}` (Safari focus move). Do NOT put it in root `app/layout.tsx`.

## Phase 2 — PWA manifest fields (`app/manifest.ts`, code-only)

- [ ] 2.1 `start_url: "/dashboard"`, add `scope: "/dashboard"`, `id: "soleur-dashboard"`, `lang: "en"`, `dir: "ltr"`, `categories: ["productivity","business"]`.
      (Open operator decision — `decision-challenges.md` Challenge 3 recommends `scope: "/"` to avoid ejecting to the browser on session-expiry; default is `/dashboard` per audit.)
- [ ] 2.2 Add `shortcuts` array (Chat `/dashboard`, Inbox `/dashboard/inbox`, Workstream `/dashboard/workstream`), each reusing `/icons/icon-192x192.png`.
- [ ] 2.3 Leave `icons`/`name`/`short_name`/`description`/`display`/`background_color`/`theme_color` unchanged; confirm `tsc` accepts the object as `MetadataRoute.Manifest`.

## Phase 3 — Global mobile hardening (`app/globals.css`)

- [ ] 3.1 Add the 16px input floor **inside `@layer base`**: `@media (max-width: 767px){ input, textarea, select { font-size: 16px } }`.
- [ ] 3.2 `[cmdk-input]` line 277 `0.9rem` → `1rem`; add **unlayered** `@media (min-width: 768px){ [cmdk-input]{ font-size: 0.9rem } }` immediately after the base rule.
- [ ] 3.3 Merge into the existing `@layer base` (166–178): `html { overscroll-behavior: none; -webkit-tap-highlight-color: transparent; text-size-adjust: 100%; -webkit-text-size-adjust: 100% }` and `body { overflow-x: hidden }` (body only).
- [ ] 3.4 Add **unlayered** `@media (prefers-reduced-motion: reduce){ .message-bubble-active { animation: none } }`.
- [ ] 3.5 No raw hex added; `--soleur-bg-base` value unchanged (keeps `theme-no-fouc-script.test.tsx` green).

## Phase 4 — Per-input keyboard hints + 16px (replace bare `text-sm` with `text-base md:text-sm`)

- [ ] 4.1 `components/chat/chat-input.tsx` textarea: `enterKeyHint="send"`.
- [ ] 4.2 `components/auth/login-form.tsx` email: `autoComplete="email" inputMode="email" autoCapitalize="none" autoCorrect="off" spellCheck={false}`.
- [ ] 4.3 `app/(auth)/signup/page.tsx` email: same email attrs.
- [ ] 4.4 `app/(auth)/setup-key/page.tsx` api-key: 16px only.
- [ ] 4.5 `components/settings/key-rotation-form.tsx` api-key: 16px only (keeps `autoComplete="off"`).
- [ ] 4.6 `components/connect-repo/create-project-state.tsx` project-name: `autoCapitalize="none" autoCorrect="off" spellCheck={false}`.
- [ ] 4.7 `components/kb/search-overlay.tsx` search: `type="search" enterKeyHint="search" autoCapitalize="none" spellCheck={false}`.
- [ ] 4.8 `components/connect-repo/select-project-state.tsx` search: same search attrs.
- [ ] 4.9 `components/support/support-composer.tsx` textarea: `enterKeyHint="send"`.
- [ ] 4.10 `components/settings/invite-member-modal.tsx` email: email attrs.
- [ ] 4.11 `components/workstream/new-issue-dialog.tsx` title + description textarea + concierge textarea: 16px only.
- [ ] 4.12 `components/onboarding/naming-modal.tsx` name: 16px only.
      (Optional per `decision-challenges.md` Challenge 2: the 16px-only rows are redundant with the Phase-3.1 floor; keep per audit unless operator opts to drop.)

## Phase 5 — Chat primary surface

- [ ] 5.1 `chat-surface.tsx` `isFull` root → `flex h-full flex-col md:h-full` (drop `h-[100dvh]`; NOT a `calc`).
- [ ] 5.2 Add `visualViewport` `resize`/`scroll` handler (touch/iOS-guarded) lifting the composer above the iOS keyboard by the covered-height offset.
- [ ] 5.3 Scroll guard: `nearBottomRef` init `true`, non-scrollable = near-bottom; gate `[messages]` auto-scroll on `nearBottomRef.current` with `behavior:"auto"`; recompute on `onScroll` + resize; `programmaticScroll` flicker guard; active = `streamState !== "idle"`.
- [ ] 5.4 "Jump to latest" pill on the **non-scrolling** flex-root parent (not inside the messages scroll div); show when `!nearBottom`; click scrolls to `messagesEndRef` and sets `nearBottomRef.current = true` synchronously; ≥44px coarse hit area.
- [ ] 5.5 `chat-input.tsx` hit areas: `min-h-11 min-w-11 md:min-h-0 md:min-w-0` on attach/send/@; **replace** the stop button's `min-w-[36px]` (don't stack). Icon glyphs unchanged.
      (Open operator decision — `decision-challenges.md` Challenge 1: 5.3/5.4 could split to a follow-up PR; 5.1/5.2 stay.)

## Phase 6 — Trim highlight grammar payload (`components/ui/markdown-renderer.tsx`)

- [ ] 6.1 Import the 11 grammar fns from `highlight.js/lib/languages/*`; pass `rehypeHighlight` `{ detect: false, languages: { …, tsx: typescript, html: xml } }`. Keep the untyped `const REHYPE_PLUGINS = [...]` (no `PluggableList` annotation).
- [ ] 6.2 Verify a ```ts / ```tsx / ```bash / ```json / ```python / ```diff block still highlights.

## Phase 7 — Fixed-bottom safe-area + chrome hit targets

- [ ] 7.1 `components/support/support-launcher.tsx`: `bottom-5` → `bottom-[calc(1.25rem+env(safe-area-inset-bottom))]` (offset shift; h-12 stays).
- [ ] 7.2 `components/shared/cta-banner.tsx` (corrected path): add `.safe-bottom` to the bottom bar.
- [ ] 7.3 `app/(dashboard)/layout.tsx` hamburger + close buttons: `h-10 w-10` → `h-11 w-11` (glyphs unchanged).

## Phase 8 — Dense-page gutters

- [ ] 8.1 `workstream/page.tsx` (22), `crm/page.tsx` (22): `px-6` → `px-4 sm:px-6`.
- [ ] 8.2 `routines/page.tsx` (18): `mx-auto max-w-5xl px-6 py-8` → `mx-auto max-w-5xl px-4 py-8 sm:px-6`.

## Phase 9 — Verify + ship

- [ ] 9.1 `tsc --noEmit` clean.
- [ ] 9.2 `vitest run` green; confirm `github-app-manifest-parity` + `middleware*` + `theme-no-fouc-script` unaffected.
- [ ] 9.3 (Recommended) mobile visual QA on 390×844 + a real iOS Safari for the keyboard case.
- [ ] 9.4 Ship PR titled for mobile + PWA Phase 1; `ship` folds `decision-challenges.md` into the PR body + files an `action-required` issue. Merge when green.
