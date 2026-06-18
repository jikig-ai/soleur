---
title: "fix: live-verify harness classifies server-side send rejections as CANT-RUN not FAIL"
date: 2026-06-18
branch: feat-one-shot-live-verify-ratelimit-cantrun
type: fix
lane: single-domain
status: planned
brand_survival_threshold: none
---

# 🐛 fix: live-verify harness classifies server-side send rejections as CANT-RUN, not FAIL

## Enhancement Summary

**Deepened on:** 2026-06-18
**Passes run:** repo-research-analyst, learnings-researcher (plan phase); verify-the-negative grep pass + architecture-strategist (deepen phase). Gates 4.6/4.7/4.8/4.9 all pass.

### Key improvements from deepen-plan
1. **P0 — WS listener timing fixed.** The original plan said register `page.on("websocket")` "before the Send click." Architecture review proved the client fires `start_session` from a React effect on WS-connect during hydration (chat-surface.tsx:347-365) — BEFORE the click — and `page.on("websocket")` only captures sockets opened after attachment. The plan now registers the listener immediately after `context.newPage()`, BEFORE the first `page.goto`. Without this the fix silently fails in its own target scenario.
2. **P1 — session-rejected match narrowed.** Changed from the broad `"No active session"` substring to the start-rejection signature `"Send start_session first"`. Four ws-handler sites share the bare `"No active session."` prefix; three (2094/2441/2509) signal an *established*-session drop (a genuine FAIL class) that the broad match would have masked. Added a negative test AC2b.
3. **P2 — teardown ordering + no-clobber pinned.** The short-circuit CANT-RUN must `return` BEFORE the `teardownConversation` call (else `CANT-TEARDOWN-empty-predicate` masks the reason); `latestWsError` is monotonic-once-set (success frames parse to `null`). Added AC6b.
4. **Wording corrections** from the verify-the-negative pass: clarified that the CONFIG/catch CANT-RUN paths (run.ts:602/628) DO `redact()`/set `exitCode=1`, while the new driveAndVerify CANT-RUN returns keep exit 0 by construction (AC7b).

### Confirmed sound (no change needed)
- App WS URL `/ws` vs Supabase realtime `/realtime/v1/websocket` filter (R-2).
- `errorCode: "rate_limited"` already in `WSErrorCode` (no type change).
- Playwright 1.58 API shapes (`page.on("websocket")`, `ws.url()`, `ws.on("framereceived", {payload})`).
- AC4 precedence (rate_limited > convId) is safe: `sinceIso` high-water mark + `reapOrphans` make a coexisting stale fresh-convId unreachable within one run.
- Test file location `test/live-verify/` collected by vitest `unit` project; pure-function extraction matches repo precedent.

## Overview

