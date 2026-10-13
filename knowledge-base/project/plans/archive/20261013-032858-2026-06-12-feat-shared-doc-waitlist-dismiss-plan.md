---
title: Remember "already joined" on the shared-doc waitlist banner
type: feat
date: 2026-06-12
feature: shared-doc-waitlist-dismiss
branch: feat-shared-doc-waitlist-dismiss
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-shared-doc-waitlist-dismiss/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-12-shared-doc-waitlist-dismiss-brainstorm.md
wireframe: knowledge-base/product/design/shared-document/cta-banner-visibility-states.pen
related_prs: ["#5035", "#5075", "#5076", "#5153"]
---

# Remember "already joined" on the shared-doc waitlist banner

A visitor who joins the waitlist from the public shared-document page is currently
re-prompted with the full empty form on every reload, because the CTA banner
(`apps/web-platform/components/shared/cta-banner.tsx`) keeps all of its state in
`useState` only. This plan adds a per-browser durable marker so that, on any
subsequent mount in that browser, the banner does **not render at all**
(wireframe **State C**). The marker is a single client-side `localStorage`
boolean written **only** after a confirmed `{ok:true}` join — never on error,
never on a manual collapse, and the entered email is never persisted.

Scope is exactly one component file plus its already-existing test file. No API
change, no migration, no new server surface, no new PII at rest, no enumeration
vector.

## Enhancement Summary

**Deepened on:** 2026-06-12
**Mandatory gates:** 4.6 User-Brand Impact (pass — `single-user incident`),
4.7 Observability (skip — client-only, no server/src/infra surface),
4.8 PAT-shaped var (pass — none), 4.9 UI-wireframe (pass — `.pen` committed).
**Agents:** verify-the-negative (grep sweep), React-19/Next.js best-practices
(Explore), code-simplicity-reviewer, user-impact-reviewer (single-user threshold).

### Key Improvements

1. **AC3b added (closes user-impact FINDING 1)** — the load-bearing "write only
   on `res.ok`" invariant was enforced by prose/convention alone; now there is a
   grep-AC asserting `writeJoinedFlag` has exactly one call site, inside the
   `if (res.ok)` branch. This is the single-user-incident gate made mechanical.
2. **Dead `typeof window` SSR guard removed** (simplicity + verify-the-negative)
   — the component is never server-rendered, so the guard is unreachable. Use
   bare `localStorage`; keep the two named helpers for grep-ability.
3. **Instance-level spy** (`vi.spyOn(localStorage, "setItem")`) instead of
   `Storage.prototype` for the new tests — `Storage.prototype` is shared with
   `sessionStorage` and could false-match; the existing close-test keeps its
   `Storage.prototype` spy and stays untouched/green.
4. **AC6 re-scoped + promoted to required** — the read-throw safe-fallback
   direction (throw → banner shows, never suppress) is load-bearing (a hiding
   read-throw is a distinct single-user incident); the write-throw half is a
   no-op and dropped. Added TST2c.
5. **AC3 sufficiency made explicit** — `Response.ok === false` for all non-2xx,
   so 429 represents the whole non-2xx class; no per-status enumeration needed.

### New Considerations Discovered

- `vi.spyOn(localStorage, "setItem")` is unambiguous vs the prototype spy; both
  work in happy-dom 20.x (the test env is happy-dom, not jsdom — confirmed).
- No `useSyncExternalStore` needed: the flag is read once at mount and never
  changes during the mount, so lazy `useState` is the minimal correct tool.
- The localStorage write inside the async handler needs no extra `act()`
  handling — the existing `waitFor(...)` on the success copy already wraps the
  React state update; the synchronous storage write completes before re-render.
- `CtaBanner` (unlike `PdfPreview`/`C4Diagram` on the same page) is NOT a
  `dynamic(..., { ssr: false })` import — safe only because the whole page is
  `"use client"`. Worth a one-line code comment so a future move to a
  server-rendered surface re-triggers the SSR consideration.

