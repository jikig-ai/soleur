# Tasks: split connect-repo/page.tsx god component

Source plan: `knowledge-base/project/plans/2026-04-05-refactor-split-connect-repo-god-component-plan.md`

## Phase 0: Pre-flight Check

- [x] 0.1 Run `grep -r "connect-repo"` -- only URL references found, no lint/CI coupling issues

## Phase 1: Extract Icons

- [x] 1.1 Create `components/icons/index.tsx` with all 13 icon components as named exports

## Phase 2: Extract UI Primitives

- [x] 2.1 Create `components/ui/constants.ts` with `GOLD_GRADIENT` constant
- [x] 2.2 Create `components/ui/badge.tsx` (add `"use client"`)
- [x] 2.3 Create `components/ui/gold-button.tsx` (imports `GOLD_GRADIENT` from `constants.ts`, add `"use client"`)
- [x] 2.4 Create `components/ui/outlined-button.tsx` (add `"use client"`)
- [x] 2.5 Create `components/ui/card.tsx` (add `"use client"`)

## Phase 3: Extract Shared Dependencies and State-View Components

- [x] 3.1 Create `components/connect-repo/fonts.ts`
- [x] 3.2 Create `components/connect-repo/types.ts`
- [x] 3.3 Create `lib/relative-time.ts`
- [x] 3.4 Extract `ChooseState` to `components/connect-repo/choose-state.tsx`
- [x] 3.5 Extract `CreateProjectState` to `components/connect-repo/create-project-state.tsx`
- [x] 3.6 Extract `GitHubRedirectState` to `components/connect-repo/github-redirect-state.tsx`
- [x] 3.7 Extract `SelectProjectState` to `components/connect-repo/select-project-state.tsx`
- [x] 3.8 Extract `NoProjectsState` to `components/connect-repo/no-projects-state.tsx`
- [x] 3.9 Extract `SettingUpState` to `components/connect-repo/setting-up-state.tsx`
- [x] 3.10 Extract `ReadyState` to `components/connect-repo/ready-state.tsx`
- [x] 3.11 Extract `FailedState` to `components/connect-repo/failed-state.tsx`
- [x] 3.12 Extract `InterruptedState` to `components/connect-repo/interrupted-state.tsx`

## Phase 4: Slim Down page.tsx

- [x] 4.1 Replace all inline icon definitions with imports from `@/components/icons`
- [x] 4.2 Replace UI primitive definitions with imports from `@/components/ui`
- [x] 4.3 Replace font declarations with imports from `@/components/connect-repo/fonts`
- [x] 4.4 Replace `Repo` and `SetupStep` type definitions with imports from `@/components/connect-repo/types`
- [x] 4.5 Replace state-view component definitions with imports from `@/components/connect-repo/*`
- [x] 4.6 Remove `relativeTime` helper and `GOLD_GRADIENT` constant (now in extracted files)
- [x] 4.7 page.tsx is 427 lines (handlers + state management are irreducible core; 69% reduction from 1380)

## Phase 5: Verify

- [x] 5.1 Run `npx tsc --noEmit` -- zero type errors
- [x] 5.2 Run existing tests -- 438 passed, 0 failed
- [ ] 5.3 Visual spot-check if dev server available
