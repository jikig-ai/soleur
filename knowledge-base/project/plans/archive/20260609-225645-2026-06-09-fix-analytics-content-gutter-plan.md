---
title: "fix: Analytics page content gutter (left padding between sidebar and main content)"
type: fix
date: 2026-06-09
branch: feat-one-shot-analytics-nav-content-gutter
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: none
---

# 🐛 fix: Analytics page content gutter between sidebar and main content

## Enhancement Summary

**Deepened on:** 2026-06-09
**Sections enhanced:** Overview (root cause + fix direction verified live), Observability (5-field schema), Research Insights added.

### Key Improvements

1. **Root cause confirmed against live code** — layout `<main>`
   (`layout.tsx:517-519`) className is exactly
   `flex-1 overflow-y-auto bg-soleur-bg-base` (no horizontal padding);
   `globals.css` has no `main` rule at all. The gutter is page-owned by
   convention, and the Analytics content roots are bare `space-y-6` divs.
2. **Fix scoped to the page, not the shared layout** — verified that editing
   `<main>` would double-pad `audit` (`px-6 py-8`), `settings`
   (`px-4 py-10 md:px-10`), and break the KB/chat full-bleed drilled layouts.
3. **Both-toggle-states satisfied by one change** — collapse toggles only the
   `<aside>` width (`md:w-14`/`md:w-56`, `layout.tsx:314`); `<main>` + children
   are identical across states, so a single content-wrapper fix covers both
   screenshots (no PR #2494/#2504-style follow-up needed).

### New Considerations Discovered

- The metrics table is 8 columns and wider than `audit`'s `max-w-4xl`. The plan
  widens the clamp to `max-w-6xl` (or drops `max-w` entirely if cramped) so the
  fix introduces a gutter without narrowing the table vs today.
- All **four** render surfaces (loaded, empty-state, error-state, loading
  skeleton) must share the identical wrapper string, or the gutter flickers
  across render phases — captured as AC2/AC3/AC4.

## Overview

On `/dashboard/admin/analytics`, the main content (the **Analytics** heading,
the **P4 validation metrics** subtitle, the **Activation funnel** card, and the
user metrics table) renders flush against the right edge of the left nav
sidebar — there is no left gutter. This is visible in **both** the
expanded-sidebar and the collapsed-sidebar states.

### Root cause (verified)

The dashboard layout's `<main>` element provides **no horizontal padding**:

```tsx
// apps/web-platform/app/(dashboard)/layout.tsx:517-520
<main
  className="flex-1 overflow-y-auto bg-soleur-bg-base"
  inert={drawerOpen || undefined}
>
  {/* payment banners … */}
  {children}
</main>
```

In this codebase the convention is **page-supplies-its-own-padding** — the
layout `<main>` is an intentionally bare scroll container, and each page wraps
its own content with a padded container. Verified sibling precedents:

- `app/(dashboard)/dashboard/audit/page.tsx:38` →
  `<main className="mx-auto max-w-4xl px-6 py-8">`
- `components/settings/settings-shell.tsx:138-139` →
  `<div className="relative flex-1 px-4 py-10 md:px-10"><div className="mx-auto max-w-2xl">…`

`apps/web-platform/app/globals.css` contains **no** `main`/gutter padding rule
(only `safe-top`/`safe-bottom` safe-area insets at lines 174/177), confirming
the gutter is not provided globally.

The Analytics surface is the **outlier**: its content roots are bare
`<div className="space-y-6">` wrappers with **no horizontal padding**, so the
content paints against the sidebar edge. This is why the bug appears only on
this page.

### Fix direction (confirmed)

Add the page-level horizontal gutter **at the Analytics content wrappers**, not
in the shared layout `<main>`. Rationale:

- Changing the shared `<main>` would double-pad `audit`, `settings`, `kb`,
  `chat`, and the `dashboard` landing page, which already supply their own
  padding (and would break the KB/chat drilled full-bleed layouts).
- The repo convention is page-owned padding; matching it keeps the fix local
  and review-simple.

Adopt the **`audit` page's exact wrapper shape** as the convention to mirror:
`px-6 py-8` plus a centering `mx-auto max-w-*`. The Analytics table is wider
than the audit page's `max-w-4xl`; use `mx-auto max-w-6xl` (or `max-w-5xl`) so
the 8-column table is not clamped narrower than it renders today. (`max-w-6xl`
= 72rem / 1152px comfortably exceeds the current table's natural width while
still introducing the right-side breathing room a centered container gives.)

### Both toggle states are fixed by one change (no over-scope)

The sidebar collapse state changes **only the `<aside>` width** (`md:w-14`
collapsed vs `md:w-56` expanded — `layout.tsx:314`). The `<main>` is `flex-1`
and the `{children}` subtree is byte-identical across both states — there is no
collapsed-specific DOM branch in the analytics render path. Therefore a single
padding fix on the content wrapper corrects **both** the expanded and collapsed
screenshots simultaneously. Per the AGENTS.md sharp edge on toggleable-control
alignment (PR #2494/#2504), both states are explicitly accounted for here: they
share one DOM subtree, so one fix covers both — no second follow-up needed.

### Research Insights

**Best Practices (Tailwind content-gutter / centered reading column):**

- The repo's own convention is the authority here — match `audit/page.tsx:38`'s
  `mx-auto max-w-* px-6 py-8` shape rather than inventing a new spacing scale.
  Consistency across admin pages beats a bespoke value.
- `px-6` (1.5rem / 24px) is the established horizontal gutter on the comparable
  `audit` page; reuse it verbatim so the Analytics page reads as part of the
  same admin surface.
- `mx-auto max-w-6xl` centers wide content and yields a symmetric right-side
  gutter as a bonus (the bug report only asks for the left gutter, but a
  centered max-width container is the idiomatic way the codebase already does
  it, and it avoids an asymmetric "left padding only" look on ultrawide
  viewports). If the 8-column table feels clamped at `max-w-6xl`, drop the
  `max-w` and keep `px-6 py-8` — `px-6` alone fully satisfies the report.

**Edge Cases (verified):**

- **Both sidebar states:** one fix covers both because the collapse state only
  resizes the `<aside>` (`md:w-14`/`md:w-56`) and never branches the
  `<main>`/children DOM. Verified at `layout.tsx:314`.
- **Four render phases:** loaded (`analytics-dashboard.tsx:194`), empty
  (`:186`), error (`page.tsx:44-55`), loading skeleton (`loading.tsx:2`) — all
  four must carry the identical wrapper or the gutter flickers between phases.
- **Mobile (`< md`):** the sidebar is a drawer (`-translate-x-full` off-canvas,
  `layout.tsx:307`), so on mobile there is no persistent sidebar to gutter
  against; the `px-6` simply provides comfortable edge padding, which is
  desirable. No mobile-specific branch needed.

**Anti-pattern to avoid:**

- Do NOT add the padding to the shared layout `<main>` — it would double-pad
  every sibling dashboard page that already self-pads, and break the KB/chat
  full-bleed drilled layouts. (Verified: `audit`, `settings` self-pad;
  `<main>` is deliberately a bare scroll container.)

## User-Brand Impact

**If this lands broken, the user experiences:** the admin Analytics dashboard
content still touching the sidebar (cosmetic, no functional loss), or — if
over-padded — a too-narrow / mis-centered table. Admin-only surface
(`ADMIN_USER_IDS` gate, `page.tsx:18-22`); end users never see it.
**If this leaks, the user's data is exposed via:** N/A — this is a pure
CSS/className gutter change. It reads, persists, and transmits nothing; the data
already on the page (admin-only aggregate metrics) is unchanged.
**Brand-survival threshold:** none — admin-internal cosmetic spacing fix on an
already-provisioned page; no user-facing blast radius, no sensitive-path touch.

> Sharp edge: a plan whose `## User-Brand Impact` section is empty or contains
> only placeholder text fails `deepen-plan` Phase 4.6. This section is filled.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Loaded-state gutter.** The populated Analytics dashboard
  (`AnalyticsDashboard` with `metrics.length > 0`) wraps its content in a
  container carrying horizontal padding `px-6` and a centering `mx-auto max-w-6xl`
  (mirroring `audit/page.tsx:38`, widened to `max-w-6xl` for the table).
  Verify: `grep -nE 'mx-auto max-w-6xl|px-6' apps/web-platform/components/analytics/analytics-dashboard.tsx` returns the wrapper for the populated branch (`analytics-dashboard.tsx:193-194`).
- [ ] **AC2 — Empty-state gutter.** The `metrics.length === 0` branch
  (`analytics-dashboard.tsx:184-191`) uses the **same** padded wrapper, so the
  heading + funnel card do not sit flush when there are no users.
- [ ] **AC3 — Error-state gutter.** The query-failure branch in
  `page.tsx:44-55` (`Failed to load analytics data…`) is wrapped in the same
  padded container so the error message + Retry link are not flush against the
  sidebar.
- [ ] **AC4 — Loading-skeleton gutter.** `loading.tsx:2` wraps its skeleton in
  the same padded container so the gutter does **not** pop in/out across the
  loading → loaded → error transitions (the four surfaces stay visually
  consistent during render).
- [ ] **AC5 — No layout regression elsewhere.** `app/(dashboard)/layout.tsx`
  `<main>` className is **unchanged** (`flex-1 overflow-y-auto bg-soleur-bg-base`).
  Verify: `git diff app/(dashboard)/layout.tsx` is empty. (Confirms the fix did
  not double-pad sibling pages.)
- [ ] **AC6 — Typecheck passes.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] **AC7 — Visual confirmation (both states).** Playwright screenshot of
  `/dashboard/admin/analytics` in expanded-sidebar AND collapsed-sidebar states
  shows a visible left gutter between the sidebar edge and the Analytics
  heading/table in both. (See Test Scenarios.)

## Files to Edit

- `apps/web-platform/components/analytics/analytics-dashboard.tsx` — wrap **both**
  return branches (empty-state root `<div className="space-y-6">` at line 186 and
  populated root `<div className="space-y-6">` at line 194) in the padded
  container `mx-auto max-w-6xl px-6 py-8`. Two options, pick the simpler at
  /work time:
  - (a) replace each bare `space-y-6` root with
    `<div className="mx-auto max-w-6xl px-6 py-8 space-y-6">`, or
  - (b) introduce a single wrapper element around the existing `space-y-6` div.
    Prefer (a) — fewer nodes, matches `audit`'s single-element wrapper.
- `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx` — wrap
  the error-state return (lines 44-55) so the failure message inherits the same
  gutter. Use the same `mx-auto max-w-6xl px-6 py-8` (or keep the existing
  `min-h-[400px]` centering but add `px-6`); the populated/error states should
  both have a left gutter.
- `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/loading.tsx` —
  wrap the skeleton root (`<div className="space-y-6">` at line 2) with the same
  `mx-auto max-w-6xl px-6 py-8` so the skeleton and the real content occupy the
  same box (no gutter flicker on first paint).

## Files to Create

None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open
scope-out referencing `analytics-dashboard` or `admin/analytics`.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (direct one-shot → plan path). All premises
were verified against the live worktree:

| Claim | Reality | Plan response |
| --- | --- | --- |
| "Analytics page content sits flush against the sidebar" | Confirmed — content roots are bare `space-y-6` divs; layout `<main>` has no horizontal padding; `globals.css` has no gutter rule | Add page-owned gutter at the content wrappers |
| "Both expanded and collapsed states affected" | Confirmed — collapse changes only `<aside>` width; `<main>`+children DOM is identical across states | One wrapper fix covers both states; no second follow-up |
| Convention = layout provides the gutter | False — convention is page-owned padding (`audit` `px-6 py-8`, `settings` `px-4 py-10 md:px-10`) | Fix at the page/component, NOT the shared `<main>` |

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — modifies an existing admin page's spacing; adds
no new interactive surface, no new component file, no new page/flow. The
mechanical UI-surface override does not escalate to BLOCKING (no NEW
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` file is
created; existing files are edited only).
**Pencil available:** N/A — no new UI surface; an existing `.pen`
(`knowledge-base/product/design/analytics/activation-funnel.pen`) and a
`dashboard-nav/sidebar-float-collapse-toggle.pen` already cover this surface's
design intent. No wireframe production required for a CSS-gutter spacing fix.

#### Findings

Cosmetic spacing alignment on an admin-only page. No product-strategy, brand, or
flow implications. Auto-accepted per pipeline ADVISORY path.

## Observability

Per plan Phase 2.9, this change touches no `apps/*/server/`, `apps/*/src/`, or
`apps/*/infra/` surface (all three edits are client-rendered JSX under
`apps/web-platform/app/(dashboard)/**` and `components/analytics/**`), so no NEW
observability surface is introduced — the data flow, the admin gate, and the
existing error handling are unchanged. The schema is filled against the
existing surface so the discoverability test is non-SSH and operator-runnable:

```yaml
liveness_signal:
  what: "Next.js page render of /dashboard/admin/analytics (server component returns AnalyticsDashboard); production health via the existing Docker HEALTHCHECK on the web-platform container"
  cadence: "per request (on each admin page load)"
  alert_target: "Sentry web-platform issue (client + server runtime errors); container health surfaces via the existing deploy webhook at deploy.soleur.ai/hooks/deploy-status"
  configured_in: "apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx (route); container HEALTHCHECK in apps/web-platform/Dockerfile"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (existing project-wide instrumentation); plus console.error in page.tsx:40-43 on query failure"
  fail_loud: "On data-load failure the page renders the visible 'Failed to load analytics data. Please try again.' card with a Retry link (page.tsx:44-55) — operator sees it directly. A padding regression is visually self-evident on the page; no silent failure mode is introduced by Tailwind utility classes."

failure_modes:
  - mode: "Wrapper className typo / invalid Tailwind utility (e.g. mistyped max-w token) silently drops the gutter"
    detection: "tsc --noEmit (AC6) does not catch invalid Tailwind strings, so the Playwright visual screenshot in AC7 is the detection — gutter absent/wrong in either sidebar state fails the check"
    alert_route: "PR CI (typecheck) + the AC7 visual screenshot at review/QA time; no production alert needed (admin-only cosmetic surface)"
  - mode: "Gutter applied to only some of the four render surfaces (loaded/empty/error/loading) → gutter flickers between phases"
    detection: "AC2/AC3/AC4 grep assertions confirm the identical wrapper string on all four surfaces"
    alert_route: "PR review (AC check-off)"

logs:
  where: "Browser console (client errors) + Sentry web-platform project; server-side query errors via console.error in page.tsx → container stdout (docker logs)"
  retention: "Sentry per project retention (existing); container stdout per existing Docker log driver — unchanged by this PR"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/tsc --noEmit && grep -rEc 'mx-auto max-w-6xl|px-6' apps/web-platform/components/analytics/analytics-dashboard.tsx"
  expected_output: "tsc exits 0 with no output; grep returns a non-zero count confirming the gutter wrapper is present on the analytics dashboard. Visual confirmation via the AC7 Playwright screenshot (expanded + collapsed sidebar)."
```

## Test Scenarios

- **Manual / Playwright visual (AC7):**
  1. Navigate to `/dashboard/admin/analytics` (admin session).
  2. Screenshot with sidebar **expanded** — assert a visible gap between the
     sidebar right border and the "Analytics" heading / table left edge.
  3. Toggle the sidebar **collapsed** (⌘B or the floated toggle), screenshot —
     assert the same visible gap persists (collapsed `<aside>` is narrower, but
     the content gutter is unchanged because it is page-owned).
  4. Optionally force the empty-state (no users) and error-state to confirm
     those branches also carry the gutter.
- **Typecheck (AC6):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- No new unit test is required — this is a Tailwind className change with no
  branching logic. (If the repo's frontend convention wants a snapshot/class
  assertion, a lightweight test asserting the wrapper className exists on the
  populated branch may be added under `apps/web-platform/test/components/` to
  match `apps/web-platform/vitest.config.ts` `include:` globs — confirm the glob
  before placing the file; do NOT co-locate a `*.test.tsx` next to the component,
  which vitest would skip.)

## Non-Goals / Out of Scope

- Do **not** change the shared `app/(dashboard)/layout.tsx` `<main>` padding —
  that would double-pad every other dashboard page (AC5).
- Do **not** restyle the Activation funnel card, the metrics table, or any
  colors/typography — gutter spacing only.
- Do **not** introduce a vertical-rhythm or responsive-breakpoint overhaul; the
  fix is the horizontal gutter the bug report describes (`px-6`) plus the
  `audit`-matching `py-8` for top/bottom breathing room and `mx-auto max-w-*`
  centering consistency.

## Implementation Notes

- The exact `max-w-*` clamp (`max-w-5xl` vs `max-w-6xl`) is a judgment call at
  /work time — pick the smallest clamp that does **not** make the 8-column
  table narrower than it renders today. `max-w-6xl` (1152px) is the safe
  default; verify visually via AC7. If the table feels cramped at `max-w-6xl`,
  drop the `max-w` entirely and keep `px-6 py-8` (a pure gutter with no
  centering clamp) — the `px-6` alone satisfies the bug report.
- Keep all three loading/loaded/error surfaces on the **identical** wrapper
  string so they don't visually jump between render phases (AC4).
