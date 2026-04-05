---
title: "refactor: split connect-repo/page.tsx god component"
type: refactor
date: 2026-04-05
deepened: 2026-04-05
---

# refactor: split connect-repo/page.tsx god component

`apps/web-platform/app/(auth)/connect-repo/page.tsx` is 1,380 lines containing 13 inline SVG icon components, 4 shared UI primitives, 1 helper function, 8 state-view components, and the main page orchestrator with all handlers. Extract each concern into its own file following the existing `@/components/<domain>/<file>` convention.

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 5
**Sources used:** Next.js official docs (Context7), codebase pattern analysis, institutional learnings

### Key Improvements

1. Font sharing strategy validated against Next.js official documentation -- the `fonts.ts` shared module pattern is the recommended approach
2. Shared types strategy refined -- `Repo` and `SetupStep` types extracted to `components/connect-repo/types.ts` to avoid duplication across state-view files
3. `"use client"` directive guidance added for each extracted component category
4. Lint/CI coupling check added to prevent extraction from breaking downstream validators
5. Import order convention documented for consistency across all extracted files

## Acceptance Criteria

- [x] `page.tsx` contains only the main `ConnectRepoPage` component, types, constants, font declarations, and handler functions
- [x] All 13 SVG icon components consolidated into a single `components/icons/index.tsx` as named exports
- [x] 4 shared UI primitives (`Badge`, `GoldButton`, `OutlinedButton`, `Card`) extracted to `components/ui/` as individual files
- [x] `GOLD_GRADIENT` constant extracted to `components/ui/constants.ts` (shared by `GoldButton` and `SettingUpState`)
- [x] 8 state-view components extracted to `components/connect-repo/` as individual files
- [x] Font declarations (`serif`, `sans`) extracted to `components/connect-repo/fonts.ts` so state-views can import them directly
- [x] `Repo` and `SetupStep` types extracted to `components/connect-repo/types.ts` (shared by page.tsx and state-view components)
- [x] `relativeTime` helper extracted to `lib/relative-time.ts` (consistent with existing `lib/safe-return-to.ts`)
- [x] All imports use the `@/components/` alias pattern consistent with the rest of the codebase
- [x] Zero runtime behavior change -- the page renders and behaves identically before and after the refactor
- [x] TypeScript compiles without errors (`npx tsc --noEmit`)
- [x] Existing tests (if any) continue to pass

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

- `components/connect-repo/fonts.ts` -- export `serif` and `sans` font declarations (currently in `page.tsx`). State-view components that render headings need `serif.className`. Extracting to a shared module avoids prop-threading font class names through every component. This follows the [Next.js recommended pattern](https://nextjs.org/docs/app/api-reference/components/font) for sharing font instances across files: "If you need to use the same font in multiple places, you should load it in one place and import the related font object where you need it."
- `components/connect-repo/types.ts` -- export `Repo` and `SetupStep` types. Both are used by `page.tsx` state and by state-view prop interfaces (`SelectProjectState` needs `Repo`, `SettingUpState` needs `SetupStep`). Without a shared types file, the type definitions would be duplicated in each consumer -- violating DRY for a structural type that should be a single source of truth. The `State` union type stays in `page.tsx` since only the orchestrator uses it.
- `lib/relative-time.ts` -- export `relativeTime` helper (pure utility, consistent with existing `lib/safe-return-to.ts`)

**State-view files:** Create `apps/web-platform/components/connect-repo/` with individual files for each state-view. Each file imports icons from `@/components/icons`, UI primitives from `@/components/ui`, and fonts from `./fonts`.

**Files to create:**

- `components/connect-repo/fonts.ts` -- `serif`, `sans` font declarations
- `components/connect-repo/types.ts` -- `Repo`, `SetupStep` types
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

Three types exist: `State`, `Repo`, and `SetupStep`.

- **`State`** stays in `page.tsx` -- only the orchestrator uses it for the state machine union.
- **`Repo`** and **`SetupStep`** go to `components/connect-repo/types.ts` -- both are used by `page.tsx` state declarations AND by state-view prop interfaces (`SelectProjectState` needs `Repo`, `SettingUpState` needs `SetupStep`). Duplicating these across files invites drift.
- Each state-view component defines its own **props interface** locally (e.g., `interface ChooseStateProps { onCreateNew: () => void; ... }`). Props interfaces are component-specific and do not need sharing.

## Implementation Notes

### `"use client"` directive

All extracted `.tsx` component files need `"use client"` at the top. The reason: the page is already a client component, and several state-view components use React hooks internally (`useState` in `CreateProjectState` and `SelectProjectState`). For consistency and to avoid confusing Next.js boundary issues, add the directive to all component files. The `.ts` files (`fonts.ts`, `types.ts`, `constants.ts`, `relative-time.ts`) do NOT need `"use client"` since they export only data/types.

### Import order convention

Follow the existing codebase pattern (visible in `components/auth/oauth-buttons.tsx`, `components/chat/chat-input.tsx`):

1. `"use client";` directive (first line, if applicable)
2. React imports (`import { useState } from "react"`)
3. Next.js imports (`import { useRouter } from "next/navigation"`)
4. Absolute project imports (`import { ... } from "@/components/..."`, `import { ... } from "@/lib/..."`)
5. Relative imports (`import { serif } from "./fonts"`)
6. Blank line, then component code

### Lint/CI coupling check

Per institutional learning `2026-03-20-lint-scripts-break-on-extract-refactor`: before implementing, run `grep -r "connect-repo" apps/web-platform/ --include="*.ts" --include="*.tsx" --include="*.sh"` to find any scripts, tests, or CI checks that grep for patterns inside the file being split. If any downstream validator matches strings being moved, update it in the same PR.

### Font module structure

The `fonts.ts` file follows Next.js's official recommended pattern for font sharing ([docs reference](https://nextjs.org/docs/app/api-reference/components/font)):

```typescript
// components/connect-repo/fonts.ts
import { Cormorant_Garamond, Inter } from "next/font/google";

export const serif = Cormorant_Garamond({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-serif",
  display: "swap",
});

export const sans = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-sans",
  display: "swap",
});
```

Next.js loads each font instance only once regardless of how many files import it. The `variable` property generates CSS custom properties (`--font-serif`, `--font-sans`) that are applied via `className` on the page wrapper.

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
