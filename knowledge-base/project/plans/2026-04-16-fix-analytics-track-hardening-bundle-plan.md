# fix: /api/analytics/track hardening bundle (memory leak, IP-spoof, PII, log-injection)

**Issue:** [#2383](https://github.com/jikig-ai/soleur/issues/2383)
**Branch:** `feat-analytics-track-hardening`
**Worktree:** `.worktrees/feat-analytics-track-hardening/`
**Milestone:** Phase 3: Make it Sticky
**Labels:** `priority/p2-medium`, `type/security`, `code-review`, `deferred-scope-out`
**Type:** Security hardening (bug-fix bundle)
**Status:** Planning

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
- [ ] `stripUserIds` is replaced by an allowlist (`sanitizeProps` / `pickAllowedProps`) containing exactly `path`. String values are truncated at 200 chars. Unknown keys drop with a `log.debug({ droppedKeys }, ...)` line (control-char stripped).
- [ ] Every `log.warn` / `log.info` that includes `goal` first passes it through a `sanitizeForLog()` helper that strips `[\x00-\x1f]`.
- [ ] No non-HTTP-method exports added to `route.ts` (guardrail: `cq-nextjs-route-files-http-only-exports`). Helpers live in `./throttle.ts` or a new `./sanitize.ts`.
- [ ] Test file `test/api-analytics-track.test.ts` adds four new cases (see Test Scenarios).
- [ ] All existing tests in `test/api-analytics-track.test.ts` still pass.
- [ ] `next build` succeeds locally (route-file validator only runs under real build).

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

Add cases:

1. **`prefers cf-connecting-ip over x-forwarded-for for rate-limit keying`**
   - Issue 10 POST requests with `origin=https://app.soleur.ai`, `cf-connecting-ip=7.7.7.7`, and a different `x-forwarded-for: <rotated>` per request.
   - Set `ANALYTICS_TRACK_RATE_PER_MIN=3`.
   - Expect request 4+ to return 429 (proving the throttle keyed on `cf-connecting-ip`, not the rotating XFF).
2. **`throttle pruner removes idle keys`**
   - Import `analyticsTrackThrottle` from `@/app/api/analytics/track/throttle`.
   - Use `vi.useFakeTimers()`; check `.size === 0`; issue one request; check `.size === 1`; advance time past the 60 s window; call `.prune()`; check `.size === 0`. (Test the pruner helper directly rather than the `setInterval`, to avoid fake-timer/real-setInterval interactions.)
3. **`strips non-allowlisted prop keys (email, sessionId, fingerprint, deviceId, ip)`**
   - Body: `{ goal: "kb.chat.opened", props: { path: "x", email: "a@b", sessionId: "s", fingerprint: "f", deviceId: "d", ip: "1.1.1.1", user_id: "u", userId: "u" } }`.
   - Assert forwarded `payload.props` is exactly `{ path: "x" }`.
4. **`truncates prop string values at 200 chars`**
   - Body: `{ goal: "kb.chat.opened", props: { path: "a".repeat(500) } }`.
   - Assert forwarded `payload.props.path.length === 200`.
5. **`strips control characters from goal before logging`**
   - Mock `createChildLogger` with spies (already mocked at top of file — extend to return shared spies instead of fresh `vi.fn()` each call).
   - Force a `fetch` rejection so the `log.warn` at the `catch` branch fires.
   - Body: `{ goal: "kb.chat.opened\n[FAKE] event" }` — this is 29 chars, under the 120 cap.
   - Assert `log.warn` was called with `{ err: <str>, goal: "kb.chat.opened[FAKE] event" }` — no `\n`.
   - Also cover the 402 branch with control chars.

**Expected RED state:** All 5 cases fail against `main` / current HEAD.

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

| # | Name | Asserts |
| --- | --- | --- |
| T1 | `prefers cf-connecting-ip over x-forwarded-for for rate-limit keying` | Fix 4B: throttle keyed on CF IP, not rotating XFF |
| T2 | `throttle pruner removes idle keys` | Fix 4A: `.prune()` reduces `.size` after window |
| T3 | `strips non-allowlisted prop keys` | Fix 4C: only `path` forwarded |
| T4 | `truncates prop string values at 200 chars` | Fix 4C: length cap |
| T5 | `strips control characters from goal before logging` | Fix 4D: `\n` removed from log payload |

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

## References

- Issue: [#2383](https://github.com/jikig-ai/soleur/issues/2383)
- Origin PR: [#2347](https://github.com/jikig-ai/soleur/pull/2347) (kb-chat-sidebar)
- Hotfix precedent: [#2401](https://github.com/jikig-ai/soleur/pull/2401) (non-HTTP exports in route file — prevents the Docker build outage)
- Learning: `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`
- Pattern source: `apps/web-platform/server/rate-limiter.ts:180-229` (`extractClientIpFromHeaders`, `shareEndpointThrottle` / `invoiceEndpointThrottle` pruners)
- Log-sanitize pattern source: `apps/web-platform/lib/auth/validate-origin.ts:42` (`rejectCsrf`)
- AGENTS.md guardrails: `cq-nextjs-route-files-http-only-exports`, `cq-write-failing-tests-before`, `cq-in-worktrees-run-vitest-via-node-node`
