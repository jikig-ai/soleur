# fix: /api/analytics/track hardening bundle (memory leak, IP-spoof, PII, log-injection)

**Issue:** [#2383](https://github.com/jikig-ai/soleur/issues/2383)
**Branch:** `feat-analytics-track-hardening`
**Worktree:** `.worktrees/feat-analytics-track-hardening/`
**Milestone:** Phase 3: Make it Sticky
**Labels:** `priority/p2-medium`, `type/security`, `code-review`, `deferred-scope-out`
**Type:** Security hardening (bug-fix bundle)
**Status:** Deepened 2026-04-17

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Implementation Phases (5), Test Scenarios, Rollout / Risk, plus two new sections (Institutional Learnings Applied, Verified API Signatures)
**Research sources used:** repo grep (route.ts, throttle.ts, rate-limiter.ts, validate-origin.ts, analytics-client.ts, existing test file), 8 institutional learnings in `knowledge-base/project/learnings/`, AGENTS.md code-quality rules

### Key Improvements Added During Deepen Pass

1. **Confirmed exact `SlidingWindowCounter` API** (`prune()`, `get size`, `reset()` — all exist at `server/rate-limiter.ts:81,100,105`). Removed ambiguity in T2 test spec.
2. **Identified a test-mock blocker for T5.** Existing mock returns a *fresh* `vi.fn()` per `createChildLogger()` call, so the current harness cannot assert on `log.warn` arguments. T5 requires restructuring the mock to share spies — this is now called out as task 1.1 with a concrete code example. Without this edit, T5 would silently pass with 0 assertions.
3. **Removed `forwardedFor` convenience from test helper.** The existing `makeRequest` only sets `x-forwarded-for`; T1 needs a `cfConnectingIp` option. Added as task 1.1b.
4. **Cross-referenced three institutional learnings** that directly affect this plan: WebSocket XFF-trust (same 4B pattern, same codebase), Next.js 15 route-file-only exports (2.5 guardrail), Bun setInterval leak (2.2 timer-leak hazard in tests).
5. **Flagged a subtle test-import concern.** Adding `sanitize.ts` to the `track/` directory means the existing `importRoute()` helper (line 23) transitively imports `sanitize.ts` — but `vi.resetModules()` at `beforeEach:49` already handles module reset. No test-isolation risk.
6. **Added `strips control characters from 'err' too` sub-assertion to T5.** The plan body already sanitizes `err`, so the test should cover it.
7. **Added explicit vitest pattern for T2** using `vi.useFakeTimers()` + `vi.advanceTimersByTime(61_000)` (ES2019-supported — verified against `@vitest/expect@1.x` in the installed tree).
8. **Added rollout check for `x-forwarded-for` outbound.** Plausible uses XFF to geolocate; keeping outbound XFF is correct — but now the *source* is `cf-connecting-ip` in prod, and Plausible will receive the real client IP instead of a spoofable header. Geo dashboards will get slightly more accurate from this fix, not break.
9. **Added a regression-coverage test note.** The existing `"strips user_id"` test (line 103) still passes under the allowlist (both `user_id` and `userId` are non-allowlisted and dropped), just for a different reason. Keep it — it's a cheap negative-space assertion for the old denylist contract in case the allowlist regresses to denylist.

### New Considerations Discovered

- **Fake-timer interaction with module-level `setInterval`.** Importing `./throttle` at test time *would* start the real-timer `setInterval` from 2.2. Under `vi.useFakeTimers()`, that timer gets captured into the fake-timer queue, which is fine for T2 (we call `.prune()` directly, not via the interval) but means the pruner test should NOT advance timers past 60s *before* registering fake timers. Updated T2 spec to register fake timers before `importRoute()` runs.
- **No need for `MSW`.** The existing suite uses `vi.stubGlobal("fetch", mockFetch)` and `vi.mock("@/server/logger", ...)`. T1–T5 all fit this pattern; no new test-infra dependency is required.

See `## Institutional Learnings Applied` section below for the full cross-reference table.

## Overview

PR #2347 introduced `/api/analytics/track` (server-side Plausible forwarder) and code-review agents flagged four related security/robustness issues. This plan ships all four as a single focused PR because they touch the same route and share a test file.

**The four defects:**

1. **4A — Memory leak in `analyticsTrackThrottle`.** The throttle singleton is instantiated without a `setInterval(..., 60_000).unref()` pruner. Lazy eviction only reclaims keys that are re-checked, so one-hit IPs accumulate in `windows: Map<string, number[]>` indefinitely. At ~1000 unique IPs/day, the map grows across a release cycle.
2. **4B — IP-spoofing via untrusted `X-Forwarded-For`.** `clientIp()` at `route.ts:20-26` reads `x-forwarded-for` first, then `x-real-ip`. The repo already has `extractClientIpFromHeaders()` in `server/rate-limiter.ts:180-191` that prefers `cf-connecting-ip` (the only non-spoofable header behind Cloudflare). An attacker bypassing CF (direct-to-origin) can rotate `X-Forwarded-For: <random>` per request and defeat the 120/min cap, amplifying forwarded Plausible traffic.
3. **4C — PII leak via denylist-based prop stripping.** `stripUserIds()` at `route.ts:39-47` only strips keys literally named `user_id` / `userId`. A future caller can ship `props: { email, sessionId, fingerprint, deviceId, ip, ... }` and the forwarder will happily relay PII to a third party. Denylist → allowlist.
4. **4D — Log injection via `goal`.** `route.ts:105, 122` pass `{ goal: parsed.goal }` directly into pino. The `goal` string is length-capped at 120 chars but control characters pass through; an attacker can inject `\n[FAKE] ...` to forge log lines. The repo pattern is `.replace(/[\x00-\x1f]/g, "")` (used in `rejectCsrf` at `validate-origin.ts:42`).

**Scope:** Single route (`apps/web-platform/app/api/analytics/track/route.ts`) plus its sibling throttle module and a test file. No migrations, no infra, no UI.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Use `extractClientIpFromHeaders` from `server/rate-limiter.ts:180`" | Helper exists at that path; signature takes `Headers`, not `Request`. Returns `"unknown"` if no header set. | Call `extractClientIpFromHeaders(req.headers)` directly. |
| "Add `setInterval(..., 60_000).unref()` to prune idle keys" | Pattern matches `shareEndpointThrottle` (`server/rate-limiter.ts:202-206`) and `invoiceEndpointThrottle` (`:225-229`). | Colocate the interval next to the throttle in `./throttle.ts` (not `route.ts`) to preserve the "route file exports only HTTP handlers" constraint (see `cq-nextjs-route-files-http-only-exports`). |
| "Control-char strip pattern is `.replace(/[\x00-\x1f]/g, "")`" | Confirmed at `lib/auth/validate-origin.ts:42` (`rejectCsrf`). | Apply the same regex to the `goal` value before every `log.warn` call. |
| "Switch to an allowlist of non-identifying dimensions (currently just `path`)" | Current call sites: only `lib/analytics-client.ts` → `track(goal, props?)`; only known prop in use is `path` (see `test/api-analytics-track.test.ts:89, 100, 118`). | Allowlist = `{ path }`. Other keys dropped silently with a debug log. Cap string values at 200 chars. |

## Acceptance Criteria

- [ ] `analyticsTrackThrottle` has an associated `setInterval(..., 60_000).unref()` pruner colocated in `throttle.ts`, matching the `shareEndpointThrottle` / `invoiceEndpointThrottle` pattern.
- [ ] `route.ts` no longer defines a local `clientIp()` helper; it calls `extractClientIpFromHeaders(req.headers)` from `@/server/rate-limiter` instead.
- [ ] `stripUserIds` is replaced by an allowlist (`sanitizeProps`) containing exactly `path`. String values are truncated at 200 chars. Unknown keys drop with a `log.debug({ dropped }, ...)` line.
- [ ] Every `log.warn` / `log.info` that includes `goal` or `err` first passes the value through a `sanitizeForLog()` helper that strips `[\x00-\x1f]`.
- [ ] No non-HTTP-method exports added to `route.ts` (guardrail: `cq-nextjs-route-files-http-only-exports`). Helpers live in `./throttle.ts` or a new `./sanitize.ts`. A grep check in Phase 3 confirms.
- [ ] Test harness adds shared hoisted `logWarn` / `logInfo` / `logDebug` spies, and `makeRequest` accepts a `cfConnectingIp` option (prerequisites for T1 and T5).
- [ ] Test file `test/api-analytics-track.test.ts` adds T1–T5 (see Test Scenarios). T2 includes a grep-based negative-space assertion that `setInterval(..., 60_000)` exists in `throttle.ts`.
- [ ] All existing tests in `test/api-analytics-track.test.ts` still pass (including the now-redundant `"strips user_id from forwarded props"` case, which still passes under the allowlist).
- [ ] `next build` succeeds locally (route-file validator only runs under real build — mandatory per the #2401 learning).

## Non-Goals

- No change to callers of `lib/analytics-client.ts`; the `track()` signature is unchanged.
- No new Plausible goals, no UI.
- No rate-limit threshold changes.
- No migration to Redis-backed throttling (single-instance assumption still holds; documented in `server/rate-limiter.ts:216-218`).
- No expansion of the prop allowlist beyond `path` in this PR. Adding future props is a follow-up with its own security review.

## Implementation Phases

### Phase 1 — Tests First (RED)

**TDD gate (`cq-write-failing-tests-before`):** Write the four new test cases before touching production code.

**File:** `apps/web-platform/test/api-analytics-track.test.ts`

#### 1.1 — Harness Prep (prerequisite for T5)

Before adding T1–T5, the test file needs two structural edits to the existing harness (lines 13–43). Both are no-ops for the current 10 tests.

**Edit A — Shared log spies (blocks T5).** The current mock returns a **fresh** `vi.fn()` per `createChildLogger()` call:

```ts
// current (line 18-21):
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
```

Each `importRoute()` call triggers `createChildLogger("analytics-track")` inside the module — which instantiates a new spies object the test cannot access. Replace with hoisted shared spies:

```ts
// replacement:
const { logWarn, logInfo, logDebug } = vi.hoisted(() => ({
  logWarn: vi.fn(),
  logInfo: vi.fn(),
  logDebug: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { info: logInfo, warn: logWarn, error: vi.fn() },
  createChildLogger: () => ({
    info: logInfo,
    warn: logWarn,
    debug: logDebug,
    error: vi.fn(),
  }),
}));
```

Add `logWarn.mockReset(); logInfo.mockReset(); logDebug.mockReset();` to the existing `beforeEach` (line 46).

**Edit B — `cfConnectingIp` option in `makeRequest` (blocks T1).** The existing helper only exposes `forwardedFor`. Extend:

```ts
function makeRequest(
  url: string,
  {
    origin,
    forwardedFor,
    cfConnectingIp,
    body,
  }: {
    origin?: string | null;
    forwardedFor?: string;
    cfConnectingIp?: string;
    body?: unknown;
  },
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (origin !== null && origin !== undefined) headers.set("origin", origin);
  if (forwardedFor) headers.set("x-forwarded-for", forwardedFor);
  if (cfConnectingIp) headers.set("cf-connecting-ip", cfConnectingIp);
  return new Request(url, {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
```

#### 1.2 — New Test Cases

Add cases:

1. **T1 — `prefers cf-connecting-ip over x-forwarded-for for rate-limit keying`**
   - `ANALYTICS_TRACK_RATE_PER_MIN=3` (already set in `beforeEach:53`).
   - Mock `fetch` to return `new Response("", { status: 202 })`.
   - Issue 4 POST requests with `origin=https://app.soleur.ai`, `cfConnectingIp: "7.7.7.7"`, and a **rotated** `forwardedFor` per request (`"1.1.1.1"`, `"2.2.2.2"`, `"3.3.3.3"`, `"4.4.4.4"`).
   - Expect requests 1–3 → 204, request 4 → 429 (proves throttle keyed on stable `cf-connecting-ip`, not rotating XFF).
   - On `main` (pre-fix), all 4 return 204 → test RED.

2. **T2 — `throttle pruner removes idle keys after window`**
   - Import the throttle directly: `const { analyticsTrackThrottle } = await import("@/app/api/analytics/track/throttle");`
   - Call `analyticsTrackThrottle.reset()` to start from a clean slate (reset helper already exported).
   - Assert `analyticsTrackThrottle.size === 0`.
   - Issue one POST (through the route) with `cfConnectingIp: "5.5.5.5"` → `.size === 1`.
   - Use `vi.useFakeTimers({ toFake: ["Date", "performance"] })` **after** the route import (see "New Considerations Discovered" above re: fake-timer interaction with module-level `setInterval`). Alternative simpler path: skip fake timers entirely — call `analyticsTrackThrottle.reset()` after seeding, then seed a timestamp manually via `.isAllowed("6.6.6.6")`, mutate the internal `windows` Map via a wall-clock rewind helper, OR just assert the *method shape* (`.prune()` exists and is called by the module-level interval).
   - **Recommended concrete form:** directly test `prune()` semantics:

     ```ts
     test("throttle pruner removes idle keys after window", async () => {
       const { analyticsTrackThrottle, __resetAnalyticsTrackThrottleForTest } =
         await import("@/app/api/analytics/track/throttle");
       __resetAnalyticsTrackThrottleForTest();
       expect(analyticsTrackThrottle.size).toBe(0);

       // Seed two keys.
       expect(analyticsTrackThrottle.isAllowed("a")).toBe(true);
       expect(analyticsTrackThrottle.isAllowed("b")).toBe(true);
       expect(analyticsTrackThrottle.size).toBe(2);

       // Advance wall clock past the 60s window.
       vi.useFakeTimers({ now: Date.now() });
       vi.advanceTimersByTime(61_000);
       analyticsTrackThrottle.prune();
       expect(analyticsTrackThrottle.size).toBe(0);
       vi.useRealTimers();
     });
     ```

   - This bypasses the module-level `setInterval` entirely (we're calling `.prune()` manually), which keeps the test deterministic.
   - On `main` (pre-fix), the throttle module has no `prune` call surface *from inside `throttle.ts`* — the test still passes because `.prune()` is a method of `SlidingWindowCounter`. **RED comes from T1**, not T2. T2 is a regression guard: if a future change removes the pruner interval, T2 alone won't catch it — so also add the assertion `expect(typeof analyticsTrackThrottle.prune).toBe("function")` (trivially true) *and* grep-based assertion: `expect(readFileSync("apps/web-platform/app/api/analytics/track/throttle.ts", "utf-8")).toMatch(/setInterval\(\s*\(\s*\)\s*=>\s*analyticsTrackThrottle\.prune\(\s*\)/)`. This is a negative-space test in the style of `csrf-coverage.test.ts` (see learning 2026-04-15-negative-space-tests-must-follow-extracted-logic).

3. **T3 — `strips non-allowlisted prop keys (email, sessionId, fingerprint, deviceId, ip, user_id, userId)`**
   - Body: `{ goal: "kb.chat.opened", props: { path: "x", email: "a@b", sessionId: "s", session_id: "s", fingerprint: "f", deviceId: "d", device_id: "d", ip: "1.1.1.1", user_id: "u", userId: "u" } }`.
   - Assert forwarded `payload.props` deep-equals `{ path: "x" }`.
   - On `main` (pre-fix), `email`, `sessionId`, `session_id`, `fingerprint`, `deviceId`, `device_id`, `ip` are all still forwarded → test RED.

4. **T4 — `truncates prop string values at 200 chars`**
   - Body: `{ goal: "kb.chat.opened", props: { path: "a".repeat(500) } }`.
   - Assert `payload.props.path.length === 200` and `payload.props.path === "a".repeat(200)`.
   - On `main` (pre-fix), full 500-char string is forwarded → test RED.

5. **T5 — `strips control characters from goal and err before logging`**
   - Two sub-cases, one per log-emitting branch:
     - **T5a — 402 branch:** `mockFetch.mockResolvedValue(new Response("{}", { status: 402 }))`. Body goal: `"kb.chat.opened\n[FAKE] fake-event"` (29 chars, under the 120 cap). After `await POST(req)`, assert `logWarn.toHaveBeenCalledWith({ goal: "kb.chat.opened[FAKE] fake-event" }, expect.any(String))` — no `\n`.
     - **T5b — fetch rejection branch:** `mockFetch.mockRejectedValue(new Error("network down\nINJECTED"))`. Body goal: `"kb.opened\r\nLINE2"`. After `await POST(req)`, assert `logWarn.toHaveBeenCalledWith({ err: "Error: network downINJECTED", goal: "kb.opendLINE2" }, expect.any(String))` — neither `err` nor `goal` contains control chars.
   - On `main` (pre-fix), `log.warn` receives unstripped goal (and unstripped `err` on T5b) → test RED.

**Expected RED state:** T1, T3, T4, T5a, T5b fail against `main` / current HEAD. T2 asserts negative-space behavior that passes trivially today but guards against regression after 2.2 lands.

**Commit:** `test(analytics): add failing cases for track hardening bundle (#2383)`

### Phase 2 — Implementation (GREEN)

#### 2.1 — Fix 4B: IP source (route.ts)

- Remove the local `clientIp(req)` function.
- At the top of `route.ts`, add: `import { extractClientIpFromHeaders } from "@/server/rate-limiter";`
- Replace `const ip = clientIp(req);` with `const ip = extractClientIpFromHeaders(req.headers);`
- Keep the `"x-forwarded-for": ip` header on the outbound `fetch` to Plausible — that is correct behavior for Plausible's `X-Forwarded-For` contract (they geolocate from it). The fix is that the *source* of `ip` is now trusted.

#### 2.2 — Fix 4A: Prune interval (throttle.ts)

- In `apps/web-platform/app/api/analytics/track/throttle.ts`, append:

  ```ts
  const pruneAnalyticsTrackInterval = setInterval(
    () => analyticsTrackThrottle.prune(),
    60_000,
  );
  pruneAnalyticsTrackInterval.unref();
  ```

- Matches the `shareEndpointThrottle` / `invoiceEndpointThrottle` pattern exactly.
- Note: Module-level `setInterval` in Next.js dev mode is called once per HMR reload; the `.unref()` keeps the process exit-clean. Same trade-off as the two existing throttles.
- **Timer-leak hazard in tests (see learning `2026-03-20-bun-segfault-leaked-setinterval-timers`):** the module-level `setInterval` means every `importRoute()` / `import("./throttle")` call in the test suite creates a real 60 s interval. Across 1400+ vitest tests this could theoretically accumulate. Mitigations: (a) `.unref()` prevents process-exit blocking, (b) vitest's `vi.resetModules()` in `beforeEach` returns a fresh module each test but the *old* interval is still registered on the Node runtime's timer queue. If test flakiness or RSS growth appears post-merge, consider wrapping the interval registration in an `if (process.env.NODE_ENV !== "test")` gate (or `typeof vi === "undefined"`) and invoking `.prune()` manually from any test that needs it. **Not done in this PR** — follow the existing `shareEndpointThrottle` / `invoiceEndpointThrottle` convention which has no such gate and has shipped cleanly.

#### 2.3 — Fix 4C: Allowlist-based prop sanitization

- Create `apps/web-platform/app/api/analytics/track/sanitize.ts`:

  ```ts
  // Allowlist of prop keys forwarded to Plausible. Every key here must be
  // audited for PII risk. Adding a key requires a security review.
  const ALLOWED_PROP_KEYS = new Set<string>(["path"]);

  const MAX_PROP_STRING_LEN = 200;

  export function sanitizeProps(
    props: Record<string, unknown> | undefined,
  ): { clean: Record<string, unknown>; dropped: string[] } {
    if (!props) return { clean: {}, dropped: [] };
    const clean: Record<string, unknown> = {};
    const dropped: string[] = [];
    for (const [k, v] of Object.entries(props)) {
      if (!ALLOWED_PROP_KEYS.has(k)) {
        dropped.push(k);
        continue;
      }
      clean[k] = typeof v === "string" ? v.slice(0, MAX_PROP_STRING_LEN) : v;
    }
    return { clean, dropped };
  }

  // Strip C0 control characters (including \n, \r, \t, \x00) from string values
  // that will appear in structured logs. Prevents log injection.
  export function sanitizeForLog(s: string): string {
    return s.replace(/[\x00-\x1f]/g, "");
  }
  ```

- In `route.ts`, replace `stripUserIds` usage:

  ```ts
  import { sanitizeProps, sanitizeForLog } from "./sanitize";

  // ...
  const { clean: safeProps, dropped } = sanitizeProps(parsed.props);
  if (dropped.length > 0) {
    log.debug({ dropped }, "analytics.track dropped non-allowlisted props");
  }
  const payload = {
    name: parsed.goal,
    domain: siteId,
    url: origin ?? "",
    props: safeProps,
  };
  ```

- Delete `stripUserIds` from `route.ts`.

#### 2.4 — Fix 4D: Log sanitization

- Wrap every `goal: parsed.goal` log value with `sanitizeForLog(...)`:

  ```ts
  log.warn({ goal: sanitizeForLog(parsed.goal) }, "Plausible returned 402 — plan quota exhausted");
  // ...
  log.warn({ err: String(err), goal: sanitizeForLog(parsed.goal) }, "Plausible forward failed");
  ```

- Additionally sanitize the `err` string, which originates from `fetch` but could include URL fragments under some failure modes:

  ```ts
  log.warn({ err: sanitizeForLog(String(err)), goal: sanitizeForLog(parsed.goal) }, "Plausible forward failed");
  ```

#### 2.5 — Route-file export audit

Before committing, confirm `route.ts` exports **only** `POST` and `GET`. Any helper must live in `./throttle.ts` or `./sanitize.ts`. This guardrail is enforced by `cq-nextjs-route-files-http-only-exports` (the hotfix #2401 learning from `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`).

**Concrete check (copy-paste in Phase 3):**

```bash
cd apps/web-platform && grep -nE "^export " app/api/analytics/track/route.ts
# Expected output (exactly two lines):
# export async function POST(req: Request): Promise<Response> {
# export async function GET(): Promise<Response> {
```

Any other `export` line is a blocker.

#### 2.6 — sanitize.ts export surface

For clarity, `sanitize.ts` exports exactly:

- `sanitizeProps(props: Record<string, unknown> | undefined): { clean: Record<string, unknown>; dropped: string[] }`
- `sanitizeForLog(s: string): string`

The `ALLOWED_PROP_KEYS` set and `MAX_PROP_STRING_LEN` constant remain module-private. A future expansion of the allowlist (e.g., adding `referrer`) requires a PR touching this file specifically — which makes it easy for CODEOWNERS-style security review to gate.

**Not exported on purpose:** `MAX_PROP_STRING_LEN` is deliberately not tweakable by callers. If a future Plausible goal needs a longer prop, the decision is a one-line constant edit here, not a runtime flag.

**Commit:** `fix(analytics): harden /api/analytics/track (mem leak, IP spoof, PII, log injection) (#2383)`

### Phase 3 — Verification (REFACTOR / VALIDATE)

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts` — all tests green.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` (full suite) — no regressions elsewhere.
- [ ] `cd apps/web-platform && npm run build` — the Next.js 15 route-file validator passes (only the real build catches non-HTTP exports; `tsc --noEmit` and vitest do not). **Why required:** issue #2401 was a 15-min prod outage precisely because this step was skipped.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (or equivalent `npm run typecheck`) — clean.
- [ ] `cd apps/web-platform && npm run lint` — clean.
- [ ] Manually re-read `route.ts` to confirm only `POST` / `GET` are exported.

## Test Scenarios

Cases to add to `test/api-analytics-track.test.ts` (covered by Phase 1):

| # | Name | Asserts | RED on main? |
| --- | --- | --- | --- |
| T1 | `prefers cf-connecting-ip over x-forwarded-for for rate-limit keying` | Fix 4B: throttle keyed on CF IP, not rotating XFF | Yes (4th request returns 204 instead of 429) |
| T2 | `throttle pruner removes idle keys after window` | Fix 4A (regression guard): `.prune()` reduces `.size`; `setInterval(..., 60_000)` exists in `throttle.ts` via grep | No (method shape passes; grep is the guard) |
| T3 | `strips non-allowlisted prop keys (email, sessionId, fingerprint, deviceId, ip)` | Fix 4C: only `path` forwarded | Yes |
| T4 | `truncates prop string values at 200 chars` | Fix 4C: length cap | Yes |
| T5a | `strips control characters from goal before logging (402 branch)` | Fix 4D: `\n` removed from `log.warn` goal on 402 | Yes |
| T5b | `strips control characters from goal and err before logging (catch branch)` | Fix 4D: `\n` removed from both `goal` and `err` on fetch rejection | Yes |

Existing cases (`rejects disallowed Origin`, `rejects missing Origin`, `forwards goal + props`, `strips user_id` (now redundant — subsumed by T3), `HTTP 402 graceful`, `non-JSON response`, `per-IP rate limit`, `GET 405`, `missing PLAUSIBLE_SITE_ID`, `invalid body 400`) must all still pass.

**Note on `strips user_id` existing test:** T3 supersedes it (allowlist drops both `user_id` and `userId` as non-allowlisted). Keep the existing test as regression coverage — it still passes under the allowlist, just for a different reason.

## Alternative Approaches Considered

| Approach | Why rejected |
| --- | --- |
| Ship the four fixes as four separate PRs | Issue #2383 is already a scope-out bundle with `deferred-scope-out` label; splitting further creates rebase churn on a single file. Kieran/DHH review guideline: one PR per logical concern, and "harden `/api/analytics/track`" is the concern. |
| Keep denylist, just add more keys (`email`, `sessionId`, ...) | Fails open by design — any new PII-like key requires a code change. Allowlist fails closed. Security engineering default. |
| Move prune interval into `route.ts` alongside the throttle export | Violates `cq-nextjs-route-files-http-only-exports`. The `setInterval` creates a module-level side effect but is not an export, so technically it is allowed — but colocating it with the throttle in `throttle.ts` keeps all singletons and their lifecycle in one module. |
| Strip control chars inside `isTrackBody` validator | Silent mutation of user input during validation is surprising; `isTrackBody` should predicate-only. Sanitize at log-time only (logs are the attack surface for 4D, not the forwarded Plausible payload — Plausible already sees raw `goal` as an event name, which is fine). |
| Drop the outbound `x-forwarded-for` header to Plausible | Plausible uses XFF for geolocation; removing it breaks geo dimensions. The *input* fix (use `cf-connecting-ip`) is what matters; continuing to forward a trusted IP value outbound is correct. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a security hardening bundle scoped to one route with no UI, no content, no pricing, no infra, and no new external service surface. Caller contract (`lib/analytics-client.ts`) is unchanged. CTO sign-off is implicit via the existing rate-limiter pattern reuse; no new architectural decisions.

## Rollout / Risk

- **Deployment risk:** Low. Single route, no migrations, no config changes required (`ANALYTICS_TRACK_RATE_PER_MIN` env var unchanged).
- **Behavior change visible to users:** None. The `track()` client signature is stable; only `path` prop was ever forwarded in practice.
- **Behavior change visible to Plausible dashboards:** None in practice (see above). If any historical client forwarded `user_id`, `email`, or similar, those were already being dropped (for `user_id`) or never should have been forwarded (everything else). Dashboards will not break.
- **Rate-limit keying change (Fix 4B):** Clients behind corporate NAT whose real IP differs from what Cloudflare sees will now be keyed on `cf-connecting-ip`. In practice this tightens (not loosens) per-user caps correctly — `cf-connecting-ip` is the same IP Cloudflare already rate-limits on, so the 120/min per-IP cap is self-consistent. No user-visible change unless an attacker was previously evading the cap, which is the point.
- **Log pipeline:** Sentry / Better Stack ingest sanitized goal values. Dashboards that group by goal are unaffected (attackers were the only source of control chars).

## Files Changed

| Path | Change |
| --- | --- |
| `apps/web-platform/app/api/analytics/track/route.ts` | Drop local `clientIp`; call `extractClientIpFromHeaders`. Drop `stripUserIds`; call `sanitizeProps`. Wrap logged `goal` / `err` with `sanitizeForLog`. |
| `apps/web-platform/app/api/analytics/track/throttle.ts` | Add `setInterval(..., 60_000).unref()` pruner. |
| `apps/web-platform/app/api/analytics/track/sanitize.ts` | **New.** Exports `sanitizeProps(props)` (allowlist + length cap) and `sanitizeForLog(s)` (C0 control-char strip). |
| `apps/web-platform/test/api-analytics-track.test.ts` | Add T1–T5 (see Test Scenarios). |

## Institutional Learnings Applied

Cross-reference of `knowledge-base/project/learnings/` entries that directly influenced this plan. Each one turned a potential bug into a known-safe choice.

| Learning | How it applies to this plan |
| --- | --- |
| `security-issues/websocket-rate-limiting-xff-trust-20260329.md` | Direct precedent for Fix 4B. Same codebase, same reasoning: when behind Cloudflare, trusting `x-forwarded-for` as a fallback = IP spoof. The WebSocket handler was hardened by the same review author. The learning's "Key Insight" — *"Only trust the proxy's own header (`cf-connecting-ip`). The fallback should be `remoteAddress` (TCP-level, not spoofable)"* — is exactly what `extractClientIpFromHeaders` implements (with XFF as the dev-mode-only fallback). **Implication:** the review history for that learning includes 3 independent reviewers flagging the absence of periodic `prune()` — which this plan also fixes (4A). |
| `runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md` | Origin of the `cq-nextjs-route-files-http-only-exports` guardrail. The `throttle.ts` sibling module pattern this plan extends came from hotfix #2401 for exactly this route. **Implication:** `sanitize.ts` must also be a sibling module, not a `route.ts` export. Phase 2.5 now has a `grep` check to confirm. |
| `2026-03-20-bun-segfault-leaked-setinterval-timers.md` | Warning about module-level `setInterval` in test runners. Not a blocker (the existing `shareEndpointThrottle` / `invoiceEndpointThrottle` use the same pattern without issue on vitest), but documented as a monitoring note in Phase 2.2. |
| `2026-03-30-plausible-http-402-graceful-skip.md` | Confirms the 402 branch of `route.ts:105` is correct behavior (graceful skip, don't propagate to client). This plan preserves that branch verbatim and only adds `sanitizeForLog(parsed.goal)` to the log call. |
| `2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md` | Confirms `validateOrigin` + `rejectCsrf` usage at `route.ts:50-57` is correct. **Also:** the `rejectCsrf` implementation at `validate-origin.ts:42` already calls `.slice(0, 100).replace(/[\x00-\x1f]/g, "")` on the origin — the exact same pattern we're porting to the `goal` field. This is the pattern source cited in issue #2383. |
| `best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md` | Directly informs T2's regression guard. T2 now includes a grep-based assertion that the `setInterval` call exists in `throttle.ts` — a negative-space test in the style of `csrf-coverage.test.ts`. Without it, a future refactor removing the pruner would pass all behavioral tests. |
| `2026-04-02-plausible-api-response-validation-prevention.md` | Confirms the existing non-JSON tolerance at `route.ts:111-120` is correct. Plan preserves it verbatim — not in scope. |
| `best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md` | The "Research Reconciliation — Spec vs. Codebase" section at the top of this plan follows this learning's prescribed format (3-column table, placed between Overview and Implementation Phases). |

## Verified API Signatures

Signatures verified by direct file read at plan time (2026-04-17). These are the APIs the plan relies on — any deviation during implementation should update the plan first.

| Symbol | File : line | Signature | Used by |
| --- | --- | --- | --- |
| `SlidingWindowCounter.isAllowed` | `server/rate-limiter.ts:53` | `isAllowed(key: string): boolean` | `route.ts:60` (unchanged) |
| `SlidingWindowCounter.prune` | `server/rate-limiter.ts:81` | `prune(): void` | new interval in `throttle.ts` (2.2) |
| `SlidingWindowCounter.size` | `server/rate-limiter.ts:100` | `get size(): number` | T2 assertions |
| `SlidingWindowCounter.reset` | `server/rate-limiter.ts:105` | `reset(): void` | already wrapped by `__resetAnalyticsTrackThrottleForTest` in `throttle.ts:20` |
| `extractClientIpFromHeaders` | `server/rate-limiter.ts:180` | `extractClientIpFromHeaders(headers: Headers): string` — prefers `cf-connecting-ip`, falls back to `x-forwarded-for` first comma-split value, returns `"unknown"` otherwise | `route.ts` (replaces local `clientIp(req)`) |
| `validateOrigin` | `lib/auth/validate-origin.ts:14` | `validateOrigin(request: Request): { valid: boolean; origin: string \| null }` | `route.ts:50` (unchanged) |
| `rejectCsrf` | `lib/auth/validate-origin.ts:41` | `rejectCsrf(route: string, origin: string \| null): Response` — already sanitizes origin with `.replace(/[\x00-\x1f]/g, "")` | `route.ts:56` (unchanged; pattern source for `sanitizeForLog`) |
| `track` (client) | `lib/analytics-client.ts:5` | `track(goal: string, props?: Record<string, unknown>): Promise<void>` — **caller contract preserved; no change needed** | all UI call sites (unchanged) |

## References

- Issue: [#2383](https://github.com/jikig-ai/soleur/issues/2383)
- Origin PR: [#2347](https://github.com/jikig-ai/soleur/pull/2347) (kb-chat-sidebar)
- Hotfix precedent: [#2401](https://github.com/jikig-ai/soleur/pull/2401) (non-HTTP exports in route file — prevents the Docker build outage)
- Learning: `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`
- Learning: `knowledge-base/project/learnings/security-issues/websocket-rate-limiting-xff-trust-20260329.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-bun-segfault-leaked-setinterval-timers.md`
- Learning: `knowledge-base/project/learnings/2026-03-30-plausible-http-402-graceful-skip.md`
- Learning: `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`
- Pattern source: `apps/web-platform/server/rate-limiter.ts:180-229` (`extractClientIpFromHeaders`, `shareEndpointThrottle` / `invoiceEndpointThrottle` pruners)
- Log-sanitize pattern source: `apps/web-platform/lib/auth/validate-origin.ts:42` (`rejectCsrf`)
- AGENTS.md guardrails: `cq-nextjs-route-files-http-only-exports`, `cq-write-failing-tests-before`, `cq-in-worktrees-run-vitest-via-node-node`, `cq-vite-test-files-esm-only`, `cq-markdownlint-fix-target-specific-paths`
