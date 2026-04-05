---
title: "refactor: split connect-repo/page.tsx god component"
type: refactor
date: 2026-04-05
---

# refactor: split connect-repo/page.tsx god component

`apps/web-platform/app/(auth)/connect-repo/page.tsx` is 1,380 lines containing 13 inline SVG icon components, 4 shared UI primitives, 1 helper function, 8 state-view components, and the main page orchestrator with all handlers. Extract each concern into its own file following the existing `@/components/<domain>/<file>` convention.

## Acceptance Criteria

- [ ] `page.tsx` contains only the main `ConnectRepoPage` component, types, constants, font declarations, and handler functions
- [ ] All 13 SVG icon components consolidated into a single `components/icons/index.tsx` as named exports
- [ ] 4 shared UI primitives (`Badge`, `GoldButton`, `OutlinedButton`, `Card`) extracted to `components/ui/` as individual files
- [ ] `GOLD_GRADIENT` constant extracted to `components/ui/constants.ts` (shared by `GoldButton` and `SettingUpState`)
- [ ] 8 state-view components extracted to `components/connect-repo/` as individual files
- [ ] Font declarations (`serif`, `sans`) extracted to `components/connect-repo/fonts.ts` so state-views can import them directly
- [ ] `relativeTime` helper extracted to `lib/relative-time.ts` (consistent with existing `lib/safe-return-to.ts`)
- [ ] All imports use the `@/components/` alias pattern consistent with the rest of the codebase
- [ ] Zero runtime behavior change -- the page renders and behaves identically before and after the refactor
- [ ] TypeScript compiles without errors (`npx tsc --noEmit`)
- [ ] Existing tests (if any) continue to pass

## Implementation Phases

### Phase 1: Extract icons to `components/icons/`

Create `apps/web-platform/components/icons/index.tsx` -- a single file exporting all 13 icon components as named exports. Each icon is 6-10 lines; a single ~120-line file is scannable and avoids 13 tiny files. No barrel file needed -- import directly from `@/components/icons`.

**File to create:**

- `components/icons/index.tsx` -- all 13 icons: `PlusIcon`, `LinkIcon`, `ShieldIcon`, `CheckCircleIcon`, `XCircleIcon`, `AlertTriangleIcon`, `FolderIcon`, `SearchIcon`, `ArrowLeftIcon`, `SpinnerIcon`, `LockIcon`, `GlobeIcon`, `ChevronDownIcon`

Note: The dashboard layout (`app/(dashboard)/layout.tsx`) also has inline icons (`MenuIcon`, `XIcon`, `GridIcon`, `BookIcon`, `SettingsIcon`, `LogOutIcon`). Those are out of scope for this refactor -- extract them in a follow-up if reuse materializes.

### Phase 2: Extract shared UI primitives to `components/ui/`

The existing `components/ui/` directory already contains `error-card.tsx`. Add the connect-repo UI primitives there.

**Files to create:**

- `components/ui/constants.ts` -- `GOLD_GRADIENT` constant (shared by `GoldButton` and `SettingUpState`)
- `components/ui/badge.tsx` -- `Badge`
- `components/ui/gold-button.tsx` -- `GoldButton` (imports `GOLD_GRADIENT` from `constants.ts`)
- `components/ui/outlined-button.tsx` -- `OutlinedButton`
- `components/ui/card.tsx` -- `Card`

### Phase 3: Extract fonts and utility, then state-view components

**Shared dependencies first:**

- `components/connect-repo/fonts.ts` -- export `serif` and `sans` font declarations (currently in `page.tsx`). State-view components that render headings need `serif.className`. Extracting to a shared module avoids prop-threading font class names through every component.
- `lib/relative-time.ts` -- export `relativeTime` helper (pure utility, consistent with existing `lib/safe-return-to.ts`)

**State-view files:** Create `apps/web-platform/components/connect-repo/` with individual files for each state-view. Each file imports icons from `@/components/icons`, UI primitives from `@/components/ui`, and fonts from `./fonts`.

**Files to create:**

