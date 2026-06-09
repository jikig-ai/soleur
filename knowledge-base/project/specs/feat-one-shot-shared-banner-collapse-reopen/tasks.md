---
title: "Tasks: Shared CTA banner collapse/reopen"
branch: feat-one-shot-shared-banner-collapse-reopen
lane: single-domain
plan: knowledge-base/project/plans/2026-06-09-feat-shared-cta-banner-collapse-reopen-plan.md
---

# Tasks — Shared-document CTA banner collapse/reopen

## Phase 1 — Component rewrite (`apps/web-platform/components/shared/cta-banner.tsx`)

- [x] 1.1 Remove `import { safeSession } from "@/lib/safe-session";` and `const STORAGE_KEY = ...`. Do NOT delete `lib/safe-session.ts` (shared util).
- [x] 1.2 Replace `dismissed` boolean state with `const [panel, setPanel] = useState<"expanded" | "collapsed">("expanded")`. Delete `if (dismissed) return null;`. Replace `handleDismiss` with `handleCollapse` (`setPanel("collapsed")`) + add `handleExpand` (`setPanel("expanded")`).
- [x] 1.3 Add the collapsed-strip render branch (`panel === "collapsed"`): full-width `<button type="button">` reusing the `fixed bottom-0 … border-t … bg-soleur-bg-surface-1/95 backdrop-blur-sm` footprint (slim `py-2`); `onClick={handleExpand}`, `aria-label="Reopen Soleur signup banner"`, `aria-expanded={false}`, `data-testid="cta-banner-reopen"`; inner "Built with **Soleur**" gold-accent line + inline up-chevron `<svg aria-hidden="true">` using the canonical lucide up-chevron `<polyline points="18 15 12 9 6 15" />` (cited in plan Research Reconciliation). Do NOT invent a chevron path.
- [x] 1.4 In the expanded branch, change the close button: `onClick={handleCollapse}`, `aria-label="Collapse signup banner"`, add `aria-expanded={true}`, keep `data-testid="cta-banner-dismiss"` and the X icon. ARIA disclosure: `aria-expanded` reflects current state on each rendered control (true expanded / false collapsed). No `aria-controls` (YAGNI). No scripted focus moves.
- [x] 1.5 Add `transition-all duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0` to the animated wrapper(s); EVERY `transition-*`/`duration-*` paired with a `motion-reduce:` reset. Incoming panel eases in; outgoing unmounts instantly (no exit animation). No JS `matchMedia`. Unanimated conditional-render swap read fine — entry flag not needed.
- [x] 1.6 Left `handleSubmit`, `Status`, success branch, form markup, honeypot, privacy line, aria-live region byte-identical.

## Phase 2 — Rewrite close test (`apps/web-platform/test/shared-cta-banner-close.test.tsx`)

- [x] 2.1 Deleted the unmount + sessionStorage-coupled cases (incl. the two storage-throw cases).
- [x] 2.2 Added 8 cases: default render; collapse → thin bar (not unmounted); reopen aria; click reopen → form restored; expanded close `aria-expanded=true`; both controls `<button>`; no sessionStorage write on collapse; fresh mount with stale key still expanded.

## Phase 3 — Keep waitlist test green

- [x] 3.1 Did NOT edit `shared-cta-banner-waitlist.test.tsx`. Confirmed green (7/7).

## Phase 4 — (optional) Wireframe

- [~] 4.1 DEFERRED — optional documentation artifact; the existing `.pen` (#5035) already covers this surface and the Product/UX gate auto-accepted (no new component). Not gating the code change.

## Phase 5 — Verify

- [x] 5.1 `vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx` — 14/14 green.
- [x] 5.2 `./node_modules/.bin/tsc --noEmit` — clean (exit 0).
- [x] 5.3 `grep -c "safeSession\|STORAGE_KEY\|sessionStorage" cta-banner.tsx` → 0.
- [x] 5.4 `git diff --name-only` does NOT include `apps/web-platform/lib/safe-session.ts`.
- [x] 5.5 Full web-platform vitest suite — 9135 passed, 0 failures.
