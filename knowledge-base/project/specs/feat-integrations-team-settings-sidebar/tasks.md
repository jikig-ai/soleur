# Tasks: fix Integrations Settings sidebar (#2227)

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx` to confirm current state.
- [ ] 1.2 Read `apps/web-platform/components/settings/connected-services-content.tsx` to confirm current root wrapper and breadcrumb positions.
- [ ] 1.3 Re-read `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` for reference pattern.
- [ ] 1.4 Re-read `apps/web-platform/components/settings/settings-shell.tsx` to confirm the shell's padding / max-width contract (lines 71-72).

## Phase 2: Implementation

### Edit 1 — wrap page in shell

- [ ] 2.1 Add `import { SettingsShell } from "@/components/settings/settings-shell";` to `settings/services/page.tsx`.
- [ ] 2.2 Wrap the returned `<ConnectedServicesContent ... />` element in `<SettingsShell>...</SettingsShell>`.

### Edit 2 — align content component with sibling contract

- [ ] 2.3 In `connected-services-content.tsx`, change the root `<div className="mx-auto max-w-2xl space-y-10 px-4 py-10">` to `<div className="space-y-10">` (keep only `space-y-10`).
- [ ] 2.4 Remove the breadcrumb block: the `<div className="mb-1 flex items-center gap-2">...</div>` wrapping the `Link` to `/dashboard/settings` and the `<span>/</span>` separator.
- [ ] 2.5 Grep the file for remaining `Link` usages. If none, remove `import Link from "next/link"`.

## Phase 3: Verification

- [ ] 3.1 Run typecheck: `cd apps/web-platform && npx tsc --noEmit`.
- [ ] 3.2 Run project lint.
- [ ] 3.3 Run tests for `apps/web-platform/` via `node node_modules/vitest/vitest.mjs run` (worktree-safe, per AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`).
- [ ] 3.4 Start dev server; navigate to `/dashboard/settings/services`.
  - [ ] 3.4.1 Desktop: sidebar visible, Integrations tab active, content offset matches Billing page.
  - [ ] 3.4.2 No "Settings /" breadcrumb above the Connected Services heading.
  - [ ] 3.4.3 Click between Settings tabs — all navigate correctly with active-state highlighting.
- [ ] 3.5 Resize to mobile (<768px): bottom tab bar appears; sidebar hidden; last provider card fully visible above the tab bar.
- [ ] 3.6 Smoke-test Connect / Rotate / Remove flow on a provider card — no functional regression.
- [ ] 3.7 Capture before/after screenshots (desktop + mobile) for PR body.

## Phase 4: Ship

- [ ] 4.1 `soleur:compound` to capture the shell/content contract learning (if not already documented).
- [ ] 4.2 Commit: `fix(settings): wrap Integrations page in SettingsShell (#2227)`.
- [ ] 4.3 Open PR with `Closes #2227` in body; attach screenshots.
- [ ] 4.4 Apply `patch` semver label.
- [ ] 4.5 Monitor CI → merge → verify deploy.
