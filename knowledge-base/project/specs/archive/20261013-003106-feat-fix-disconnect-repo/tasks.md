# Tasks: fix disconnect repo null constraint violation

## Phase 1: Fix Route Handler

- [ ] 1.1 Update `apps/web-platform/app/api/repo/disconnect/route.ts` -- change `workspace_path: null` to `workspace_path: ""`
- [ ] 1.2 Update `apps/web-platform/app/api/repo/disconnect/route.ts` -- change `workspace_status: null` to `workspace_status: "provisioning"`

## Phase 2: Update Tests

- [ ] 2.1 Update `apps/web-platform/test/disconnect-route.test.ts` -- change assertion `workspace_path: null` to `workspace_path: ""`
- [ ] 2.2 Update `apps/web-platform/test/disconnect-route.test.ts` -- change assertion `workspace_status: null` to `workspace_status: "provisioning"`
- [ ] 2.3 Run test suite to verify all tests pass: `cd apps/web-platform && npx vitest run test/disconnect-route.test.ts`

## Phase 3: Verification

- [ ] 3.1 Run full type check: `cd apps/web-platform && npx tsc --noEmit`
- [ ] 3.2 Verify the fix against a running dev server (QA)
