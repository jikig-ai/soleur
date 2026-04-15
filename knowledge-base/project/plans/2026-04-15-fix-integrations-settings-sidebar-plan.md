# fix: Integrations page missing Team Settings sidebar (#2227)

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

## Fix

Modify `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx`:

1. Import `SettingsShell` from `@/components/settings/settings-shell`.
2. Wrap the returned `<ConnectedServicesContent ... />` in `<SettingsShell>...</SettingsShell>`.

### Pseudo-diff

```tsx
// apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx
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

## Acceptance Criteria

- [ ] Navigating to `/dashboard/settings/services` renders the Settings sidebar on desktop (md+ breakpoint).
- [ ] The "Integrations" tab in the sidebar is visually marked active while on that page.
- [ ] Other Settings tabs (General, Team, Billing) remain clickable from the Integrations page and navigate correctly.
- [ ] Mobile tab bar appears at the bottom of the viewport on small screens (<md), matching Billing/Team behaviour.
- [ ] `ConnectedServicesContent` renders inside the shell's content area without layout regressions (spacing, max-width, padding identical to Billing page).
- [ ] No console errors or hydration warnings.

## Test Scenarios

1. **Desktop navigation** — Log in, visit `/dashboard/settings/billing`, click "Integrations" in the sidebar. Expected: sidebar remains visible; Integrations tab highlighted; content area shows services list.
2. **Direct URL** — Navigate directly to `/dashboard/settings/services`. Expected: sidebar renders identically to other Settings subpages.
3. **Mobile breakpoint** — Resize viewport <768px. Expected: sidebar hides, bottom tab bar appears with Integrations tab selected when on this page.
4. **Active state** — Verify `pathname.startsWith("/dashboard/settings/services")` branch in `SettingsShell` correctly highlights the Integrations tab (no other tab highlighted simultaneously).
5. **Regression check** — Verify General, Team, Billing pages still render unchanged.

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

- `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx` — add import, wrap return value.

## Files to Create

None.

## Risks & Sharp Edges

- **Double-wrapping risk:** `ConnectedServicesContent` currently renders its own top-level content without any shell. Verified by reading `apps/web-platform/components/settings/connected-services-content.tsx` — it does not import or render `SettingsShell` internally, so wrapping at the page level is safe.
- **Layout regressions:** `SettingsShell` wraps children in `<div className="mx-auto max-w-2xl">`. If `ConnectedServicesContent` renders anything wider than `max-w-2xl`, it will be constrained. Compare to Billing, Team, General: all use the same constraint successfully; Integrations content is a similar list-based layout, so no regression expected. Verify visually during QA.
- **`"use client"` boundary:** The page component is a Server Component (async, reads Supabase). `SettingsShell` is a Client Component (`"use client"` directive, uses `usePathname`). The existing Billing page follows the identical pattern (Server page → `<SettingsShell>` → content) with no issues, so this is a validated pattern.
- **No new dependencies, no migrations, no API changes.**

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

- [ ] Read `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx` (verify current state has not shifted since plan writing).
- [ ] Add `SettingsShell` import.
- [ ] Wrap `<ConnectedServicesContent ... />` return in `<SettingsShell>`.
- [ ] Run `npm run lint` (or project lint script) in `apps/web-platform/`.
- [ ] Run `npm test` for `apps/web-platform/` (no new tests, just regression check on existing suite).
- [ ] Manual QA (or `soleur:qa`): load `/dashboard/settings/services`, verify sidebar present, verify "Integrations" tab highlighted, verify mobile breakpoint.
- [ ] Capture before/after screenshots for PR body.
- [ ] Commit with message `fix(settings): wrap Integrations page in SettingsShell (#2227)`.
- [ ] Open PR with `Closes #2227` in body.
- [ ] Apply semver label `patch` (bug fix, no API change).

## References

- Issue: <https://github.com/jikig-ai/soleur/issues/2227>
- Related commit: `745bda4f feat(settings): move billing to dedicated page and remove connected services (#2174)`
- Pattern source: `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx`
- Shell component: `apps/web-platform/components/settings/settings-shell.tsx`
