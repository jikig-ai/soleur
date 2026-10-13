---
title: "feat: Make shared-document signup CTA banner closeable"
type: enhancement
classification: ui-affordance
requires_cpo_signoff: false
branch: feat-one-shot-shared-doc-popup-closeable
created: 2026-05-04
deepened: 2026-05-04
---

# feat: Make shared-document signup CTA banner closeable

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Research Insights, Acceptance Criteria, Sharp Edges, Test Scenarios, Implementation Sketch (new)
**Research signals:** in-repo precedents (`pwa-install-banner.tsx`, `notification-prompt.tsx`), shared-doc page render flow, Next.js 15 client-component boundary, vitest+jsdom storage shape, AGENTS.md `cq-ref-removal-sweep-cleanup-closures` (touches `useEffect` shape)

### Key Improvements

1. **Hydration mismatch ruled out by render-flow proof.** `<CtaBanner />` only renders after `data` is set in a `useEffect`, so the server-prerender never includes the banner — a `sessionStorage` read at render time cannot diverge from server output. This is concrete enough to drop the "guard storage with `useEffect`-then-`setState`" complexity that other Next.js banners need.
2. **Storage-key namespace tightened.** Promoted to `soleur:shared:cta-dismissed` to match the `notification-prompt-seen` precedent's flat shape but carry the `soleur:` brand prefix so future contributors can grep our keys.
3. **Test mock parity preserved.** Confirmed all four test files mock `CtaBanner` as a named export, so the contract is "named export `CtaBanner`, no required props" — the close affordance must not require parent state plumbing.
4. **Implementation sketch added** with the exact try/catch shape from `notification-prompt.tsx:19-41` and the exact close-button JSX from `pwa-install-banner.tsx:32-42`. Reduces work-phase ambiguity to zero.
5. **Clarified deliberate non-feature: the banner does NOT auto-hide on scroll, navigation, or doc kind.** User gesture is the only dismissal signal — keeps the click target predictable.

## Overview

When a user opens a shared document via `/shared/[token]`, a fixed-bottom banner ("This document was created with Soleur — Create your account") appears and overlays the lower portion of the document. Today the banner has no close affordance, so it covers content (especially on mobile, where viewport real estate is scarce) and there is no way to read the bottom of a long markdown doc, the bottom of a PDF page, or the download CTA on the `download` kind without working around the overlap.

This plan adds a small close (X) button to the banner's existing layout and persists the dismissal across the current viewing session via `sessionStorage`. A returning visit (new tab, new browser session) re-shows the CTA — Soleur's growth funnel needs the prompt, but a single user-initiated close should be respected for the duration of that read.

The change is scoped to a single component (`apps/web-platform/components/shared/cta-banner.tsx`) plus its four mock sites in the test suite. No API, route, schema, or auth surface is touched.

## User-Brand Impact

**If this lands broken, the user experiences:** the banner stays visible after clicking X (close fails to hide), or worse, the banner becomes permanently un-showable across sessions (over-aggressive persistence collapses the funnel).

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user-owned data, credentials, or payment surface is in scope. The component is rendered to anonymous viewers of an already-public token URL.

**Brand-survival threshold:** none

Reason for `none`: cosmetic affordance on an unauthenticated marketing surface; no PII, no auth, no payments, no destructive write path. The threshold-`none` claim is supported by `apps/web-platform/components/shared/cta-banner.tsx` containing only static link markup; sensitive-path regex from `plugins/soleur/skills/preflight/SKILL.md` Check 6 does not match `components/shared/**` for non-credential UI.

## Research Insights

### Local context (no external research required)

Strong local pattern exists in `apps/web-platform/components/chat/pwa-install-banner.tsx:32-42` — a dismissable fixed banner with inline SVG X, `type="button"`, `aria-label="Dismiss …"`, `shrink-0` styling. The plan mirrors this pattern exactly to keep visual + a11y consistency.

A second relevant precedent is `apps/web-platform/components/chat/notification-prompt.tsx:20-41` — `localStorage` getter/setter wrapped in try/catch for environments where storage is unavailable (Safari private mode, embed sandboxes). The plan reuses the same defensive shape with `sessionStorage` instead.

### Storage choice — `sessionStorage` over `localStorage`

| Choice | Pro | Con |
|---|---|---|
| `localStorage` | One close = forever closed for that device | CTA never re-appears on subsequent visits → kills Soleur's documented growth lever (roadmap 3.18: "read-only external access **with signup CTAs**") |
| `sessionStorage` (chosen) | Close survives reloads / re-opens of the same tab; a fresh tab or new visit re-prompts | Close does not survive across days |
| In-memory `useState` only | Cheapest | Reload re-shows banner immediately; user clicks X repeatedly on a long PDF doc |

