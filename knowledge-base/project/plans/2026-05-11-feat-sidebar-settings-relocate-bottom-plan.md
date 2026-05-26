---
type: feature
classification: ui-only
branch: feat-one-shot-sidebar-settings-relocate-bottom
requires_cpo_signoff: false
deepened_on: 2026-05-11
---

# feat: Relocate Settings from top nav to sidebar footer

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** 5 (Phase 1, Phase 2, Test Strategy, Acceptance Criteria, Risks)
**Research sources used:** local codebase grep (verbatim class verification, hook source read, sibling test scaffold), Next.js 15 / RTL 16 / vitest 3 API conventions in installed `node_modules`, open code-review issue `#2193` live state.

### Key Improvements

1. **Verified class strings against source (lines 286-287, 333, 341 of `layout.tsx`).** The plan's `bg-soleur-bg-surface-2 text-soleur-text-primary` and `text-soleur-text-muted hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary` literals are now confirmed verbatim against the existing top-nav and sibling footer items — zero drift.
2. **Confirmed `useSidebarCollapse` defaults to `false` (expanded) on render.** No localStorage mock needed in the new test file; the sidebar starts expanded, label `<span>` is visible, `getByRole("link", { name: /settings/i })` resolves correctly. Documented in Test Strategy.
3. **Refined the active-state test assertion strategy.** `toHaveAttribute("aria-current", "page")` is the primary observable (semantic, theme-agnostic); the className assertion is a secondary defensive check that the visual active-state branch was taken.
4. **Added a4 `aria-current` design note.** Using `aria-current="page"` (not `aria-current="true"`) — matches WAI-ARIA 1.2 recommendation for active nav links and is consistent with how the rest of the codebase exposes "you are here" state to assistive tech.
5. **Tightened the Cmd/Ctrl+B invariant test.** A new optional regression-guard test was considered but rejected as out-of-scope (the existing behavior is unchanged by this PR and the handler is covered by the absence of any edit to lines 152-173). Risks section now explicitly calls out the `git diff` invariant.

### New Considerations Discovered

- The existing top-nav `Link` does **not** use `aria-current` (a known a11y gap in the sibling Dashboard / KB / Analytics links). This PR ships `aria-current="page"` on the new Settings link only — improving the baseline without scope creep. A separate scope-out could fold the same attribute into the top-nav Link map, but that's outside this PR.
- `compareDocumentPosition` returns a bitmask, not a number to compare with `===`. The test sketch already uses `& Node.DOCUMENT_POSITION_FOLLOWING` correctly — confirmed against the DOM Standard.
- The `<a>` for Status uses `target="_blank" rel="noopener noreferrer"` — Test 2's `getByRole("link", { name: /status/i })` resolves both the Status `<a>` and the new Settings `<Link>` (both have role=link). Anchored regex (`/^status$/i`, `/^settings$/i`) disambiguates them.
- `useSignOut` mock is not needed for the new test file — the sign-out button still opens the modal, but our tests don't click it. The signout test file already proves the modal mount path; we don't re-test it here.

## Overview

Move the **Settings** entry out of the top `NAV_ITEMS` array in
`apps/web-platform/app/(dashboard)/layout.tsx` and insert it into the
sidebar footer between the **Status** external link and the **Sign out**
button. The new footer order is:

```text
userEmail (when expanded)
Status     (external <a>, opens betteruptime in new tab)
Settings   (next/link to /dashboard/settings)        ← NEW POSITION
Sign out   (button, opens SignOutConfirmModal)
```

The Settings entry retains all top-nav behaviors: `aria-current="page"`
when active, semantic active-state classes that match the existing
top-nav `Link` styling, collapsed-state icon-only rendering with a
`title` tooltip, and the existing `SettingsIcon` inline component.

The mobile drawer reuses the same `<aside>` element, so a single edit
covers both desktop and mobile. The existing `Cmd/Ctrl+B` skip rule for
`/dashboard/settings` (lines 162-167) is left untouched.

## User-Brand Impact

- **If this lands broken, the user experiences:** a missing Settings
  nav button (the user can still reach `/dashboard/settings` via the
  past-due banner CTA, the unpaid banner CTA, or by typing the URL
  directly). Visual/discoverability degradation; no data loss, no
  workflow blocker, no money exposure.
