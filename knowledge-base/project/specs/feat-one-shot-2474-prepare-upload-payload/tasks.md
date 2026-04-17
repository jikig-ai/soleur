# Tasks: extract prepareUploadPayload from kb upload route

**Plan:** `knowledge-base/project/plans/2026-04-17-refactor-extract-prepare-upload-payload-plan.md`
**Issue:** #2474
**Branch:** `feat-one-shot-2474-prepare-upload-payload`

## 1. Setup

- [ ] 1.1 Confirm worktree is on `feat-one-shot-2474-prepare-upload-payload` branch
- [ ] 1.2 Pull latest main into branch if stale
- [ ] 1.3 Re-read `apps/web-platform/test/kb-upload.test.ts` to confirm pre-refactor PDF-block line ranges (525–628) match the current HEAD

## 2. RED — write failing tests (helper + delegation)

- [ ] 2.1 Create `apps/web-platform/test/kb-upload-payload.test.ts`
  - [ ] 2.1.1 Import `vitest` primitives (describe/it/expect/vi/beforeEach)
  - [ ] 2.1.2 `vi.hoisted` + `vi.mock` for `@/server/pdf-linearize` and `@/server/observability`
  - [ ] 2.1.3 `fakeFile(bytes)` helper stubbing `File.stream().getReader()`
  - [ ] 2.1.4 Scenario 1 — non-PDF passthrough (`.md` file, linearize NOT called, warn NOT called)
  - [ ] 2.1.5 Scenario 2 — PDF linearize success returns linearized buffer (warn NOT called)
  - [ ] 2.1.6 Scenario 3 — PDF linearize failure falls back, `warnSilentFallback` called with
              `{feature:"kb-upload", op:"linearize", message:"pdf linearization failed", extra:{reason, detail, inputSize, durationMs, userId, path}}`
  - [ ] 2.1.7 Scenario 4 — signed-PDF `skip_signed` returns raw buffer, warn NOT called
- [ ] 2.2 Add proof-of-delegation block to `apps/web-platform/test/kb-upload.test.ts`
  - [ ] 2.2.1 Import `readFileSync` and `resolve` from node built-ins
  - [ ] 2.2.2 Assertion: route source matches `import { prepareUploadPayload } from "@/server/kb-upload-payload"` regex
  - [ ] 2.2.3 Assertion: route source matches `await prepareUploadPayload(` regex
  - [ ] 2.2.4 Assertion: route source does NOT match `linearizePdf(` (negative gate)
- [ ] 2.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-upload-payload.test.ts test/kb-upload.test.ts`
- [ ] 2.4 Confirm helper test file fails (module not found) AND proof-of-delegation assertions fail (route unchanged)
- [ ] 2.5 Confirm the 4 pre-existing PDF assertions in `kb-upload.test.ts` still PASS at this point

## 3. GREEN — helper + route wiring + route-test migration

- [ ] 3.1 Create `apps/web-platform/server/kb-upload-payload.ts`
  - [ ] 3.1.1 Import `linearizePdf` from `@/server/pdf-linearize`
  - [ ] 3.1.2 Import `warnSilentFallback` from `@/server/observability`
  - [ ] 3.1.3 Export `prepareUploadPayload(file, sanitizedName, userId, filePath): Promise<Buffer>`
  - [ ] 3.1.4 Implement stream-to-buffer chunk loop (port from route lines 177–184)
  - [ ] 3.1.5 Non-PDF passthrough branch (ext !== "pdf")
  - [ ] 3.1.6 PDF success branch (return `result.buffer`)
  - [ ] 3.1.7 `skip_signed` branch returns raw buffer silently (no warn)
  - [ ] 3.1.8 Other linearize failures → `warnSilentFallback(null, {feature:"kb-upload", op:"linearize", message:"pdf linearization failed", extra:{...}})` + return raw buffer
- [ ] 3.2 Re-run helper test file; all 4 scenarios pass
- [ ] 3.3 Edit `apps/web-platform/app/api/kb/upload/route.ts`
  - [ ] 3.3.1 Add `import { prepareUploadPayload } from "@/server/kb-upload-payload";`
  - [ ] 3.3.2 Replace lines 176–212 with single `const payloadBuffer = await prepareUploadPayload(file, sanitizedName, user.id, filePath);`
  - [ ] 3.3.3 Remove `import { linearizePdf } from "@/server/pdf-linearize";`
  - [ ] 3.3.4 Verify `Sentry` import remains (outer catch uses `Sentry.captureException`)
- [ ] 3.4 Migrate `apps/web-platform/test/kb-upload.test.ts` PDF tests per the Route-Level Test Migration table
  - [ ] 3.4.1 KEEP "PDF upload: commits linearized bytes when qpdf succeeds" as-is
  - [ ] 3.4.2 REWRITE "PDF upload: commits original bytes and logs warning when qpdf fails":
            (a) keep GitHub PUT assertion, (b) relax logger.warn to `expect.objectContaining({reason, detail, inputSize, durationMs, userId, path})`,
            (c) update Sentry.captureMessage expectation — tags become `{feature:"kb-upload", op:"linearize"}`, `reason` moves into `extra`, message string stays `"pdf linearization failed"`
  - [ ] 3.4.3 KEEP "PDF upload: skip_signed is silent in BOTH pino and Sentry" as-is
  - [ ] 3.4.4 KEEP "non-PDF upload: does not invoke linearize" as-is
- [ ] 3.5 Run full vitest suite: `cd apps/web-platform && ./node_modules/.bin/vitest run`
- [ ] 3.6 Run `cd apps/web-platform && npx tsc --noEmit`
- [ ] 3.7 Run `cd apps/web-platform && doppler run -p soleur -c dev -- npm run build` to validate `next build` and the route-file export rule

## 4. REFACTOR (polish)

- [ ] 4.1 Review POST handler for residual readability wins (NO new extractions)
- [ ] 4.2 Verify diff: roughly -37 LOC in route.ts, +1 line helper call, -1 line import
- [ ] 4.3 Confirm no unrelated files touched

## 5. Ship

- [ ] 5.1 `skill: soleur:review` on the branch
- [ ] 5.2 Resolve review findings inline (default — fix-inline per `rf-review-finding-default-fix-inline`)
- [ ] 5.3 `skill: soleur:compound` to capture session learnings
- [ ] 5.4 `skill: soleur:ship`
  - [ ] 5.4.1 PR title: `refactor(kb-upload): extract prepareUploadPayload helper`
  - [ ] 5.4.2 PR body starts with `Closes #2474`
  - [ ] 5.4.3 Label: `semver:patch`
- [ ] 5.5 Queue auto-merge, poll until MERGED
- [ ] 5.6 Run postmerge verification
