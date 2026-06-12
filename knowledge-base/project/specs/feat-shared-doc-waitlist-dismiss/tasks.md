---
feature: shared-doc-waitlist-dismiss
date: 2026-06-12
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-12-feat-shared-doc-waitlist-dismiss-plan.md
---

# Tasks: Remember "already joined" on the shared-doc waitlist banner

Single-file React change + its existing test. NEVER write the flag on anything
other than a confirmed `res.ok` 2xx success — that is the single-user-incident
invariant (a flag on a failed signup silently suppresses the CTA = lost lead).

## Phase 1 — Component (`apps/web-platform/components/shared/cta-banner.tsx`)

- [ ] 1.1 Add module-level constant `const JOINED_KEY = "soleur:shared:waitlist-joined";`.
- [ ] 1.2 Add `function readJoinedFlag(): boolean` above the component —
  `try { return localStorage.getItem(JOINED_KEY) === "1"; } catch { return false; }`.
  NO `typeof window` guard (component is client-only; the guard is dead code).
  Use bare `localStorage`. A read throw falls back to `false` → banner shows
  (safe direction).
- [ ] 1.3 Add `function writeJoinedFlag(): void` above the component —
  `try { localStorage.setItem(JOINED_KEY, "1"); } catch { /* private mode / quota */ }`.
  Keep it a NAMED helper (grep-ability of the single call site is load-bearing
  for AC3b). Store `"1"` only — never the email.
- [ ] 1.4 In `CtaBanner`, add lazy initializer `const [joined] = useState(() => readJoinedFlag());`
  AFTER the existing `panel`/`email`/`status` hooks. Then `if (joined) return null;`
  immediately after all hook calls (rules-of-hooks: all hooks run
  unconditionally; only the return is conditional, stable per mount).
- [ ] 1.5 In `handleSubmit`, replace `setStatus(res.ok ? "success" : "error");`
  with the explicit branch:
  `if (res.ok) { writeJoinedFlag(); setStatus("success"); } else { setStatus("error"); }`.
  The `catch { setStatus("error"); }` arm is unchanged — writes nothing.
  Do NOT hoist `writeJoinedFlag()` outside the `if (res.ok)` block.
- [ ] 1.6 Leave the in-session `status === "success"` view ("You're on the list ✓")
  untouched (FR4 / State B).
- [ ] 1.7 (Optional, recommended) one-line comment near the lazy initializer
  noting the SSR-safety depends on the `"use client"` page boundary.

## Phase 2 — Tests (`apps/web-platform/test/shared-cta-banner-waitlist.test.tsx`, extend existing)

- [ ] 2.1 Add `localStorage.clear();` to the existing `beforeEach` AND `afterEach`
  (alongside the current `sessionStorage.clear()`).
- [ ] 2.2 TST1 — Seed `localStorage.setItem("soleur:shared:waitlist-joined", "1")`
  BEFORE `render(<CtaBanner />)`; assert `queryByPlaceholderText(/you@company.com/i)`
  is null AND the "Built with" header is absent (whole component returned null).
- [ ] 2.3 TST2a — `vi.spyOn(localStorage, "setItem")` (instance, not prototype),
  stub `fetch` → `Response("", { status: 200 })`, type email, click Join,
  `await waitFor` success copy, assert
  `toHaveBeenCalledWith("soleur:shared:waitlist-joined", "1")`.
- [ ] 2.4 TST2b — `vi.spyOn(localStorage, "setItem")`, two cases: `fetch` reject
  (offline) AND `Response("", { status: 429 })`; after error copy renders,
  assert `not.toHaveBeenCalledWith("soleur:shared:waitlist-joined", expect.anything())`.
- [ ] 2.5 TST2c — `vi.spyOn(localStorage, "getItem").mockImplementation(() => { throw new Error("denied"); })`,
  `render(<CtaBanner />)`, assert the banner still shows (email input truthy).
- [ ] 2.6 Do NOT touch `shared-cta-banner-close.test.tsx` (TST3 — it stays green
  by construction; close-test never touches `localStorage`).

## Phase 3 — Verification

- [ ] 3.1 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 3.2 Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-waitlist.test.tsx test/shared-cta-banner-close.test.tsx`.
- [ ] 3.3 AC3b grep:
  `grep -c "writeJoinedFlag" apps/web-platform/components/shared/cta-banner.tsx`
  returns exactly 2; confirm the single call site is inside the `if (res.ok)` block.
- [ ] 3.4 AC7 grep: confirm `setItem` is only ever called with the literal `"1"`
  (the `email` state is never passed to any storage API).
