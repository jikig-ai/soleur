---
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-22-fix-sidebar-collapse-workspace-selector-remount-plan.md
branch: feat-one-shot-sidebar-collapse-selector-remount
brand_survival_threshold: single-user incident
---

# Tasks — fix: sidebar collapse must not remount/refetch the workspace selector

Derived from the finalized plan. The fix keeps `OrgSwitcherContainer` mounted across
the collapse/expand toggle (data-bearing → ADR-047 keep-mounted idiom) and toggles only
its presentation, so React preserves its membership fetch + switch-confirm state.

## Phase 0 — Preconditions (read/grep only, no edits)

- [ ] 0.1 Confirm `nav-single-mount.test.ts` asserts a single IMPORTER of
      `org-switcher-container` (`test/nav-single-mount.test.ts:38-48`); the fix adds no
      new importer → stays green.
- [ ] 0.2 Confirm `OrgSwitcher` has no `collapsed` prop and renders three full-width
      forms (`components/dashboard/org-switcher.tsx:22-35,71,80,110`).
- [ ] 0.3 Confirm `OrgMembershipSummary` carries `organizationName`, `workspaceId`,
      `hasLogo`, `isCurrent` (`server/org-memberships-resolver.ts:8-18`).
- [ ] 0.4 Confirm sole runtime consumer of `useActiveWorkspace` is
      `app/(dashboard)/layout.tsx:136` (comment-only mention in
      `lib/workspace-logo-events.ts`; no test imports it).
- [ ] 0.5 Read all three C4 model files
      (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
      to confirm "no C4 impact" against the external-actor / external-system /
      access-relationship enumeration in the plan.

## Phase 1 — `OrgSwitcher` gains an icon-only collapsed mode (RED → GREEN)

`apps/web-platform/components/dashboard/org-switcher.tsx`

- [ ] 1.1 RED: add tests to `test/org-switcher.test.tsx` — collapsed multi renders
      `workspace-identity-icon` with org name as `title`, NO `▾`/`Switch workspace`
      button; collapsed solo renders the same icon tile; expanded forms unchanged.
- [ ] 1.2 GREEN: add optional `collapsed?: boolean` prop (default `false`). When
      `collapsed && memberships.length >= 1`, render an icon-only `WorkspaceIdentityTile`
      (`size="sm"`, `variant="identity"`, name/workspaceId/hasLogo from `current`),
      wrapped in an element carrying `data-testid="workspace-identity-icon"` +
      `aria-label`/`title = current.organizationName`. Keep `length === 0 → null`.
      Expanded path byte-unchanged.

## Phase 2 — `OrgSwitcherContainer` threads `collapsed`, renders one tree

`apps/web-platform/components/dashboard/org-switcher-container.tsx`

- [ ] 2.1 Add `collapsed?: boolean` prop; pass to `<OrgSwitcher collapsed={collapsed} />`.
- [ ] 2.2 Keep `if (memberships === null) return null` (no-flash-on-first-load).
- [ ] 2.3 Gate the switch-confirm dialog render with `pending && !collapsed` (do NOT
      unmount — `pending`/`status`/`postRpcRetries` persist; dialog reappears on expand).
- [ ] 2.4 Add a `collapsed`-prop case to `test/org-switcher-container.test.tsx` (dialog
      suppressed, identity icon shown); existing switch-write-path tests stay (default
      expanded).

## Phase 3 — `WorkspaceContextBand` stops swapping subtrees

`apps/web-platform/components/dashboard/workspace-context-band.tsx`

- [ ] 3.1 Delete the `collapsed` early return (`:83-127`). Render ONE rail subtree;
      `<OrgSwitcherContainer collapsed={variant === "rail" && collapsed} />` always at
      the same tree position.
- [ ] 3.2 Remove the `activeWorkspaceName`/`activeWorkspaceId`/`activeWorkspaceHasLogo`
      props from the signature and the inline `WorkspaceIdentityTile` render.
- [ ] 3.3 Preserve collapsed-state styling (top clearance for the floated toggle; back
      chevron + section title when drilled) via className branches on `collapsed`, not
      element swaps. Keep `data-testid`, `data-variant`, `data-collapsed="true"`.
- [ ] 3.4 Rewrite the collapsed suite in `test/workspace-context-band.test.tsx`
      (`:222-264`): supply membership data via a `fetch` stub (not the
      `activeWorkspaceName` prop); assert `workspace-identity-icon` + `title` + monogram
      render when collapsed and `nav-section-title` stays absent on top-level collapsed.

## Phase 4 — Remove redundant `useActiveWorkspace` + threading

`apps/web-platform/app/(dashboard)/layout.tsx`

- [ ] 4.1 Remove `const activeWorkspace = useActiveWorkspace(collapsed)` (`:136-137`)
      and the `activeWorkspace*` props passed to the rail band (`:390-392`).
- [ ] 4.2 Remove the `useActiveWorkspace` import (`:13`).
- [ ] 4.3 Delete `apps/web-platform/hooks/use-active-workspace.ts`. Update the
      comment-only reference in `lib/workspace-logo-events.ts` if it names the hook.
      (No test imports the hook — confirmed at deepen-plan; the "delete the test" step
      is a no-op.)
- [ ] 4.4 Scope guard: if Phase 0.4 surfaced a non-layout consumer, downgrade to "stop
      the layout from calling it" and note the deferral.

## Phase 5 — Regression test + typecheck + suite

- [ ] 5.1 Add the load-bearing regression test (`test/workspace-selector-collapse-persists.test.tsx`
      or fold into the band suite): `fetch` spy on `/api/workspace/list-memberships`;
      render expanded → assert called once → `rerender({collapsed:true})` →
      `rerender({collapsed:false})` → assert `toHaveBeenCalledTimes(1)` (no refetch).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (clean).
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-context-band.test.tsx test/org-switcher.test.tsx test/org-switcher-container.test.tsx test/dashboard-sidebar-collapse.test.tsx test/nav-single-mount.test.ts`
- [ ] 5.4 Full suite per `package.json scripts.test` before ship.
- [ ] 5.5 e2e `e2e/nav-states-shell.e2e.ts` collapsed/expanded assertions green
      (optionally extend with a Playwright network-request-count assertion across a
      collapse→expand toggle).

## Phase 6 — ADR amendment (ships in THIS PR)

- [ ] 6.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`
      via `/soleur:architecture`: the "never gated on `collapsed`" invariant extends to
      the band's INTERNAL render path; an early-return that omits `OrgSwitcherContainer`
      is the same unmount bug relocated. Record that the icon-only collapsed form is a
      mode of the mounted container, and that `useActiveWorkspace` is retired.
- [ ] 6.2 C4: confirm no impact via the three-file read (Phase 0.5); cite the
      enumeration in the ADR/plan.