`sessionStorage` is the smallest defensible win that respects user intent without making the funnel a one-shot. CMO/CPO can override in Phase 2.5 if growth metrics require `localStorage`.

### CTA banner is a fixed bar, not a dialog

The user described it as "a popup". The implementation (`cta-banner.tsx:5`) is a `<div className="fixed bottom-0 ...">` — not a `<dialog>` or modal. Naming matters because:

- A modal would need ESC handling, focus trap, return-focus, `role="dialog"`, and an overlay click-to-close.
- A fixed banner needs only a button.

The plan implements the banner-shaped close because that's the existing surface. If the user actually wanted a modal-style popup (e.g., centered card that blocks interaction), that's a different scope and would require an explicit re-spec.

### Surface where the banner renders

`apps/web-platform/app/shared/[token]/page.tsx:134` renders `<CtaBanner />` only when `data` (the document) loaded successfully — error states and the loading skeleton don't show it. The close affordance therefore never blocks an error message.

### Hydration-mismatch ruled out by parent render flow

The shared-document page is `"use client"` (`page.tsx:1`). Its initial state has `data === null` and `loading === true`, so the JSX path that renders `<CtaBanner />` (`page.tsx:134`) is `null` on the first render — both server-side (under static prerender) and client-side (first hydration tick). The fetch happens inside a `useEffect` that runs only after hydration completes. Therefore:

- The banner is **never present in the server-rendered HTML**.
- Its first appearance is during a post-hydration re-render, after `setData(...)` resolves.
- Reading `sessionStorage` synchronously inside the banner's render function (e.g., to short-circuit when dismissed === "1") **cannot** mismatch server output, because there IS no server output for this subtree.

This rules out the usual Next.js client-component storage guard pattern (`const [mounted, setMounted] = useState(false); useEffect(() => setMounted(true), []);`) — it adds a render and is unnecessary here. We can read storage in render and short-circuit cleanly.

The same render flow protects against a different bug class: vitest tests that mount `<CtaBanner />` directly (without the parent page wrapper) will exercise the storage read on the first render. Test setup MUST clear `sessionStorage` in a `beforeEach` to avoid cross-test contamination.

### Storage-key namespace

Renamed from the initial draft `soleur:shared-cta-dismissed` to `soleur:shared:cta-dismissed` (colon-separated). Rationale: `notification-prompt.tsx:6` uses a flat key (`notification-prompt-seen`) but the broader codebase has not picked a key convention. Adopting `soleur:<surface>:<key>` as we go gives future contributors a `rg "soleur:" apps/web-platform` query that surfaces every Soleur-owned client-storage key in one shot. Document the convention in the file's leading comment so a future contributor can extend it consistently.

### Test mock sites

```text
apps/web-platform/test/shared-page-ui.test.tsx:11
apps/web-platform/test/shared-page-head-first.test.tsx:11
apps/web-platform/test/shared-token-content-changed-ui.test.tsx:11
apps/web-platform/test/shared-image-a11y.test.tsx:12
```

