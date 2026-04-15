# fix: Integrations page missing Team Settings sidebar (#2227)

## Enhancement Summary

**Deepened on:** 2026-04-15
**Sections enhanced:** 5 (Root Cause, Fix, Risks & Sharp Edges, Acceptance Criteria, Test Scenarios)
**Research agents used:** static code inspection (sibling content components), learnings-grep for layout patterns

### Key Improvements Discovered

1. **Double-wrap layout regression risk is real, not hypothetical.** `ConnectedServicesContent` already applies `mx-auto max-w-2xl px-4 py-10` at its root — the same classes `SettingsShell` applies around children. Wrapping without refactoring produces nested max-width containers and doubled padding. The fix must include removing the redundant wrapper classes from `ConnectedServicesContent` to match the sibling component contract.
2. **Stale breadcrumb must be removed.** `ConnectedServicesContent` renders a `Link href="/dashboard/settings">Settings /</Link>` breadcrumb that was designed for pre-sidebar navigation. Sibling components (`BillingSection`, `TeamSettingsContent`, `SettingsContent`) do not render a breadcrumb — the sidebar is the navigation. Leaving it in place produces a visually awkward "Settings /" link inside a sidebar-framed layout that already shows Settings nav.
3. **Contract between shell and content components is implicit.** There is no typed interface saying "content components must not set their own max-width or page padding." This is a convention risk; the deepened plan calls it out so future Settings subpages don't repeat the same layout error that caused this bug in the first place.
4. **Test strategy sharpened.** Visual regression (screenshot diff) is the only honest test for a layout bug. Unit tests would either trivially pass (element exists) or fail to express the actual regression (wrong padding/width).
5. **Scope still trivial but now has 2 edits, not 1.** One file edit (page.tsx) plus one file edit (connected-services-content.tsx). Still a ~15 line diff total.

### New Considerations Discovered

- The `ConnectedServicesContent` component is a Client Component with its own internal state (connection, rotation, removal flows). Those flows are orthogonal to this fix — do not touch them.
- `SettingsShell` has a `pb-20` on mobile to make room for the bottom tab bar. If `ConnectedServicesContent` keeps its own `py-10`, mobile content will be cut off by the tab bar. Removing the internal padding lets the shell's mobile-aware padding work.
- The issue title mentions "Team Settings side bar" but the sidebar is labeled "Settings" in the UI. This is cosmetic; the screenshots confirm the user means the shared Settings sidebar.

## Summary

The Settings > Integrations page (`/dashboard/settings/services`) renders without the shared Settings sidebar navigation. All other Settings subpages (General, Team, Billing) wrap their content in `<SettingsShell>`, which provides the desktop sidebar and mobile tab bar. The Integrations page does not, leaving users stranded without in-section navigation once they land on it.

This is a trivial, single-file fix: wrap the page's returned content in `<SettingsShell>`.

## Root Cause

**File:** `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx`

Current implementation returns `<ConnectedServicesContent ... />` directly, without wrapping in `<SettingsShell>`. Compare to sibling pages:

| Page | Path | Wraps in `<SettingsShell>`? |
| --- | --- | --- |
| General | `settings/page.tsx` | Yes |
| Team | `settings/team/page.tsx` | Yes |
| **Integrations** | `settings/services/page.tsx` | **No (bug)** |
| Billing | `settings/billing/page.tsx` | Yes |

`SettingsShell` already defines the Integrations tab (`{ href: "/dashboard/settings/services", label: "Integrations" }` at `apps/web-platform/components/settings/settings-shell.tsx:9`), so no navigation registration work is needed — only the page needs to adopt the shell.

### Likely origin

Commit `745bda4f feat(settings): move billing to dedicated page and remove connected services (#2174)` restructured Settings. The services/Integrations page appears to have been preserved from the earlier architecture without being migrated to the new shell pattern.

### Content Component Contract (discovered during deepen)

After inspecting all four Settings content components, the implicit contract is:

| Component | Has own `mx-auto max-w-2xl`? | Has own `px-4 py-10`? | Has breadcrumb? |
| --- | --- | --- | --- |
| `SettingsContent` (General) | No | No | No |
| `TeamSettingsContent` | No | No | No |
| `BillingSection` | No | No | No |
| **`ConnectedServicesContent`** | **Yes** (line 232) | **Yes** (line 232) | **Yes** (lines 234-242) |