## User-Brand Impact

- **If this lands broken, the user experiences:** the shared-doc waitlist CTA
  banner is silently suppressed for a visitor who *never successfully joined* —
  a genuine prospect is never prompted and the lead is lost (banner hidden on a
  browser where the flag was wrongly written).
- **If this leaks, the user's data is exposed via:** persisting the entered email
  in client storage would expose PII on a shared machine; a server-side
  "is this email subscribed?" existence-check would leak waitlist membership of
  arbitrary emails (enumeration oracle). Both are explicitly out of scope.
- **Brand-survival threshold:** `single-user incident`. The load-bearing
  invariant is **FR3** — the flag is written on a confirmed 2xx success only.
  A flag on a failed signup silently suppresses the CTA and loses a real lead;
  one mis-targeted visitor is the single-user incident this plan guards against.

## Overview

The shared-doc page is **public** and the visitor is **anonymous** — there is no
auth session and no known email until one is typed. `/api/waitlist` deliberately
returns an identical `{ok:true}` for a brand-new signup and for an
already-subscribed email (anti-enumeration; `waitlist.ts` folds Buttondown's 400
`email_already_exists` into success). Given an anonymous visitor and an
anti-enumeration API, a **client-side, per-browser marker written after a
confirmed Join** is the only viable "remember" signal — confirmed by the
CPO + CLO + CTO triad in the brainstorm (every server-side alternative rejected;
CLO PROHIBITS a server existence-check).

The implementation is two helper functions (`readJoinedFlag`, `writeJoinedFlag`),
a lazy `useState` initializer that short-circuits the whole component to `null`
when the flag is present, and a single `writeJoinedFlag()` call in the
`success` branch of `handleSubmit`. Both helpers are fully `try/catch`-wrapped so
private mode / disabled storage falls back to today's in-memory behaviour
(banner shows) rather than throwing.

## Research Reconciliation — Spec vs. Codebase

The spec and brainstorm describe the legacy key as something to be kept distinct
from. The exact storage backing of that legacy key differs from the prose, in a
way that makes our change strictly safer — surfaced here so the implementer does
not "correct" the new code toward the wrong backing store.

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Legacy `soleur:shared:cta-dismissed` key is a `localStorage` key to stay distinct from (spec TR4, brainstorm Decision 2) | The legacy key is a **`sessionStorage`** literal — `shared-cta-banner-close.test.tsx` seeds it via `sessionStorage.setItem` and clears only `sessionStorage` in `beforeEach`/`afterEach`. The component writes it nowhere (toggle is pure in-memory `useState`). | Our new flag lives in **`localStorage`** under a different key. There is zero cross-store collision; the close-test never touches `localStorage`, so TST3 is satisfied by construction. Keep the new key in `localStorage` (per TR5 — `localStorage`, not cookie, not `sessionStorage`). |
| "Add `test/shared-cta-banner-waitlist.test.tsx`" (spec TST block, pipeline summary) | The file **already exists** with 6 passing tests (idle aria-live, privacy link, success→confirm copy, fetch-reject error, 429 error, in-flight "Joining…"). Its `beforeEach`/`afterEach` clear only `sessionStorage`. | **Extend** the existing file — do not create. Add `localStorage.clear()` to both `beforeEach` and `afterEach` (TST4), and append the three new flag tests. The pre-existing "on success replaces the form" test will now *also* write the flag (benign); keep it green. |
| Component is "purely in-memory today" | Confirmed: `grep localStorage\|sessionStorage` in the component returns zero. | New code introduces the first storage access; both paths `try/catch`-wrapped (TR2). |
| Banner mounted as `{data && <CtaBanner />}` on a `"use client"` page at `app/shared/[token]/page.tsx:150` (TR1) | Confirmed verbatim at line 150; page is `"use client"` and fetches `data` client-side. Banner is therefore never in server-rendered HTML. | Use a lazy `useState(() => readJoinedFlag())` initializer with **no** `mounted`-gate. No hydration mismatch is possible. |
| New key `soleur:shared:waitlist-joined` unused | `grep waitlist-joined apps/web-platform/` returns zero. | Safe to introduce. |

