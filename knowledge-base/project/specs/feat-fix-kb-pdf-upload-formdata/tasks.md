# Tasks: fix KB PDF upload FormData body size limit

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/next.config.ts`
- [ ] 1.2 Read `apps/web-platform/test/kb-upload.test.ts`

## Phase 2: Core Implementation

- [ ] 2.1 Add `experimental.middlewareClientMaxBodySize: 25 * 1024 * 1024` to `next.config.ts`
- [ ] 2.2 Add test case for 11 MB file upload success in `kb-upload.test.ts`

## Phase 3: Testing

- [ ] 3.1 Run existing KB upload tests to verify no regressions
- [ ] 3.2 Verify new test passes
- [ ] 3.3 Run markdownlint on changed markdown files