`SettingsShell` provides the outer `<div className="flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10"><div className="mx-auto max-w-2xl">{children}</div></div>` at `settings-shell.tsx:71-72`. Content components expect the shell to apply page padding and max-width. `ConnectedServicesContent` was written when there was no shell; its root wrapper is now duplicative and will cause:

- Double `max-w-2xl` (harmless but redundant nesting)
- Doubled padding (visible regression: content starts further right/down than siblings)
- Lost mobile bottom-bar clearance (shell's `pb-20` on mobile is overridden by content's `py-10`, causing tab bar to cover last provider card)
- Stale breadcrumb pointing to `/dashboard/settings` next to the sidebar that already contains that link

## Fix

Two file edits:

### Edit 1: Wrap page in `SettingsShell`

**File:** `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx`

```tsx
 import { redirect } from "next/navigation";
 import { createClient } from "@/lib/supabase/server";
 import { ConnectedServicesContent } from "@/components/settings/connected-services-content";
+import { SettingsShell } from "@/components/settings/settings-shell";

 export default async function ConnectedServicesPage() {
   const supabase = await createClient();
   const {
     data: { user },
   } = await supabase.auth.getUser();

   if (!user) {
     redirect("/login");
   }

   const { data } = await supabase
     .from("api_keys")
     .select("provider, is_valid, validated_at, updated_at")
     .eq("user_id", user.id);

-  return <ConnectedServicesContent initialServices={data ?? []} />;
+  return (
+    <SettingsShell>
+      <ConnectedServicesContent initialServices={data ?? []} />
+    </SettingsShell>
+  );
 }
```

### Edit 2: Remove redundant layout wrapper and stale breadcrumb from `ConnectedServicesContent`

**File:** `apps/web-platform/components/settings/connected-services-content.tsx` (around lines 231-248)

Current:

```tsx
  return (
    <div className="mx-auto max-w-2xl space-y-10 px-4 py-10">
      <div>
        <div className="mb-1 flex items-center gap-2">
          <Link
            href="/dashboard/settings"
            className="text-sm text-neutral-500 transition-colors hover:text-neutral-300"
          >
            Settings
          </Link>
          <span className="text-neutral-600">/</span>
        </div>
        <h1 className="text-2xl font-bold text-white">Connected Services</h1>
        <p className="mt-1 text-sm text-neutral-400">
          Manage API tokens for third-party services. Tokens are encrypted with
          AES-256-GCM and automatically available to your agent sessions.
        </p>
      </div>
```

Target (matches sibling pattern in `SettingsContent`, `BillingSection`, `TeamSettingsContent`):

```tsx
  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-2xl font-bold text-white">Connected Services</h1>
        <p className="mt-1 text-sm text-neutral-400">
          Manage API tokens for third-party services. Tokens are encrypted with
          AES-256-GCM and automatically available to your agent sessions.
        </p>
      </div>
```

Changes:

1. Root `<div>`: `mx-auto max-w-2xl space-y-10 px-4 py-10` → `space-y-10` (shell provides the rest).
2. Remove the entire breadcrumb block (`<div className="mb-1 flex ...">...<span>/</span></div>`) — the shell sidebar is the navigation.
3. Remove the now-unused `import Link from "next/link"` **only if** no other `Link` usages remain in the file (grep to confirm before removing — there may be rotate/connect flows that link elsewhere).

### Import cleanup verification

After edit 2, verify whether `Link` is still used anywhere in `connected-services-content.tsx`. If it is not, remove the `import Link from "next/link"` statement to keep the file clean.

## Acceptance Criteria

