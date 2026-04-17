# Tasks: /api/analytics/track hardening bundle

**Plan:** `knowledge-base/project/plans/2026-04-16-fix-analytics-track-hardening-bundle-plan.md`
**Issue:** [#2383](https://github.com/jikig-ai/soleur/issues/2383)
**Branch:** `feat-analytics-track-hardening`
**Worktree:** `.worktrees/feat-analytics-track-hardening/`
**Milestone:** Phase 3: Make it Sticky

## Phase 1 — Tests First (RED)

- [ ] 1.1a **Harness prep:** replace `vi.mock("@/server/logger", ...)` with hoisted shared spies (`logWarn`, `logInfo`, `logDebug`). Reset them in `beforeEach`. (Required for T5 — without this, fresh spies per call make assertions impossible.)
- [ ] 1.1b **Harness prep:** extend `makeRequest` helper with optional `cfConnectingIp` parameter that sets the `cf-connecting-ip` header. (Required for T1.)
- [ ] 1.2 Add test T1: `prefers cf-connecting-ip over x-forwarded-for for rate-limit keying` (sets `ANALYTICS_TRACK_RATE_PER_MIN=3` via existing beforeEach, rotates `forwardedFor` across 4 requests with stable `cfConnectingIp: "7.7.7.7"`, asserts request 4 returns 429)
- [ ] 1.3 Add test T2: `throttle pruner removes idle keys after window` (calls `__resetAnalyticsTrackThrottleForTest`, seeds 2 keys, uses `vi.useFakeTimers({ now: Date.now() })` + `vi.advanceTimersByTime(61_000)`, calls `.prune()` directly, asserts `.size === 0`; also asserts grep of `throttle.ts` contains `setInterval(...analyticsTrackThrottle.prune...)` as negative-space guard)
- [ ] 1.4 Add test T3: `strips non-allowlisted prop keys (email, sessionId, session_id, fingerprint, deviceId, device_id, ip, user_id, userId)` (asserts forwarded `payload.props` deep-equals `{ path: "x" }`)
- [ ] 1.5 Add test T4: `truncates prop string values at 200 chars` (500-char path input → asserts `payload.props.path.length === 200`)
- [ ] 1.6a Add test T5a: `strips control characters from goal before logging (402 branch)` — mocks fetch with 402, body goal `"kb.chat.opened\n[FAKE] fake-event"`, asserts `logWarn.toHaveBeenCalledWith({ goal: "kb.chat.opened[FAKE] fake-event" }, expect.any(String))`
- [ ] 1.6b Add test T5b: `strips control characters from goal and err before logging (catch branch)` — mocks fetch rejection with `"network down\nINJECTED"`, body goal `"kb.opened\r\nLINE2"`, asserts neither value in `logWarn` call contains control chars
- [ ] 1.7 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts` — confirm T1, T3, T4, T5a, T5b fail (RED); T2 passes trivially (regression guard)
- [ ] 1.8 Commit: `test(analytics): add failing cases for track hardening bundle (#2383)`

## Phase 2 — Implementation (GREEN)

### 2.1 Fix 4B: IP source

- [ ] 2.1.1 In `apps/web-platform/app/api/analytics/track/route.ts`, add `import { extractClientIpFromHeaders } from "@/server/rate-limiter";`
- [ ] 2.1.2 Delete local `clientIp()` function (lines 20–26)
- [ ] 2.1.3 Replace `const ip = clientIp(req);` with `const ip = extractClientIpFromHeaders(req.headers);`
- [ ] 2.1.4 Keep outbound `x-forwarded-for: ip` header on Plausible `fetch` (Plausible uses it for geolocation — source is now trusted)

### 2.2 Fix 4A: Prune interval

- [ ] 2.2.1 In `apps/web-platform/app/api/analytics/track/throttle.ts`, append:

  ```ts
  const pruneAnalyticsTrackInterval = setInterval(
    () => analyticsTrackThrottle.prune(),
    60_000,
  );
  pruneAnalyticsTrackInterval.unref();
  ```

- [ ] 2.2.2 Confirm pattern matches `shareEndpointThrottle` / `invoiceEndpointThrottle` in `server/rate-limiter.ts:202-229`

### 2.3 Fix 4C: Allowlist-based prop sanitization

- [ ] 2.3.1 Create `apps/web-platform/app/api/analytics/track/sanitize.ts` with:
  - `ALLOWED_PROP_KEYS = new Set<string>(["path"])`
  - `MAX_PROP_STRING_LEN = 200`
  - `sanitizeProps(props)` → `{ clean, dropped }`
  - `sanitizeForLog(s)` → `.replace(/[\x00-\x1f]/g, "")`
- [ ] 2.3.2 In `route.ts`, import `sanitizeProps` and `sanitizeForLog` from `./sanitize`
- [ ] 2.3.3 Delete `stripUserIds` function from `route.ts`
- [ ] 2.3.4 Replace `stripUserIds(parsed.props)` with `sanitizeProps(parsed.props)` destructure
- [ ] 2.3.5 Add `log.debug({ dropped }, ...)` when dropped keys are non-empty

### 2.4 Fix 4D: Log sanitization

- [ ] 2.4.1 Wrap `goal: parsed.goal` with `sanitizeForLog(parsed.goal)` in the 402 `log.warn` (route.ts:105)
- [ ] 2.4.2 Wrap `goal: parsed.goal` with `sanitizeForLog(parsed.goal)` in the catch `log.warn` (route.ts:122)
- [ ] 2.4.3 Wrap `err: String(err)` with `sanitizeForLog(String(err))` in the catch `log.warn`

### 2.5 Route-file export audit

- [ ] 2.5.1 Run `cd apps/web-platform && grep -nE "^export " app/api/analytics/track/route.ts` — expected output is exactly two lines: `export async function POST` and `export async function GET`. Any other line blocks the commit (guardrail `cq-nextjs-route-files-http-only-exports`)

### 2.6 Commit

- [ ] 2.6 Commit: `fix(analytics): harden /api/analytics/track (mem leak, IP spoof, PII, log injection) (#2383)`

## Phase 3 — Verification

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts` — all T1–T5 green, existing cases still pass
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` — no regressions across suite
- [ ] 3.3 `cd apps/web-platform && npm run build` — Next.js 15 route-file validator passes (MANDATORY — only real build catches non-HTTP exports; see #2401 learning)
- [ ] 3.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean typecheck
- [ ] 3.5 `cd apps/web-platform && npm run lint` — clean
- [ ] 3.6 Re-read `route.ts` and confirm only `POST` and `GET` are exported

## Phase 4 — Ship

- [ ] 4.1 Run `skill: soleur:review` on the PR branch
- [ ] 4.2 Run `skill: soleur:compound` to capture learnings before ship
- [ ] 4.3 Run `skill: soleur:ship` to open PR (labels: `priority/p2-medium`, `type/security`, `code-review`; milestone: Phase 3; body: `Closes #2383`)
- [ ] 4.4 After merge, verify release workflow succeeds (`skill: soleur:postmerge`)