## Implementation Phases

### Phase 1 — Storage helpers + render-null gate (`cta-banner.tsx`)

1. Add a module-level constant `const JOINED_KEY = "soleur:shared:waitlist-joined";`.
2. Add two `try/catch`-wrapped helpers above the component. **No
   `typeof window` guard** — the component is client-only (mounted as
   `{data && <CtaBanner />}` on a `"use client"` page after a client-side
   fetch; it is never server-rendered), so a `typeof window === "undefined"`
   branch is dead code from day one. Use the bare `localStorage` global,
   consistent with the rest of the component (deepen-plan: simplicity +
   verify-the-negative both flagged the SSR guard as unreachable):
   - `function readJoinedFlag(): boolean` —
     `try { return localStorage.getItem(JOINED_KEY) === "1"; } catch { return false; }`
     (TR2 — a read throw falls back to `false` → **banner shows**, the safe
     direction: a thrown read must never suppress the CTA).
   - `function writeJoinedFlag(): void` — `try { localStorage.setItem(JOINED_KEY, "1"); } catch { /* private mode / quota — keep in-memory behaviour */ }` (TR2, TR3 — boolean `"1"` only, never the email). Keep this as a **named** helper (not inlined) so the load-bearing "write only on success" invariant is grep-able as a single call site (see AC3b).
3. In `CtaBanner`, add a lazy initializer:
   `const [joined] = useState(() => readJoinedFlag());` (TR1 — initializer, not
   `useEffect`). Immediately after the hooks, `if (joined) return null;` (FR1,
   wireframe State C). Place the early-return after **all** hook calls so React's
   rules-of-hooks ordering is preserved (hooks run unconditionally; the return is
   conditional, which is legal because it is the same on every render for a given
   mount).
4. In `handleSubmit`, in the branch that sets `success`, also call
   `writeJoinedFlag()`. Concretely, replace `setStatus(res.ok ? "success" : "error");`
   with an explicit branch so the write is unambiguously gated:
   ```ts
   if (res.ok) {
     writeJoinedFlag();   // FR2 — confirmed 2xx only
     setStatus("success");
   } else {
     setStatus("error");  // FR3 — no write on non-2xx
   }
   ```
   The `catch { setStatus("error"); }` arm is unchanged and writes nothing
   (FR3 — no write on fetch rejection / offline).
