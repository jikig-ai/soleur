# Tasks: fix project setup 'Copying your project files' failure

## Phase 0: Reproduce and diagnose

- [ ] 0.1 Check production container health (volume mounts, permissions, git, /tmp)
- [ ] 0.2 Reproduce via dev server or Playwright to capture the specific error
- [ ] 0.3 Check server logs (pino stdout / Sentry) for the actual exception

## Phase 1: Fix provisioning

- [ ] 1.1 Add step-specific error wrapping with stderr capture to `provisionWorkspaceWithRepo`
- [ ] 1.2 Add Sentry `captureException` to the `.catch()` handler in `setup/route.ts`
- [ ] 1.3 Clear `stepTimerRef` when `POST /api/repo/setup` fails in `startSetup`

## Phase 2: Error persistence and display (UX enhancement)

- [ ] 2.1 Add `repo_error` column via migration; update `.catch()` to store error text; clear on retry
- [ ] 2.2 Return `errorMessage` from `status/route.ts`; display in `FailedState` component

## Phase 3: Validate

- [ ] 3.1 Write tests for error wrapping, Sentry reporting, and error persistence
- [ ] 3.2 End-to-end validation: setup completes for at least one test repository
