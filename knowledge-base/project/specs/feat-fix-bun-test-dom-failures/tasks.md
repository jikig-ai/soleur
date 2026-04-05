# Tasks: fix bun test DOM failures

Source plan: `knowledge-base/project/plans/2026-04-05-fix-bun-test-dom-failures-plan.md`

## Phase 1: Exclude vitest-only tests from bun discovery

- [ ] 1.1 Update root `bunfig.toml` -- add `"apps/web-platform/**"` to `pathIgnorePatterns` array with explanatory comment
- [ ] 1.2 Update `apps/web-platform/bunfig.toml` -- remove `[test].preload`, add `pathIgnorePatterns = ["**"]` to block all bun test discovery
- [ ] 1.3 Verify: `bun test` from repo root -- 0 failures, no web-platform tests discovered
- [ ] 1.4 Verify: `bun test apps/telegram-bridge/` -- 99 pass, 0 fail (no regression)
- [ ] 1.5 Verify: `bun test plugins/soleur/` -- all pass (no regression)
- [ ] 1.6 Verify: `cd apps/web-platform && bun test` -- 0 tests discovered
- [ ] 1.7 Verify: `bash scripts/test-all.sh` -- all suites pass

## Phase 2: Clean up happy-dom preload

- [ ] 2.1 Remove `apps/web-platform/test/happy-dom.ts`
- [ ] 2.2 Remove `@happy-dom/global-registrator` from `apps/web-platform/package.json` devDependencies
- [ ] 2.3 Run `cd apps/web-platform && bun install` to regenerate `bun.lock`
- [ ] 2.4 Run `cd apps/web-platform && npm install` to regenerate `package-lock.json`
- [ ] 2.5 Verify: `cd apps/web-platform && npx vitest run` -- 0 failures (vitest uses `happy-dom` directly, not `@happy-dom/global-registrator`)
- [ ] 2.6 Verify: `bun test` from root -- still 0 failures
- [ ] 2.7 Verify: `bash scripts/test-all.sh` -- all suites pass
- [ ] 2.8 Verify both lockfiles are committed (`bun.lock`, `package-lock.json`)
