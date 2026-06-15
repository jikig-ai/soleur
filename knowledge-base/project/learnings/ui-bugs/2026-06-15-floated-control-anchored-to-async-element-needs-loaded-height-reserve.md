# Learning: a floated control centered on an ASYNC element must reserve that element's LOADED height

## Problem

The dashboard sidebar's floated collapse toggle (`app/(dashboard)/layout.tsx`,
`absolute right-3 top-10`, `h-6`, `z-10`) visually overlapped the "Dashboard" nav
link — but only while the page was not yet fully loaded, and most reliably right
after a collapse → re-expand. The toggle painted on top of the first nav item.

It was NOT a z-index bug (`z-10` toggle < `md:z-30` aside is correct), and it was
NOT reproducible once the page settled — which is exactly why it read as "happens
when the page isn't loaded."

## Root cause

The toggle's expanded `top-10` (40px) is calibrated to vertically center the `h-6`
button on the workspace pill (PR #5015 — pill center ≈ 52px from the aside top when
the band is fully rendered). The toggle is `absolute`, OUT of the flex flow, so the
in-flow band below it is solely responsible for occupying enough vertical space that
the nav (`pt-3`) never rises into the toggle's footprint.

On the top-level route (`drill === null`) the band's ONLY content is the workspace
pill rendered by `OrgSwitcherContainer`, which **returns `null` until
`/api/workspace/list-memberships` resolves** (`org-switcher-container.tsx:214`). The
band had no reserved min-height, so while that fetch was in flight the expanded band
collapsed to ~8px and the nav slid up under the floated toggle. Once memberships
resolved, the ~64px pill rendered, the band grew, and the toggle landed back on the
pill center — so the overlap was transient and load-timing-dependent.

## Solution

Reserve the toggle's full vertical footprint on the band's pill container so it
cannot collapse below the toggle during the in-flight state:

```tsx
// components/dashboard/workspace-context-band.tsx (drill === null only)
<div className={`flex items-center gap-2 px-3 pt-2 md:pr-10${
  drill === null ? " md:min-h-[64px]" : ""
}`}>
```

`64px` = `top-10` (40px) + `h-6` (24px) = the toggle's bottom edge from the aside
top. Because the loaded pill is itself ~64px tall, the min-height does ZERO work in
the loaded state (content already meets it) — so the #5015 centering invariant is
provably unaffected; the reserve only acts during the pre-resolve window. Scoped via
`md:` (mobile band is below the breakpoint → inert) and `drill === null` (drilled
Settings/KB/Chat bands already exceed 64px via back-link + section-title rows; the
collapsed icon-only form returns early and never reaches this div, and already
reserves `pt-16`).

## Key Insight

When an `absolute`/`fixed` control is centered on an **asynchronously-rendered**
in-flow sibling, its alignment is only correct AFTER that sibling resolves. The
sibling's null/loading state collapses the anchor and drops the floated control onto
whatever is below it. **Reserve the sibling's LOADED height as a `min-height` on its
container**, so the layout is stable across the entire load lifecycle, not just the
settled state. This is the async/load-state companion to the two prior toggle-saga
learnings:
- [[2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches]]
  (both toggle STATES)
- [[2026-06-08-absolute-control-alignment-offset-parent-vs-target-band]]
  (offset-parent vs target band geometry)

New dimension added here: both LOAD STAGES (in-flight vs resolved), not just both
render branches.

Test split (ADR-049): jsdom has no layout engine, so the className token guard
(`md:min-h-[64px]` present on top-level, absent on drilled) lives in a vitest
tripwire (RED→GREEN verified); the binding overlap proof is a real-CSS Playwright
rect-non-intersection assertion under an **in-flight (never-resolving)
`list-memberships` mock**. The mock must leave the request *pending* — `route.abort()`
drives `OrgSwitcherContainer`'s `.catch` → `setMemberships(prev ?? [])`, a *resolved*
empty state that does NOT reproduce the height-collapse.

## Session Errors

1. **Local Playwright `webServer` boot failure** — the Step 2.6 structural-UI gate
   could not execute: the Next.js dev server crashed at the instrumentation hook
   (`require is not defined in ES module scope` in compiled
   `.next/server/instrumentation.js`, with `package.json "type": "module"`).
   **Recovery:** cleared `.next` and retried once — identical failure → confirmed a
   pre-existing local toolchain/env issue (the diff touches no
   instrumentation/config/package.json file, and the crash is at boot before any
   test runs). Degraded QA to unit coverage (jsdom RED→GREEN + full web-platform
   vitest 9925/9925 + `tsc --noEmit` clean + semgrep 0 findings); CI's containerized
   e2e job is the authoritative gate for the rect-non-intersection overlap proof.
   **Prevention:** already governed by
   [[2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix]] — a
   pure-CSS-utility-class fix with `brand_survival_threshold: none` and a fully
   unit-tested className contract degrades to unit coverage rather than blocking.
   No new workflow rule warranted (local env, not a repo gap); not filed to avoid a
   speculative net-negative issue.

## Tags
category: ui-bugs
module: apps/web-platform/components/dashboard