- [ ] Navigating to `/dashboard/settings/services` renders the Settings sidebar on desktop (md+ breakpoint).
- [ ] The "Integrations" tab in the sidebar is visually marked active while on that page.
- [ ] Other Settings tabs (General, Team, Billing) remain clickable from the Integrations page and navigate correctly.
- [ ] Mobile tab bar appears at the bottom of the viewport on small screens (<md), matching Billing/Team behaviour.
- [ ] Content area max-width, horizontal padding, and vertical padding are visually identical to `/dashboard/settings/billing` (no double wrapping).
- [ ] Last provider card on mobile is not clipped by the bottom tab bar (shell's `pb-20` works because content no longer overrides it with its own `py-10`).
- [ ] The "Settings /" breadcrumb link is removed from the Connected Services header.
- [ ] Provider connect / rotate / remove flows still function (no regression in form submit, error display, list refresh).
- [ ] No console errors or hydration warnings.
- [ ] TypeScript compile passes (`tsc --noEmit` in `apps/web-platform/`).

## Test Scenarios

1. **Desktop navigation** — Log in, visit `/dashboard/settings/billing`, click "Integrations" in the sidebar. Expected: sidebar remains visible; Integrations tab highlighted; content area shows services list.
2. **Direct URL** — Navigate directly to `/dashboard/settings/services`. Expected: sidebar renders identically to other Settings subpages.
3. **Mobile breakpoint** — Resize viewport <768px. Expected: sidebar hides, bottom tab bar appears with Integrations tab selected when on this page.
4. **Active state** — Verify `pathname.startsWith("/dashboard/settings/services")` branch in `SettingsShell` correctly highlights the Integrations tab (no other tab highlighted simultaneously).
5. **Layout parity** — Side-by-side screenshot comparison of `/dashboard/settings/billing` and `/dashboard/settings/services` in the same viewport width. Expected: content starts at the same horizontal offset and top offset; max-width is identical; no nested/doubled spacing.
6. **Mobile bottom-bar clearance** — On mobile viewport, scroll to the last provider card. Expected: the card is fully visible above the bottom tab bar.
7. **Breadcrumb removed** — Verify no "Settings /" breadcrumb link is rendered above the "Connected Services" heading.
8. **Functional regression** — Click Connect on an unconfigured provider, enter a token, submit. Expected: flow works identically to before (error display on bad token, success on good token, list refreshes).
9. **Regression check on siblings** — Verify General, Team, Billing pages still render unchanged (no accidental shared-component modification).

## Test Strategy

`package.json` test runner: run `npm test` (repo convention) or per-package test command from `apps/web-platform/package.json`.

Existing tests:

- `apps/web-platform/test/billing-section.test.tsx` — tests BillingSection content only, not layout/shell wrapping.
- No existing test asserts that each Settings subpage wraps in `<SettingsShell>`.

Options for automated coverage:

- **Option A (minimal):** Ship the fix with manual QA only. Pre-existing Settings pages have no shell-wrapping unit tests, so adding one only for Integrations would be inconsistent.
- **Option B (preferred if trivial):** Add a focused Playwright E2E check in the existing QA flow — not a new test framework, uses existing `soleur:qa` skill — that navigates to `/dashboard/settings/services` and asserts the sidebar `<nav>` with "Settings" heading is visible. Captures screenshot for PR.

Recommendation: **Option B** via the existing `soleur:qa` skill during the QA gate — no new test file, no new framework, just a screenshot-based verification step.

## Files to Modify

- `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx` — add `SettingsShell` import, wrap return value.
- `apps/web-platform/components/settings/connected-services-content.tsx` — remove root wrapper's `mx-auto max-w-2xl px-4 py-10` classes (keep `space-y-10`), remove the breadcrumb block, conditionally remove the unused `Link` import.

## Files to Create

None.

## Risks & Sharp Edges

- **Double-wrap layout regression (CONFIRMED, not hypothetical):** `ConnectedServicesContent` currently wraps its content in `<div className="mx-auto max-w-2xl space-y-10 px-4 py-10">`. `SettingsShell` applies the same `mx-auto max-w-2xl` plus `px-4 py-10 pb-20 md:px-10 md:pb-10` around children. Wrapping WITHOUT removing the redundant classes will cause nested max-width containers and doubled padding — a visible regression. **Mitigation:** Edit 2 above removes the redundant wrapper classes from the content component.
- **Mobile bottom tab bar clipping:** The shell's `pb-20` on mobile leaves space for the fixed bottom tab bar. `ConnectedServicesContent`'s internal `py-10` overrides this, so the last provider card would be partially hidden behind the tab bar on mobile. **Mitigation:** Edit 2 removes the internal vertical padding; shell's `pb-20` then works.
- **Breadcrumb redundancy:** The existing `Settings /` breadcrumb inside `ConnectedServicesContent` is visually awkward once the sidebar provides the same navigation. Sibling pages (Billing, Team, General) do not render a breadcrumb. **Mitigation:** Edit 2 removes the breadcrumb.
- **Dangling `Link` import:** After removing the breadcrumb, verify no other `Link` usages remain in `connected-services-content.tsx` before removing the import (a lint warning will otherwise surface and block the commit via lefthook).
- **`"use client"` boundary:** The page component is a Server Component (async, reads Supabase). `SettingsShell` is a Client Component (`"use client"` directive, uses `usePathname`). The existing Billing page follows the identical pattern (Server page → `<SettingsShell>` → Client Component child) successfully, so this is validated.
- **No change to the underlying connection flows:** Provider connect / rotate / remove handlers, API routes (`/api/services`), and encrypted token storage are untouched. This is purely a layout fix.
- **Content component contract is implicit:** Future Settings subpages will repeat this bug unless the contract is made explicit. **Optional follow-up:** add a JSDoc comment on `SettingsShell` and on each sibling content component stating "Do not apply `mx-auto max-w-2xl` or page-level `px/py` — the shell handles it." Out of scope for this PR but recommended as a trivial tech-debt follow-up.
- **No new dependencies, no migrations, no API changes, no copy changes.**

## Domain Review

**Domains relevant:** Product (advisory tier — modifies an existing user-facing page without adding new UI surfaces).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (not required — pattern already established in Billing/Team/General; implementation copies the existing shell wrapper with zero new design decisions), copywriter (no copy changes)
**Pencil available:** N/A

#### Findings

This is a pure bug fix restoring consistency with three sibling pages. No new user-facing surface, no new copy, no new flow — just adopting an existing layout shell. The UX decision was made when the shell was introduced; this PR closes a gap where one page was missed.

## Acceptance Criteria (repeat for task tracking)

See section above.

## Out of Scope

- Redesigning the Settings sidebar or tab order.
- Adding new Settings subpages.
- Restyling `ConnectedServicesContent`.
- Adding unit-test coverage retroactively for the other three Settings pages (would be a separate tech-debt issue if desired).

## Alternative Approaches Considered

| Approach | Pros | Cons | Chosen? |
| --- | --- | --- | --- |
| Wrap page in `<SettingsShell>` (chosen) | One-line fix; matches existing pattern exactly | None | Yes |
| Move `<SettingsShell>` into a `settings/layout.tsx` route-group layout so all children inherit it | DRY — single wrap covers all Settings subpages; prevents this bug recurring | Larger refactor; requires removing explicit `<SettingsShell>` from Billing, Team, General; risk of layout regression on all four pages | No — out of scope for this bug fix; could be a follow-up refactor |
| Add layout-wrapping unit tests for all four Settings pages | Prevents regression | New test patterns; larger PR | No — file as tech debt if desired |

### Deferral

The "lift `<SettingsShell>` into a shared `settings/layout.tsx`" refactor is a legitimate follow-up. If the team wants it tracked, a separate issue should be created with:

- What: move sidebar into shared layout file
- Why: DRY, prevents future missed-wrap bugs
- Re-evaluation criteria: whenever a 5th Settings subpage is added or the pattern is revisited
- Milestone: Post-MVP / Later

Not creating that issue now unless requested — it's not a regression, just a hypothetical future cleanup.

## Implementation Checklist

- [x] Read both target files to verify current state has not shifted since plan writing.
- [x] **Edit 1** — `settings/services/page.tsx`: add `SettingsShell` import, wrap `<ConnectedServicesContent ... />` in `<SettingsShell>`.
- [x] **Edit 2** — `connected-services-content.tsx`: change root `<div className="mx-auto max-w-2xl space-y-10 px-4 py-10">` to `<div className="space-y-10">`; remove the breadcrumb block (`<div className="mb-1 flex items-center gap-2">...</div>`); grep for remaining `Link` usages in the file; if none, remove `import Link from "next/link"`.
- [x] Run typecheck: `cd apps/web-platform && npx tsc --noEmit` (or project script).
- [ ] Run lint: project lint script on `apps/web-platform/`.
- [ ] Run tests for `apps/web-platform/`. **Worktree note:** per AGENTS.md, run vitest via `node node_modules/vitest/vitest.mjs run` not `npx vitest`.
- [ ] Manual QA via `soleur:qa` skill or local dev server: load `/dashboard/settings/services`, verify sidebar + active tab + no breadcrumb + no double-padding; resize to mobile; scroll to last provider card.
- [ ] Capture before/after screenshots (desktop + mobile) for PR body.
- [ ] `soleur:compound` to capture any learnings about the implicit shell/content-component contract.
- [ ] Commit with message `fix(settings): wrap Integrations page in SettingsShell (#2227)`.
- [ ] Open PR with `Closes #2227` in body, attach before/after screenshots.
- [ ] Apply semver label `patch`.

## References

- Issue: <https://github.com/jikig-ai/soleur/issues/2227>
- Related commit: `745bda4f feat(settings): move billing to dedicated page and remove connected services (#2174)`
- Pattern source: `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx`
- Shell component: `apps/web-platform/components/settings/settings-shell.tsx`