5. Leave the in-session success view (`status === "success"` → "You're on the
   list ✓ — check your inbox to confirm.") untouched (FR4, wireframe State B).
   The hide-entirely behaviour takes effect on the *next* mount via the
   `joined` gate, not mid-session.

### Phase 2 — Tests (`test/shared-cta-banner-waitlist.test.tsx`, extend existing)

1. Add `localStorage.clear();` to the existing `beforeEach` and to the existing
   `afterEach` (alongside the current `sessionStorage.clear()`) (TST4 — jsdom
   does not reset storage between tests).
2. **TST1** — Seed before mount: `localStorage.setItem("soleur:shared:waitlist-joined", "1");`
   then `render(<CtaBanner />)`; assert `screen.queryByPlaceholderText(/you@company.com/i)`
   is `null` AND the brand header text ("Built with") is absent (the whole
   component returned `null`, State C). Seed before mount — do not rely on a
   remount carrying in-component state.
3. **TST2a** — Successful submit writes the flag:
   `const setItemSpy = vi.spyOn(localStorage, "setItem");` — spy the
   **instance** method (`localStorage.setItem`), NOT `Storage.prototype.setItem`.
   `Storage.prototype` is shared by `localStorage` AND `sessionStorage`; spying
   the instance is unambiguous and avoids a false match if any
   `sessionStorage` write occurs in the same test (deepen-plan: research +
   user-impact). Stub `fetch` → `new Response("", { status: 200 })`, type
   email, click Join, `await waitFor` success copy, then assert
   `expect(setItemSpy).toHaveBeenCalledWith("soleur:shared:waitlist-joined", "1")`.
4. **TST2b** — Errored submit does NOT write the flag:
   `const setItemSpy = vi.spyOn(localStorage, "setItem");` (instance), stub
   `fetch` → reject (offline) AND a separate case stub → `status: 429`; in
   each, after the error copy renders, assert the spy was **not** called with
   the joined key
   (`expect(setItemSpy).not.toHaveBeenCalledWith("soleur:shared:waitlist-joined", expect.anything())`).
   Use `not.toHaveBeenCalledWith(key, ...)` rather than `not.toHaveBeenCalled()`
   so the assertion is robust to any unrelated incidental `setItem`. Note:
   `Response.ok` is `false` for **every** non-2xx status, so the 429 case is
   representative of the entire non-2xx class (500/401/503 share the same
   `else` branch) and the offline case is representative of the `catch` branch
   — the two cases cover both code paths, no per-status enumeration needed.
5. **TST2c** (read-throw safe-fallback, required) — Make the read throw:
   `vi.spyOn(localStorage, "getItem").mockImplementation(() => { throw new Error("denied"); });`
   then `render(<CtaBanner />)` and assert the banner still shows
   (`queryByPlaceholderText(/you@company.com/i)` is truthy). This pins the
   load-bearing fallback DIRECTION: a thrown read must render the banner (show),
   never suppress it (TR2 / AC6). The write-throw half is intentionally NOT
   tested — a swallowed write is a no-op with no user-facing artifact, so a test
   for it would assert nothing observable.
6. **TST3** — `shared-cta-banner-close.test.tsx` is untouched and stays green:
   it already proves toggling writes nothing and the legacy `sessionStorage`
   key is ignored. No edit needed; the run is the assertion. (Cross-store
   isolation is structural — close-test never touches `localStorage`.)

### Phase 3 — Verification

- Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  (NOT `npm run -w` — repo root declares no `workspaces`).
- Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-waitlist.test.tsx test/shared-cta-banner-close.test.tsx`
  (vitest `include` glob is `test/**/*.test.tsx`; both files match. Runner is
  `vitest`, NOT `bun test` — `bunfig.toml` sets `pathIgnorePatterns = ["**"]`).

## Files to Edit

- `apps/web-platform/components/shared/cta-banner.tsx` — add `JOINED_KEY`
  constant, `readJoinedFlag`/`writeJoinedFlag` helpers, lazy `useState`
  initializer + `if (joined) return null;` gate, and the `writeJoinedFlag()`
  call in the `res.ok` branch of `handleSubmit`.
- `apps/web-platform/test/shared-cta-banner-waitlist.test.tsx` — add
  `localStorage.clear()` to `beforeEach`/`afterEach`; append TST1 (seed→null),
  TST2a (success writes, instance spy), TST2b (error/offline/429 does not
  write), TST2c (read-throw → banner shows).

## Files to Create

- None. (Both target files already exist on disk — verified.)

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (FR1 / State C)** — With `localStorage["soleur:shared:waitlist-joined"]="1"`
  seeded before mount, `CtaBanner` renders nothing: `queryByPlaceholderText(/you@company.com/i)`
  is `null` and the "Built with" header is absent. (TST1)
- **AC2 (FR2)** — A `fetch` → 200 submit calls
  `localStorage.setItem("soleur:shared:waitlist-joined", "1")` exactly (instance
  spy, `vi.spyOn(localStorage, "setItem")`). (TST2a)
- **AC3 (FR3 — load-bearing)** — A `fetch` rejection (offline) AND a non-2xx
  (429) submit each leave the joined key unwritten: the `setItem` spy is never
  called with `"soleur:shared:waitlist-joined"`. Because `Response.ok` is
  `false` for every non-2xx status, the 429 case is representative of all
  non-2xx responses and the offline case of the `catch` branch — together they
  cover both write-suppression paths. (TST2b)
- **AC3b (FR3 — call-site placement, load-bearing)** — The write is gated inside
  the success branch, machine-verified, not convention-only:
  `grep -c "writeJoinedFlag" apps/web-platform/components/shared/cta-banner.tsx`
  returns exactly **2** (one declaration + one call site), and the single call
  site sits inside the `if (res.ok)` block of `handleSubmit` — confirm the
  call is on a line whose enclosing block is the `res.ok` true-branch (read the
  surrounding 3 lines). This closes the deepen-plan user-impact FINDING 1 gap:
  the lost-lead invariant is no longer enforced by prose alone. A second call
  site (count > 2) or a call outside `if (res.ok)` fails this AC.
- **AC4 (FR4 / State B)** — In the same session as a successful join, the
  "You're on the list ✓ — check your inbox to confirm." copy still renders
  (existing success test stays green; no abrupt unmount mid-session).
- **AC5 (TST3)** — `shared-cta-banner-close.test.tsx` runs green unchanged:
  toggle writes nothing, legacy `sessionStorage` key ignored.
- **AC6 (TR2 — read-throw safe direction, required)** — A thrown
  `localStorage.getItem` (`vi.spyOn(localStorage, "getItem").mockImplementation(() => { throw new Error(); })`)
  does not crash the component and the banner **still renders the form** —
  read-throw falls back to "show" (never suppress). This direction is the
  load-bearing half (a read-throw that hid the banner would silently suppress
  the CTA — a different single-user incident). Promoted from optional to
  required per deepen-plan user-impact FINDING 5. (TST2c) The write-throw half
  is a swallowed no-op with no observable artifact and is intentionally not
  tested.
- **AC7 (TR3)** — `grep` of the component shows `setItem` is only ever called
  with the literal `"1"` value — the `email` state is never passed to any
  storage API.
- **AC8** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- **AC9** — `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-waitlist.test.tsx test/shared-cta-banner-close.test.tsx` passes (all tests green).

### Post-merge (operator)

- None. Pure client-side code change against an already-deployed page; the
  `web-platform-release.yml` pipeline restarts the container on merge to `main`
  touching `apps/web-platform/**`. No migration, no terraform, no external
  service state to verify.

## Observability

Phase 2.9 trigger set is `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`,
`plugins/*/scripts/`, or new infrastructure. This plan edits only
`apps/web-platform/components/**` (client-side React) and a test file — **no
server/infra surface** — so the formal 5-field server-observability schema does
not apply (skip per Phase 2.9 "pure client component" exemption). The relevant
failure mode (FR3 — flag written on a non-success) is **fully observable in CI**:
AC3's `setItem`-spy test fails loud if the flag is ever written outside the
confirmed-success branch. There is intentionally no server-side telemetry — the
whole point of the design is that nothing about the join is sent to or stored on
the server beyond the existing `/api/waitlist` call (anti-enumeration, no PII at
rest). A client-side Sentry breadcrumb would carry no operator value and is out
of scope.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from
brainstorm `## Domain Assessments`; Marketing, Operations, Sales, Finance,
Support assessed as not-relevant).

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Client-only `localStorage` is correct; no defensible server
path. Render `null` on the remembered state via a lazy initializer (banner is
never in SSR HTML → no `mounted`-gate flash). Highest-risk path: writing the flag
on anything other than a confirmed success — addressed by FR3 + AC3. Single-file
blast radius; no migration. Complexity: small.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `components/shared/cta-banner.tsx` is a UI path)
**Decision:** auto-accepted (pipeline) — wireframe pre-exists and is operator-confirmed
**Agents invoked:** none (carry-forward; see below)
**Skipped specialists:** none — `ux-design-lead` output already on disk (see Pencil line)
**Pencil available:** N/A — wireframe `.pen` already committed and operator-confirmed

#### Findings

The wireframe `knowledge-base/product/design/shared-document/cta-banner-visibility-states.pen`
exists on disk (22 KB, non-empty, operator-confirmed per the pipeline prompt and
brainstorm Decision 11) and is referenced in the spec FRs as States A/B/C. No
new component file is created (`## Files to Create` is empty — the change edits an
existing component), so the mechanical component-creation escalation adds nothing
beyond the already-satisfied wireframe. CPO carry-forward: per-browser scope is
acceptable for v1; no distinct already-subscribed message (anti-enumeration
feature, not a gap); operator chose full-hide over the CPO-recommended thin bar —
recorded as the v1 decision. `requires_cpo_signoff: true` is set; CPO reviewed
the brainstorm (triad), satisfying the plan-time product-owner ack.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Client-only boolean flag — **PERMIT**. Functional/strictly-
necessary storage under ePrivacy Art. 5(3); no cookie-consent banner, not
personal data (device-local, no identifier), no Art. 30 change. Server existence-
check — **PROHIBIT** (breaks the anti-enumeration design). This is why no
GDPR-gate re-invocation is needed at plan time: the regulated-surface regex
(schema/migration/auth/API) is not touched, and the single-user-incident trigger
(b) is already adjudicated PERMIT by the CLO in the brainstorm.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Server-side existence-check ("is this email on the list?") | CLO-PROHIBITED — converts the uniform `{ok:true}` into an enumeration oracle leaking waitlist membership. |
| Persist the entered email in `localStorage` | PII at rest on shared machines (shared docs open on shared machines). Boolean `"1"` only (TR3). |
| Cookie instead of `localStorage` | Puts the marker on every HTTP request + into the cookie-consent surface. `localStorage` keeps it client-only and consent-free (TR5). |
| Reuse the legacy `soleur:shared:cta-dismissed` key | That key is the in-memory dismissal marker (actually `sessionStorage`, asserted non-persistent by the close-test). A *join* is a different, durable signal — distinct key (Decision 2). |
| `useEffect` + `mounted`-gate to read storage | Unnecessary — banner is never in SSR HTML (`{data && <CtaBanner/>}` on a `"use client"` page), so a lazy `useState` initializer is safe and avoids a one-frame flash (TR1). |

## Sharp Edges

- **The load-bearing invariant is FR3.** The write MUST live inside the `res.ok`
  branch only. Do not "simplify" back to `setStatus(res.ok ? "success" : "error")`
  with the write outside the branch — that re-opens the lost-lead failure mode.
  The explicit `if (res.ok) { writeJoinedFlag(); setStatus("success"); } else { setStatus("error"); }`
  shape is intentional.
- **Legacy key is `sessionStorage`, not `localStorage`.** Do not align the new
  write to `sessionStorage` to "match" the legacy key. The new marker is
  `localStorage` (durable, per TR5); the legacy key is `sessionStorage`
  (in-memory dismissal). They are different stores by design.
- **The waitlist test file already exists — extend, never overwrite.** It has 6
  passing tests; clobbering it loses the success/error/in-flight coverage. Add
  `localStorage.clear()` to the existing hooks and append the 3 new tests.
- **Place `if (joined) return null;` after all hook calls.** All three
  `useState` hooks must run unconditionally (rules of hooks); only the *return*
  is conditional. It is stable per mount (the initializer reads once), so this is
  legal.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This section is filled with a concrete artifact, vector, and the
  `single-user incident` threshold.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open
scope-out whose body references `components/shared/cta-banner.tsx`.

## Infrastructure (IaC)

None. Pure client-side code change against an already-provisioned page; no
server, service, secret, vendor, DNS, cert, or runtime process introduced.
Phase 2.8 skipped.
