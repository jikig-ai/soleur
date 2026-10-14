---
title: "Mobile + PWA revision — Phase 1 (installable dashboard + mobile hardening)"
type: feat
date: 2026-07-22
branch: feat-one-shot-mobile-pwa-phase-1
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: draft
---

# ✨ feat: Mobile + PWA revision — Phase 1 (installable dashboard + pervasive mobile hardening)

## Enhancement Summary

**Deepened on:** 2026-07-22 · **Gates cleared:** User-Brand Impact (4.6, threshold `aggregate pattern`), Observability (4.7, existing-signals schema — no new surface), PAT-shaped-variable (4.8, none), UI-Wireframe (4.9, `.pen` produced — see below). Verify-the-negative pass ran against every `NEVER`/`does-not`/`untouched` claim in the body; all confirmed against code (`/manifest.webmanifest` ∈ `PUBLIC_PATHS` `lib/routes.ts:48`; `--soleur-bg-base: #0a0a0a` unchanged; `NoFoucScript` + `x-nonce` + `await headers()` intact in `app/layout.tsx`; no `apple-icon`/`sitemap` route added).

**Key deepen changes (folded into the phases above):**
1. Chat height → **`h-full`** (not `calc(100dvh-3.5rem)`): Kieran verified the `calc` regresses on notched devices because this PR's own `viewportFit:cover` makes the bar's `.safe-top` inset non-zero; the flex chain resolves `h-full` cleanly.
2. **CSS-layer placement made explicit** (Kieran P2a/P2b): 16px floor in `@layer base`; cmdk desktop override + reduced-motion rule **unlayered** — else dead CSS.
3. **Chat scroll-guard hardened** (spec-flow G1–G7): `nearBottomRef` (live, not state), init `true`, pill on the non-scrolling parent, `streamState !== "idle"`, `behavior:"auto"` always, resize recompute.
4. **iOS keyboard avoidance added** (spec-flow G8): `interactiveWidget` is Chromium-only; a `visualViewport` offset lifts the composer above the iOS keyboard.
5. **Skip-link scoped to the dashboard layout** (spec-flow G10/G11/G12): a root-`<body>` link was a dead control off-dashboard, a no-op into `inert` `<main>`, and needs an explicit Safari focus move.
6. Stop-button `min-w` replace-not-stack (Kieran P2c); dropped `PluggableList` annotation (Kieran P2d); one uniform 5c hit-area mechanism (code-simplicity).