- **If this leaks, the user's data is exposed via:** N/A — this change
  does not touch authentication, authorization, network calls, storage,
  or any data path. The Settings page's own access controls are
  unchanged.
- **Brand-survival threshold:** none — the regression class for a
  miswired nav button is recoverable in seconds via direct URL or banner
  CTA, and zero PII is reachable from the failure surface.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from request) | Codebase reality | Plan response |
|---|---|---|
| Active-state styling should be `bg-neutral-800 text-white` | Existing top-nav `Link` uses `bg-soleur-bg-surface-2 text-soleur-text-primary` (semantic tokens that adapt to light/dark theme). Literal `bg-neutral-800` would break the light theme. | Honor the *intent* of "match the top-nav active-state styling" by reusing the **exact** classes from line 286 of `layout.tsx`. Do not introduce `bg-neutral-800` / `text-white` literals. Recorded as a known reconciliation. |
| "Status link" → "Settings" → "Sign out" | Status is currently an external `<a>` to `https://soleur-ai.betteruptime.com/` (opens in new tab via `target="_blank"`), not a `next/link`. | Preserve Status as-is; Settings is the only new `next/link` element. The footer order matches the spec. |
| `md:hidden` on the label is the mechanism for collapsed icon-only state | Confirmed: existing footer items (Status, Sign out) use `className="overflow-hidden whitespace-nowrap ${collapsed ? 'md:hidden' : ''}"` on the label `<span>`. The icon stays at `h-4 w-4 shrink-0`. | Mirror this pattern exactly. Same `min-h-[44px]`, same gap, same px/py, same hover classes — only the active-state branch is new. |
| Cmd/Ctrl+B handler "skips toggle on /dashboard/settings" | Confirmed (line 162-167) — the handler already early-returns when `pathname.startsWith("/dashboard/settings")`. | Leave the effect block untouched. No edit. |
| The mobile drawer reuses the same sidebar | Confirmed: the single `<aside>` at line 228 is both desktop sidebar and mobile drawer (CSS-toggled via `translate-x-*` + `md:relative md:translate-x-0`). | One change covers both. No separate drawer code path. |

## Open Code-Review Overlap

One open code-review issue touches `apps/web-platform/app/(dashboard)/layout.tsx`:

- **#2193** — `refactor(billing): unify past_due and unpaid banners into shared component + extract useDismissiblePersistent`. **Disposition: Acknowledge.** Different concern (banner extraction, not sidebar nav). Folding it in would balloon the PR scope and obscure the small targeted relocation. The scope-out remains open; this PR's diff is mechanically disjoint from #2193's planned diff.

## Files to Edit

1. `apps/web-platform/app/(dashboard)/layout.tsx`
   - Remove the Settings entry from the `NAV_ITEMS` array (line 90).
   - Insert a new `<Link>` element in the footer block between the
     Status `<a>` (lines 328-337) and the Sign out `<button>` (lines
     338-345).
   - The new `<Link>` mirrors the top-nav `Link`'s class structure
     (lines 280-294) for the active-state branch.

## Files to Create

1. `apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx`
   - 3 tests as specified by the user (NAV_ITEMS check, footer order,
     active state).
   - Mocks pattern lifted from
     `apps/web-platform/test/dashboard-layout-signout.test.tsx` (already
     verified to exercise the same `<aside>` mount path).

## Implementation Phases

### Phase 1 — RED: Write the three failing tests

Create `apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx` with the same mock scaffold as `dashboard-layout-signout.test.tsx`:

- Stub `next/navigation` `usePathname` per test via a hoisted setter so
  the "active state" test can switch between `/dashboard` and
  `/dashboard/settings/billing`.
- Stub `@/lib/supabase/client` (no-op session).
- Stub `@/hooks/use-team-names` and `@/components/theme/theme-provider`
  exactly as the sibling file does.
- Stub `fetch` to return `{ isAdmin: false }` for `/api/admin/check`.

**Test 1 — NAV_ITEMS no longer contains Settings:**

