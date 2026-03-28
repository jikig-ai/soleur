# Tasks: fix: match local TypeScript strictness to CI Docker build

## Phase 1: tsconfig.json update

- [x] 1.1 ~~Add `"noImplicitAny": true` to tsconfig.json~~ — skipped, already implied by `strict: true`

## Phase 2: Fix existing type errors

- [x] 2.1 Fix `process.env.NODE_ENV` readonly assignment in `validate-origin.test.ts` — cast `process.env as Record<string, string | undefined>`
- [x] 2.2 Fix `process.env` readonly assignment in `agent-env.test.ts` — cast for loop-based assignment
- [x] 2.3 Fix `process.env.NODE_ENV` readonly assignment in `callback.test.ts` — cast with inline save/restore
- [x] 2.4 Replace `bun:test` import with `vitest` in `domain-router.test.ts`
- [x] 2.5 Fix `reason` type annotation in `ws-abort.test.ts` — narrowed to `"disconnected" | "superseded"`

## Phase 3: Add typecheck script and CI integration

- [x] 3.1 Add `"typecheck": "npx tsc --noEmit"` script to `apps/web-platform/package.json`
- [x] 3.2 Add `web-platform-typecheck` command to `lefthook.yml` at priority 5, array glob
- [x] 3.3 Add type-check step to `.github/workflows/ci.yml` after web-platform deps install

## Phase 4: Verify

- [x] 4.1 `npm run --prefix apps/web-platform typecheck` — zero errors
- [x] 4.2 `bun test apps/web-platform/` — 267 pass, 0 fail
- [x] 4.3 `lefthook run pre-commit` — typecheck hook triggered and passed (3.90s)
