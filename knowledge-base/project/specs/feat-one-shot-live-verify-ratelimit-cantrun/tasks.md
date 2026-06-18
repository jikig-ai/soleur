# Tasks — fix: live-verify classifies server-side send rejections as CANT-RUN

Plan: `knowledge-base/project/plans/2026-06-18-fix-live-verify-ws-error-cant-run-plan.md`
Lane: single-domain (no spec.md present; default per plan frontmatter)

## Phase 1 — RED (failing tests first; cq-write-failing-tests-before)

- [ ] 1.1 Create `apps/web-platform/test/live-verify/drive-result-ws-error.test.ts` importing
      `{ classifyDriveResult, parseWsErrorFrame }` from `../../scripts/live-verify/run`
      (these do not exist yet → tests fail to compile/run = RED).
- [ ] 1.2 Encode AC1-AC5 (rate_limited→CANT-RUN:rate-limited; "No active session"→
      CANT-RUN:session-rejected; no-error+no-row→FAIL; rate_limited wins over present
      convId; parseWsErrorFrame ignores non-error/non-JSON, returns only {errorCode,message}).
- [ ] 1.3 Confirm RED: `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/drive-result-ws-error.test.ts` fails.

## Phase 2 — GREEN (implement in run.ts)

- [ ] 2.1 Add exported pure `parseWsErrorFrame(payload: string)` — JSON.parse in try/catch;
      null for non-`{type:"error"}` / parse failure; return ONLY `{errorCode,message}` (never raw payload).
- [ ] 2.2 Add exported pure `classifyDriveResult({ convId, wsError })` with precedence:
      rate_limited → CANT-RUN:rate-limited; **`message.includes("Send start_session first")`** →
      CANT-RUN:session-rejected (P1 — NOT the broad "No active session" substring, which also
      matches established-session drops at ws-handler.ts:2094/2441/2509 → FAIL); else convId-driven
      seam (PROCEED/null) for the rail assertion; convId null + no wsError → FAIL.
      Keep `Result`'s three public kinds unchanged (R-5). Pin the seam choice in a one-line comment.
- [ ] 2.3 Wire WS-error capture into `driveAndVerify`: `page.on("websocket")` filtered on
      `new URL(ws.url()).pathname === "/ws"` (NOT /realtime/v1/websocket); `ws.on("framereceived",
      ({payload}) => { const e = parseWsErrorFrame(payload.toString()); if (e) latestWsError = e; })`.
      **Register immediately after `context.newPage()`, BEFORE the first `page.goto` (P0 — start_session
      fires on WS-connect during hydration, before the Send click; a listener attached after goto misses
      the rate_limited frame).** latestWsError is monotonic-once-set (success frames parse to null).
- [ ] 2.4 Race short-circuit: check `latestWsError` via `classifyDriveResult` BEFORE the 30s poll
      and inside each 1s poll tick so a rate_limited/session-rejected error wins over the timeout.
      **`return` the short-circuit CANT-RUN BEFORE the teardownConversation call (run.ts:468)** — no row
      to tear down; falling through would mask the reason with CANT-TEARDOWN-empty-predicate (P2).
      Keep the 30s poll budget + rail assertion (run.ts:448-465) unchanged.
- [ ] 2.5 Confirm GREEN: the new test passes; full `test/live-verify/*` suite still passes.

## Phase 3 — ADR amend + verification

- [ ] 3.1 Amend ADR-064: append `CANT-RUN:rate-limited` + `CANT-RUN:session-rejected` to the
      CANT-RUN taxonomy (lines ~88/182), status stays `accepted` (AC11).
- [ ] 3.2 AC6/AC7 static greps: no raw `payload` emit; WS-URL filter is `/ws` not realtime.
- [ ] 3.3 AC8: `git diff --name-only origin/main...HEAD` excludes `.github/workflows/web-platform-release.yml`.
- [ ] 3.4 AC9 typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 3.5 AC10 tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/`.

## Phase 4 — Ship

- [ ] 4.1 PR body: note the optional server-side cap-exemption follow-up (do NOT implement);
      `Ref` the relevant issue (NOT a blocking-flip; this is the prerequisite).
- [ ] 4.2 Review + merge per ship lifecycle. No post-merge operator action (report-only gate).