```ts
// dashboard-layout-sidebar-settings.test.tsx
import { NAV_ITEMS } from "@/app/(dashboard)/layout";
// NOTE: NAV_ITEMS is currently not exported. Phase 2 step (a) must
// add `export` to the const so this assertion is meaningful and not
// just a module-shape check.

it("NAV_ITEMS does not include a Settings entry", () => {
  expect(NAV_ITEMS.map((i) => i.href)).not.toContain("/dashboard/settings");
  expect(NAV_ITEMS.map((i) => i.label)).not.toContain("Settings");
});
```

**Test 2 — Footer renders Settings between Status and Sign out:**

```ts
it("renders the sidebar footer in order: Status → Settings → Sign out", async () => {
  await renderDashboard(); // pathname = "/dashboard"
  const status = screen.getByRole("link", { name: /^status$/i });
  const settings = screen.getByRole("link", { name: /^settings$/i });
  const signOut = screen.getByRole("button", { name: /^sign out$/i });

  // documentPosition: a < b → DOCUMENT_POSITION_FOLLOWING (4)
  expect(
    status.compareDocumentPosition(settings) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
  expect(
    settings.compareDocumentPosition(signOut) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
});
```

`compareDocumentPosition` is the canonical way to assert sibling order without coupling to DOM structure or sibling counts. Bitmask `Node.DOCUMENT_POSITION_FOLLOWING` (= 4) is set when the argument comes *after* the receiver in document order. jsdom supports this.

The test uses `getByRole("link", { name: /^settings$/i })` (anchored regex) to disambiguate the new footer Settings `Link` from any "Settings" alt-text inside SVGs or stray prose. Anchoring matters because if the relocation regresses and Settings stays in the top nav, both elements would match a loose `/settings/i` regex.