All four mock `CtaBanner` as `() => <div data-testid="cta-banner" />`. The test mocks do not need to change because the component's exported signature stays `() => JSX.Element` (no new props added) — the close logic is internal.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/components/shared/cta-banner.tsx` renders a close button with `aria-label="Dismiss signup banner"` and `type="button"`, visually consistent with `pwa-install-banner.tsx` (16x16 inline SVG X, neutral-500 → neutral-300 hover).
- [x] Clicking the close button hides the banner immediately (in the same render frame — no animation requirement).
- [x] Dismissed state persists across page reloads within the same browser session via `sessionStorage` key `soleur:shared:cta-dismissed` (value `"1"`).
- [x] A new browser session (close tab, open new tab) re-shows the banner.
- [x] Storage access is wrapped in try/catch — Safari private mode or storage-disabled embeds do not throw at render time. On storage error the close still works in-memory for the current page lifetime.
- [x] The banner remains a `<div className="fixed bottom-0 …">` (no role/dialog change) — the contract this plan owns is "closeable banner", not "modal".
- [x] No new dependencies added (`package.json` unchanged; reuse inline SVG approach from `pwa-install-banner.tsx`).
- [x] All four existing test mocks continue to pass without modification (component's exported signature unchanged).
- [x] One new component-level vitest covering: (a) banner renders by default, (b) clicking close hides it, (c) re-rendering after `sessionStorage.getItem` returns `"1"` does not show the banner.
- [ ] PR body uses `Closes #<issue>` if a tracking issue is filed; otherwise the PR body links the worktree branch and notes "no tracking issue — direct user request, scope < 30 LoC".

### Post-merge (operator)

- [ ] None. No deploy hooks, migrations, or external-state changes.

## Files to Edit

- `apps/web-platform/components/shared/cta-banner.tsx` — add `useState` + close button + `sessionStorage` getter/setter wrapped in try/catch. Convert from server component to client component (`"use client"`) since it now has interaction.

## Implementation Sketch (work-phase scaffolding)

This is the canonical shape expected at GREEN. Names and structure mirror in-repo precedents (`notification-prompt.tsx` for storage helpers, `pwa-install-banner.tsx` for the close button JSX).

```tsx
// apps/web-platform/components/shared/cta-banner.tsx
"use client";

import { useState } from "react";
import Link from "next/link";

// Storage convention: soleur:<surface>:<key>
// Sessionwide on purpose — see plan 2026-05-04-feat-shared-doc-cta-banner-closeable-plan.md
const STORAGE_KEY = "soleur:shared:cta-dismissed";

function getInitialDismissed(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return sessionStorage.getItem(STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

function persistDismissed(): void {
  try {
    sessionStorage.setItem(STORAGE_KEY, "1");
  } catch {
    // sessionStorage unavailable (Safari private mode, sandboxed iframe) — fall back to in-memory only
  }
}

export function CtaBanner() {
  const [dismissed, setDismissed] = useState<boolean>(getInitialDismissed);

  if (dismissed) return null;

  function handleDismiss() {
    persistDismissed();
    setDismissed(true);
  }

  return (
    <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-neutral-800 bg-neutral-900/95 px-4 py-3 backdrop-blur-sm">
      <div className="mx-auto flex max-w-3xl items-center justify-between gap-4">
        <p className="text-sm text-neutral-300">
          This document was created with{" "}
          <span className="font-medium text-amber-400">Soleur</span> — AI agents for every department of your startup.
        </p>
        <div className="flex shrink-0 items-center gap-2">
          <Link
            href="/signup"
            className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black transition-colors hover:bg-amber-400"
          >
            Create your account
          </Link>
          <button
            type="button"
            onClick={handleDismiss}
            className="rounded p-1 text-neutral-500 transition-colors hover:text-neutral-300"
            aria-label="Dismiss signup banner"
            data-testid="cta-banner-dismiss"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
```

Key shape decisions encoded above:

- `useState<boolean>(getInitialDismissed)` — lazy initializer reads storage **once** on mount, no `useEffect`.
- `persistDismissed` is fire-and-forget; failure does not block the in-memory update.
- `data-testid="cta-banner-dismiss"` lets the new vitest reference the button without relying on `aria-label` text (which may be localized later).
- The close button lives inside the same `flex` row as the CTA link; `gap-2` between the two; the outer `gap-4` between text and button-group is preserved.
- No `useEffect` is added → AGENTS.md `cq-ref-removal-sweep-cleanup-closures` is N/A (no refs added either).

## Files to Create

- `apps/web-platform/test/shared-cta-banner-close.test.tsx` — three vitest cases per Acceptance Criteria above. Use `@testing-library/react` (already present in sibling tests).

No new component file. No new route. No new API.

## Domain Review

**Domains relevant:** product (UX-shaped), marketing (growth-funnel implication)

### Marketing (CMO)

**Status:** carry-forward — no leader spawned

**Assessment:** The shared-doc CTA banner is an explicit growth lever per `knowledge-base/product/roadmap.md:201` (Phase 3.18: "read-only external access with signup CTAs"). Making it closeable trades a small amount of impression frequency for read-experience quality. The `sessionStorage` choice (vs. `localStorage`) preserves the funnel: a new browser session re-shows the CTA. If post-launch metrics show the close button collapses signup conversion materially, escalate to CMO for re-design (e.g., timed re-show, scroll-triggered re-show, less-intrusive presentation). This plan does not require CMO sign-off because the storage scope is per-session — the CTA still appears on every fresh visit.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (no new component, mirroring an in-repo precedent — `pwa-install-banner.tsx` — that already shipped through UX), copywriter (no new copy added; the close button uses an `aria-label` only)
**Pencil available:** N/A

#### Findings

The change reuses the in-repo `pwa-install-banner.tsx` close-button pattern verbatim (16x16 SVG X, neutral-500 hover-to-neutral-300, top-right of the banner row). No new visual or copy decisions. The mechanical-escalation rule (`components/**/*.tsx` new file → BLOCKING) does not apply because no new component file is created — only an existing one is edited. ADVISORY tier holds.

The user's word "popup" was deliberately re-interpreted as "fixed banner" in the Research Insights section because that is what the implementation actually is. If the user pushes back at review time and confirms they meant a modal-style centered overlay, this plan is the wrong scope and should be re-planned.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (Already filled above — threshold `none` with explicit reason.)
- The CTA banner is currently a server component (no `"use client"` directive at top of `cta-banner.tsx`). Adding `useState` and `useEffect` requires the directive. Verify the import in `app/shared/[token]/page.tsx` (already a `"use client"` file) still tree-shakes correctly under Next.js 15 RSC boundaries.
- `sessionStorage` and `localStorage` access in the render path can throw in some embed contexts (sandbox iframes with `allow-scripts` but not `allow-same-origin`). Wrap every read AND every write in try/catch. The component must render successfully even when storage throws — fall back to in-memory `useState`.
- Do NOT animate the close (no `transition-opacity` on the dismissed state). The user wanted to read the doc; an animation delays that. Hide on the next render; that's the contract.
- The `sessionStorage` key `soleur:shared-cta-dismissed` is a flat boolean, not per-token. A user who closes the CTA on one shared doc will not see it on another shared doc opened in the same session. This is intentional — the user's intent ("get the CTA out of my way") is per-session, not per-document. Document this explicitly in the component file's leading comment so a future contributor doesn't "fix" it into a per-token map.
- When extending `cta-banner.tsx`, the test mocks at the four sites listed in Research Insights mock the *named export* `CtaBanner`. If the close logic is later extracted into a sibling helper (e.g., `useCtaDismissed`), the named export must remain stable so vitest mocks keep applying. Treat the export shape as a load-bearing contract.

## Test Scenarios

The component-level vitest covers:

1. **Renders by default** — mount `<CtaBanner />` in a fresh test (cleared `sessionStorage`); assert the "Create your account" link is visible.
2. **Close hides the banner** — mount, query the close button by `data-testid="cta-banner-dismiss"` (or fallback to `aria-label="Dismiss signup banner"`), click; assert the "Create your account" link is no longer in the DOM.
3. **`sessionStorage` short-circuit** — set `sessionStorage.setItem("soleur:shared:cta-dismissed", "1")` before mount; assert the banner renders nothing (queryByText returns `null`).
4. **Persistence across remount** — mount, click close, unmount, remount in the same test; assert the second mount renders nothing (proves `persistDismissed` wrote to storage and `getInitialDismissed` reads it).
5. **Storage-throws fallback** — stub `Storage.prototype.getItem` to throw (covers both `sessionStorage.getItem` paths under jsdom); mount; assert the banner still renders without throwing. Then click close; the click handler swallows the setItem throw and the banner hides in-memory.

### Test setup contract

```ts
// apps/web-platform/test/shared-cta-banner-close.test.tsx
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

const STORAGE_KEY = "soleur:shared:cta-dismissed";

beforeEach(() => {
  sessionStorage.clear();
});

afterEach(() => {
  cleanup();
  sessionStorage.clear();
});

// ... test cases per the list above
```

The `sessionStorage.clear()` in both `beforeEach` and `afterEach` is intentional — vitest+jsdom does NOT reset `sessionStorage` between tests within a file, so cross-test contamination is the most likely false-fail mode. Mirror this if any future test in the same file imports the banner.

The four existing mocks at the sites listed in Research Insights do NOT need updates because they replace the entire `CtaBanner` export with a `() => <div data-testid="cta-banner" />` dummy. The contract this plan keeps stable: **named export `CtaBanner` with no required props**.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` returned no entries whose body contains `cta-banner`, `CtaBanner`, or `shared/[token]/page.tsx`. **None.**

## Out of Scope

- Modal/dialog version of the popup. Out of scope unless the user re-spec's intent.
- Per-document or per-token dismissal state. Sessionwide is intentional.
- Re-show heuristics (timed re-show, scroll-triggered re-show). If conversion metrics demand it, file as a follow-up.
- A11y audit of the broader shared-document page beyond this banner. The page has been live since Phase 3.18; broader audit is its own scope.
- Mobile-specific layout adjustments (e.g., stacking the CTA above the close on narrow screens). The current `flex items-center justify-between gap-4` already handles narrow widths via gap-collapse; if QA finds visual issues at < 360px, file as a follow-up.

## Resume prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-05-04-feat-shared-doc-cta-banner-closeable-plan.md. Branch: feat-one-shot-shared-doc-popup-closeable. Worktree: .worktrees/feat-one-shot-shared-doc-popup-closeable/. No issue. Plan written; deepen-plan next.
```
