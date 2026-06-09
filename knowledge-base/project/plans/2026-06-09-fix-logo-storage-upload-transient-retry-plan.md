---
title: "Fix: workspace-logo upload to Storage should retry on transient failure"
date: 2026-06-09
type: fix
branch: feat-one-shot-logo-storage-retry
lane: cross-domain
requires_cpo_signoff: false
brand_survival_threshold: none
status: planned
---

# 🐛 Fix: workspace-logo upload to Storage retries on transient failure

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec file
> existed under `specs/feat-one-shot-logo-storage-retry/` at plan time.

## Overview

The workspace-logo upload route (`apps/web-platform/app/api/workspace/logo/route.ts`,
shipped in #4916) performs a **single-attempt** Supabase Storage upload at line 130. Any
transient failure — a Storage 5xx blip, a 429, or a network-level fetch failure between the
Next.js container and Supabase — immediately surfaces as `500 "Logo upload failed"` to the
workspace owner, even though the exact same request would succeed milliseconds later. The
upload is idempotent by construction (deterministic key `${workspaceId}/logo.webp` +
`upsert: true`), which makes it a textbook safe-retry candidate.

**Fix:** add a small, dependency-free retry leaf module (`server/storage-retry.ts`,
mirroring the existing `server/github-retry.ts` precedent) that retries **result-returning**
Supabase Storage operations on transient errors with bounded exponential backoff, and wire
the logo route's `.upload()` call through it. Terminal failures keep the exact same
`reportSilentFallback` op slug (`storage-upload`) and user-facing 500; retried attempts gain
a distinct warn-level breadcrumb so transient-failure frequency becomes observable.

## Premise Validation

No external GitHub issue is cited by the feature description — the work item originates
from the one-shot pipeline argument directly ("logo upload to storage should retry on
transient failure"). Checked at plan time:

- **Branch + PR:** `feat-one-shot-logo-storage-retry` exists; draft PR #5084 is OPEN
  (`gh pr view 5084` → `state: OPEN, isDraft: true`). This is a RESUME after a terminal
  crash — no new worktree/PR is created.
- **Cited artifact exists:** the upload route exists on this branch and on `origin/main`
  (`apps/web-platform/app/api/workspace/logo/route.ts`, upload at line 130) — the premise
  is "behavior gap" (no retry), not "never built". Plan shape is *fix/harden*, correct.
- **No duplicate issue:** `gh issue list --search "logo storage retry"` → 0 open matches;
  #4916 (the logo feature) is CLOSED.
- **No relevant brainstorm:** newest brainstorms (2026-06-08/09) cover unrelated topics.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Reality (verified) | Plan response |
| --- | --- | --- |
| "logo upload to storage" | Single call site: `route.ts:130` `service.storage.from(BUCKET).upload(key, out, { contentType, upsert: true })` | Wrap exactly this call site |
| "should retry on transient failure" | No retry exists anywhere on the Storage write path; codebase HAS two retry precedents (`server/github-api.ts` `fetchWithRetry`, `lib/supabase/tenant.ts` verifyOtp loop) | New leaf module mirrors both precedents (see Precedent Diff) |
| (implicit) "errors are catchable" | storage-js 2.99.2 `.upload()` is **result-returning**: API errors AND network errors come back as `{ data: null, error }`, never thrown (verified against installed `dist/index.mjs:282,438` — network failures are wrapped in `StorageUnknownError` and rejected inside the SDK's own catch, which returns them) | Retry classifies the **returned** error (per learning `2026-05-27-retry-on-401-gap-in-result-returning-call-sites.md`); non-StorageError throws still propagate unchanged |

## Research Insights

**Verified-at-plan-time claims (all live-checked this session):**

1. **storage-js error taxonomy (installed `@supabase/storage-js@2.99.2`,
   `src/lib/common/errors.ts`):**
   - `StorageApiError extends StorageError` — `status: number` (HTTP), `statusCode: string`.
   - `StorageUnknownError extends StorageError` — wraps network-level failures
     (`originalError`), **no numeric `status`**; `name === "StorageUnknownError"`.
   - `isStorageError(error)` type guard exported; SDK request helper rejects network errors
     as `StorageUnknownError` (`dist/index.mjs:282`) and the file-API methods' catch returns
     `{ data: null, error }` for any StorageError (`dist/index.mjs:438`).
2. **Retry precedent A — `apps/web-platform/server/github-retry.ts`:** dependency-free leaf
   (`isRetryable(err)` + `delay(ms)`) extracted exactly so two consumers share one transient
   classification without an import cycle. The new module copies this *shape*.
3. **Retry precedent B — `apps/web-platform/server/github-api.ts:20-75` `fetchWithRetry`:**
   `MAX_RETRIES = 2` (3 total attempts), `BASE_DELAY_MS = 1_000`, plain exponential
   `BASE * 2 ** attempt`, retry on 5xx + thrown-retryable, `log.warn` per attempt.
4. **Retry precedent C — `apps/web-platform/lib/supabase/tenant.ts:371-400`:** retry loop on
   a **result-returning** supabase call (`verifyOtp`), classified by structured error code,
   `for (let attempt = 0; ; attempt++) { … if (!retryable || attempt >= max) break; await sleep(...) }`.
   This is the loop shape for our result-returning case.
5. **Existing tests:** `apps/web-platform/test/workspace-logo-route.test.ts` exists (route
   suite with `mockUpload` already factored; observability mocked via
   `importActual` + override). **No existing test sets a `mockUpload` error** — no current
   test constrains single-attempt semantics, so adding retry breaks nothing. Verified there
   is no other suite importing the route (`git grep -l "workspace/logo/route"` →
   only this file) and no existing `storage-retry` test anywhere.
6. **Sentry op-contract coupling:** `grep -rn "storage-upload" apps/web-platform/infra/sentry/`
   → 0 matches. No alert filters on this op slug; preserving it is still required by the
   dashboard-keyed-message learning, but no `op IS_IN` alert can go dark.
7. **Vitest discovery:** `apps/web-platform/vitest.config.ts:44` node project collects
   `test/**/*.test.ts`; `test/server/` exists. New helper test at
   `test/server/storage-retry.test.ts` IS collected. Runner is vitest —
   invoke as `./node_modules/.bin/vitest run <paths>` (never `bun test`, never `npm -w`).
8. **Code-review overlap:** two-stage `gh issue list --label code-review --json` +
   standalone `jq --arg` against all planned file paths → 0 matches (see section below).

**Institutional learnings applied:**

- `knowledge-base/project/learnings/2026-05-27-retry-on-401-gap-in-result-returning-call-sites.md`
  — retry mechanism must match the call site's error-handling pattern; `.upload()` is
  result-returning, so the retry classifies the returned error, not a caught exception.
- `knowledge-base/project/learnings/2026-04-13-github-api-fetch-retry-undici-error-codes.md`
  — network-level transient classification precedent (here unnecessary to enumerate undici
  codes: storage-js already collapses them into `StorageUnknownError`).
- `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md` — every
  retry needs an explicit ceiling; loop is depth-bounded by `maxRetries`.
- `knowledge-base/project/learnings/test-failures/2026-04-19-retry-once-early-return-masks-first-attempt-failures.md`
  — tests assert across ALL attempts (exact `mockUpload` call counts), never just the last.
- `knowledge-base/project/learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`
  — terminal-failure `reportSilentFallback` call (op `storage-upload`, same extra payload)
  must remain byte-identical.

## User-Brand Impact

- **If this lands broken, the user experiences:** a workspace owner's logo upload fails
  (500 "Logo upload failed") or takes up to ~1.5 s longer in the worst transient case —
  identical or strictly-better than today's single-attempt behavior; the monogram fallback
  still renders. No data loss is possible (deterministic key + upsert; orphan-cleanup paths
  unchanged).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure
  vector — the retry re-sends the exact same canonical-WebP bytes to the same private
  bucket under the same service-role client; no new logging of image content, no new
  endpoint, no auth change.
- **Brand-survival threshold:** none
  - `threshold: none, reason:` the diff touches a sensitive path (`app/api/**`) but only
    re-invokes an existing idempotent write with unchanged auth, payload, destination, and
    error surface; a failure here degrades to today's exact behavior (single attempt → 500
    → monogram fallback), which is cosmetic and self-recoverable by the owner re-uploading.

## Implementation Phases

TDD throughout (`cq-write-failing-tests-before`): each phase writes RED tests first,
then the minimal implementation to GREEN.

### Phase 1 — `server/storage-retry.ts` leaf module + unit tests

**1.1 RED — create `apps/web-platform/test/server/storage-retry.test.ts`:**

Unit tests against the (not-yet-existing) module. Scenarios (see Test Scenarios table):
classification truth table + loop semantics with an injected no-op `sleep` (`vi.fn()`
resolving immediately — no fake timers needed; backoff values asserted from the `sleep`
mock's call args).

**1.2 GREEN — create `apps/web-platform/server/storage-retry.ts`:**

Dependency-free leaf (the `github-retry.ts` shape — no imports from sibling server modules,
structural typing instead of importing storage-js types):

```ts
// apps/web-platform/server/storage-retry.ts
// Shared Supabase-Storage transient-retry primitives (leaf, like ./github-retry).
// storage-js (2.99.2) file-API methods are RESULT-RETURNING: API errors AND
// network-level failures come back as { data, error } (StorageApiError carries
// numeric `status`; StorageUnknownError wraps fetch-level failures and has no
// status) — so retry classifies the RETURNED error, never a caught exception.
// Non-StorageError throws (programming errors) propagate unchanged.

export interface StorageErrorLike {
  name?: string;
  message: string;
  status?: number;
}

const DEFAULT_MAX_RETRIES = 2; // 3 total attempts — mirrors github-api.ts
const DEFAULT_BASE_DELAY_MS = 500; // worst added latency: 500 + 1000 = 1.5 s

export function isRetryableStorageError(error: StorageErrorLike | null): boolean {
  if (!error) return false;
  // Network-level wrap (storage-js dist:282) — always worth retrying.
  if (error.name === "StorageUnknownError") return true;
  // StorageApiError: HTTP status. 5xx + 429 are transient; 4xx are not.
  return typeof error.status === "number" && (error.status >= 500 || error.status === 429);
}

export async function withStorageRetry<R extends { error: StorageErrorLike | null }>(
  op: () => Promise<R>,
  opts: {
    maxRetries?: number;
    baseDelayMs?: number;
    sleep?: (ms: number) => Promise<void>;
    onRetry?: (attempt: number, error: StorageErrorLike) => void;
  } = {},
): Promise<R> {
  const maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES;
  const baseDelayMs = opts.baseDelayMs ?? DEFAULT_BASE_DELAY_MS;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  let result = await op();
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    if (!result.error || !isRetryableStorageError(result.error)) return result;
    opts.onRetry?.(attempt + 1, result.error);
    await sleep(baseDelayMs * 2 ** attempt); // plain exponential — see Alternatives
    result = await op();
  }
  return result;
}
```

(Pseudo-code — implementer owns final naming/JSDoc; the loop shape, defaults, and
classification truth table are normative.)

### Phase 2 — wire the logo route + route tests

**2.1 RED — extend `apps/web-platform/test/workspace-logo-route.test.ts`:**

New `describe("POST /api/workspace/logo — transient-retry (storage upload)")` block.
The existing `vi.mock("@/server/observability", ...)` gains a `mockWarn` override for
`warnSilentFallback` (same `importActual` + override pattern already in the file). To keep
the suite fast, partially mock the retry module so route tests run with zero delay:

```ts
vi.mock("@/server/storage-retry", async () => {
  const actual = await vi.importActual<typeof import("@/server/storage-retry")>(
    "@/server/storage-retry",
  );
  return {
    ...actual,
    withStorageRetry: (op: never, opts = {}) =>
      actual.withStorageRetry(op, { ...opts, sleep: async () => {} }),
  };
});
```

Tests (assert EXACT `mockUpload` call counts — every attempt, not just the last, per the
2026-04-19 retry-masking learning):

1. transient-then-success: `mockUpload` **resolves** once with
   `{ data: null, error: { status: 503, message: "Service Unavailable" } }` (storage-js is
   result-returning — never use `mockRejectedValue` for storage errors), then default
   success → `200`, `mockUpload` called **exactly 2** times,
   `mockReport` (reportSilentFallback) **not** called with op `storage-upload`,
   `mockWarn` called once with op `storage-upload-retry`.
2. persistent transient: `{ error: { status: 503 } }` on every call → `500`, `mockUpload`
   called **exactly 3** times, `mockReport` called once with op `storage-upload`.
3. non-retryable: `{ error: { status: 400, … } }` → `500`, `mockUpload` called
   **exactly 1** time (no retry), `mockReport` once with op `storage-upload`.
4. network-class: `{ error: { name: "StorageUnknownError", message: "fetch failed" } }`
   once, then success → `200`, 2 attempts.

**2.2 GREEN — edit `apps/web-platform/app/api/workspace/logo/route.ts`:**

Replace the single-attempt upload (line 130) with:

```ts
const up = await withStorageRetry(
  () => service.storage.from(BUCKET).upload(key, out, { contentType: "image/webp", upsert: true }),
  {
    onRetry: (attempt, error) =>
      warnSilentFallback(error, {
        feature: FEATURE,
        op: "storage-upload-retry",
        extra: { userId: user.id, workspaceId, attempt },
      }),
  },
);
if (up.error) {
  // UNCHANGED terminal-failure block — same op slug "storage-upload", same extra
  // payload, same 500 body (dashboard-keyed; do not reword).
  ...
}
```

Imports: add `withStorageRetry` from `@/server/storage-retry` and `warnSilentFallback`
from `@/server/observability` (already exported there; route currently imports only
`reportSilentFallback`).

### Phase 3 — verification

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/storage-retry.test.ts test/workspace-logo-route.test.ts`
  → all green.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0.
- Scope guard: `grep -c "withStorageRetry(" apps/web-platform/app/api/workspace/logo/route.ts`
  → exactly `1` (only the upload call site is wrapped; `.remove()` cleanups and the DB
  update stay un-retried — see Non-Goals).

## Files to Create

| File | Purpose |
| --- | --- |
| `apps/web-platform/server/storage-retry.ts` | Dependency-free leaf: `isRetryableStorageError` + `withStorageRetry` (result-returning retry loop, bounded exponential backoff) |
| `apps/web-platform/test/server/storage-retry.test.ts` | Unit tests: classification truth table + loop semantics with injected sleep |

## Files to Edit

| File | Change |
| --- | --- |
| `apps/web-platform/app/api/workspace/logo/route.ts` | Wrap the line-130 `.upload()` in `withStorageRetry`; per-retry `warnSilentFallback` (op `storage-upload-retry`); terminal-failure block byte-identical |
| `apps/web-platform/test/workspace-logo-route.test.ts` | Add `mockWarn` to the observability mock; partial-mock `@/server/storage-retry` (zero-delay sleep); add 4 retry scenarios with exact attempt-count assertions |

No SKILL.md `description:` edits → skill-description budget check not applicable.

## Acceptance Criteria

### Pre-merge (PR)

1. **Helper exists and is the only retry surface:**
   `grep -c "withStorageRetry(" apps/web-platform/app/api/workspace/logo/route.ts` → `1`
   (upload only); `git grep -l "withStorageRetry" -- 'apps/web-platform'` → exactly the
   helper, the route, and the two test files.
2. **Classification truth table pinned by unit tests** in
   `test/server/storage-retry.test.ts`: status `500/502/503/504/429` → retryable;
   `400/403/404/409/413` → not retryable; `name: "StorageUnknownError"` (no status) →
   retryable; plain `{ message }` error (no status, no name match — the shape existing
   route tests use) → not retryable; `null` error → no retry.
3. **Backoff bounded and exponential:** unit test asserts injected `sleep` receives
   `[500, 1000]` (base × 2^attempt) and is called at most `maxRetries` times — worst-case
   added route latency 1.5 s.
4. **Route retry semantics** (all in `test/workspace-logo-route.test.ts`, exact call
   counts): transient-then-success → `200` + 2 upload attempts; persistent transient →
   `500` + exactly 3 attempts; non-retryable 400 → `500` + exactly 1 attempt.
5. **Terminal-failure observability unchanged:**
   `grep -c 'op: "storage-upload",' apps/web-platform/app/api/workspace/logo/route.ts` → `1`
   (trailing comma anchors the exact slug — a bare `'op: "storage-upload"'` grep would
   substring-match the new `storage-upload-retry` slug and report 2), and the
   persistent-transient route test asserts `mockReport` was called with op `storage-upload`.
6. **Per-retry visibility:** transient-then-success route test asserts `warnSilentFallback`
   called once with op `storage-upload-retry` and `extra.attempt === 1`.
7. **Suite + types green:**
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/storage-retry.test.ts test/workspace-logo-route.test.ts`
   exits 0; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
8. **No new dependencies:** `git diff origin/main -- apps/web-platform/package.json` → empty.

### Post-merge (operator)

None — `web-platform-release.yml` redeploys the container on merge (path-filtered
`apps/web-platform/**`); no migration, no infra, no secrets. The PR merge IS the rollout.

## Open Code-Review Overlap

None. (Two-stage check at plan time: `gh issue list --label code-review --state open
--json number,title,body --limit 200` then standalone `jq --arg path` per planned file
path — `apps/web-platform/app/api/workspace/logo/route.ts`,
`apps/web-platform/test/workspace-logo-route.test.ts`, and the `storage-retry` stem all
returned 0 matches.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — backend reliability hardening of an existing
engineering surface. No UI-surface file appears in Files to Create/Edit (the mechanical
UI-surface override does not fire); no pricing, legal, marketing, sales, support, or
people implications. Product/UX Gate tier: NONE (no user-facing flow changes — the only
user-visible delta is *fewer* spurious upload failures). Pipeline note: this plan was
authored in a one-shot subagent without the Task tool; the domain sweep was performed
inline against `brainstorm-domain-config.md` semantics rather than via spawned leader
agents — the NONE outcome makes the delta moot.

### GDPR / Compliance Gate (Phase 2.7, advisory-only)

The diff touches an API route (canonical regex hit), so the gate was assessed inline:
the retry introduces **no new processing activity, data category, recipient, or
destination** — it re-sends the identical canonical-WebP payload to the identical private
bucket under the identical service-role client. The per-retry breadcrumb adds `attempt`
(an integer) to an existing pseudonymized observability payload (`userId` is
pepper-hashed by `server/observability.ts` before emit). No Art. 30 register change; no
Critical findings. *This automated assessment is not legal advice.*

## Infrastructure (IaC)

Not applicable — no new infrastructure, secrets, services, vendors, or persistent
processes. Pure code change against an already-provisioned surface
(`apps/web-platform/app/` + `server/`), which per plan Phase 2.8 skips the gate.

## Observability

```yaml
liveness_signal:
  what: "Sentry warning events tagged feature:workspace-logo op:storage-upload-retry (one per retried attempt) — a rising rate signals Storage-transient degradation BEFORE users see terminal 500s"
  cadence: "on-event (push); reviewed via existing Sentry issue stream"
  alert_target: "existing Sentry issue alerts on the web-platform project (jikigai-eu org); no new alert rule — terminal failures already route via reportSilentFallback (error level)"
  configured_in: "apps/web-platform/server/observability.ts (warnSilentFallback → Sentry + pino); apps/web-platform/infra/sentry/ (unchanged)"
error_reporting:
  destination: "Sentry (eu.sentry.io, org jikigai-eu, project web-platform) + structured pino server logs"
  fail_loud: "terminal failure keeps reportSilentFallback (error level, op storage-upload) + 500 to the caller — retry never converts a hard failure into silence"
failure_modes:
  - mode: "transient exhausted (3 attempts all 5xx/429/network)"
    detection: "Sentry error event op:storage-upload (existing) preceded by 2 warn events op:storage-upload-retry"
    alert_route: "existing Sentry issue alerting"
  - mode: "non-retryable Storage error (4xx)"
    detection: "Sentry error event op:storage-upload with exactly 0 storage-upload-retry warn events"
    alert_route: "existing Sentry issue alerting"
  - mode: "retry succeeded (transient absorbed)"
    detection: "warn event op:storage-upload-retry with NO subsequent storage-upload error for the same user/workspace"
    alert_route: "none (informational — this is the fix working)"
logs:
  where: "pino server logs in the web-platform container (warnSilentFallback logs err + feature + op + extra)"
  retention: "platform log retention (unchanged)"
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd_terraform --plain)\" 'https://eu.sentry.io/api/0/projects/jikigai-eu/web-platform/events/?query=storage-upload-retry' | jq 'length'"
  expected_output: "a JSON integer ≥ 0 (HTTP 200 — proves the op slug is queryable without SSH; > 0 only after a real transient fires in prod)"
```

## Test Scenarios

| # | Surface | Scenario | Fixture | Expected |
| --- | --- | --- | --- | --- |
| U1 | unit | retryable statuses | `{status: 500/502/503/504/429}` | `isRetryableStorageError` → true |
| U2 | unit | non-retryable statuses | `{status: 400/403/404/409/413}` | false |
| U3 | unit | network wrap | `{name: "StorageUnknownError"}` (no status) | true |
| U4 | unit | legacy plain error | `{message: "db down"}` only | false |
| U5 | unit | null error | `null` | false; `withStorageRetry` returns after 1 op call, sleep never called |
| U6 | unit | backoff shape | persistent 503, injected sleep | op called 3×; sleep called with `[500, 1000]`; final result carries the error |
| U7 | unit | onRetry callback | transient-then-success | onRetry called once with `(1, error)` |
| R1 | route | transient-then-success | mockUpload 503 once, then success | 200; 2 attempts; 1 `storage-upload-retry` warn; no `storage-upload` error |
| R2 | route | persistent transient | mockUpload 503 ×3 | 500; exactly 3 attempts; `reportSilentFallback` op `storage-upload` once |
| R3 | route | non-retryable | mockUpload `{status: 400}` | 500; exactly 1 attempt |
| R4 | route | network-class | `StorageUnknownError`-shaped once, then success | 200; 2 attempts |
| R5 | route | existing suite | all pre-existing tests | unchanged green (no fixture in the file sets a mockUpload error today — verified) |

## Non-Goals (explicit scope-outs)

- **`.remove()` cleanup calls (route lines 146, 246):** already best-effort/fail-soft with
  distinct `logo-orphan-cleanup-failed` breadcrumbs; a transient remove failure orphans at
  most one ≤1 MB object that the next upload overwrites (deterministic key + upsert) and
  account-delete purges. Retrying a cleanup adds latency to an already-failed path.
- **DB `update` persist (PostgREST layer):** different failure domain; the zero-rows guard
  + orphan cleanup already fail loud. Retry there needs its own classification design.
- **`[id]/logo` proxy route `createSignedUrl` (read path):** out of the stated scope
  ("upload … should retry"); a read blip degrades to the monogram for one render.
- **Other Storage write sites** (`account-delete.ts`, `dsar-export.ts` removals,
  `export/[jobId]/download` remove): enumerated at plan time
  (`git grep "\.storage\.from("`); all are removals on non-interactive paths with their own
  error handling. The new leaf module is available to them later — not migrated now.

No deferral issues filed: each scope-out is a deliberate "current behavior is correct"
judgment, not deferred work product.

## Alternative Approaches Considered

| Alternative | Verdict |
| --- | --- |
| Inline retry loop in route.ts (no module) | Rejected — untestable backoff without exporting internals; `github-retry.ts` precedent shows the leaf-module shape is the codebase convention for exactly this |
| Jittered backoff (±25%, tenant.ts precedent) | Rejected for now — tenant.ts added jitter for lockstep CI bursts against a rate limiter; logo uploads are user-initiated, per-user rate-limited (10/min), and uncorrelated. Plain exponential matches `github-api.ts`. Two-line change later if Sentry shows thundering-herd retries |
| Env-tunable retry config (tenant.ts `getVerifyOtpRetryConfig` style) | Rejected — no operational need to tune; opts-injection covers tests; YAGNI |
| Retry inside a generic fetch wrapper around the storage client | Rejected — storage-js owns its fetch; wrapping it fights the SDK. Result-classification is the supported seam |
| `vi.useFakeTimers` in route tests instead of partial-mocking the retry module | Rejected — the route handler awaits real async work (sharp encode, FormData parse) before the retry sleep; mixing fake timers with that is fragile. Zero-delay sleep injection is deterministic |

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Added latency on a user-waiting HTTP path | Bounded: worst case 1.5 s added (500 + 1000 ms) only when Storage is already failing; today's alternative is an instant *failure*. Max input pixel/byte work happens once (re-encode is outside the retry closure — only `.upload()` re-runs) |
| Retry masks a real outage | Terminal `reportSilentFallback` (error level, op `storage-upload`) is unchanged; per-attempt warns make transients MORE visible than today, not less |
| Double-write side effects | None possible: deterministic key + `upsert: true` makes the operation idempotent; a retry after an ambiguous "failed but actually wrote" still converges to the same object |
| Misclassification retries a permanent error | Classification is status-gated against the **installed** storage-js 2.99.2 error shapes (verified in `dist/index.mjs` + `src/lib/common/errors.ts`, not docs); 4xx and unknown shapes fail fast, preserving today's behavior |
| storage-js major bump changes error shape | Structural typing (`StorageErrorLike`) + unit truth-table pins the contract; a shape change breaks the suite loudly, not silently (U1-U4) |

## Sharp Edges

- The terminal-failure `reportSilentFallback` block (op `storage-upload`, extra
  `{userId, workspaceId}`) is dashboard-keyed — keep it **byte-identical** when wrapping
  the call (learning `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`).
- `withStorageRetry` must wrap a **closure that re-invokes** `.from(BUCKET).upload(...)` —
  capturing the promise (`withStorageRetry(uploadPromise)`) would retry nothing.
- Tests must assert **exact** attempt counts; a `toHaveBeenCalled()` on the last attempt
  silently passes when the first attempt's behavior regresses (learning
  `2026-04-19-retry-once-early-return-masks-first-attempt-failures.md`).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan
  Phase 4.6 — section above is filled, threshold `none` with the required sensitive-path
  reason bullet.

## References

- Route: `apps/web-platform/app/api/workspace/logo/route.ts` (upload at :130)
- Precedents: `apps/web-platform/server/github-retry.ts`,
  `apps/web-platform/server/github-api.ts:20-75`,
  `apps/web-platform/lib/supabase/tenant.ts:371-400`
- Feature origin: #4916 (CLOSED); this PR: #5084 (draft)
- Learnings cited: see Research Insights (paths glob-verified at plan-write time)
