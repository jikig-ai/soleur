# Tasks — feat-refactor-dashboard-polish

Plan: `knowledge-base/project/plans/2026-04-14-refactor-dashboard-polish-leader-avatar-plan.md`

## 1. Setup & Verification

- [ ] 1.1 Re-read source files after any context compaction (all files below)
- [ ] 1.2 Grep-verify no hidden consumers of `DOMAIN_LEADERS[*].color`:
  `grep -rE '\.color\b' apps/web-platform/{app,components,hooks,lib,server}/ | grep -v node_modules`
- [ ] 1.3 Confirm Tailwind v4 is in use (`apps/web-platform/package.json`, `tailwindcss: ^4.1.0`)

## 2. Test Infrastructure (TDD — write tests first)

- [ ] 2.1 Create `apps/web-platform/test/mocks/use-team-names.ts` with `createUseTeamNamesMock` factory
- [ ] 2.2 Create `apps/web-platform/test/mocks/use-team-names.test.ts` — asserts factory returns all `TeamNamesState` keys and overrides merge
- [ ] 2.3 Rewrite `apps/web-platform/test/leader-avatar.test.tsx` with behavioral assertions (no `bg-*`/`h-*`/`w-*` class checks); add fallback-on-img-error test
- [ ] 2.4 Create `apps/web-platform/test/foundation-cards.test.tsx` — asserts done → `<a>`, incomplete → `<button>` with click handler
- [ ] 2.5 Add CSP header assertion to a route test (extend `apps/web-platform/test/csp.test.ts` or create `apps/web-platform/test/kb-content-route.test.ts`)

## 3. Shared Test Mock Migration (issue #2169)

- [ ] 3.1 Replace inline `useTeamNames` mocks with factory in `start-fresh-onboarding.test.tsx`
- [ ] 3.2 Replace in `team-settings.test.tsx`
- [ ] 3.3 Replace in `display-format.test.tsx`
- [ ] 3.4 Replace in `error-states.test.tsx` (heals stale mock — adds `iconPaths`, `updateIcon`, `refetch`, `getIconPath`, `error`)
- [ ] 3.5 Replace in `components/status-badge-interaction.test.tsx`
- [ ] 3.6 Replace in `dashboard-layout-banner.test.tsx`
- [ ] 3.7 Replace in `chat-page-resume.test.tsx` (heals stale mock)
- [ ] 3.8 Replace in `chat-page.test.tsx`
- [ ] 3.9 Replace in `command-center.test.tsx`
- [ ] 3.10 Replace in `components/conversation-row.test.tsx`
- [ ] 3.11 Audit `team-names-hook.test.tsx` — leave unchanged if it tests the hook itself and does not mock it
- [ ] 3.12 Run vitest after mock migration — commit as isolated checkpoint

## 4. CSP Header (issue #2141 c)

- [ ] 4.1 Edit `apps/web-platform/app/api/kb/content/[...path]/route.ts`:
  add `"Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'"` to the binary `Response` headers
- [ ] 4.2 Verify route test passes
- [ ] 4.3 Local smoke: fetch a KB-hosted PDF in dev and confirm `react-pdf` viewer still renders (per risk note)

## 5. FoundationCards Extraction (issue #2141 e)

- [ ] 5.1 Create `apps/web-platform/components/dashboard/foundation-cards.tsx` with `FoundationCards` component (grid + card map only)
- [ ] 5.2 Replace both inline grids in `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (lines ~477–515 and ~591–628) with `<FoundationCards>`
- [ ] 5.3 Keep outer wrappers (FOUNDATIONS header, description, margin classes) inline at each call site
- [ ] 5.4 Run `foundation-cards.test.tsx` + visual diff check

## 6. LeaderAvatar Adoption (issue #2141 a)

- [ ] 6.1 `apps/web-platform/components/chat/naming-nudge.tsx` — replace inline badge with `<LeaderAvatar leaderId={leaderId} size="lg" />`; remove `LEADER_BG_COLORS` import
- [ ] 6.2 `apps/web-platform/components/onboarding/naming-modal.tsx` — same migration, `size="lg"`
- [ ] 6.3 `apps/web-platform/components/chat/at-mention-dropdown.tsx` — migrate to `<LeaderAvatar size="md" />`; drop three-letter text-in-badge (redundant with adjacent row label)
- [ ] 6.4 Grep-verify `LEADER_BG_COLORS\[` has no hits outside `components/leader-avatar.tsx` and `components/chat/leader-colors.ts`

## 7. Color Field Removal (issue #2141 b)

- [ ] 7.1 Delete `color` field from all 9 entries in `apps/web-platform/server/domain-leaders.ts`
- [ ] 7.2 Run `npx tsc --noEmit` — TypeScript must pass
- [ ] 7.3 Re-grep for `\.color\b` against the DOMAIN_LEADERS type — zero hits expected

## 8. Test & Ship

- [ ] 8.1 Run full vitest: `node node_modules/vitest/vitest.mjs run` from `apps/web-platform/` — zero new failures
- [ ] 8.2 Run `npx tsc --noEmit`
- [ ] 8.3 Run `npx markdownlint-cli2 --fix` on changed `.md` files (plan + tasks only)
- [ ] 8.4 Review diff; push branch; update PR #2265 from WIP to ready
- [ ] 8.5 Use `/ship` with `patch` semver label (pure refactor)
- [ ] 8.6 PR body includes `Closes #2141` and `Closes #2169`
- [ ] 8.7 Auto-merge: `gh pr merge 2265 --squash --auto`; poll until MERGED; `cleanup-merged`
