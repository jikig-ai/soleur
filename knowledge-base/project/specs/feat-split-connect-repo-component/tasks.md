# Tasks: split connect-repo/page.tsx god component

Source plan: `knowledge-base/project/plans/2026-04-05-refactor-split-connect-repo-god-component-plan.md`

## Phase 0: Pre-flight Check

- [ ] 0.1 Run `grep -r "connect-repo" apps/web-platform/ --include="*.ts" --include="*.tsx" --include="*.sh"` to find lint/CI scripts that grep for patterns being moved (per learning: lint-scripts-break-on-extract-refactor)

## Phase 1: Extract Icons

- [ ] 1.1 Create `components/icons/index.tsx` with all 13 icon components as named exports (`PlusIcon`, `LinkIcon`, `ShieldIcon`, `CheckCircleIcon`, `XCircleIcon`, `AlertTriangleIcon`, `FolderIcon`, `SearchIcon`, `ArrowLeftIcon`, `SpinnerIcon`, `LockIcon`, `GlobeIcon`, `ChevronDownIcon`)

## Phase 2: Extract UI Primitives

- [ ] 2.1 Create `components/ui/constants.ts` with `GOLD_GRADIENT` constant
- [ ] 2.2 Create `components/ui/badge.tsx` (add `"use client"`)
- [ ] 2.3 Create `components/ui/gold-button.tsx` (imports `GOLD_GRADIENT` from `constants.ts`, add `"use client"`)
- [ ] 2.4 Create `components/ui/outlined-button.tsx` (add `"use client"`)
- [ ] 2.5 Create `components/ui/card.tsx` (add `"use client"`)

## Phase 3: Extract Shared Dependencies and State-View Components

- [ ] 3.1 Create `components/connect-repo/fonts.ts` with `serif` and `sans` font declarations (no `"use client"` -- data-only module)
- [ ] 3.2 Create `components/connect-repo/types.ts` with `Repo` and `SetupStep` types (no `"use client"` -- types-only module)
- [ ] 3.3 Create `lib/relative-time.ts` with `relativeTime` helper (no `"use client"` -- pure utility)
- [ ] 3.4 Extract `ChooseState` to `components/connect-repo/choose-state.tsx` (add `"use client"`)
- [ ] 3.5 Extract `CreateProjectState` to `components/connect-repo/create-project-state.tsx` (add `"use client"` -- uses `useState`)
- [ ] 3.6 Extract `GitHubRedirectState` to `components/connect-repo/github-redirect-state.tsx` (add `"use client"`)
- [ ] 3.7 Extract `SelectProjectState` to `components/connect-repo/select-project-state.tsx` (add `"use client"` -- uses `useState`)
- [ ] 3.8 Extract `NoProjectsState` to `components/connect-repo/no-projects-state.tsx` (add `"use client"`)
- [ ] 3.9 Extract `SettingUpState` to `components/connect-repo/setting-up-state.tsx` (add `"use client"`)
- [ ] 3.10 Extract `ReadyState` to `components/connect-repo/ready-state.tsx` (add `"use client"`)
- [ ] 3.11 Extract `FailedState` to `components/connect-repo/failed-state.tsx` (add `"use client"`)
- [ ] 3.12 Extract `InterruptedState` to `components/connect-repo/interrupted-state.tsx` (add `"use client"`)

## Phase 4: Slim Down page.tsx

- [ ] 4.1 Replace all inline icon definitions with imports from `@/components/icons`
- [ ] 4.2 Replace UI primitive definitions with imports from `@/components/ui`
- [ ] 4.3 Replace font declarations with imports from `@/components/connect-repo/fonts`
- [ ] 4.4 Replace `Repo` and `SetupStep` type definitions with imports from `@/components/connect-repo/types`
- [ ] 4.5 Replace state-view component definitions with imports from `@/components/connect-repo/*`
- [ ] 4.6 Remove `relativeTime` helper and `GOLD_GRADIENT` constant (now in extracted files)
- [ ] 4.7 Verify `page.tsx` is under 250 lines

## Phase 5: Verify

- [ ] 5.1 Run `npx tsc --noEmit` -- zero type errors
- [ ] 5.2 Run existing tests -- all pass
- [ ] 5.3 Visual spot-check if dev server available
