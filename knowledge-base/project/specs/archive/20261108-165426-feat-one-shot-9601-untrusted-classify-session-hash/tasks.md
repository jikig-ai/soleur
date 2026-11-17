# Tasks: hash the sessionId on the untrusted-classify log line

Plan: `knowledge-base/project/plans/2026-11-08-fix-untrusted-classify-session-id-hash-plan.md`
Ref #9601 (epic, slice 2), Ref #4671, Ref #10195. Single small PR; no flag, scorer or other surface changes.

## Phase 1: Setup

- [x] 1.1 Confirm the worktree and branch (`feat-one-shot-9601-untrusted-classify-session-hash`) and that PR 12415 is the draft for this branch.
- [x] 1.2 Re-read `emit()` in `apps/web-platform/server/untrusted-content.ts` and confirm `hashUserId` is already imported from `./observability`.

## Phase 2: Tests first (RED)

- [x] 2.1 Create `apps/web-platform/test/untrusted-content-session-hash.test.ts` with the logger and `mirrorWithDebounce` mocks.
  - [x] 2.1.1 Pepper-unset describe (`SENTRY_USERID_PEPPER` deleted in `vi.hoisted`): six emit paths (flagged, unflagged, truncated-only, flagged and truncated, unscored shape, unscored error); assert no `sessionId` own key, `sessionIdHash === "pepper_unset"`, raw sentinel absent from every serialized sink (four logger methods and `mirrorWithDebounce` calls), and an emit-count floor of six.
  - [x] 2.1.2 Pepper-set describe (`vi.resetModules` + `vi.stubEnv` + dynamic import): same six paths; `sessionIdHash` equals an HMAC computed in the test with `node:crypto`; 64 hex characters; not the raw id.
  - [x] 2.1.3 Absent-id case (pepper-unset graph): empty or missing session id gives no `sessionIdHash` value and no `sessionId` key; the distinct-id must-PASS case (second sentinel gives a different hash) belongs in the pepper-set describe.
  - [x] 2.1.4 Sentinel precondition assertion (length and distinctiveness).
  - [x] 2.1.5 Haystack is NOT lowercased and each row carries a positive control (the serialized sink contains `sessionIdHash`); `afterEach` runs `vi.unstubAllEnvs()` and `vi.resetModules()`.
  - [x] 2.1.6 One real-logger case (real `createChildLogger`, `@sentry/nextjs` `addBreadcrumb` spy, stdout capture): pino line and breadcrumb carry `sessionIdHash` and not the raw sentinel.
- [x] 2.2 Edit `apps/web-platform/test/untrusted-content.test.ts` ("telemetry carries metadata only"): remove the `sessionId: "se1"` pin, add `expect(fields).not.toHaveProperty("sessionId")` and a `sessionIdHash` string-not-raw check.
- [x] 2.3 Edit `apps/web-platform/test/untrusted-content-wiring.test.ts` ("forwards the telemetry context"): hoist a fixed `SENTRY_USERID_PEPPER` in `vi.hoisted`, assert `sessionIdHash` equals the independently computed HMAC of `"sess-forwarded"`, add the negative `sessionId` assertion.
- [x] 2.4 Run the three test files and confirm 2.1 to 2.3 fail against the unchanged `emit()`.

## Phase 3: Core implementation (GREEN)

- [x] 3.1 In `emit()` replace `sessionId: ctx.sessionId,` with `sessionIdHash: ctx.sessionId ? hashUserId(ctx.sessionId) : undefined,`.
- [x] 3.2 Update the `emit()` doc comment and the `sessionId?: string` option comment (raw in, hashed at the log boundary only).
- [x] 3.3 Do not touch `cc-dispatcher.ts`, `agent-runner-query-options.ts`, `mirrorOnce`, flags or the scorer.
- [x] 3.4 Run the three targeted vitest files and `./node_modules/.bin/tsc --noEmit` from `apps/web-platform`. Do not await the slow local `--affected` battery; CI is the ship gate.
- [x] 3.5 Apply each mutation-matrix row from the plan's Guard Contract by hand once, observe RED, revert. Ran rows 1, 2, 4, 5, 6, 7 (each RED, then restored; control GREEN). Rows 3, 8, 9 were not run: 3 is a variant of 1 and 2 on one arm, 8 and 9 are harness rows covered by the sentinel precondition and the distinct-id case.

## Phase 4: Docs

- [x] 4.1 Runbook `betterstack-log-query.md`, `op:"untrusted-classify"` section: `sessionId` becomes `sessionIdHash` in the field list, plus the one-sentence lookup note.
- [x] 4.2 Append the dated addendum to the end of ADR-287 (text in the plan, Phase 4); change no earlier line.
- [x] 4.3 Run `bash scripts/markdown-lint.sh --repo-sweep` and `npx markdownlint-cli2` on the plan and this file.
- [x] 4.4 Run the ship skill's `technical-ruling-gate.sh --branch`.

## Phase 5: Ship

- [x] 5.1 Verify the diff scope against the merge-base is the planned file set (plan AC7).
- [x] 5.2 PR body: `Ref #9601`, `Ref #4671`, `Ref #10195`; state that the Article 30 PA-8(c) amendment is still owed and is operator/CLO-class, not part of this PR; state that lines already shipped keep the raw id until log retention expires; make no public security claim.
- [ ] 5.3 Hand off to CI as the ship gate; no flag, environment or production action.