The post-deploy live-verify harness (`apps/web-platform/scripts/live-verify/run.ts`,
ADR-064) drives the deployed prod app under a synthetic principal and asserts that
a freshly-started conversation persists and appears in the Recent Conversations
rail (the #5391/#5421/#5436 rail-race regression class). Today `driveAndVerify`
verifies persistence **only** by polling the `conversations` table
(`pollFreshConversationId`) — it never inspects the app's WebSocket frames.

**The bug:** when the synthetic principal's `start_session` is rejected by the
`start_session` rate limiter (`apps/web-platform/server/start-session-rate-limit.ts`
— 10 start_session/user/hour, 30/IP/hour, process-local, enforced unconditionally
at `apps/web-platform/server/ws-handler.ts:1601-1617`), the server emits an error
frame `{ type: "error", errorCode: "rate_limited", message: "Rate limited: too many
conversations this hour." }`, no conversation persists, and the subsequent chat
frame is answered `{ type: "error", message: "No active session. Send start_session
first." }` (ws-handler.ts:2135). The poll then times out at 30s and the harness
returns **`RESULT: FAIL`** — identical to a genuine rail-race regression. The
synthetic principal shares this per-hour budget across local runs AND CI (same prod
ws-handler process, same `userId`), so rate-limit exhaustion is a realistic, recurring
false-FAIL.

This is the **prerequisite** for the separately-tracked report-only→blocking
deploy-gate flip (#5463 item 4). Once that gate is blocking, a rate-limited run
would FALSE-FAIL and block a legitimate deploy. **This PR is NOT the flip** — it does
not touch the gate's `continue-on-error`, job topology, or `web-platform-release.yml`
at all (the existing `RESULT: CANT-RUN*` case at `web-platform-release.yml:692` already
routes any CANT-RUN to report-only warning level — see Research Reconciliation row R5).

**The fix:** subscribe to the app WebSocket (`wss://<prodHost>/ws`) via Playwright's
`page.on("websocket")` filtered by URL path `/ws`, capture server **error** frames,
and map a `rate_limited` errorCode → `CANT-RUN:rate-limited` and a "No active session"
message → `CANT-RUN:session-rejected`, short-circuiting the 30s poll so the WS-error
signal wins over the poll timeout. Genuine FAIL (session established, conversation
should persist but doesn't within the unchanged 30s budget — the rail-race class) is
preserved.

## Research Reconciliation — Spec vs. Codebase

The feature description was paraphrased; three claims diverge from `origin`/worktree reality:

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| R1: "extend the harness unit tests … `apps/web-platform/scripts/live-verify/run.test.ts`" | **No such file exists.** Existing live-verify tests live in `apps/web-platform/test/live-verify/*.test.ts` (`gate.test.ts`, `cookie-injection.test.ts`, `redact.test.ts`, `trigger.test.ts`, `redact-stdin.test.ts`). The vitest `unit` project glob is `test/**/*.test.ts` (`vitest.config.ts:44`); a co-located `scripts/live-verify/run.test.ts` would **never be collected**. | Write the new test as `apps/web-platform/test/live-verify/drive-result-ws-error.test.ts`, importing the extracted pure function from `../../scripts/live-verify/run`. |
| R2: "in run.ts `driveAndVerify`" is the testable unit | `driveAndVerify` is a **private, non-exported** async fn that launches a real browser inline (run.ts:336) — untestable without Playwright. The repo precedent is to **extract** the testable logic as exported pure functions (`buildLaunchOptions`, `buildInjectedCookies`, `pollFreshConversationId`) and unit-test those. | Extract a pure `classifyDriveResult` function (the poll-vs-WS-error race + classification) + a pure `parseWsErrorFrame` helper; `driveAndVerify` calls them. Tests drive the pure functions with mocked WS-error captures — never a real browser. |
| R3: `errorCode: "rate_limited"` is a new code | Already a member of `WSErrorCode` (`apps/web-platform/lib/types.ts:154`). The error frame shape `{ type, message, errorCode? }` is confirmed at ws-handler.ts:1611-1615. | No type change; the harness only **reads** the frame. |
| R4 (Playwright API): `page.on("websocket")` / `ws.on("framereceived")` shapes | Verified against installed `@playwright/test@^1.58.2`: `page.on('websocket', (ws: WebSocket) => …)`, `ws.url(): string`, `ws.on('framereceived', (data: { payload: string \| Buffer }) => …)` (`playwright-core/types/types.d.ts:1173, 21087, 21096`). | Use these exact shapes; no fabricated API. |
| R5 (CI gate): "do NOT touch the gate" | `web-platform-release.yml:692` already maps `"RESULT: CANT-RUN"*` → `RESULT="CANT-RUN"; LEVEL="warning"` (report-only). New reasons flow through unchanged. The harness step has `continue-on-error: true` and the job has no dependents (report-only by topology). | **Zero workflow edits.** Confirmed the constraint is naturally satisfied. |

## User-Brand Impact

This is a CI/test-tooling change to a **report-only** post-deploy harness. It does not
touch any user-facing surface, schema, auth, or persisted data; the synthetic
principal is the only account exercised, read-mostly + conversation-scoped (ADR-064
I-blast-radius).

- **If this lands broken, the user experiences:** nothing directly. Worst case is a
  harness regression that mislabels a genuine rail-race FAIL as CANT-RUN (a false
  negative on the gate) — caught by the unchanged genuine-FAIL test path (FR3) and by
  the report-only Sentry event; no end-user impact because the gate is still report-only.
- **If this leaks, the user's data is exposed via:** N/A — the change only *reads* WS
  **error** frames (never the auth/`start_session` frames that carry tokens) and routes
  detail through the existing `redact()` boundary; no new capture surface persists.
- **Brand-survival threshold:** none — report-only CI tooling, synthetic principal,
  no regulated-data surface. (Justification per preflight Check 6: the diff touches
  `apps/web-platform/scripts/live-verify/*` + `apps/web-platform/test/live-verify/*`
  only — no schema/auth/API/`.sql` surface; reason: report-only test harness, no
  end-user data path.)

## Root cause (verified WS trace, 2026-06-18)

```
client → start_session frame
server → { type:"error", errorCode:"rate_limited",
           message:"Rate limited: too many conversations this hour." }   ws-handler.ts:1611-1615
client → chat frame
server → { type:"error", message:"No active session. Send start_session first." }  ws-handler.ts:2135
```

No `conversations` row is materialized (rows materialize only on the first message —
ws-handler.ts:2164 / ADR-064 I-action-send-free note), so `pollFreshConversationId`
(run.ts:485) times out at 30s and `driveAndVerify` returns the FAIL at run.ts:431-437.

## Files to Edit

- **`apps/web-platform/scripts/live-verify/run.ts`** — the load-bearing change:
  - **Add** exported pure `parseWsErrorFrame(payload: string): { errorCode?: string; message?: string } | null` — `JSON.parse` inside try/catch; return `null` for non-`{type:"error"}` frames or parse failures; return ONLY `{ errorCode, message }` (never the raw payload object). *Only error frames are parsed* (ADR-064 I-ephemerality; the auth/`start_session` frames carry a token and are never parsed).
  - **Add** an exported pure classifier, e.g.
    `classifyDriveResult(args: { convId: string | null; wsError: { errorCode?: string; message?: string } | null }): Result` —
    precedence: (1) `wsError?.errorCode === "rate_limited"` → `{ kind:"CANT-RUN", reason:"rate-limited" }`; (2) `wsError?.message?.includes("Send start_session first")` → `{ kind:"CANT-RUN", reason:"session-rejected" }` — **match the start-rejection signature `"Send start_session first"`, NOT the broad substring `"No active session"` (P1).** Four ws-handler sites emit a bare `"No active session."` (ws-handler.ts:2094/2441/2509) for an *established* session that later lost its `conversationId` — matching the broad prefix would misclassify a genuine mid-run session-drop (a real failure adjacent to the rail-race class) as session-rejected and suppress it. Only the chat-path start-rejection (ws-handler.ts:2135, `"No active session. Send start_session first."`) carries the `"Send start_session first"` tail. (3) `convId` truthy → caller proceeds to the rail assertion (return a sentinel/`PASS`-precursor or have the caller branch — design the seam so the rail assertion stays in `driveAndVerify`); (4) `convId` null + no wsError → `{ kind:"FAIL", detail:"send did not persist a conversation within budget …" }` (the existing genuine-FAIL string, unchanged). *Pin the exact return contract in the implementation so FR1/FR2/FR3 tests assert on `kind` + `reason`/`detail`.*
  - **Wire** a WS-error capture into `driveAndVerify`: register `page.on("websocket", (ws) => { if (new URL(ws.url()).pathname === "/ws") ws.on("framereceived", ({ payload }) => { const e = parseWsErrorFrame(payload.toString()); if (e) latestWsError = e; }); })` **immediately after `context.newPage()` and BEFORE the first `page.goto`** (both the dry-run goto and the gate goto). **This timing is load-bearing (P0):** the client fires `start_session` from a React effect the instant the WS reaches `status === "connected"` (chat-surface.tsx:347-365), which happens during page-load hydration — BEFORE the Send click — and `page.on("websocket")` only captures sockets opened AFTER the listener is attached. Registering after `page.goto` (or "before the Send click") would miss the `start_session` rate_limited frame entirely and the harness would false-FAIL in exactly the scenario this fix targets. **Filter by URL path `/ws`** — do NOT match the Supabase realtime socket (its path is `/realtime/v1/websocket`, confirmed absent from prod source — only a test fixture references it). Hold the latest server **error frame** in a closure var `latestWsError`; it is set ONLY by `parseWsErrorFrame` (which returns `null` for non-error frames), so a later success frame (e.g. `conversation_created`) can NEVER clear a stored error — `latestWsError` is monotonic-once-set by error frames only.
  - **Race-safety / short-circuit:** after the Send click, before/around the 30s poll, check `latestWsError` so a `rate_limited`/`session-rejected` error returns its CANT-RUN immediately instead of waiting out the full 30s then returning FAIL. Concretely: run `classifyDriveResult` against `latestWsError` first; if it yields a CANT-RUN, **`return` it directly — BEFORE the `teardownConversation` call site (run.ts:468)**, never after. No row was created on a rejection, so there is nothing to tear down; falling through to teardown with an empty `convId` would return `CANT-RUN:CANT-TEARDOWN-empty-predicate` and MASK the rate-limited/session-rejected reason (P2 guardrail). Otherwise poll as today and re-classify. (The poll loop MAY also break early when `latestWsError` becomes a short-circuit error mid-poll — keep it simple: a check before the poll plus a check inside the existing 1s poll tick. JS is single-threaded, so the `framereceived` callback runs to completion between `await`s — a check before the poll + per-tick is race-adequate.)
  - **Redaction:** never `console.log`/emit a raw WS payload; only `parseWsErrorFrame`'d `{errorCode,message}` ever reaches a `detail` string, and `emit()` already `redact()`s `detail`. CANT-RUN `reason` strings are flat safe literals (`rate-limited`, `session-rejected`) carrying no captured value — consistent with the existing taxonomy (`send-button-never-enabled:ws-not-connected`, `browser-launch:<name>`).
  - Keep the **30s poll budget** and the **rail assertion** (`railRow.waitFor`, run.ts:448-465) unchanged. Genuine FAIL is the `convId` persisted but rail-absent branch (run.ts:462-465) **and** the `convId` null + no-wsError branch.

- **`apps/web-platform/test/live-verify/drive-result-ws-error.test.ts`** *(new)* — see Test Scenarios. Imports `{ classifyDriveResult, parseWsErrorFrame, type Result }` from `../../scripts/live-verify/run`. No browser, no Supabase needed for these pure tests.

- **`knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`** — append the two new reasons to the harness's CANT-RUN taxonomy (currently enumerated at lines 88 and 182): add `CANT-RUN:rate-limited` and `CANT-RUN:session-rejected` (server rejected the send; surfaced non-blocking, NOT a rail regression). One-paragraph amendment under the existing "report-only / detect-fast gate" framing; `status` stays `accepted` (extension, not reversal). See Architecture Decision section.

## Files to Create

- `apps/web-platform/test/live-verify/drive-result-ws-error.test.ts` (above).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (FR1):** `classifyDriveResult({ convId: null, wsError: { errorCode: "rate_limited", message: "Rate limited: too many conversations this hour." } })` returns `{ kind: "CANT-RUN", reason: "rate-limited" }`.
- [ ] **AC2 (FR2):** `classifyDriveResult({ convId: null, wsError: { message: "No active session. Send start_session first." } })` returns `{ kind: "CANT-RUN", reason: "session-rejected" }`. **AC2b (negative — P1 over-match guard):** `classifyDriveResult({ convId: null, wsError: { message: "No active session." } })` (the bare established-session-drop message, WITHOUT the `"Send start_session first"` tail) returns `{ kind: "FAIL", … }` — it must NOT be classified session-rejected.
- [ ] **AC3 (FR3 — unchanged genuine-FAIL):** `classifyDriveResult({ convId: null, wsError: null })` returns `{ kind: "FAIL", … }` (no WS error, no persisted row → FAIL — the rail-race regression class is preserved).
- [ ] **AC4 (precedence/race):** when both a `convId` and a `rate_limited` `wsError` are present, the `rate_limited` CANT-RUN wins (the WS-error signal short-circuits over a stale/leftover poll match). *(Encodes the "WS-error wins over the poll timeout" requirement at the pure-function boundary.)*
- [ ] **AC5 (`parseWsErrorFrame` ignores non-error frames):** `parseWsErrorFrame('{"type":"conversation_created","id":"…"}')` and `parseWsErrorFrame('not json')` both return `null`; `parseWsErrorFrame('{"type":"error","errorCode":"rate_limited","message":"…"}')` returns `{ errorCode:"rate_limited", message:"…" }` and nothing else (no `type`, no raw payload object).
- [ ] **AC6 (no raw payload leak):** grep `run.ts` proves no `console.log`/template-literal emits a `payload` variable directly; the only stdout emit path is `emit(result)`. (`git grep -n "payload" apps/web-platform/scripts/live-verify/run.ts` — every hit is inside `parseWsErrorFrame` or the `framereceived` listener, never an emit.) NOTE: the new `rate-limited`/`session-rejected` CANT-RUN reasons are flat safe literals carrying no captured value; `emit()` formats CANT-RUN as `RESULT: CANT-RUN:${reason}` without `redact()` (the existing CONFIG/catch CANT-RUN paths at run.ts:602/628 already `redact()` THEIR messages because those embed `error.message` — the new driveAndVerify reasons need no redaction by construction).
- [ ] **AC6b (no-clobber):** a success frame arriving AFTER an error frame does not clear the verdict — `parseWsErrorFrame` returns `null` for a non-error frame so the `if (e) latestWsError = e` guard never overwrites a stored error. (Pure-function analog: `classifyDriveResult({ convId: "…uuid…", wsError: { errorCode: "rate_limited" } })` still returns CANT-RUN:rate-limited per AC4 — covered — plus a code-comment pinning the monotonic-once-set property on the listener.)
- [ ] **AC7 (WS-URL filter + listener timing):** the `page.on("websocket")` listener filters on `new URL(ws.url()).pathname === "/ws"` (does NOT match `/realtime/v1/websocket`) AND is registered immediately after `context.newPage()`, BEFORE the first `page.goto` (so the hydration-time `start_session` frame is captured — P0). *(Static assertion; verified by reading the listener placement.)*
- [ ] **AC7b (exit-code parity):** the driveAndVerify CANT-RUN returns keep `process.exitCode` at 0 (only `FAIL` sets `process.exitCode = 1` at run.ts:623; the CONFIG/catch CANT-RUN paths set it for pre-launch gate failures, which is unchanged). The new CANT-RUN reasons flow through `emit()` with exit 0, consistent with `browser-launch:*` / `send-button-never-enabled:*`.
- [ ] **AC8 (no workflow change):** `git diff --name-only origin/main...HEAD` does NOT include `.github/workflows/web-platform-release.yml`. The gate's `continue-on-error`, job topology, and `RESULT: CANT-RUN*` case are untouched.
- [ ] **AC9 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] **AC10 (tests green):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/drive-result-ws-error.test.ts` passes; the full existing `test/live-verify/*` suite still passes (no regression to `gate.test.ts`/`cookie-injection.test.ts`).
- [ ] **AC11 (ADR amended):** ADR-064 CANT-RUN taxonomy lists `rate-limited` and `session-rejected`; `status` remains `accepted`.

### Post-merge (operator)

- None. Report-only gate; no migration, no infra, no operator action. The harness fires on the next `web-platform-release.yml` run that touches a triggering path; the new CANT-RUN reasons surface as report-only Sentry warning events automatically.

## Test Scenarios

Write the failing test FIRST (RED), then implement to GREEN (`cq-write-failing-tests-before`). All scenarios drive the **pure** `classifyDriveResult` / `parseWsErrorFrame` with mocked inputs — never a real browser (the "remove the browser from the assertion path" principle, learning `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` + `2026-06-17-mock-e2e-cannot-verify-deployed-realtime…`).

```ts
// apps/web-platform/test/live-verify/drive-result-ws-error.test.ts
import { describe, expect, it } from "vitest";
import { classifyDriveResult, parseWsErrorFrame } from "../../scripts/live-verify/run";

describe("classifyDriveResult — server-send-rejection → CANT-RUN", () => {
  it("AC1: rate_limited errorCode → CANT-RUN:rate-limited", () => {
    const r = classifyDriveResult({
      convId: null,
      wsError: { errorCode: "rate_limited", message: "Rate limited: too many conversations this hour." },
    });
    expect(r).toEqual({ kind: "CANT-RUN", reason: "rate-limited" });
  });
  it("AC2: 'No active session. Send start_session first.' → CANT-RUN:session-rejected", () => {
    const r = classifyDriveResult({
      convId: null,
      wsError: { message: "No active session. Send start_session first." },
    });
    expect(r).toEqual({ kind: "CANT-RUN", reason: "session-rejected" });
  });
  it("AC2b: bare 'No active session.' (established-session drop) → FAIL, NOT session-rejected", () => {
    const r = classifyDriveResult({
      convId: null,
      wsError: { message: "No active session." },
    });
    expect(r.kind).toBe("FAIL");
  });
  it("AC3: no WS error + no row → FAIL (genuine rail-race class preserved)", () => {
    const r = classifyDriveResult({ convId: null, wsError: null });
    expect(r.kind).toBe("FAIL");
  });
  it("AC4: rate_limited wins over a present convId (WS-error short-circuit)", () => {
    const r = classifyDriveResult({
      convId: "11111111-1111-1111-1111-111111111111",
      wsError: { errorCode: "rate_limited" },
    });
    expect(r).toEqual({ kind: "CANT-RUN", reason: "rate-limited" });
  });
});

describe("parseWsErrorFrame — only error frames, no raw payload", () => {
  it("AC5a: non-error frame → null", () => {
    expect(parseWsErrorFrame('{"type":"conversation_created","id":"x"}')).toBeNull();
  });
  it("AC5b: non-JSON → null", () => {
    expect(parseWsErrorFrame("not json")).toBeNull();
  });
  it("AC5c: error frame → only {errorCode,message}", () => {
    expect(parseWsErrorFrame('{"type":"error","errorCode":"rate_limited","message":"m"}'))
      .toEqual({ errorCode: "rate_limited", message: "m" });
  });
});
```

> NOTE on the `classifyDriveResult` seam: design the function so the rail assertion stays inside `driveAndVerify`. Option A — `classifyDriveResult` returns a `Result | { kind: "PROCEED"; convId: string }` discriminated result and the caller runs the rail `waitFor` on `PROCEED`. Option B — `classifyDriveResult` returns only the short-circuit cases (`CANT-RUN`/`FAIL`/`null`) and `null` means "no verdict yet, run the rail assertion." Pick whichever keeps `Result`'s three public kinds unchanged; the tests above assert only the short-circuit verdicts so either seam satisfies them. **Decide the seam at /work time and pin it in a one-line comment.**

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-064** (`…/decisions/ADR-064-live-production-verification-harness.md`) — append `CANT-RUN:rate-limited` and `CANT-RUN:session-rejected` to the harness's CANT-RUN taxonomy (the reason set currently enumerated at lines 88/182), under the existing "detect-fast, report-only gate; CANT-RUN reasons are surfaced non-blocking" framing. This is an **extension** of the recorded decision (a new pair of CANT-RUN reasons distinguishing a server-side send rejection from a genuine rail regression), **not** a reversal: the substrate (GH-Action in `web-platform-release.yml`), the I-* invariants, and the report-only-by-topology property are all unchanged. `status` stays `accepted`.

### C4 views
**No C4 impact** — verified by reading all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration checked and found NOT to require an edit:
- **External human actors:** none added. No new correspondent/reviewer/recipient — the synthetic principal is an internal test fixture, not an external actor.
- **External systems / vendors:** none added. The WS subscription reads `wss://<prodHost>/ws`, an **internal** endpoint of the already-existing (though, separately, unmodeled) web-platform container; the Supabase realtime socket is explicitly **excluded**. No new inbound webhook, outbound API, or third-party store.
- **Containers / data stores:** none touched beyond the existing `conversations` poll (read-only, unchanged).
- **Access relationships:** none changed — the harness's existing "harness → deployed web-platform + prod Supabase" relationship is unchanged in endpoints (ADR-064 already records this edge as driver-only-changed).

*(Pre-existing gap, explicitly out of scope: the live-verify harness itself is not modeled as a C4 element today — `grep live.verify *.c4` returns zero. That omission predates this change and is not introduced by it; modeling the harness is a separate ADR-064 follow-up, not a deliverable of this fix.)*

## Observability

```yaml
liveness_signal:
  what: "RESULT: CANT-RUN:rate-limited / RESULT: CANT-RUN:session-rejected lines emitted by run.ts emit()"
  cadence: "per web-platform-release.yml run that triggers the live-verify gate"
  alert_target: "Sentry (gate:live-verify event, level=warning), GITHUB_STEP_SUMMARY"
  configured_in: ".github/workflows/web-platform-release.yml live-verify job (UNCHANGED — existing CANT-RUN case at :692 routes the new reasons)"
error_reporting:
  destination: "Sentry report-only event {gate:live-verify, result:CANT-RUN} + Actions run log (redacted stream)"
  fail_loud: "true — a CANT-RUN is a distinct, queryable warning event, never a silent pass; the reason string (rate-limited|session-rejected) is embedded in the Sentry message"
failure_modes:
  - mode: "rate-limit exhaustion of the synthetic principal's start_session budget"
    detection: "WS error frame errorCode=rate_limited captured → CANT-RUN:rate-limited"
    alert_route: "Sentry warning event (report-only); distinguishable from FAIL"
  - mode: "start_session refused so chat send hits 'No active session'"
    detection: "WS error frame message contains 'No active session' → CANT-RUN:session-rejected"
    alert_route: "Sentry warning event (report-only)"
  - mode: "genuine rail-race regression (session established, no row / row not in rail within 30s)"
    detection: "poll timeout with NO short-circuit WS error → FAIL"
    alert_route: "Sentry error event (report-only today; the signal the #5463 blocking flip will gate on)"
logs:
  where: "GitHub Actions run log for the live-verify job (redacted via redact-stdin.ts stream), single RESULT line + Sentry event"
  retention: "GitHub Actions default log retention; Sentry event retention"
discoverability_test:
  command: "gh run list --workflow web-platform-release.yml --json databaseId,conclusion ; gh run view <id> --log | grep -E 'RESULT: CANT-RUN:(rate-limited|session-rejected)'   # gh-CLI only, no remote shell"
  expected_output: "the RESULT line and/or a Sentry warning event with reason rate-limited|session-rejected"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a CI test-harness change (no user-facing
surface, no schema, no auth, no payments, no marketing/legal/ops surface). Infrastructure/
tooling change.

## Risks & Mitigations

- **R-1 (false short-circuit):** a non-`rate_limited`/non-"No active session" error frame
  must NOT short-circuit to CANT-RUN (it would mask a genuine FAIL). *Mitigation:*
  `classifyDriveResult` matches ONLY the two explicit error signatures; any other captured
  error leaves the verdict to the poll → genuine FAIL path. AC3 + AC4 lock this.
- **R-2 (wrong socket):** matching the Supabase realtime socket would capture unrelated
  frames (and its frames carry `access_token`/`apikey` in the URL). *Mitigation:* filter
  `new URL(ws.url()).pathname === "/ws"`; the realtime socket path is `/realtime/v1/websocket`
  (AC7). The app WS URL is `${proto}://${window.location.host}/ws` (ws-client.ts:722).
- **R-3 (payload leak):** raw WS payloads can embed the auth token (the `start_session`/auth
  frame). *Mitigation:* only `parseWsErrorFrame` (type:"error" frames) is ever read; it
  returns only `{errorCode,message}`; nothing else reaches a `detail` string; `emit()`
  `redact()`s `detail`. AC5 + AC6 lock this. (Stream-level redaction via `redact-stdin.ts`
  in CI is a pre-existing second layer.)
- **R-4 (race timing):** the `rate_limited` error frame and the poll deadline race.
  *Mitigation:* the closure var `latestWsError` is checked BEFORE the poll and inside each
  1s poll tick, so a captured short-circuit error wins deterministically over the 30s
  timeout (the learning `2026-03-27-ws-session-race-abort-before-replace.md` synchronous-check
  pattern). AC4 encodes the precedence at the pure-function boundary.
- **R-5 (seam leaks a 4th Result kind):** the new classifier must not widen `Result`'s
  public discriminants. *Mitigation:* `Result` stays `PASS | FAIL | CANT-RUN`; any
  intermediate "PROCEED"/`null` seam is internal to the classifier↔caller contract, not
  exported as a `Result` member. The existing `gate.test.ts` import of `Result` is unchanged.

## Optional follow-up (PR body only — do NOT implement here)

Widening or exempting the per-hour `start_session` cap for the allowlisted live-verify
UID (`apps/web-platform/server/start-session-rate-limit.ts` +
`apps/web-platform/server/ws-handler.ts:1600-1617`) would prevent the rate-limit
rejection at its source. **Deliberately out of scope:** the CANT-RUN classification is the
load-bearing fix (it correctly classifies the rejection regardless of cause); a server-side
cap exemption is a separate change with DoS-surface tradeoffs (an allowlisted UID bypass is
a new attack-shape if the allowlist ever leaks) and belongs in its own PR. Mention in the PR
body; file a tracking issue only if the operator wants to pursue it.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Parse `conversations`-table absence + a separate Supabase query for rate-limit state | Rejected — the rate limiter is process-local (`start-session-rate-limit.ts:14-16`), no DB row to query; the WS error frame is the only signal. |
| Match the Supabase realtime socket too (capture all frames) | Rejected — wrong socket, and its URL carries `access_token`/`apikey` (R-2/R-3). |
| Test `driveAndVerify` directly with a mocked Playwright page | Rejected — heavier, brittle (`page.on` plumbing), and the repo precedent is pure-function extraction (R2). The classification logic is the part with bugs; extract + unit-test it. |
| Server-side cap exemption instead of harness classification | Deferred to optional follow-up (above) — separate concern, DoS tradeoff. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's threshold
  is `none` with the sensitive-path scope-out reason recorded.)
- The new test file MUST live under `apps/web-platform/test/live-verify/` (vitest `unit`
  glob `test/**/*.test.ts`); a co-located `scripts/live-verify/*.test.ts` is silently never
  collected (R1). Typecheck/test commands are the in-package binaries
  (`./node_modules/.bin/tsc --noEmit`, `./node_modules/.bin/vitest run …`) — NOT
  `npm run -w` (no root `workspaces` field).
- `errorCode: "rate_limited"` is already a `WSErrorCode` member — do NOT re-declare it; the
  harness only reads the frame.