- `components/connect-repo/fonts.ts` -- `serif`, `sans` font declarations
- `lib/relative-time.ts` -- `relativeTime` helper
- `components/connect-repo/choose-state.tsx` -- `ChooseState`
- `components/connect-repo/create-project-state.tsx` -- `CreateProjectState`
- `components/connect-repo/github-redirect-state.tsx` -- `GitHubRedirectState`
- `components/connect-repo/select-project-state.tsx` -- `SelectProjectState` (imports `relativeTime` from `@/lib/relative-time`)
- `components/connect-repo/no-projects-state.tsx` -- `NoProjectsState`
- `components/connect-repo/setting-up-state.tsx` -- `SettingUpState` (imports `GOLD_GRADIENT` from `@/components/ui/constants`)
- `components/connect-repo/ready-state.tsx` -- `ReadyState`
- `components/connect-repo/failed-state.tsx` -- `FailedState`
- `components/connect-repo/interrupted-state.tsx` -- `InterruptedState`

No barrel file -- import directly from each file.

### Phase 4: Slim down `page.tsx`

Replace all inline definitions in `page.tsx` with imports from the extracted files. The page should contain only:

- Type definitions (`State`, `Repo`, `SetupStep`)
- Constants (`DEFAULT_GITHUB_APP_SLUG`, `SETUP_STEPS_TEMPLATE`)
- Font imports from `@/components/connect-repo/fonts`
- The `ConnectRepoPage` component with all handler functions and state management
- The render switch

### Phase 5: Verify

- Run `npx tsc --noEmit` to confirm TypeScript compiles
- Run any existing tests
- Visual spot-check (dev server) if available

## Shared Types

The `State`, `Repo`, and `SetupStep` types are used by both `page.tsx` and the state-view components. Each state-view already receives its data via props, so each file defines its own prop interface locally. The `State` union type stays in `page.tsx` (only the orchestrator uses it). `Repo` and `SetupStep` are passed as props -- state-views that need them define the shape in their prop interface. If duplication becomes a problem, extract to `components/connect-repo/types.ts` later.

## Test Scenarios

- Given the extracted files exist, when `npx tsc --noEmit` runs, then it exits 0 with no type errors
- Given the page is loaded in a browser, when navigating through each state (choose, create_project, github_redirect, select_project, no_projects, setting_up, ready, failed, interrupted), then the UI renders identically to the pre-refactor version
- Given the refactor is complete, when counting lines in `page.tsx`, then it is under 250 lines

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal code refactoring with zero behavioral change.

## Plan Review

Reviewed by dhh-rails-reviewer, kieran-rails-reviewer, and code-simplicity-reviewer in parallel. All three agreed on the following changes (applied):

1. **Consolidated icons into a single file** -- 13 individual files for 6-10 line SVG components was over-engineered. Single `components/icons/index.tsx` replaces 14 files.
2. **Removed barrel files** -- no external consumers exist; direct imports are simpler.
3. **Added font sharing strategy** -- state-view components use `serif.className` internally, which the original plan did not address. Extracted to `components/connect-repo/fonts.ts`.
4. **Fixed primitive count** -- "3 shared UI primitives" corrected to "4" (`Badge`, `GoldButton`, `OutlinedButton`, `Card`).
5. **Moved `GOLD_GRADIENT` to shared constants** -- used by both `GoldButton` and `SettingUpState`, so it belongs in `components/ui/constants.ts`.
6. **Decided `relativeTime` location** -- `lib/relative-time.ts`, consistent with existing `lib/safe-return-to.ts`.

File count reduced from ~28 to ~18.

## Context

Flagged during review of PR #1464 by code-quality-analyst and architecture-strategist agents. See [#1470](https://github.com/jikig-ai/soleur/issues/1470).

## References

- Existing component pattern: `@/components/auth/oauth-buttons.tsx`, `@/components/ui/error-card.tsx`
- Target file: `apps/web-platform/app/(auth)/connect-repo/page.tsx` (1,380 lines)
- Related issue: #1470
