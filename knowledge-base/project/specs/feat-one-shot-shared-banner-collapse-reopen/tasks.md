---
title: "Tasks: Shared CTA banner collapse/reopen"
branch: feat-one-shot-shared-banner-collapse-reopen
lane: single-domain
plan: knowledge-base/project/plans/2026-06-09-feat-shared-cta-banner-collapse-reopen-plan.md
---

# Tasks — Shared-document CTA banner collapse/reopen

## Phase 1 — Component rewrite (`apps/web-platform/components/shared/cta-banner.tsx`)

- [ ] 1.1 Remove `import { safeSession } from "@/lib/safe-session";` and `const STORAGE_KEY = ...`. Do NOT delete `lib/safe-session.ts` (shared util).
- [ ] 1.2 Replace `dismissed` boolean state with `const [panel, setPanel] = useState<"expanded" | "collapsed">("expanded")`. Delete `if (dismissed) return null;`. Replace `handleDismiss` with `handleCollapse` (`setPanel("collapsed")`) + add `handleExpand` (`setPanel("expanded")`).
- [ ] 1.3 Add the collapsed-strip render branch (`panel === "collapsed"`): full-width `<button type="button">` reusing the `fixed bottom-0 … border-t … bg-soleur-bg-surface-1/95 backdrop-blur-sm` footprint (slim `py-2`); `onClick={handleExpand}`, `aria-label="Reopen Soleur signup banner"`, `aria-expanded={false}`, `data-testid="cta-banner-reopen"`; inner "Built with **Soleur**" gold-accent line + inline up-chevron `<svg aria-hidden="true">` using the repo's EXISTING up-chevron form from `chat-input.tsx:691-694` (`<line x1="12" y1="19" x2="12" y2="5" /><polyline points="5 12 12 5 19 12" />`, or polyline-only). Do NOT invent a chevron path.
- [ ] 1.4 In the expanded branch, change the close button: `onClick={handleCollapse}`, `aria-label="Collapse signup banner"`, add `aria-expanded={true}`, keep `data-testid="cta-banner-dismiss"` and the X icon. ARIA disclosure: `aria-expanded` reflects current state on each rendered control (true expanded / false collapsed) — matches `debug-stream-panel.tsx:105`, `org-switcher.tsx:116`, `file-tree.tsx:204`. Do NOT add `aria-controls` (YAGNI). Do NOT script focus moves.
- [ ] 1.5 Add `transition-all duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0` to the animated wrapper(s); pair EVERY `transition-*`/`duration-*` with a `motion-reduce:` reset. `motion-reduce:` is built into Tailwind 4.2.1 (no `@custom-variant` needed). Animation scope = INCOMING panel eases in on mount; outgoing panel unmounts instantly (no exit animation — that is YAGNI-correct, do not build a crossfade). If a plain `transition-*` on the conditionally-rendered element does not visibly ease in, add a one-frame `useEffect` entry flag flipping `translate-y-1 opacity-0`→`translate-y-0 opacity-100`; if the unanimated swap reads fine in QA, drop the flag (simplest). NO JS `matchMedia` — happy-dom lacks it and CSS-only needs no test stub.
- [ ] 1.6 Leave `handleSubmit`, `Status`, success branch, form markup, honeypot, privacy line, aria-live region byte-identical.

## Phase 2 — Rewrite close test (`apps/web-platform/test/shared-cta-banner-close.test.tsx`)

- [ ] 2.1 Delete the unmount + sessionStorage-coupled cases (incl. the two storage-throw cases).
- [ ] 2.2 Add cases: (1) default render = form + collapse button, no reopen; (2) collapse → thin bar present, form gone, NOT unmounted; (3) reopen aria (`Reopen Soleur signup banner`, `aria-expanded=false`); (4) click reopen → form restored, no reload; (5) both controls are `<button>` (keyboard-operable); (6) collapse writes nothing to sessionStorage (`getItem(...) === null` && `sessionStorage.length === 0`); (7) fresh mount with stale key pre-seeded still renders expanded.

## Phase 3 — Keep waitlist test green

- [ ] 3.1 Do NOT edit `apps/web-platform/test/shared-cta-banner-waitlist.test.tsx`. Run to confirm green.

## Phase 4 — (optional) Wireframe

- [ ] 4.1 Add "Desktop — Collapsed (thin bar)" frame to `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen` mirroring the Idle Banner Bar footprint. Defer if Pencil unavailable (existing wireframe already covers the surface).

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx` — all green.
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] 5.3 `grep -c "safeSession\|STORAGE_KEY\|sessionStorage" apps/web-platform/components/shared/cta-banner.tsx` → 0.
- [ ] 5.4 `git diff --name-only` does NOT include `apps/web-platform/lib/safe-session.ts`.
