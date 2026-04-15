---
module: System
date: 2026-04-15
problem_type: best_practice
component: rails_view
symptoms:
  - "One sibling page missing shared shell wrapper that others had"
  - "Implicit layout contract violated via duplicated wrapper classes causing double-wrap regression"
root_cause: missing_workflow_step
resolution_type: code_fix
severity: low
tags: [nextjs, app-router, layout, route-group, settings-shell, ui-pattern]
---

# Lift duplicated shell wrappers into route-group `layout.tsx`

## Problem

`/dashboard/settings/services` (Integrations) was the only Settings subpage
not wrapping its content in `<SettingsShell>`, leaving users without sidebar
navigation. Root cause: when `SettingsShell` was introduced (PR #1880), the
services page was never migrated — the wrapper was manually added to each
sibling (`page.tsx` for General, Team, Billing) as a convention, with nothing
enforcing it.

Fixing only `services/page.tsx` would have left the underlying class of bug
in place: any future Settings subpage could repeat the same omission.

## Solution

Promote the shared wrapper into a **Next.js route-group `layout.tsx`** so the
contract becomes structural, not conventional.

```tsx
// apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx
import { SettingsShell } from "@/components/settings/settings-shell";

export default function SettingsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <SettingsShell>{children}</SettingsShell>;
}
```

Then remove the `<SettingsShell>` import and wrapper from every
`settings/*/page.tsx`. Subpages now render their content component directly;
Next.js applies the shell automatically at the route-segment boundary.

Because `SettingsShell` declares `"use client"` (uses `usePathname`), the
`layout.tsx` itself stays a Server Component and simply renders
`{children}` inside `<SettingsShell>`. No hydration or serialization changes.

## Key Insight

**When a shared shell is duplicated across sibling pages, it belongs in a
route-group `layout.tsx`, not in each `page.tsx`.** Route-group layouts make
the "every subpage must be wrapped" contract enforced by Next.js routing
rather than by convention. The "one sibling missed the wrapper" bug class
becomes structurally impossible.

Related content contract: child content components must NOT redeclare
`mx-auto max-w-*` or page-level `px-*`/`py-*` that the shell already applies.
Doing so causes double-wrap regressions (nested max-width, doubled padding,
mobile `pb-20` overridden by local `py-10`). This is easy to miss during
code review because siblings silently coexist with their wrapper — removing
the wrapper + fixing the double-wrap is a single atomic refactor.

## Session Errors

**Dev server CSS compile failure (ERR_INVALID_URL_SCHEME on globals.css)** —
Recovery: fell back to static verification (typecheck + 9 review agents +
1354 unit tests) per QA skill's graceful degradation policy.
**Prevention:** QA skill already handles this; no workflow change needed.

**Supabase admin `generate_link` response structure** — first `jq` query
used `.properties.email_otp` but the field is at top level (`email_otp`).
Minor; one retry resolved.
**Prevention:** add reference note to QA skill's "Sharp edges for API
verification" section documenting Supabase admin API response shape.