**Test 3 — Active-state class applied on /dashboard/settings/* routes:**

```ts
// Re-render with pathname = "/dashboard/settings/billing"
it("applies the active-state classes when on a /dashboard/settings route", async () => {
  setPathname("/dashboard/settings/billing"); // hoisted setter
  await renderDashboard();
  const settings = screen.getByRole("link", { name: /^settings$/i });

  expect(settings).toHaveAttribute("aria-current", "page");
  expect(settings.className).toContain("bg-soleur-bg-surface-2");
  expect(settings.className).toContain("text-soleur-text-primary");
});
```

The test asserts the **semantic-token class names** (not `bg-neutral-800` / `text-white`) per the Research Reconciliation row above.

Run `bun test apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx` and confirm all 3 fail with the expected reasons (NAV_ITEMS still contains `/dashboard/settings`; no Settings link in footer; etc.).

### Phase 2 — GREEN: Apply the relocation

(a) Add `export` to `NAV_ITEMS` so the test can import it:

```diff
-const NAV_ITEMS = [
+export const NAV_ITEMS = [
   { href: "/dashboard", label: "Dashboard", icon: GridIcon },
   { href: "/dashboard/kb", label: "Knowledge Base", icon: BookIcon },
-  { href: "/dashboard/settings", label: "Settings", icon: SettingsIcon },
 ];
```

(Reuse the existing `SettingsIcon` component at line 460 of the same file. No new import.)

(b) Insert the new `<Link>` between Status and Sign out in the footer block (after line 337, before line 338):

```tsx
{(() => {
  const settingsActive = pathname.startsWith("/dashboard/settings");
  return (
    <Link
      href="/dashboard/settings"
      title={collapsed ? "Settings" : undefined}
      aria-current={settingsActive ? "page" : undefined}
      className={`flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
        settingsActive
          ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
          : "text-soleur-text-muted hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary"
      } ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
    >
      <SettingsIcon className="h-4 w-4 shrink-0" />
      <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>
        Settings
      </span>
    </Link>
  );
})()}
```

If the IIFE pattern is undesired, hoist the `settingsActive` computation
above the `return` statement of `DashboardLayout` (cheap — it's one
string-startsWith).

(c) Run `bun test apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx`. All 3 should now pass. Also run the full dashboard-layout test family to confirm no regression:

```bash
bun test apps/web-platform/test/dashboard-layout-banner.test.tsx \
         apps/web-platform/test/dashboard-layout-signout.test.tsx \
         apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx
```

(d) Smoke-check `tsc --noEmit` from `apps/web-platform/` to catch any
discriminated-union or JSX-prop regressions from the new `<Link>`.

### Phase 3 — REFACTOR: pull the footer items into a shared sub-render (optional, skip by default)

The Status / Settings / Sign-out blocks now share 85% of their class string. A future cleanup could extract a `<SidebarFooterItem>` component, but **do not do it in this PR** — the three items diverge on element type (`<a target=_blank>` vs `<Link>` vs `<button onClick>`), which is exactly the divergence that breaks naïve extraction. File a deferral note in the PR body if appetite remains, but do not extract inline.

## Test Strategy

- **Framework:** vitest 3.x (`apps/web-platform/package.json` → `"vitest": "^3.1.0"`, `"test": "vitest"`). No new test framework, no new dependency.
- **Renderer:** `@testing-library/react` 16.x (already used by the sibling tests).
- **Pathname mocking:** the existing `dashboard-layout-signout.test.tsx` hardcodes `usePathname: () => "/dashboard"`. For Test 3, the new test file declares a `let _pathname = "/dashboard";` outside the mock and writes `usePathname: () => _pathname`, with a `setPathname` helper that mutates it before `renderDashboard()`. This is the lowest-friction way to vary pathname per-test without re-mocking inside each `it`.
- **Cleanup:** `afterEach(cleanup)` per the sibling file's pattern.
- **No new MSW handlers.** The Settings entry's `next/link` does not make a network call.
- **No `useSidebarCollapse` mock needed.** Verified by reading `apps/web-platform/hooks/use-sidebar-collapse.ts`: `useState(false)` initial; the localStorage hydration runs only in a `useEffect` and defaults to expanded when storage is empty (which it is in the jsdom test env). The sidebar renders expanded for all three tests, so the label `<span>` is visible and `getByRole("link", { name: /settings/i })` resolves to the new footer Link without ambiguity.

### Research Insights

**Best Practices for active-link a11y in Next.js 15 + React 19:**

- The MDN `aria-current` spec lists `"page"` as the canonical value for "the link to the current page in a navigation set". Use `"page"`, not `"true"` or `"location"` — `"page"` is the most specific and survives screen-reader announcements unchanged across NVDA, JAWS, and VoiceOver.
- Conditional attribute pattern: `aria-current={active ? "page" : undefined}`. Passing `undefined` (not `false`) ensures the attribute is omitted entirely from the rendered DOM — `aria-current="false"` is a valid value with different semantic meaning ("not current") that some screen readers will announce.
- The existing top-nav `Link` block in this file (line 280) does NOT set `aria-current` — a known accessibility gap. Adding it here improves the baseline without scope creep; a future PR can fold the same attribute into the top-nav loop.

**Test assertion strategy — primary vs. secondary observables:**

- **Primary:** `expect(link).toHaveAttribute("aria-current", "page")`. This is semantic, theme-agnostic, and survives any future CSS refactor.
- **Secondary (defensive):** `expect(link.className).toContain("bg-soleur-bg-surface-2")`. Confirms the visual active branch was taken; protects against a bug where `aria-current` is set but the className was hard-coded to the inactive branch. The two assertions together protect against both regression classes.
- Do NOT use `toHaveClass()` with the full class string — Tailwind/jsx whitespace, conditional gaps, and the `${collapsed ? ... : ""}` ternary make full-string matching brittle. `.className.toContain("bg-soleur-bg-surface-2")` is the right granularity.

**`compareDocumentPosition` — bitmask semantics:**

```ts
// Returns a 16-bit bitmask. Constants:
//   Node.DOCUMENT_POSITION_DISCONNECTED         = 1
//   Node.DOCUMENT_POSITION_PRECEDING            = 2
//   Node.DOCUMENT_POSITION_FOLLOWING            = 4
//   Node.DOCUMENT_POSITION_CONTAINS             = 8
//   Node.DOCUMENT_POSITION_CONTAINED_BY         = 16
const flags = a.compareDocumentPosition(b);
const bFollowsA = (flags & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
```

The test sketch uses `& 4 (FOLLOWING)` correctly. jsdom (vitest 3's default DOM impl) implements this per the DOM Living Standard. If a future jsdom regresses, the fallback is `Array.from(footer.querySelectorAll("a, button"))` and index comparison.

**Anchored regex selectors prevent silent collisions:**

- `getByRole("link", { name: /settings/i })` would also match a link whose accessible name is "Update Payment Settings" or "Open Settings Panel" if such a thing existed. Anchored regex `/^settings$/i` requires the accessible name to be exactly "Settings".
- This is load-bearing: if the relocation regresses and Settings stays in `NAV_ITEMS`, Test 2 would otherwise quietly pass with TWO Settings links in the DOM (one in nav, one in footer) — anchored regex + the `compareDocumentPosition` invariant would still fail on the duplicate-name `getByRole` lookup (`Found multiple elements...`), but failing on the right reason matters for debug time.

**Edge cases:**

- **Test 3's pathname assertion arity.** `pathname.startsWith("/dashboard/settings")` matches `/dashboard/settings` AND `/dashboard/settings/billing` AND `/dashboard/settings-foo` (the third would also match). The codebase has no route at `/dashboard/settings-foo`, so the `startsWith` mirrors the top-nav loop's existing approach and stays consistent. If a sibling route like `/dashboard/settings-team` is ever added, this predicate would over-match — a future scope-out, not this PR.
- **Test 2's order brittleness.** If `userEmail` resolves to a string in the test env and `!collapsed` is true, the `<p>userEmail</p>` element renders between the border and Status. The order test only constrains Status → Settings → Sign out, so the userEmail row is invisible to the assertion. (Our test mocks return `session: null`, so `userEmail` stays `null` and the `<p>` is conditional-out anyway.)
- **`@testing-library/jest-dom` matchers (`toHaveAttribute`).** The sibling test file uses these without explicit setup — verify by reading the project's vitest setup file (`apps/web-platform/test/setup.ts` or `vitest.config.ts`) if test 3 fails with "toHaveAttribute is not a function". Mitigation: import `"@testing-library/jest-dom/vitest"` at the top of the new test file. The sibling signout test does not need it because its assertions are `toHaveBeenCalledTimes`-style; ours uses DOM matchers.

**References:**

- WAI-ARIA 1.2 — `aria-current`: <https://www.w3.org/TR/wai-aria-1.2/#aria-current>
- DOM Living Standard — `Node.compareDocumentPosition`: <https://dom.spec.whatwg.org/#dom-node-comparedocumentposition>
- Testing Library — `getByRole` queries and accessible names: <https://testing-library.com/docs/queries/byrole/>
- Next.js 15 — `next/link` API: <https://nextjs.org/docs/app/api-reference/components/link>

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/app/(dashboard)/layout.tsx`'s `NAV_ITEMS` array contains exactly 2 entries (Dashboard, Knowledge Base) — Settings is removed.
- [x] The footer block contains, in DOM order: `userEmail` (when expanded) → Status `<a>` → Settings `<Link>` → Sign out `<button>`.
- [x] The new Settings `<Link>` carries `aria-current="page"` when `pathname.startsWith("/dashboard/settings")` and omits the attribute otherwise.
- [x] The active-state class branch resolves to `bg-soleur-bg-surface-2 text-soleur-text-primary` (matching the top-nav `Link` exactly).
- [x] The inactive-state class branch resolves to `text-soleur-text-muted hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary` (matching the sibling footer items exactly).
- [x] When `collapsed && md+ viewport`, the Settings label is hidden via `md:hidden`, the icon is centered (`md:justify-center md:gap-0 md:px-0`), and the `title="Settings"` tooltip is present.
- [x] The existing Cmd/Ctrl+B effect block (lines 152-173) is unchanged — verify with `git diff` that the lines are identical.
- [x] `apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx` ships with 3 passing tests.
- [x] The new test file imports `@testing-library/jest-dom/vitest` at the top if the project's vitest setup does not register the matchers globally (verify by reading `apps/web-platform/vitest.config.ts` and the file referenced as `setupFiles`; if `jest-dom` is registered globally, omit the per-file import to avoid duplicate registration warnings).
- [x] `bun test apps/web-platform/test/dashboard-layout-banner.test.tsx apps/web-platform/test/dashboard-layout-signout.test.tsx apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx` is all-green.
- [x] `tsc --noEmit` (from `apps/web-platform/`) is clean.

### Post-merge (operator)

- None — this is a UI-only client-rendered change. No migration, no Doppler config, no Terraform apply, no rebuild step beyond the standard Vercel deploy.

## Risks

- **Reconciliation drift.** The user's brief named `bg-neutral-800 text-white` literals; the codebase uses semantic tokens. The Research Reconciliation row above documents the divergence. Mitigation: tests assert the *semantic* token class names — a future maintainer who flips to literals will see Test 3 fail, which surfaces the convention violation. (See `cq-` family on theme-token discipline.)
- **`NAV_ITEMS` becoming exported.** Adding `export` widens the module surface area by one named binding. This is acceptable (test fixture) and the smallest plausible coupling; the alternative — testing the rendered DOM for absence of a Settings link in the top nav block — is brittle to where in the DOM the loop renders. Documented in Phase 1 Test 1's inline comment.
- **`compareDocumentPosition` jsdom support.** jsdom implements this correctly per its `Node` interface; no known regressions across vitest's jsdom version range. If a future jsdom bump regresses, fall back to `screen.getAllByRole("link")` index comparison.
- **Light-theme regression.** Hardcoded `bg-neutral-800` would have been invisible in dark mode but unreadable in light mode. The semantic-token choice avoids this entirely. No further mitigation needed.
- **Discoverability of Settings.** Moving Settings from the top nav (always visible) to the footer (below recents/conversations) marginally reduces visual prominence. This is a deliberate design choice (the task spec is explicit) and Settings remains reachable via two banner CTAs (`past_due`, `unpaid`) and direct URL.
- **Mobile drawer parity.** The single `<aside>` mount renders both surfaces. Verified by reading the JSX tree (no separate mobile fork). No additional test needed because `dashboard-layout-signout.test.tsx` already exercises the same mount path.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here with `none` threshold per the recoverability analysis.
- The Cmd/Ctrl+B handler already references `/dashboard/settings`. Do **not** delete that branch when removing Settings from `NAV_ITEMS` — the route still exists, the handler skip is still load-bearing for the Settings page's own internal collapsible (per `feat-one-shot-fix-settings-sidebar-gap-and-header-alignment`).
- Do not extract `<SidebarFooterItem>` in this PR. The three footer items diverge on element type (`<a>` external, `<Link>` internal, `<button>` modal opener) — naïve extraction will fight prop-shape unification and either bloat the component with three variant props or push the divergence one level up via `as=` polymorphism (also unnecessary).
- When the test imports `NAV_ITEMS` directly, ensure the `export` keyword survives any future deepen-plan or re-plan iteration. A consumer-side import that silently breaks (because `NAV_ITEMS` becomes file-local again) would turn Test 1 into a module-resolution error rather than a clear failure.

## Domain Review

**Domains relevant:** Product (advisory only)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline mode; no new component file created at `components/**/*.tsx` or `app/**/page.tsx`)
**Skipped specialists:** none (no recommendations from any domain leader)
**Pencil available:** N/A

#### Findings

This is a relocation within an existing surface (`apps/web-platform/app/(dashboard)/layout.tsx`) with no new component file, no new route, no new flow, no new copy, and no change to the Settings page itself. The mechanical escalation criterion ("any new file path matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`") does NOT fire — only test files and the existing layout are touched. Tier resolves to ADVISORY; in pipeline mode, ADVISORY auto-accepts.

The "Settings less discoverable" framing is acknowledged in Risks; the user's explicit intent overrides discoverability concerns.

No GDPR surface (no schema, no migration, no API route, no auth flow). GDPR gate skipped silently.

## Out of Scope

- The Cmd/Ctrl+B handler block (lines 152-173). Left untouched per the user's explicit constraint.
- The `feat-one-shot-fix-settings-sidebar-gap-and-header-alignment` plan (separate PR concern — internal Settings collapsible).
- The #2193 banner unification scope-out (acknowledged in Open Code-Review Overlap).
- Extracting a shared `<SidebarFooterItem>` component (see Sharp Edges).
- Any change to `ADMIN_NAV_ITEMS`. Analytics stays in the top nav.

## References

- `apps/web-platform/app/(dashboard)/layout.tsx` (lines 87-91 NAV_ITEMS, lines 152-173 Cmd/B handler, lines 272-297 top-nav Link, lines 318-346 footer block, line 460 SettingsIcon)
- `apps/web-platform/test/dashboard-layout-signout.test.tsx` (mock-scaffold template)
- `apps/web-platform/test/dashboard-layout-banner.test.tsx` (existing dashboard-layout test)
- Open scope-out #2193 (acknowledged, not folded)
