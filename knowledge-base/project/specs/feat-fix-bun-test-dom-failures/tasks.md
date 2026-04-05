# Tasks: fix bun test DOM failures

Source plan: `knowledge-base/project/plans/2026-04-05-fix-bun-test-dom-failures-plan.md`

## Phase 1: Exclude vitest-only tests from bun discovery

- [ ] 1.1 Update root `bunfig.toml` -- add `"apps/web-platform/**"` to `pathIgnorePatterns` array
- [ ] 1.2 Remove `[test].preload` from `apps/web-platform/bunfig.toml`
- [ ] 1.3 Verify: `bun test` from repo root discovers 0 web-platform tests
- [ ] 1.4 Verify: no regression in root-level tests (`test/content-publisher.test.ts`, `test/x-community.test.ts`, `test/pre-merge-rebase.test.ts`)

## Phase 2: Fix remaining non-web-platform failures

- [ ] 2.1 Run `bun test` from root after Phase 1 changes and identify any remaining failures
- [ ] 2.2 Fix any remaining failures individually
- [ ] 2.3 Verify: `bun test` from root -- 0 failures

## Phase 3: Harden test-all.sh

- [ ] 3.1 Verify `scripts/test-all.sh` still covers all test suites (web-platform via vitest, telegram-bridge, plugins, root-level)
- [ ] 3.2 Add explanatory comment in root `bunfig.toml` about web-platform exclusion
- [ ] 3.3 Verify: `bash scripts/test-all.sh` -- all suites pass

## Phase 4: Clean up happy-dom preload

- [ ] 4.1 Remove `apps/web-platform/test/happy-dom.ts`
- [ ] 4.2 Remove `@happy-dom/global-registrator` from `apps/web-platform/package.json` devDependencies
- [ ] 4.3 Run `cd apps/web-platform && bun install` to regenerate `bun.lock`
- [ ] 4.4 Run `cd apps/web-platform && npm install` to regenerate `package-lock.json`
- [ ] 4.5 Verify: `cd apps/web-platform && npx vitest run` -- 0 failures (vitest uses `happy-dom` directly, not `@happy-dom/global-registrator`)
- [ ] 4.6 Verify: `bun test` from root -- still 0 failures
- [ ] 4.7 Verify: `bash scripts/test-all.sh` -- all suites pass

## Phase 5: Final validation

- [ ] 5.1 Run full test suite: `bun test` from root, `vitest run` from web-platform, `test-all.sh`
- [ ] 5.2 Verify both lockfiles are committed (`bun.lock`, `package-lock.json`)
