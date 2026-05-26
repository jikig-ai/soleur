---
title: "fix(dsar): enqueueExport missing workspace_id"
type: fix
date: 2026-05-26
lane: single-domain
---

# Tasks: fix(dsar) enqueueExport missing workspace_id

## Phase 1: Core Fix — EnqueueExportInput + enqueueExport

- [ ] 1.1 Add `workspaceId: string` to `EnqueueExportInput` interface in `apps/web-platform/server/dsar-export.ts`
- [ ] 1.2 Add fail-loud assertion at top of `enqueueExport`: `if (!input.workspaceId) throw new Error("enqueueExport: workspaceId is required")`
- [ ] 1.3 Add `workspace_id: input.workspaceId` to the `.insert({...})` call in `enqueueExport`
- [ ] 1.4 Run `tsc --noEmit` -- expect type errors in route.ts and tests (workspaceId now required but not yet provided)

## Phase 2: Callers — Resolve workspaceId in BOTH callers

- [ ] 2.1 In `apps/web-platform/app/api/account/export/route.ts`, add `workspaceId: reauthSession.userId` to the `enqueueExport({...})` call
- [ ] 2.2 In `apps/web-platform/server/account-tools.ts`, add `workspaceId: userId` to the `enqueueExport({...})` call (userId is already available from `BuildAccountToolsOpts`)
- [ ] 2.3 Run `tsc --noEmit` -- expect type errors in test files only (both callers now pass workspaceId)

## Phase 3: Test Updates

- [ ] 3.1 In `apps/web-platform/test/dsar-export-route.test.ts`, update mock expectations to include `workspaceId` field
- [ ] 3.2 In `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts`:
  - [ ] 3.2.1 Change `test.skip(` to `test(` at line ~222
  - [ ] 3.2.2 Add `workspaceId: userA.id` to the `enqueueExport({...})` call
  - [ ] 3.2.3 Optionally add `workspace_id` assertion on the inserted row
- [ ] 3.3 Run `tsc --noEmit` -- expect clean (zero errors)

## Phase 4: Verification

- [ ] 4.1 Run `./node_modules/.bin/vitest run test/dsar-export-route.test.ts` -- all tests pass
- [ ] 4.2 Run `./node_modules/.bin/vitest run test/dsar-export-cross-tenant.integration.test.ts` -- all non-integration tests pass (integration tests gated on SUPABASE_DEV_INTEGRATION=1)
- [ ] 4.3 Verify `grep -c 'test.skip' test/dsar-export-cross-tenant.integration.test.ts` returns 0
- [ ] 4.4 Verify `grep -c 'workspaceId' apps/web-platform/server/dsar-export.ts` returns >= 3 (interface + assertion + insert)
