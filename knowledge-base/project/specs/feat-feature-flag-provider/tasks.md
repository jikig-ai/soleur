# Tasks: Runtime Feature Flags

**Plan:** `knowledge-base/project/plans/2026-04-16-feat-runtime-feature-flags-plan.md`
**Issue:** #2409
**Branch:** `feat-feature-flag-provider`

## Phase 1: Server-side flag reader

- [x] 1.1 Create `apps/web-platform/lib/feature-flags/server.ts`
  - `FLAG_VARS` const with `"kb-chat-sidebar"` mapping
  - `getFeatureFlags()` returns all flags as `Record<FlagName, boolean>`
  - `getFlag(name)` returns single boolean
  - Type safety via `as const` assertion
- [x] 1.2 Write tests: `apps/web-platform/lib/feature-flags/server.test.ts`
  - Test `getFlag()` returns `true` when env var is `"1"`
  - Test `getFlag()` returns `false` when env var is `"0"`, unset, or other value
  - Test `getFeatureFlags()` returns all flags

## Phase 2: Wire KB Chat Sidebar flag

- [x] 2.1 Locate KB chat sidebar trigger component render site (from PR #2347)
- [x] 2.2 Add `getFlag("kb-chat-sidebar")` check in the nearest server component
  - Conditionally render sidebar: `{showChatSidebar && <KbChatTrigger />}`
- [x] 2.3 Update `.env.example` with `FLAG_KB_CHAT_SIDEBAR=0` under new
      `# --- Runtime Feature Flags ---` section
- [x] 2.4 Set Doppler secrets:
  - `doppler secrets set FLAG_KB_CHAT_SIDEBAR=1 -p soleur -c dev`
  - `doppler secrets set FLAG_KB_CHAT_SIDEBAR=0 -p soleur -c prd`

## Phase 3: Verify

- [x] 3.1 Run tests: `node node_modules/vitest/vitest.mjs run lib/feature-flags/`
- [x] 3.2 Run `next build` to verify no route export violations
- [x] 3.3 Start dev server with flag on: verify sidebar visible
- [x] 3.4 Start dev server with flag off: verify sidebar hidden