**Three scope challenges** (would alter the operator's explicit audit change-list) are recorded in `knowledge-base/project/specs/feat-one-shot-mobile-pwa-phase-1/decision-challenges.md` for `ship` to render + file as an `action-required` issue: (1) split Phase 5b to a follow-up PR, (2) drop the redundant 16px-only rows, (3) **`scope:"/"` vs `"/dashboard"`** (the latter ejects users to the system browser on session-expiry — highest-signal). None applied silently.

**Framework grounding (Context7, Next.js App Router):** `Viewport`/`Metadata`/`MetadataRoute.Manifest` shapes for the `viewport`/`appleWebApp`/`shortcuts`/`scope`/`id` additions confirmed against current docs and cross-checked against the installed Next 15.5 types (Kieran).

## Overview

Phase 1 of the mobile + PWA revision of `apps/web-platform`. Two cohesive goals in one PR:

1. **Make the dashboard a correctly installable PWA** — activate the safe-area padding that is already written but dead, add the iOS web-app metadata, and give `app/manifest.ts` the code-only fields (`start_url`/`scope`/`id`/`lang`/`dir`/`categories`/`shortcuts`) an installable app needs.
2. **Land the low-risk, pervasive mobile-hardening fixes** from the mobile+PWA audit (2026-07-22): the 16px iOS-auto-zoom floor, per-input mobile keyboard hints, ≥44px hit targets on the chat composer and mobile chrome, a chat surface that fills its slot with the composer above the fold, a near-bottom scroll guard, a smaller syntax-highlight grammar payload on the chat critical path, safe-area on fixed-bottom elements, and dense-page gutters.

**Scope is CODE-ONLY.** Explicitly **excluded** (Phase 2): new image assets (screenshots, regenerated maskable icon), and the offline / service-worker / install-prompt / CSP-nonce-offline work. The existing `<SwRegister />` and `icons` array are left as-is.

**Preserved invariants (all confirmed by research, see Research Reconciliation):**
- **ADR-067 hard-nav / Router-Cache invariant** — this is a pure client-side manifest/CSS/viewport/className change. It touches none of the hard-nav call-sites, `next.config.ts` `staleTimes`, `middleware.ts`, or the SWR cache-clear wiring. No soft navigation across an authenticated-principal boundary is added.
- **No-FOUC theme bootstrap** — `<NoFoucScript nonce={nonce} />` stays first in `<head>`, before `<ThemeProvider>`; `await headers()` / nonce plumbing untouched; no `--soleur-bg-base` hex is changed, so `test/components/theme-no-fouc-script.test.tsx` stays green.
- **CSP nonce (network-only HTML)** — untouched; the offline/SW CSP work is Phase 2.
- **Brand tokens** — every new CSS rule consumes `var(--soleur-*)` (or a Tailwind `*-soleur-*` utility); no raw hex is introduced.

**No new dependencies.** `rehype-highlight` and `highlight.js` are already installed; the markdown-renderer change imports existing grammar modules.

## User-Brand Impact

**If this lands broken, the user experiences:** on a phone, the chat composer sits below the fold on first paint (can't send a message without scrolling), inputs zoom the viewport on focus, tap targets miss, or — worst case if the chat-surface height fix regresses — the primary chat surface renders with the composer clipped for the entire mobile cohort.

**If this leaks, the user's data is exposed via:** N/A. This change ships no new data path, no server code, no auth/session surface, no network egress, and no persisted state. It edits presentation-layer files only (`app/*.tsx`/`.ts`/`.css` render config, `components/**` classNames + input attributes, `app/manifest.ts` static config). None of the change-list paths match the canonical sensitive-path regex.

**Brand-survival threshold:** aggregate pattern — a regression degrades the mobile cohort's UX (presentation only); there is no single-user data/money exposure vector. No CPO sign-off gate; no per-PR sign-off required.

## Research Reconciliation — Spec vs. Codebase

The audit change-list was verified line-by-line against current source. Two premises were **stale** and are corrected here; everything else held exactly.

| Audit claim | Codebase reality | Plan response |
|---|---|---|
| `components/chat/cta-banner.tsx` (fixed bottom-0) | File is at **`components/shared/cta-banner.tsx`**. No file exists under `components/chat/cta-banner.tsx`. Positioning (`fixed bottom-0 left-0 right-0 … px-4 py-3 backdrop-blur-sm`, line 99) is exactly as described. | Edit the real path `components/shared/cta-banner.tsx`. |
| `globals.css` — "scope the old 0.9rem back inside `@media (min-width: 768px)`" and "add to the html/body base layer" | `[cmdk-input] { font-size: 0.9rem }` exists (line 277). There is **no `html { }` rule** in `@layer base` today (only `body { }` at 166–178) and **no input-zoom media query** exists. | The base-layer hardening props (`overscroll-behavior`, tap-highlight, text-size-adjust, `overflow-x`) are **greenfield additions** to `@layer base` (a new `html`/`body` block), not edits to an existing rule. The 16px input floor and reduced-motion `pulse-border` rule are also greenfield. |
| `components/chat/chat-surface.tsx` full-variant root `flex h-[100dvh] flex-col md:h-full` | Confirmed verbatim (the `isFull` branch, line 640). Force-scroll `useEffect` is unconditional `scrollIntoView({behavior:"smooth"})` on `[messages]` (lines 352–354); no near-bottom guard / jump-to-latest exists. | Fix as specified (Phase 5). |
| `app/(dashboard)/layout.tsx` mobile chrome buttons `h-10 w-10` | Confirmed: hamburger (296–303) and close (369–375) are both `h-10 w-10`. Mobile top bar is `min-h-14` = 56px = 3.5rem (295). `<main>` (609–612) is `flex-1 overflow-y-auto` with **no id / tabIndex**. | Bump both to `h-11 w-11`; add `id="main-content" tabIndex={-1}` to `<main>` (Phase 1). |
| `/manifest.webmanifest` reachability | Already in `PUBLIC_PATHS` (`lib/routes.ts:48`) and asserted at `test/middleware.test.ts:23`. This PR adds **no new metadata route** (icons array unchanged, no `app/apple-icon.ts`/`sitemap.ts`). | **No `PUBLIC_PATHS` / middleware change needed.** Editing existing manifest fields does not add a served path. |
| `rehype-highlight` ships lowlight `common` (~35 langs) | Confirmed: `rehypeHighlight` is used with no options (`const REHYPE_PLUGINS = [rehypeHighlight]`, line 137) → default `common`. Installed API (v7) `Options = { languages: Record<string,LanguageFn>, detect: boolean, aliases, plainText, subset }`. All target grammars exist under `highlight.js/lib/languages/*` (`typescript.js` handles ts/tsx; `xml.js` handles html). | Pass an explicit `languages` map + `detect:false` (Phase 6). |

## Implementation Phases

Phases are grouped by audit item and are mostly independent; they land in one atomic PR. Where a contract precedes a consumer (skip-link target), the target is created in the same phase.

### Phase 1 — Viewport, metadata, skip-link (`app/layout.tsx` + `app/(dashboard)/layout.tsx`)

1. **`app/layout.tsx` `viewport` export** (currently `{ themeColor: "#0a0a0a" }`): add `viewportFit: "cover"` (activates the existing `.safe-top`/`.safe-bottom` env() padding) and `interactiveWidget: "resizes-content"` (dvh reflows above the on-screen keyboard). Keep `themeColor`. Result:
   ```ts
   export const viewport: Viewport = {
     themeColor: "#0a0a0a",
     viewportFit: "cover",
     interactiveWidget: "resizes-content",
   };
   ```
2. **`app/layout.tsx` `metadata` export**: add `appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "Soleur" }`. Keep the existing `icons`/`title`/`description`.
3. **`app/(dashboard)/layout.tsx` `<main>`** (609–612): add `id="main-content"`, `tabIndex={-1}`, and a `ref={mainRef}` (so the skip-link can move focus into it). Keep `className="flex-1 overflow-y-auto bg-soleur-bg-base"` and the existing `inert={drawerOpen || undefined}`.
4. **Skip-to-content link — placed in the dashboard layout, NOT the root `<body>`** (spec-flow G10/G11/G12). The `#main-content` target only exists on dashboard routes; a global root-`<body>` skip-link would be a dead control on `/login`, `/signup`, `/setup-key`, and marketing pages (activating it targets a nonexistent fragment and focus never moves). So mount it as the **first focusable child of the dashboard layout's root**, targeting its own `<main id="main-content">`. Use the existing focus-ring convention (Tailwind `sr-only` + `focus:not-sr-only …`, brand-token background/text). Two correctness requirements:
   - **Hide/disable it while `drawerOpen`** — with the mobile drawer open `<main>` is `inert`, and moving focus into an `inert` element fails silently (G11). Render it only when `!drawerOpen` (or have it close the drawer before focusing).
   - **Move focus explicitly** — native `href="#id"` + `tabIndex={-1}` does not reliably move focus in Safari (it scrolls without focusing, so the next Tab resumes from the link) (G12). Add an `onClick` (and/or `hashchange`) handler that calls `mainRef.current?.focus()`.
   ```tsx
   {!drawerOpen && (
     <a
       href="#main-content"
       onClick={() => mainRef.current?.focus()}
       className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[100] focus:rounded-lg focus:bg-soleur-bg-surface-1 focus:px-4 focus:py-2 focus:text-soleur-text-primary focus:shadow-lg"
     >
       Skip to content
     </a>
   )}
   ```
   The dashboard layout is a `"use client"` component; this touches no FOUC/nonce plumbing (those live only in root `app/layout.tsx`, which is untouched by the skip-link now).

### Phase 2 — PWA manifest fields (`app/manifest.ts`, code-only)

Add to the returned object (keep `name`/`short_name`/`description`/`display`/`background_color`/`theme_color`/`icons` **unchanged**):
- `start_url: "/dashboard"` (was `"/"`), `scope: "/dashboard"`, `id: "soleur-dashboard"`.
- `lang: "en"`, `dir: "ltr"`, `categories: ["productivity", "business"]`.
- `shortcuts` array, reusing the existing `/icons/icon-192x192.png` as each shortcut icon:
  ```ts
  shortcuts: [
    { name: "Chat", short_name: "Chat", url: "/dashboard",
      icons: [{ src: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" }] },
    { name: "Inbox", short_name: "Inbox", url: "/dashboard/inbox",
      icons: [{ src: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" }] },
    { name: "Workstream", short_name: "Workstream", url: "/dashboard/workstream",
      icons: [{ src: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" }] },
  ],
  ```
- Verify the returned object still satisfies `MetadataRoute.Manifest` under `tsc` (the two-entry `any`/`maskable` icon split stays as-is — see learning `2026-03-29-pwa-manifest-...`). Deep-link URLs (`/dashboard/inbox`, `/dashboard/workstream`) must be real routes — confirm both exist under `app/(dashboard)/dashboard/`.

### Phase 3 — Global mobile hardening (`app/globals.css`)

**Layer placement is load-bearing (Kieran P2a/P2b).** Tailwind utilities live in `@layer utilities` and beat `@layer base`; the existing `[cmdk-input]` and the two `prefers-reduced-motion` blocks are **unlayered** (unlayered beats every `@layer`). Follow these placements exactly, else you ship dead CSS.

1. **16px iOS-auto-zoom floor** (greenfield): add **inside the existing `@layer base` block** (so the per-input `md:text-sm` utility from Phase 4 can still override it on desktop; on mobile the floor and `text-base` both resolve to 16px — a harmless tie, no zoom):
   ```css
   @layer base {
     @media (max-width: 767px) {
       input, textarea, select { font-size: 16px; }
     }
   }
   ```
2. **`[cmdk-input]` 16px base**: change line 277 `font-size: 0.9rem;` → `font-size: 1rem;`, and re-introduce the old `0.9rem` for desktop **UNLAYERED, immediately after the base `[cmdk-input]` rule** — the base rule is unlayered, so a `@layer`-wrapped override would lose to it and the desktop palette input would stay 16px:
   ```css
   @media (min-width: 768px) { [cmdk-input] { font-size: 0.9rem; } }
   ```
3. **`@layer base` html/body hardening** (greenfield — no `html {}` rule exists today):
   ```css
   @layer base {
     html {
       overscroll-behavior: none;
       -webkit-tap-highlight-color: transparent;
       text-size-adjust: 100%;
       -webkit-text-size-adjust: 100%;
     }
     body { overflow-x: hidden; }  /* body only — do NOT clip legit horizontal-scroll containers */
   }
   ```
   (Merge into the existing `@layer base` block at 166–178 rather than adding a second `@layer base`.)
4. **Reduced-motion for the chat pulse** (greenfield rule; two `prefers-reduced-motion` blocks already exist at 217–223 and 344–350 but neither touches the bubble). `.message-bubble-active` lives in `@layer components`, so this override must be **UNLAYERED** (matching the two existing reduced-motion blocks) or in `@layer components` — a `@layer base` placement would lose to it and the pulse would keep running (Kieran P2b):
   ```css
   @media (prefers-reduced-motion: reduce) {
     .message-bubble-active { animation: none; }
   }
   ```

### Phase 4 — Per-input keyboard hints + 16px on hot inputs

The global floor (Phase 3.1) already kills zoom; these add correct mobile keyboards + autofill while keeping desktop at `text-sm`. For each field, set `className` to include `text-base md:text-sm` (replacing the bare `text-sm`) **and** add the listed attributes. All are currently `text-sm` with no `inputMode`.

| File | Element | Attributes to add (in addition to `text-base md:text-sm`) |
|---|---|---|
| `components/chat/chat-input.tsx` | textarea (686–697) | `enterKeyHint="send"` |
| `components/auth/login-form.tsx` | email (142–148) | `autoComplete="email" inputMode="email" autoCapitalize="none" autoCorrect="off" spellCheck={false}` |
| `app/(auth)/signup/page.tsx` | email (117–123) | same email attrs as above |
| `app/(auth)/setup-key/page.tsx` | api-key (122–133) | 16px only (`text-base md:text-sm`); `type="password"` already suppresses the rest |
| `components/settings/key-rotation-form.tsx` | api-key (119–127) | 16px only (already has `autoComplete="off"`) |
| `components/connect-repo/create-project-state.tsx` | project-name (57–65) | `autoCapitalize="none" autoCorrect="off" spellCheck={false}` (becomes a GitHub repo slug) |
| `components/kb/search-overlay.tsx` | search (65–71) | `type="search" enterKeyHint="search" autoCapitalize="none" spellCheck={false}` |
| `components/connect-repo/select-project-state.tsx` | search (75–84) | `type="search" enterKeyHint="search" autoCapitalize="none" spellCheck={false}` |
| `components/support/support-composer.tsx` | textarea (46–54) | `enterKeyHint="send"` |
| `components/settings/invite-member-modal.tsx` | email (202–208) | email attrs (as login-form) |
| `components/workstream/new-issue-dialog.tsx` | title (110–120) + description textarea (129–137) + concierge textarea (167–173) | 16px only |
| `components/onboarding/naming-modal.tsx` | name (51–58) | 16px only |

Notes: `text-base` is 16px = the same as the Phase-3 floor, so this is belt-and-suspenders on mobile and correctly `text-sm` on `md:`. Do not alter existing `type`/`id`/`ref`/`aria-*`/`disabled` on any field. The `text-search` `type="search"` change on the two search inputs is safe (they are plain text filters, not forms).

### Phase 5 — Chat primary surface (`components/chat/chat-surface.tsx` + `components/chat/chat-input.tsx`)

**5a. Height fix (composer above the fold). Use `h-full`, NOT `calc(100dvh-3.5rem)`.** The `isFull` root (line 640) is `flex h-[100dvh] flex-col md:h-full`. On mobile the dashboard `<main>` slot is already `100dvh − barHeight` (the top bar), so `h-[100dvh]` overflows the slot and pushes the bottom-pinned composer below the fold. A `calc(100dvh-3.5rem)` fix is **wrong** because (i) this PR's Phase-1 `viewportFit:"cover"` makes the bar's existing `.safe-top` `env(safe-area-inset-top)` padding non-zero on notched devices, so the bar is `56px + inset-top` (~103px), not 56px — `calc` under-subtracts and reintroduces the overflow (Kieran P1); and (ii) the bar is `min-h-14`, so a wrapped status label grows it past 56px (spec-flow G9). Kieran verified the flex chain resolves `h-full` cleanly: `ChatSurface` is the direct root of the chat page (`app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:93`), a direct child of `<main>`, which is a `flex-1` item of a `flex h-dvh flex-col` column → definite height → `h-full` = the true slot height regardless of bar padding. So:
```ts
const rootClass = isFull ? "flex h-full flex-col md:h-full" : "flex h-full min-w-0 flex-col";
```
(This collapses to `"flex h-full flex-col"` for both branches.) **Composer must be visible on first paint with no outer scroll.** Pre-existing caveat (not introduced here): a conditional billing/error banner rendered inside `<main>` would push content down — out of scope.

**5a-iOS. Keyboard avoidance on iOS Safari (spec-flow G8).** `interactiveWidget: "resizes-content"` (Phase 1) is **Chromium/Android only** — iOS Safari overlays the keyboard without shrinking `dvh`/`visualViewport`-driven layout, so with `h-full` and no outer scroll the bottom-pinned composer sits *behind* the iOS keyboard with no way to reveal it (the largest mobile cohort hitting the plan's own worst case). Add a small `visualViewport` handler (guarded to touch/iOS): subscribe to `window.visualViewport` `"resize"`+`"scroll"` and apply a bottom offset to the composer wrapper equal to `max(0, layoutViewportHeight − visualViewport.height − visualViewport.offsetTop)` (i.e. the covered height), so the composer rides above the keyboard. On Chromium this stays 0 (content already reflowed). Keep it minimal and effect-cleanup-safe.

**5b. Near-bottom scroll guard + Jump-to-latest.** Replace the unconditional effect (352–354). Implementation details are load-bearing (spec-flow G1–G7):
- Compute `nearBottom` as `scrollHeight − scrollTop − clientHeight ≤ ~80px`. **Initialize `true`**, and treat a non-scrollable container (`scrollHeight − clientHeight ≤ threshold`) as near-bottom — else the empty-state and resumed-history flows (which fire no `onScroll` before first paint) strand with the pill over a short list and no auto-scroll (G1).
- **Gate the `[messages]` auto-scroll on a live `nearBottomRef.current`, not a state snapshot.** The effect closes over the render's value; a fast token stream can `scrollIntoView` before the user's `onScroll` (`setNearBottom(false)`) commits, yanking them back down (G2). Keep a `nearBottomRef` updated in the `onScroll` handler and read `.current` in the effect.
- **Always use `behavior: "auto"`** for the auto-scroll (drop the smooth/stream branch — code-simplicity + G4). Per-token smooth-scroll is the jank source, and smooth animation emits intermediate non-near-bottom `onScroll` values that flash the pill; `"auto"` removes both and deletes a code path.
- Recompute `nearBottom` on **resize too**, not only `onScroll` — subscribe to `ResizeObserver`/`window.visualViewport` resize on the scroll container; when the keyboard opens (`clientHeight` shrinks) no `onScroll` fires and the guard goes stale (G3). Reuse the 5a-iOS `visualViewport` subscription.
- Guard against self-flicker: set a `programmaticScroll` flag while an auto-scroll is in flight and skip the `nearBottom` recompute during it (G4).
- Define **"active stream" as `streamState !== "idle"`** (includes `stopping`, matching the effect at line 450) wherever stream-active is checked (G6).
- **"Jump to latest" pill:** mount it on the **non-scrolling flex-root parent** (sticky/absolute relative to the `isFull` root, NOT inside the `overflow-y-auto` messages container at line 771 — inside it, the pill scrolls away exactly when the user is scrolled up, the state it serves) (G5). Brand-token styled, ≥44px coarse hit area (same treatment as 5c). Show when `!nearBottom`, hide when `nearBottom`. On click: scroll to `messagesEndRef` **and set `nearBottomRef.current = true` synchronously** in the handler (not only `setState`) so streaming keeps following (G7).
- Keep the effect keyed on `[messages]`; do not change the two unrelated `[messages]`-dep memos at 253/592.

**5c. ≥44px hit areas on the composer (coarse pointers only).** In `chat-input.tsx`, the attach (661–671, `h-[36px] w-[36px]`), send (728–734, `h-[36px] w-[36px]`), stop (715–726, `h-[36px] min-w-[36px]`), and mobile-only `@` button (699–707, `p-1` ≈ 22–24px) must reach ≥44px on coarse pointers while staying ~36px on desktop. Use **one uniform mechanism on all four** (code-simplicity): `min-h-11 min-w-11 md:min-h-0 md:min-w-0` (the `md:` breakpoint is a cheaper proxy for coarse-pointer than a custom `@media (pointer: coarse)` utility Tailwind does not ship). Two element-specific notes:
  - **Stop button: REPLACE its existing `min-w-[36px]`, do not stack `min-w-11` on top** — two competing `min-width` utilities resolve by Tailwind emit-order, not source-order, and can silently settle at 36px (Kieran P2c; the plan's own "replace, don't stack" edge). Attach/send have no `min-*` so layering is fine there.
  - **`@` button:** apply the same `min-h-11 min-w-11 md:min-h-0 md:min-w-0` (which supersedes its `p-1` for hit-area purposes) rather than a separate `p-1`-under-coarse treatment.
  Do not change icon glyph sizes (`h-5 w-5`), only the hit area.

### Phase 6 — Trim syntax-highlight grammar payload (`components/ui/markdown-renderer.tsx`)

Replace the bare `import rehypeHighlight from "rehype-highlight"` + `const REHYPE_PLUGINS = [rehypeHighlight]` with an explicit small `languages` subset and `detect: false`, so only these grammars ship on the `/dashboard/chat` critical path (instead of `common`'s ~35). Import the grammar functions from the already-installed `highlight.js/lib/languages/*`:
```ts
import rehypeHighlight from "rehype-highlight";
import javascript from "highlight.js/lib/languages/javascript";
import typescript from "highlight.js/lib/languages/typescript";
import bash from "highlight.js/lib/languages/bash";
import json from "highlight.js/lib/languages/json";
import python from "highlight.js/lib/languages/python";
import sql from "highlight.js/lib/languages/sql";
import diff from "highlight.js/lib/languages/diff";
import markdown from "highlight.js/lib/languages/markdown";
import yaml from "highlight.js/lib/languages/yaml";
import css from "highlight.js/lib/languages/css";
import xml from "highlight.js/lib/languages/xml"; // html

// Keep the existing untyped `const REHYPE_PLUGINS = [...]` form — do NOT add a
// `: PluggableList` annotation (that type is not imported today; adding it needs
// `import type { PluggableList } from "unified"` or it won't compile — Kieran P2d).
const REHYPE_PLUGINS = [
  [rehypeHighlight, {
    detect: false,
    languages: {
      javascript, js: javascript, jsx: javascript,
      typescript, ts: typescript, tsx: typescript,
      bash, sh: bash, json, python, py: python,
      sql, diff, markdown, md: markdown, yaml, yml: yaml,
      css, html: xml, xml,
    },
  }],
];
```
Verify a ```ts / ```tsx / ```bash / ```json / ```python / ```diff fenced block still renders highlighted in a chat message (Phase 0/QA visual check). `detect: false` means un-fenced / unlisted languages render as plain text (acceptable — the audit's chosen subset). Keep everything else (`remarkGfm`, `react-markdown`, C4 wiring) unchanged.

### Phase 7 — Fixed-bottom safe-area + mobile chrome hit targets

1. **`components/support/support-launcher.tsx`** (line 50, FAB `fixed bottom-5 right-5 … h-12 w-12`): the FAB is positioned by offset, so a `padding-bottom` won't lift it — shift the offset to respect the home indicator:
   ```
   fixed bottom-[calc(1.25rem+env(safe-area-inset-bottom))] right-5 …
   ```
   (h-12 w-12 = 48px already ≥ 44px; leave it.)
2. **`components/shared/cta-banner.tsx`** (line 99, bottom bar `fixed bottom-0 left-0 right-0 … px-4 py-3`): it is a full-width bar with content, so `padding-bottom` correctly clears the home indicator — add the existing `.safe-bottom` utility (`padding-bottom: env(safe-area-inset-bottom)`) to the className. Keep `py-3`.
3. **`app/(dashboard)/layout.tsx` chrome buttons**: bump the hamburger (296–303) and close (369–375) buttons `h-10 w-10` → `h-11 w-11` (44px). Icon glyphs (`h-5 w-5`) unchanged.

### Phase 8 — Dense-page gutters

Change the unconditional `px-6` to `px-4 sm:px-6` on the `<main>` wrapper in:
- `app/(dashboard)/dashboard/workstream/page.tsx` (line 22: `className="px-6 py-8"` → `"px-4 py-8 sm:px-6"`)
- `app/(dashboard)/dashboard/crm/page.tsx` (line 22: same)
- `app/(dashboard)/dashboard/routines/page.tsx` (line 18: `className="mx-auto max-w-5xl px-6 py-8"` → `"mx-auto max-w-5xl px-4 py-8 sm:px-6"`)

### Phase 9 — Verify + ship

1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.
2. `cd apps/web-platform && ./node_modules/.bin/vitest run` → full suite green. Confirm `test/github-app-manifest-parity.test.ts` and `test/middleware*.test.ts` (incl. the `isPublicPath("/manifest.webmanifest")` assertion and the CSP-coverage invariant) still pass — none should be affected.
3. Optional targeted QA (visual): chat surface on a 390×844 viewport — composer above the fold on first paint; ≥44px hit targets; input focus does not zoom; code block highlights. (Manifest install / Lighthouse PWA verification is nice-to-have but the icon/screenshot completeness is Phase 2.)
4. Ship a PR titled for mobile + PWA Phase 1; merge when green.

## Files to Edit

- `apps/web-platform/app/layout.tsx` — viewport (`viewportFit`, `interactiveWidget`), metadata (`appleWebApp`). (Skip-link moved OUT of root layout — see below.)
- `apps/web-platform/app/(dashboard)/layout.tsx` — `<main id tabIndex ref>`, the scoped skip-to-content link (first focusable, hidden while `drawerOpen`), chrome buttons `h-11 w-11`.
- `apps/web-platform/app/manifest.ts` — start_url/scope/id/lang/dir/categories/shortcuts.
- `apps/web-platform/app/globals.css` — 16px floor, cmdk-input responsive font-size, base-layer html/body hardening, reduced-motion pulse-border.
- `apps/web-platform/components/chat/chat-input.tsx` — enterKeyHint, 16px, ≥44px coarse hit areas.
- `apps/web-platform/components/chat/chat-surface.tsx` — height fix, scroll guard, jump-to-latest.
- `apps/web-platform/components/ui/markdown-renderer.tsx` — languages subset + detect:false.
- `apps/web-platform/components/auth/login-form.tsx` — email attrs + 16px.
- `apps/web-platform/app/(auth)/signup/page.tsx` — email attrs + 16px.
- `apps/web-platform/app/(auth)/setup-key/page.tsx` — 16px.
- `apps/web-platform/components/settings/key-rotation-form.tsx` — 16px.
- `apps/web-platform/components/connect-repo/create-project-state.tsx` — slug attrs + 16px.
- `apps/web-platform/components/kb/search-overlay.tsx` — search attrs + 16px.
- `apps/web-platform/components/connect-repo/select-project-state.tsx` — search attrs + 16px.
- `apps/web-platform/components/support/support-composer.tsx` — enterKeyHint + 16px.
- `apps/web-platform/components/settings/invite-member-modal.tsx` — email attrs + 16px.
- `apps/web-platform/components/workstream/new-issue-dialog.tsx` — title + 2 textareas 16px.
- `apps/web-platform/components/onboarding/naming-modal.tsx` — 16px.
- `apps/web-platform/components/support/support-launcher.tsx` — safe-area bottom offset.
- `apps/web-platform/components/shared/cta-banner.tsx` — `.safe-bottom` (corrected path).
- `apps/web-platform/app/(dashboard)/dashboard/workstream/page.tsx` — `px-4 sm:px-6`.
- `apps/web-platform/app/(dashboard)/dashboard/crm/page.tsx` — `px-4 sm:px-6`.
- `apps/web-platform/app/(dashboard)/dashboard/routines/page.tsx` — `px-4 sm:px-6`.

## Files to Create

None. (No new image assets, no new metadata routes, no new tests required beyond the existing green suite — the change is presentation config; a component test for the scroll guard is optional and would live under `test/**/*.test.tsx` per the vitest `component` project glob.)

## Acceptance Criteria

Pre-merge (all checkable post-conditions):

- [ ] `app/layout.tsx` `viewport` export contains `viewportFit: "cover"` **and** `interactiveWidget: "resizes-content"` **and** still `themeColor: "#0a0a0a"`. (`grep -n 'viewportFit\|interactiveWidget\|themeColor' app/layout.tsx` shows all three.)
- [ ] `app/layout.tsx` `metadata` contains `appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "Soleur" }`.
- [ ] A `href="#main-content"` skip-link is the first focusable element in `<body>`; `app/(dashboard)/layout.tsx` `<main>` has `id="main-content"` and `tabIndex={-1}`.
- [ ] `app/manifest.ts` returns `start_url: "/dashboard"`, `scope: "/dashboard"`, `id: "soleur-dashboard"`, `lang: "en"`, `dir: "ltr"`, `categories: ["productivity","business"]`, and a `shortcuts` array of 3 entries deep-linking `/dashboard`, `/dashboard/inbox`, `/dashboard/workstream`; the `icons` array is byte-identical to before.
- [ ] `globals.css`: a `@media (max-width: 767px)` rule sets `input, textarea, select { font-size: 16px }`; `[cmdk-input]` base font-size is `1rem` with `0.9rem` scoped inside `@media (min-width: 768px)`; the `@layer base` block sets `overscroll-behavior: none`, `-webkit-tap-highlight-color: transparent`, `text-size-adjust: 100%` + `-webkit-text-size-adjust: 100%` (on `html`) and `overflow-x: hidden` on `body` only; a `@media (prefers-reduced-motion: reduce)` rule sets `.message-bubble-active { animation: none }`. No raw hex added; no `--soleur-bg-base` value changed.
- [ ] Every input/textarea listed in Phase 4 carries `text-base md:text-sm` and its specified attributes; `grep -n 'inputMode="email"' components/auth/login-form.tsx app/\(auth\)/signup/page.tsx components/settings/invite-member-modal.tsx` returns 3 matches; `grep -n 'type="search"' components/kb/search-overlay.tsx components/connect-repo/select-project-state.tsx` returns 2.
- [ ] `chat-surface.tsx` `isFull` root uses `h-full` (no `h-[100dvh]`, no `calc`); a near-bottom guard reads a live `nearBottomRef` and gates the `[messages]` auto-scroll with `behavior:"auto"`; a "Jump to latest" control mounted on the non-scrolling parent renders only when scrolled up; a `visualViewport` handler lifts the composer above the iOS keyboard.
- [ ] Skip-to-content link is in `app/(dashboard)/layout.tsx` (not root `<body>`), rendered only when `!drawerOpen`, with an explicit focus handler; root `app/layout.tsx` no longer contains a skip-link.
- [ ] `chat-input.tsx` attach/send/stop and the mobile `@` button reach ≥44px on coarse pointers while remaining ~36px on desktop (min-h-11/min-w-11 coarse treatment present).
- [ ] `markdown-renderer.tsx` passes `rehypeHighlight` an explicit `languages` map (js/ts/tsx/bash/json/python/sql/diff/markdown/yaml/css/html) with `detect: false`; a ```ts and a ```bash fenced block still render highlighted.
- [ ] `support-launcher.tsx` FAB bottom offset includes `env(safe-area-inset-bottom)`; `shared/cta-banner.tsx` carries `.safe-bottom`; both dashboard chrome buttons are `h-11 w-11`.
- [ ] `workstream/page.tsx`, `crm/page.tsx`, `routines/page.tsx` wrappers use `px-4 sm:px-6` (no bare `px-6`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` is green, including `test/github-app-manifest-parity.test.ts` and `test/middleware*.test.ts` (unchanged behavior).

## Domain Review

**Domains relevant:** Product (UI change to existing surfaces).

### Product/UX Gate

**Tier:** advisory (mechanically forced to run via the UI-surface glob; no new page/flow → not BLOCKing)
**Decision:** reviewed (pipeline) — wireframe produced, ready for async operator review
**Agents invoked:** spec-flow-analyzer (chat-surface flow), ux-design-lead (wireframe)
**Skipped specialists:** cpo (no product-strategy decision — but see the `scope:"/"` challenge in decision-challenges.md), copywriter (no new copy)
**Pencil available:** yes
**Wireframe artifact (committed):** `knowledge-base/product/design/mobile-pwa/mobile-chat-surface-phase-1.pen` (Frame 1 default/scrolled-up + Frame 2 keyboard-open; 44px targets, safe-area top/bottom bands, and "above the fold" annotated). Screenshots under `knowledge-base/product/design/mobile-pwa/screenshots/`.

**Note on scope:** this PR modifies **existing** surfaces and creates **zero** new pages/flows (`## Files to Create` is empty; the CREATE-based escalation did not fire). The UI-surface glob still forces the wireframe gate, so ux-design-lead produced a wireframe of the primary changed surface (the mobile chat view — where the safe-area, 44px hit targets, composer-above-fold, and the one net-new "Jump to latest" affordance land). The pipeline halts after deepen-plan, so the operator reviews the wireframe before any implementation.

#### Findings

**spec-flow-analyzer (chat surface + skip-link flow):** 12 flow gaps, all folded into Phases 1/5 above. Highest-signal:
- **G8 (P1, iOS keyboard):** `interactiveWidget` is Chromium/Android only → iOS composer behind keyboard. Fixed by the 5a-iOS `visualViewport` handler.
- **G10/G11/G12 (P1, skip-link):** a root-`<body>` skip-link is a dead control off-dashboard (`#main-content` only exists on dashboard), a silent no-op into an `inert` `<main>` while the drawer is open, and Safari won't move focus on `href="#id"`+`tabIndex=-1`. Fixed by scoping the link to the dashboard layout, hiding it while `drawerOpen`, and an explicit `mainRef.focus()` handler.
- **G1/G2/G5 (P1, scroll guard):** `nearBottom` must init `true` + treat non-scrollable as near-bottom; gate on a live `nearBottomRef` not a state snapshot; mount the "Jump to latest" pill on the non-scrolling parent. All folded into Phase 5b.
- G3/G4/G6/G7/G9 (P2): resize recompute, programmatic-scroll flicker guard, `streamState !== "idle"`, synchronous ref-set on click, `3.5rem` magic-number desync (dissolved by the `h-full` decision). Folded in.

**Eng panel (DHH / Kieran / code-simplicity):** correctness findings auto-applied — `h-full` over `calc` (Kieran P1), explicit CSS-layer placement for the 16px floor / cmdk-desktop-override / reduced-motion (Kieran P2a/P2b), stop-button `min-w` replace-not-stack (Kieran P2c), drop `PluggableList` annotation (Kieran P2d), always-`behavior:auto` + one uniform 5c hit-area mechanism (code-simplicity). Three **scope challenges** raised by DHH/code-simplicity that would change the audit's explicit change-list are recorded (headless) in `knowledge-base/project/specs/feat-one-shot-mobile-pwa-phase-1/decision-challenges.md` for `ship` to render into the PR body + file as an `action-required` issue — they are NOT silently applied.

## Architecture Decision (ADR/C4)

**No ADR or C4 change required.** This is a pure client-side manifest/CSS/viewport/className change: no new external actor, no new external system/vendor edge, no new data store, and no changed access relationship.

**C4 completeness check (all three `.c4` files read):** `spec.c4` defines only element kinds + `external`/`selfhosted` tags — no PWA vocabulary needed. `model.c4` **already** models the web app as a PWA (`webapp = system "Web Application"` desc "Next.js PWA…", `dashboard = container "Dashboard"`), and a `SwRegister` service-worker registration already exists in `app/layout.tsx` (pre-existing, not added here). The founder→webapp→api→supabase topology (model.c4:318,368–369) is unchanged — installability changes render/display behavior, not network topology or data flow. External actors checked: none added (no new correspondent/vendor/recipient). External systems checked: none (manifest is served by the existing Next.js `api`/`dashboard` container). Data stores checked: none. This matches ADR-067's own twice-recorded "C4 impact: None" reasoning for an in-process client-only change.

## Observability

This is a presentation-layer change with **no new server code, error path, log call, cron, or infra surface** (no Files-to-Edit under `server/`, `supabase/`, `app/api/`, `infra/`, or `plugins/*/scripts/`; zero matches against the canonical sensitive-path regex). The 5-field schema below is filled with the **existing** signals that already cover this surface — no new observability wiring is introduced, and none of the failure modes are on a blind execution surface (§2.9.2 does not apply — this is not a sandbox/container/cron).

```yaml
liveness_signal:
  what: existing web-platform HTTP health check (unauth → 307 /login) + client Sentry init on app/layout tree
  cadence: continuous (per request / per page load)
  alert_target: existing web-platform Sentry project + Better Stack uptime (unchanged by this PR)
  configured_in: pre-existing (apps/web-platform/infra/sentry/*, deploy pipeline) — not modified here
error_reporting:
  destination: existing client-side Sentry (already initialized in the app/layout provider tree)
  fail_loud: N/A — this PR adds no new throw/catch sites; it is CSS/className/manifest/viewport config
failure_modes:
  - mode: chat composer renders below the fold on mobile first paint (5a regression)
    detection: mobile visual QA at 390×844 + optional Playwright viewport smoke (composer in initial viewport)
    alert_route: none (presentation regression — caught pre-merge by QA/tsc/vitest, not a runtime signal)
  - mode: input focus zooms the viewport on iOS (16px floor regression)
    detection: mobile visual QA on iOS Safari
    alert_route: none (presentation)
  - mode: code fences stop highlighting (rehype-highlight languages subset wrong)
    detection: visual QA of a ```ts/```bash block in a chat message
    alert_route: none (presentation)
logs:
  where: N/A — no new server logs; client console only (unchanged)
  retention: N/A
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vitest run"
  expected_output: "tsc exits 0 (no type errors); vitest suite green incl. github-app-manifest-parity + middleware* + theme-no-fouc-script"
```

## Open Code-Review Overlap

3 open code-review issues mention files this plan touches; all are **acknowledged** (different concerns, no fold-in):
- **#3564** (Core Web Vitals infrastructure for web-platform) — mentions `app/layout.tsx` + `globals.css`. Different concern: a separate CWV/Lighthouse-CI observability initiative. **Acknowledge.** Note: this PR touches above-the-fold layout/font-size, which is one of #3564's listed re-evaluation triggers — worth a heads-up in the PR body, but the CWV infra is out of scope for a hardening PR.
- **#2193** (unify past_due/unpaid billing banners; extract `useDismissiblePersistent`) — targets `app/(dashboard)/layout.tsx:23-80,283-298`. Different concern (billing-banner refactor); this PR only touches the `<main>` element (609–612) and the chrome buttons in that file — no line overlap. **Acknowledge.**
- **#2349** (qa skill port-probe / multi-worktree ESM loader cache) — mentions `globals.css` only as an error symptom in the `qa` SKILL.md prose; not a code overlap. **Acknowledge.**

## Test Scenarios

- **tsc**: no type regression from the manifest fields (`MetadataRoute.Manifest` accepts `shortcuts`/`scope`/`id`/`lang`/`dir`/`categories`), the `Viewport` additions, the `Metadata.appleWebApp` block, and the `rehype-highlight` options object.
- **Existing suite**: `github-app-manifest-parity` (reads `infra/github-app-manifest.json` — unrelated to the PWA manifest) and all `middleware*` tests stay green; `theme-no-fouc-script` stays green (no base-bg hex change).
- **Manual (recommended)**: 390×844 mobile viewport — (a) chat composer above the fold on first paint, (b) focusing chat/login/search inputs does not zoom, (c) attach/send/@ are comfortably tappable, (d) scrolling up during a stream shows "Jump to latest" and does not auto-yank to bottom, (e) a fenced ```ts and ```bash code block highlights, (f) with `prefers-reduced-motion` the active message bubble does not pulse.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with threshold `aggregate pattern`.
- **`highlight.js` has no separate `tsx`/`html` grammar module** — `typescript.js` handles ts/tsx and `xml.js` handles html. The `languages` map aliases `tsx: typescript` and `html: xml`; do not `import "highlight.js/lib/languages/tsx"` (does not exist — build would fail). Verify a ```tsx block highlights after the change.
- **The chat-surface height fix must not regress desktop or other dashboard pages.** Both branches collapse to `flex h-full flex-col`; `h-full` resolves against the bounded `<main>` slot (verified flex chain), so no magic viewport-minus-bar number is introduced and desktop (`md:h-full`, same value) is unchanged.
- **safe-area on a `fixed bottom-N` FAB needs an offset shift, not padding** — `.safe-bottom` (padding-bottom) lifts *content inside a bar* but does not move a point-positioned FAB. support-launcher uses the `bottom-[calc(1.25rem+env(safe-area-inset-bottom))]` offset form; cta-banner (a bar) uses `.safe-bottom`. Do not swap them.
- **Do not add a second `@layer base`** in globals.css — merge the new `html`/`body` hardening into the existing `@layer base` block (166–178) so cascade order is preserved.
- **`text-base md:text-sm` must replace the bare `text-sm`**, not stack after it — leaving both `text-sm` and `text-base` yields undefined precedence. Remove the standalone `text-sm` token where present.
- **`interactiveWidget: "resizes-content"` is Chromium/Android only — iOS Safari ignores it.** On iOS the keyboard overlays without reflowing `dvh`, so with `h-full` + no outer scroll the composer is trapped behind the keyboard. The 5a-iOS `visualViewport` offset is the load-bearing fix for the iOS cohort; do not assume `interactiveWidget` alone solves keyboard avoidance. Verify on a real iOS Safari (or an iOS-emulating harness) before merge.
- **The chat height fix is `h-full`, NOT `calc(100dvh-3.5rem)`.** The `calc` form regresses on notched devices precisely because this PR ships `viewportFit:"cover"` in the same change (it makes the bar's `.safe-top` `env()` inset non-zero) and because the bar is `min-h-14` (can grow). `h-full` resolves against the real slot height. If anyone "simplifies" back to a hardcoded viewport-minus-bar calc, it re-breaks on iPhones.
- **CSS-layer placement is load-bearing in `globals.css`:** the 16px input floor goes in `@layer base`; the cmdk desktop `0.9rem` override and the reduced-motion `.message-bubble-active` rule go **unlayered** (their base rules are unlayered / in `@layer components`, which beat `@layer base`). A wrong layer ships dead CSS that passes `tsc` and vitest silently.
- **The skip-to-content link lives in the dashboard layout, not root `<body>`** — `#main-content` only exists on dashboard routes, so a global link is a dead control on `/login` etc. It must be hidden while `drawerOpen` (focus into `inert` is a silent no-op) and must call `mainRef.current?.focus()` explicitly (Safari won't move focus on a bare fragment jump).
