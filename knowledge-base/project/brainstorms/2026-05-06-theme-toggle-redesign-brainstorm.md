---
date: 2026-05-06
topic: theme-toggle-redesign
branch: feat-theme-toggle-redesign
status: brainstorm
---

# Theme Toggle — Redesign & Relocation

## What We're Building

A visual + structural redesign of the dashboard theme toggle (`apps/web-platform/components/theme/theme-toggle.tsx`). The white and dark theme tokens themselves are NOT changing — only the toggle control and its placement.

**Two-state component:**

- **Expanded sidebar** (md:w-56): a 3-segment rounded pill — Dark / Light / System — anchored at the top of the sidebar, between the Soleur brand and the navigation list.
- **Collapsed sidebar** (md:w-14): a single circular icon button that cycles Dark → Light → System on click, with a tooltip showing the next state.

A self-contained interactive HTML mock has been produced at `knowledge-base/product/design/web-platform/theme-toggle-mock.html`. No app code has been modified. The user explicitly asked to mock first to avoid useless integration.

## Why This Approach

The current toggle has two real problems:

1. **Invisibility when sidebar is collapsed.** The component is gated behind `!collapsed` in `app/(dashboard)/layout.tsx`. Users who keep the sidebar collapsed have no visible way to switch themes — discovered as the worst-case in the user-impact framing ("theme stuck / unreachable").
2. **Visual style clashes.** The current 3-segment hard-square strip with full-width borders is visually heavier than the rest of the chrome (which uses thin rules + gold accents). The pill treatment matches brand-guide aesthetic.

**Why the sidebar header (and not a topbar)?** Desktop has no header strip today — the main content sits flush against the sidebar. Building a desktop topbar just to host a pill is a 150–200 LOC structural change. The sidebar header gives us "always visible" without that refactor: ~30 LOC delta plus the collapsed-state cycle variant.

**Why preserve the 3 modes (Dark / Light / System)?** They are already shipping (#3271, #3308, #3309, #3312). Cutting back to a 2-mode binary would regress the system-follows-OS behavior users have been getting for ~2 weeks.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Placement | Sidebar header (above nav, below brand) | No new desktop topbar required; visible in both expanded + collapsed states |
| Expanded shape | Rounded pill (3 segments, icon-only) | Brand-fit; gold ring on active; replaces hard-square strip |
| Collapsed shape | Single circular cycle button | Fits 56px-wide sidebar; one click per step; tooltip surfaces next state |
| Mode set | Dark / Light / System (unchanged) | No regression of #3271's system-follows-OS behavior |
| Theme tokens | Untouched | Per user constraint: "don't change the white and dark theme" |
| Mock-first | HTML mock at `knowledge-base/product/design/web-platform/theme-toggle-mock.html` | User: "with a mock to avoid integrate uselessly" — review before code |

## Non-Goals

- No changes to `--soleur-*` token values or `theme-provider.tsx` logic.
- No new desktop topbar component. (Re-evaluate when 2nd topbar tenant arrives — search, notifs, account menu.)
- No shadcn/Radix dropdown menu component (the alternative "tuck it inside an avatar menu" path was rejected because no avatar menu exists today; building one is out of scope for a button redesign).
- No relocation to `/dashboard/settings`. The toggle stays in the chrome — settings-only would degrade discoverability.

## Open Questions

- **Icon-only vs icon+label in expanded state?** The mock is icon-only to fit the 224px sidebar. Worth A/B-checking once mounted; if discoverability suffers, the segments have ~70px each which is enough room for "Dark" / "Light" / "System" labels.
- **Cycle direction in collapsed state.** Mock cycles Dark → Light → System. Some products go Light → Dark → System (sun first). Either is defensible; following the existing `SEGMENTS` order in `theme-toggle.tsx` (Dark, Light, System) keeps it consistent.
- **Keyboard nav in collapsed state.** Pill keeps the existing arrow-key handling. The cycle button responds to Enter/Space (native) but has no arrow-key sub-menu. Simple click cycle is sufficient for a single-button affordance.

## User-Brand Impact

- **Artifact:** the dashboard theme toggle (sidebar UI control).
- **Vector:** placement / visual redesign of an existing accessible control.
- **Threshold:** worst-case is "theme stuck / unreachable on collapsed sidebar" — recoverable annoyance, not a single-user incident. The redesign actively improves on this by making the toggle visible in both states.
- **Not user-brand-critical:** no credentials, auth, data, or payment surfaces are touched.

## Domain Assessments

**Assessed:** none. Scope is a single component redesign with no new capability, no architecture change, no marketing/legal/finance/sales/support/ops surface. Per `hr-new-skills-agents-or-user-facing` the CPO+CMO mandate fires for *new* user-facing capabilities; this is iteration on an already-shipped one. Skipped to avoid spawning agents on trivial scope.

## Next Steps

1. Review the mock at `knowledge-base/product/design/web-platform/theme-toggle-mock.html` (open in browser).
2. If approved → `/soleur:plan` for implementation tasks; if changes needed → iterate on the mock first.
3. Implementation will modify only:
   - `apps/web-platform/components/theme/theme-toggle.tsx` (rewrite for dual-mode + accept `collapsed` prop)
   - `apps/web-platform/app/(dashboard)/layout.tsx` (move from footer block to sidebar header; pass `collapsed` prop; remove `!collapsed` gate)
   - `apps/web-platform/test/components/theme-toggle.test.tsx` (extend for collapsed mode)
