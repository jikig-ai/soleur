# Tasks: sec: add settingSources: [] to production agent-runner query()

## Phase 1: Core Fix

- [ ] 1.1 Add `settingSources: []` to `query()` options in `apps/web-platform/server/agent-runner.ts` (line ~179, inside the `options` object, after `permissionMode`)
- [ ] 1.2 Add inline comment above `settingSources: []` explaining the security rationale: prevents SDK from loading `.claude/settings.json` whose `permissions.allow` entries bypass `canUseTool` at permission chain step 4; default is `[]` since SDK v0.1.0; explicit for defense-in-depth
- [ ] 1.3 Update `patchWorkspacePermissions()` section comment (lines 24-26) to explain layered defense: `settingSources: []` is layer 1 (prevents loading); this migration is layer 2 (cleans stale pre-approvals from disk for if `settingSources` ever changes to `["project"]`)

## Phase 2: Verification

- [ ] 2.1 Run `npm install` in `apps/web-platform/` (worktree may lack `node_modules/`)
- [ ] 2.2 Run existing test: `./node_modules/.bin/vitest run canusertool-caching` from `apps/web-platform/`
- [ ] 2.3 Grep codebase for other `query(` calls to confirm single call site
- [ ] 2.4 Verify TypeScript compiles: `npx tsc --noEmit` from `apps/web-platform/`

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #895` in body
