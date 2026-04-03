# Tasks: fix web-platform test failures and CI gates

## Phase 1: Fix bun test DOM environment

- [ ] 1.1 Create `apps/web-platform/test/happy-dom.ts` preload script
  - Import `@happy-dom/global-registrator` and call `GlobalRegistrator.register()`
- [ ] 1.2 Update `apps/web-platform/bunfig.toml` with `[test]` section
  - Add `preload = ["./test/happy-dom.ts"]`
- [ ] 1.3 Verify `bun test` passes in `apps/web-platform/` (390 pass, 0 fail)
- [ ] 1.4 Verify `npx vitest run` still passes in `apps/web-platform/` (regression check)
- [ ] 1.5 Verify `bash scripts/test-all.sh` passes end-to-end

## Phase 2: Fix /ship skill test command

- [ ] 2.1 Update `plugins/soleur/skills/ship/SKILL.md` Phase 4 test command
  - Change `bun test` to `bash scripts/test-all.sh`
  - Update surrounding context to explain why test-all.sh is used (per-directory isolation, vitest for web-platform)

## Phase 3: CI gate hardening (evaluate and apply)

- [ ] 3.1 Check recent e2e CI run history for flakiness
  - `gh run list --workflow ci.yml --limit 20` and check e2e job conclusions
- [ ] 3.2 If e2e is stable, add `e2e` to CI Required ruleset via GitHub API
- [ ] 3.3 If e2e is flaky, create a GitHub issue to track stabilization before requiring it

## Phase 4: Quality and verification

- [ ] 4.1 Run full test suite: `bash scripts/test-all.sh`
- [ ] 4.2 Commit changes
- [ ] 4.3 Push and verify CI passes
