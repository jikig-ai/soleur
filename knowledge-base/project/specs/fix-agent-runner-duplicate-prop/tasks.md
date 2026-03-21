# Tasks: fix duplicate settingSources property

## Phase 1: Fix

- [ ] 1.1 Remove duplicate `settingSources: []` at line 198 of `apps/web-platform/server/agent-runner.ts`
- [ ] 1.2 Verify the remaining instance at line 191 retains the defense-in-depth comment

## Phase 2: Verify

- [ ] 2.1 Run `npx tsc --noEmit` in `apps/web-platform/` -- confirm TS2300 is resolved
- [ ] 2.2 Run `next build` in `apps/web-platform/` -- confirm Docker build step equivalent passes
- [ ] 2.3 Run existing tests (`bun test` or equivalent) to confirm no regressions

## Phase 3: Ship

- [ ] 3.1 Run `skill: soleur:compound` before commit
- [ ] 3.2 Commit, push, create PR targeting main with `Closes #<issue>` if applicable
- [ ] 3.3 Merge via `gh pr merge --squash --auto` and poll until MERGED
