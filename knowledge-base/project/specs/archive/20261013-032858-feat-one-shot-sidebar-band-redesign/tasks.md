# Tasks — Sidebar band reorder + fold repo into pill

Plan: `knowledge-base/project/plans/2026-06-03-feat-sidebar-band-reorder-fold-repo-into-pill-plan.md`
Lane: cross-domain (spec lacks `lane:` — defaulted, TR2 fail-closed)

## 1. Setup / data plumbing

- [ ] 1.1 Create `apps/web-platform/hooks/use-active-repo.ts` — move the fetch/poll
      (mount + window focus, keep-last-known) from `live-repo-badge.tsx`; export the hook +
      `ActiveRepo` type. No render, no `dismissed` state.

## 2. Core implementation

- [ ] 2.1 `org-switcher.tsx`: add `repoName?: string | null` prop.
- [ ] 2.2 `org-switcher.tsx`: solo branch (`workspace-identity-static`) — replace role
      subtitle with repo subtitle (`data-testid="live-repo-badge"`, muted, `{repoName}`),
      no-repo → render nothing.
- [ ] 2.3 `org-switcher.tsx`: multi-org button — replace role subtitle with the same repo
      subtitle element. Leave the dropdown body (role already shown per row) untouched.
- [ ] 2.4 `org-switcher-container.tsx`: call `useActiveRepo()`, pass
      `repoName={repo?.repoName ?? null}` to `<OrgSwitcher />`.
- [ ] 2.5 `workspace-context-band.tsx`: reorder expanded variant — pill block ABOVE the
      "Back to menu" Link.
- [ ] 2.6 `workspace-context-band.tsx`: re-tune top padding — leading pill `pt-3`,
      following "Back to menu" `pt-2`.
- [ ] 2.7 `workspace-context-band.tsx`: remove the standalone `LiveRepoBadge` repo row;
      keep `LiveRepoBadge` mounted for the interstitial only.
- [ ] 2.8 `live-repo-badge.tsx`: consume `useActiveRepo()`; delete the repo-name render
      branch (this retires the `live-repo-badge-empty` testid — no test references it); keep
      the `fellBackToSolo` interstitial + empty guard.

## 3. Tests

- [ ] 3.1 `org-switcher.test.tsx`: add `repoName` to fixtures; assert repo subtitle on
      solo + multi-org faces; assert role NOT on face but IS in dropdown (AC3/4/5/6).
      **Pinned:** invert `:50` `expect(trigger.textContent).toContain("Owner")` →
      `.not.toContain("Owner")` (deliberate behavior inversion — old test asserted role-on-face).
- [ ] 3.2 `workspace-context-band.test.tsx`: DOM-order pill-before-back-chevron (AC1);
      spacing (AC2); relocate `live-repo-badge` assertion into pill; standalone-row-gone (AC7).
- [ ] 3.3 `org-switcher-container.test.tsx`: stub `/api/workspace/active-repo`; assert
      `repoName` reaches the pill.
- [ ] 3.4 `live-repo-badge.test.tsx`: drop repo-name assertions; keep interstitial (AC8).
- [ ] 3.5 Verify `nav-single-mount.test.ts` (AC10) + collapsed/rail-drill tests (AC9) pass.

## 4. Verify

- [ ] 4.1 `cd apps/web-platform && npx tsc --noEmit` clean (AC11).
- [ ] 4.2 `./node_modules/.bin/vitest run` the 5 affected test files green (AC11).
- [ ] 4.3 QA browser screenshot via Playwright MCP / `/soleur:qa` (AC12).

## Design

- [ ] D.1 Produce `knowledge-base/product/design/navigation/sidebar-band-reorder-fold.pen`
      wireframe (closed pill name+repo subtitle above Back-to-menu; dropdown role per-row;
      collapsed unchanged) — non-skippable per `wg-ui-feature-requires-pen-wireframe`.
