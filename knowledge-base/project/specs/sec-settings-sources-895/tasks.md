# Tasks: sec: add settingSources: [] to production agent-runner query()

## Phase 1: Core Fix

- [ ] 1.1 Add `settingSources: []` to `query()` options in `apps/web-platform/server/agent-runner.ts` (line ~179, inside the `options` object)
- [ ] 1.2 Add inline comment explaining the security rationale: prevents SDK from loading `.claude/settings.json` which could bypass `canUseTool` via `permissions.allow` at permission chain step 4
- [ ] 1.3 Add comment above `patchWorkspacePermissions()` explaining it is retained as defense-in-depth alongside `settingSources: []`

## Phase 2: Verification

- [ ] 2.1 Run existing test: `./node_modules/.bin/vitest run canusertool-caching` from `apps/web-platform/`
- [ ] 2.2 Grep codebase for other `query()` calls to verify no other production paths are missing `settingSources: []`
- [ ] 2.3 Verify TypeScript compiles: `npx tsc --noEmit` from `apps/web-platform/`

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #895` in body
