# Tasks: hash the sessionId on the untrusted-classify log line

Plan: `knowledge-base/project/plans/2026-11-08-fix-untrusted-classify-session-id-hash-plan.md`
Ref #9601 (epic, slice 2), Ref #4671, Ref #10195. Single small PR; no flag, scorer or other surface changes.

## Phase 1: Setup

- [ ] 1.1 Confirm the worktree and branch (`feat-one-shot-9601-untrusted-classify-session-hash`) and that PR 12415 is the draft for this branch.
- [ ] 1.2 Re-read `emit()` in `apps/web-platform/server/untrusted-content.ts` and confirm `hashUserId` is already imported from `./observability`.

## Phase 2: Tests first (RED)

- [ ] 2.1 Create `apps/web-platform/test/untrusted-content-session-hash.test.ts` with the logger and `mirrorWithDebounce` mocks.
  - [ ] 2.1.1 Pepper-unset describe (`SENTRY_USERID_PEPPER` deleted in `vi.hoisted`): six emit paths (flagged, unflagged, truncated-only, flagged and truncated, unscored shape, unscored error); assert no `sessionId` own key, `sessionIdHash === "pepper_unset"`, raw sentinel absent from every serialized sink (four logger methods and `mirrorWithDebounce` calls), and an emit-count floor of six.
  - [ ] 2.1.2 Pepper-set describe (`vi.resetModules` + `vi.stubEnv` + dynamic import): same six paths; `sessionIdHash` equals an HMAC computed in the test with `node:crypto`; 64 hex characters; not the raw id.
  - [ ] 2.1.3 Absent-id and distinct-id cases: empty or missing session id gives no `sessionIdHash` value and no `sessionId` key; a second sentinel id gives a different hash.
  - [ ] 2.1.4 Sentinel precondition assertion (length and distinctiveness).
- [ ] 2.2 Edit `apps/web-platform/test/untrusted-content.test.ts` ("telemetry carries metadata only"): remove the `sessionId: "se1"` pin, add `expect(fields).not.toHaveProperty("sessionId")` and a `sessionIdHash` string-not-raw check.
- [ ] 2.3 Edit `apps/web-platform/test/untrusted-content-wiring.test.ts` ("forwards the telemetry context"): hoist a fixed `SENTRY_USERID_PEPPER` in `vi.hoisted`, assert `sessionIdHash` equals the independently computed HMAC of `"sess-forwarded"`, add the negative `sessionId` assertion.
- [ ] 2.4 Run the three test files and confirm 2.1 to 2.3 fail against the unchanged `emit()`.

## Phase 3: Core implementation (GREEN)

- [ ] 3.1 In `emit()` replace `sessionId: ctx.sessionId,` with `sessionIdHash: ctx.sessionId ? hashUserId(ctx.sessionId) : undefined,`.
- [ ] 3.2 Update the `emit()` doc comment and the `sessionId?: string` option comment (raw in, hashed at the log boundary only).
- [ ] 3.3 Do not touch `cc-dispatcher.ts`, `agent-runner-query-options.ts`, `mirrorOnce`, flags or the scorer.
- [ ] 3.4 Run the three targeted vitest files and `./node_modules/.bin/tsc --noEmit` from `apps/web-platform`. Do not await the slow local `--affected` battery; CI is the ship gate.
- [ ] 3.5 Apply each mutation-matrix row from the plan's Guard Contract by hand once, observe RED, revert.

## Phase 4: Docs

- [ ] 4.1 Runbook `betterstack-log-query.md`, `op:"untrusted-classify"` section: `sessionId` becomes `sessionIdHash` in the field list, plus the one-sentence lookup note.
- [ ] 4.2 Append the dated addendum to the end of ADR-287 (text in the plan, Phase 4); change no earlier line.
- [ ] 4.3 Run `bash scripts/markdown-lint.sh --repo-sweep` and `npx markdownlint-cli2` on the plan and this file.
- [ ] 4.4 Run the ship skill's `technical-ruling-gate.sh --branch`.

## Phase 5: Ship

- [ ] 5.1 Verify the diff scope against the merge-base is the planned file set (plan AC7).
- [ ] 5.2 PR body: `Ref #9601`, `Ref #4671`, `Ref #10195`; state that the Article 30 PA-8(c) amendment is still owed and is operator/CLO-class, not part of this PR; state that lines already shipped keep the raw id until log retention expires; make no public security claim.
- [ ] 5.3 Hand off to CI as the ship gate; no flag, environment or production action.
