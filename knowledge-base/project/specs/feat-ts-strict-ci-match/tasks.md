# Tasks: fix: match local TypeScript strictness to CI Docker build

## Phase 1: tsconfig.json update

- [ ] 1.1 Add `"noImplicitAny": true` to `apps/web-platform/tsconfig.json` compilerOptions (after `"strict": true`)

## Phase 2: Fix existing type errors

- [ ] 2.1 Fix `process.env.NODE_ENV` readonly assignment in `apps/web-platform/lib/auth/validate-origin.test.ts` -- use `vi.stubEnv`/`vi.unstubAllEnvs`, remove manual save/restore pattern
- [ ] 2.2 Fix `process.env.NODE_ENV` readonly assignment in `apps/web-platform/test/agent-env.test.ts` -- use `process.env as Record<string, string | undefined>` cast for loop-based assignment (vi.stubEnv inappropriate for dynamic loop pattern)
- [ ] 2.3 Fix `process.env.NODE_ENV` readonly assignment in `apps/web-platform/test/callback.test.ts` -- use `vi.stubEnv`/`vi.unstubAllEnvs`
- [ ] 2.4 Replace `bun:test` import with `vitest` in `apps/web-platform/test/domain-router.test.ts`
- [ ] 2.5 Fix `reason` type annotation in `apps/web-platform/test/ws-abort.test.ts` -- change `reason?: string` to `reason?: "disconnected" | "superseded"`

## Phase 3: Add typecheck script and CI integration

- [ ] 3.1 Add `"typecheck": "tsc --noEmit"` script to `apps/web-platform/package.json` (NOT bunx tsc -- bunx sandboxing breaks module resolution)
- [ ] 3.2 Add `web-platform-typecheck` command to `lefthook.yml` pre-commit hooks at priority 5 (before bun-test at 6), using array glob to avoid gobwas `**` edge case
- [ ] 3.3 Add type-check step to `.github/workflows/ci.yml` after web-platform dependency install, before test run

## Phase 4: Verify

- [ ] 4.1 Run `npm run --prefix apps/web-platform typecheck` -- zero errors
- [ ] 4.2 Run `bun test apps/web-platform/` -- all tests pass
- [ ] 4.3 Run `lefthook run pre-commit` -- verify typecheck hook triggers on web-platform .ts files
