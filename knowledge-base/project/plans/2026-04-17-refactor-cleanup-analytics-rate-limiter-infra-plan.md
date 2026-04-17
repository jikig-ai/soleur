# refactor: drain analytics-track / rate-limiter scope-out backlog (#2459 + #2460 + #2461)

**Type:** refactor (infrastructure / code hygiene)
**Branch:** `feat-cleanup-analytics-rate-limiter-infra`
**Worktree:** `.worktrees/feat-cleanup-analytics-rate-limiter-infra/`
**Pattern reference:** PR #2486 (batched cleanup of three scope-outs from one review cycle)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Research Reconciliation, Files to Edit, Implementation Phases, Test Scenarios, Risk Assessment, Acceptance Criteria
**Research inputs used:**

- Direct code grep for existing vitest patterns (`vi.useFakeTimers`, `vi.spyOn`, `.unref()`, `setInterval` in test files)
- Learning file `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`
- Source inspection of `test/ws-subscription-refresh.test.ts` (established fake-timer cadence pattern)

### Key Improvements from Deepening

1. **Identified pre-existing negative-space test T2b in `test/api-analytics-track.test.ts:289-308` that will break on extraction.** The source-grep regex `setInterval([\s\S]*analyticsTrackThrottle\.prune\(\)[\s\S]*60_?000` in T2b enforces inline wiring — our extraction removes that wiring from `throttle.ts`. Plan updated to migrate T2b per the 2026-04-15 learning's two-layer pattern (route-level proves delegation, helper-level proves invariant).
2. **Fake-timer test strategy tightened.** Existing codebase uses `vi.useFakeTimers()` + `vi.advanceTimersByTimeAsync` (async variant, not sync) in timer-adjacent tests. Plan updated to prefer `advanceTimersByTimeAsync` for consistency and to avoid pruning synchronous-microtask surprises.
3. **`setInterval` spy strategy grounded.** No existing test in the codebase spies on `global.setInterval` directly — the dominant pattern is `vi.spyOn(counter, "prune")` plus `vi.advanceTimersByTime*`. Plan updated to drop the fragile `setInterval` spy in favor of the idiomatic pattern: assert `prune` is called on cadence, plus a typeof-check that `.unref` exists on the returned handle (since Node `Timeout`s always expose it — a behavioral spy on `.unref` itself adds no safety and is brittle).
4. **Direct helper assertion added** for `startPruneInterval` body per Layer 2 of the 2026-04-15 learning — a regex test asserting `rate-limiter.ts` source contains `handle.unref()` inside `startPruneInterval` so the invariant can't silently disappear from the helper.
5. **Scope-fence extended** to include `test/api-analytics-track.test.ts` as a seventh file-to-edit — strictly for T2b migration. Called out explicitly so review doesn't flag it as scope creep.

## Overview

Close three deferred-scope-out issues filed during review of PR #2445 (analytics-track hardening, ref #2383) in a single focused refactor PR. All three live in the same code area — `apps/web-platform/server/rate-limiter.ts` plus two small sibling helpers — so batching is safer and cheaper than three separate PRs. No user-facing behavior change; no new runtime dependencies; the only observable diff is a shared log-sanitize helper that extends (not changes) the existing regex to cover U+2028/U+2029 at the CSRF-reject call site.

### Non-goals

- **NOT closing #2462** (PII scrubbing for CSRF-reject origin) — contested-design, needs product/ops discussion first.
- **NOT closing #2196** fully — overlaps with #2460 on the `startPruneInterval` extraction (fold that item in). Other items (compaction dedupe, `__resetInvoiceThrottleForTest` removal, config hoist) stay open because they expand blast radius past the scope fence.
- **NOT closing #2197** — adjacent but a separate doc/typing concern; overlaps only conceptually.
- **NOT closing #2391 item 11A** (session supersession UX comment) — touches ws-handler code unrelated to the three scope-outs. See Open Code-Review Overlap below.
- **NOT refactoring Route file exports** — per rule `cq-nextjs-route-files-http-only-exports`, non-HTTP exports live in sibling modules. `throttle.ts` already is a sibling; do not touch `route.ts`.
- **NOT unifying `pdf-linearize.ts`'s private `sanitizeForLog` copy** with the new shared helper. It uses a different replacement character (`"?"` vs `""`) intentionally (keeps stderr readable when inspecting qpdf output). Leave as a separate follow-up.

## Research Reconciliation — Arguments vs. Codebase

The scope-out issues and the calling arguments prescribe specific line numbers. Before implementing, reconcile them against HEAD of this worktree:

| Argument claim | Reality | Plan response |
|---|---|---|
| `server/rate-limiter.ts:202-206, 225-229, 274-278, 280-284` — four prune-interval copies | Confirmed. Plus a fifth at `server/rate-limiter.ts:202-206` (shareEndpointThrottle), `:225-229` (invoiceEndpointThrottle), `:274-278` (connectionThrottle), `:280-284` (sessionThrottle). Total 4 in this file. | Correct — 4 copies here. The 5th copy is in `throttle.ts:19-23` as stated. |
| `app/api/analytics/track/throttle.ts:17-21` — fifth copy | Actual range is `:19-23` (lines 17-18 are a comment block). | Use `:19-23` in the edit, not `:17-21`. |
| `server/ws-handler.ts:716` caller of `extractClientIp` | Line 716 is a comment inside the default switch branch. Actual caller is `ws-handler.ts:740` (`const clientIp = extractClientIp(req);`). | Use `:740` in the JSDoc cross-reference. Do NOT use the arguments' stale line number. |
| `lib/auth/validate-origin.ts:42` inline `.slice(0,100).replace(...)` | Confirmed at `:42` inside `rejectCsrf`. Regex is `/[\x00-\x1f]/g` — narrower than the analytics regex (missing `\x7f`, U+2028, U+2029). | Replace with `sanitizeForLog(origin ?? "none", 100)`. This intentionally widens the regex at this call site; U+2028/U+2029 smuggling into `rejectedOrigin` logs is a real (if low-severity) hazard. Document in commit message. |
| `app/api/analytics/track/sanitize.ts:36` exports `sanitizeForLog(s: string)` with no `maxLen` | Confirmed. Regex is `/[\x00-\x1f\x7f\u2028\u2029]/g`, empty-string replacement. No length cap. | Migration: `sanitize.ts` re-exports `sanitizeForLog` from the shared helper (preserves the named import at `route.ts:6`). Default `maxLen = 500` is larger than the longest current input (`parsed.goal` capped upstream at 100 chars, `err` capped at `MAX_ERR_LOG_LEN`), so default-arg call sites continue producing identical output. |
| Additional caller of `extractClientIpFromHeaders` not mentioned in arguments | Second caller at `app/api/shared/[token]/route.ts:52`. Both callers rely on the same `"unknown"` fallback. | Issue #2459 is doc-only; no behavior change. The second caller is covered by the same JSDoc. No code edit needed at the second caller. |
| Third `sanitizeForLog` copy in `server/pdf-linearize.ts:26` | Confirmed. Uses `"?"` replacement, not `""`. Scope fence excludes this file. | Leave alone. Document the divergence in the new helper's header comment so a future reader sees it. |

## Research Findings

### Local

- `apps/web-platform/server/rate-limiter.ts` (285 lines) — home of `SlidingWindowCounter`, `PendingConnectionTracker`, `extractClientIp`, `extractClientIpFromHeaders`, and four module-level prune intervals. Already tested by `apps/web-platform/test/rate-limiter.test.ts` (242 lines, covers counter + tracker + `extractClientIp`; no tests for `extractClientIpFromHeaders` here — those live in `share-links.test.ts`).
- `apps/web-platform/test/share-links.test.ts:30-49` — covers `extractClientIpFromHeaders` (4 cases: cf-connecting-ip wins, unknown fallback, XFF chain takes first, plain cf-connecting-ip). The JSDoc we're adding must not break any of these.
- `apps/web-platform/app/api/analytics/track/route.ts` calls `sanitizeForLog` at three sites (`:101`, `:118`, `:119`). Imports it by name from `./sanitize`. Re-export strategy in `sanitize.ts` preserves the import.
- `apps/web-platform/app/api/analytics/track/throttle.ts` already imports `SlidingWindowCounter` from `@/server/rate-limiter` (line 4). Adding `startPruneInterval` to that same import is natural.
- `apps/web-platform/test/api-analytics-track.test.ts:28` has a comment `"T5 — sanitizeForLog strips C0 control characters from goal + err"` but it's a comment inside the file — no direct unit test for `sanitizeForLog` today. We will add one for the shared helper.

### Institutional learnings (apply here)

- **`cq-nextjs-route-files-http-only-exports`** — `throttle.ts` exists precisely because PR #2401 had to hotfix a build failure from non-HTTP exports in `route.ts`. Do NOT touch `route.ts` exports. Keep `startPruneInterval` in `rate-limiter.ts`, NOT in any file under `app/**/route.ts`.
- **`cq-vite-test-files-esm-only`** — new tests MUST use top-level `import`, not `require()`.
- **`cq-in-worktrees-run-vitest-via-node-node`** / app-level vitest — run tests as `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`, not `npx vitest`.
- **`cq-silent-fallback-must-mirror-to-sentry`** — NOT triggered here. None of the changed code paths add a new silent fallback; `rejectCsrf` remains an expected-state path (exempt). Logs stay on pino.
- **`cq-markdownlint-fix-target-specific-paths`** — for this plan file, run `npx markdownlint-cli2 --fix` on the exact path, not a repo-wide glob.
- **`wg-use-closes-n-in-pr-body-not-title-to`** — three `Closes #NNNN` lines MUST live in PR body, separate lines, not in the PR title.
- **`rf-review-finding-default-fix-inline`** — PR #2486 pattern. This PR is the scope-out-drain pattern in action.

### External

None. Pure infrastructure refactor on already-well-tested code; no framework semantics in play beyond the Next.js route-file rule (loaded via `cq-nextjs-route-files-http-only-exports`).

## Open Code-Review Overlap

Five open scope-outs touch files this plan will edit. Per the Code-Review Overlap Check procedure:

| Issue | Scope | Files overlap | Disposition | Rationale |
|---|---|---|---|---|
| #2196 | 5 cleanup items in rate-limiter.ts | `server/rate-limiter.ts` | **Partial fold-in** — item 1 (prune-interval helper) is literally #2460; it closes when #2460 closes. Items 2-5 stay open. | Item 1 is exactly our scope. Item 2 (compaction dedupe) and item 5 (config hoist) are code-quality refactors that need separate review budget. Items 3-4 (`__resetInvoiceThrottleForTest` removal, `.unref()` style) expand blast radius past the scope fence in the arguments — the arguments explicitly say "Preserve existing variable names". |
| #2197 | SubscriptionStatus type + single-instance throttle doc + Sentry UUID policy | `server/rate-limiter.ts` (item 2 only) | **Acknowledge / keep open** | Item 2 (hoist single-instance assumption to a module-level comment) is doc-only and adjacent but not required to close the three target scope-outs. Folding it in would mix a module-level doc reorganization with a helper extraction. Separate follow-up. |
| #2391 | 11A supersession UX + 11B rate-limit scaling note | `server/rate-limiter.ts`, `server/ws-handler.ts` | **Acknowledge / keep open** | 11A touches ws-handler session supersession logic — product/UX concern, not infra. 11B (add scaling-note comment to `analyticsTrackThrottle`) is technically a one-line edit in `throttle.ts` which IS in scope, but the issue bundles it with 11A; closing half of an issue is worse than closing neither. If this PR grows a follow-up, #2391 11B becomes a 1-line fix. Leave open. |
| #2191 | `clearSessionTimers` helper + jitter + consecutive-failure close | `server/ws-handler.ts` | **Acknowledge / keep open** | Medium-severity session-management work. Not a scope-out of PR #2445. Leave open. |

No overlap on `lib/log-sanitize.ts` (new), `lib/auth/validate-origin.ts`, `app/api/analytics/track/sanitize.ts`, or `app/api/analytics/track/throttle.ts`.

## Files to Create

1. **`apps/web-platform/lib/log-sanitize.ts`** — shared `sanitizeForLog(s, maxLen=500)` helper.
2. **`apps/web-platform/test/log-sanitize.test.ts`** — unit tests for the helper.
3. **`apps/web-platform/test/start-prune-interval.test.ts`** — unit test for the new `startPruneInterval` helper. (Alternative: add cases to `apps/web-platform/test/rate-limiter.test.ts` instead of a new file. Prefer adding to the existing file to avoid test-file sprawl; see Phase 3.)

## Files to Edit

1. **`apps/web-platform/server/rate-limiter.ts`**
   - Add `export function startPruneInterval(t: SlidingWindowCounter, ms = 60_000): NodeJS.Timeout`.
   - Replace 4 inline `setInterval(..., ...).unref()` blocks with `const pruneXxxInterval = startPruneInterval(xxx[, ms])`.
   - Keep `setInterval` at call-site offset for `pruneSessionInterval` (uses `300_000` ms, not the default 60_000); pass `300_000` explicitly.
   - Add JSDoc block above `extractClientIp` (lines 152-173) — "for `IncomingMessage` (WS upgrade) callers only; falls back to `socket.remoteAddress` when `cf-connecting-ip` is absent".
   - Add JSDoc block above `extractClientIpFromHeaders` (lines 180-191) — "for Next.js Web-API Request callers (App Router routes); no socket access available, so missing `cf-connecting-ip` collapses to `"unknown"` rather than sharing a bucket with an unspoofable socket IP. The asymmetry with `extractClientIp` is intentional — Next.js routes cannot reach `req.socket.remoteAddress`".
   - No other changes; preserve all existing variable names.

2. **`apps/web-platform/lib/auth/validate-origin.ts`**
   - Import `sanitizeForLog` from `@/lib/log-sanitize`.
   - Replace line 42: `const sanitized = (origin ?? "none").slice(0, 100).replace(/[\x00-\x1f]/g, "");` → `const sanitized = sanitizeForLog(origin ?? "none", 100);`.
   - Note: regex widens from `/[\x00-\x1f]/g` to `/[\x00-\x1f\x7f\u2028\u2029]/g`. This is a deliberate hardening; document in the commit subject.

3. **`apps/web-platform/app/api/analytics/track/sanitize.ts`**
   - Remove the local `sanitizeForLog` function body and the comment above it (keep a one-line comment pointing to the shared helper).
   - Re-export: `export { sanitizeForLog } from "@/lib/log-sanitize";` — preserves `import { sanitizeProps, sanitizeForLog } from "./sanitize"` at `route.ts:6` without touching `route.ts`.
   - No change to `sanitizeProps` or `ALLOWED_PROP_KEYS`.

4. **`apps/web-platform/app/api/analytics/track/throttle.ts`**
   - Change import to `import { SlidingWindowCounter, startPruneInterval } from "@/server/rate-limiter";`.
   - Replace lines 19-23 with `const pruneAnalyticsInterval = startPruneInterval(analyticsTrackThrottle);`.
   - Preserve `__resetAnalyticsTrackThrottleForTest` unchanged.

5. **`apps/web-platform/test/rate-limiter.test.ts`**
   - Add a new `describe("startPruneInterval")` block with three tests (see Test Scenarios).
   - Add a Layer-2 direct helper assertion: a source-grep test asserting `rate-limiter.ts` contains the `startPruneInterval` function body with the `handle.unref()` call — prevents a silent regression where the helper stops marking timers as unref'd.

6. **`apps/web-platform/test/api-analytics-track.test.ts`** (scope-fenced; T2b migration ONLY)
   - **Migrate T2b (lines 289-308)** per the 2026-04-15 negative-space-tests-must-follow-extracted-logic learning. Currently T2b asserts `throttle.ts` source matches `/setInterval\([\s\S]*analyticsTrackThrottle\.prune\(\)[\s\S]*60_?000/` and `/\.unref\(\)/`. After extraction, those strings live in `rate-limiter.ts::startPruneInterval`, not in `throttle.ts`. Replace the single-layer check with a two-layer check:
     - **Layer 1 (route/caller level — prove delegation):** `throttle.ts` source matches `/startPruneInterval\(\s*analyticsTrackThrottle\s*\)/` — proves `throttle.ts` calls the helper with the right counter.
     - **Layer 2 (helper level — prove invariant):** `rate-limiter.ts` source matches `/export function startPruneInterval[\s\S]*setInterval\([\s\S]*\.prune\(\)[\s\S]*\.unref\(\)/` — proves the helper still installs a periodic prune + unref.
   - Keep T2a (behavioral) unchanged.
   - Do NOT touch any other test in this file. Scope fence: only T2b's regex assertions change.

## Implementation Phases

### Phase 1: RED — failing tests first

Per rule `cq-write-failing-tests-before`, write tests BEFORE implementation. Order:

1. Create `apps/web-platform/test/log-sanitize.test.ts` with four cases:
   - `strips C0 control characters and DEL` — input `"a\x00b\x1fc\x7fd"`, expect `"abcd"`.
   - `strips U+2028 and U+2029` — input `"a\u2028b\u2029c"`, expect `"abc"`.
   - `truncates to maxLen default 500` — input `"x".repeat(1000)`, expect length 500.
   - `truncates to custom maxLen` — input `"x".repeat(200)`, expect `sanitizeForLog(input, 100).length === 100`.
   - `preserves ordinary text under the cap` — input `"hello world"`, expect `"hello world"`.
2. Add `describe("startPruneInterval", ...)` to `apps/web-platform/test/rate-limiter.test.ts`. Use the idiomatic codebase pattern (see `test/ws-subscription-refresh.test.ts:50` for the reference — `vi.useFakeTimers()` in `beforeEach`, `vi.useRealTimers()` in `afterEach`, `vi.advanceTimersByTimeAsync` inside tests). Do NOT spy on `global.setInterval` — no existing test in the codebase uses that pattern, and a returned-handle spy on `.unref` is brittle. Instead:
   - **Test 1 — `returns a Node Timeout handle with .unref available`**: construct a counter, call `startPruneInterval(counter)`, assert `typeof handle.unref === "function"` and `typeof handle[Symbol.toPrimitive] === "function"` (Node Timeout invariants). Immediately `clearInterval(handle)` to avoid leaking into subsequent tests.
   - **Test 2 — `invokes counter.prune() on each tick at default cadence`**: `vi.useFakeTimers()`; `const counter = new SlidingWindowCounter({windowMs: 60_000, maxRequests: 1});`; `const spy = vi.spyOn(counter, "prune");`; `const handle = startPruneInterval(counter);` then `await vi.advanceTimersByTimeAsync(60_000)` → expect `spy` called once; `await vi.advanceTimersByTimeAsync(60_000)` → expect `spy` called twice. `clearInterval(handle)`.
   - **Test 3 — `accepts a custom interval`**: same setup but `startPruneInterval(counter, 5_000)`; advance `4_999` ms → `spy` NOT called; advance `1` ms more → `spy` called once; advance `5_000` ms → `spy` called twice. `clearInterval(handle)`.
   - **Test 4 (Layer-2 helper invariant, per 2026-04-15 learning)** — `startPruneInterval source installs setInterval + prune + unref`: read `server/rate-limiter.ts` via `readFileSync`, assert `/export function startPruneInterval[\s\S]*setInterval\([\s\S]*\.prune\(\)[\s\S]*\.unref\(\)/` matches. This catches a silent regression where the helper drops the `.unref()` call.
3. Migrate T2b in `apps/web-platform/test/api-analytics-track.test.ts:289-308` to the two-layer form described in the Files to Edit section. This test will be RED until `throttle.ts` is updated in Phase 2.
4. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/log-sanitize.test.ts test/rate-limiter.test.ts test/api-analytics-track.test.ts`. All new/migrated tests MUST fail (helper not created yet, throttle.ts not yet using helper). Confirm RED.

### Phase 2: GREEN — minimal implementation

1. Create `apps/web-platform/lib/log-sanitize.ts`:

    ```typescript
    // Strip C0 control characters, DEL, and Unicode line/paragraph separators
    // before strings reach structured logs. U+2028 and U+2029 are especially
    // important: JSON loggers pass them through, but many log viewers and
    // JavaScript consumers treat them as line terminators — re-enabling log
    // injection through a "sanitized" goal.
    //
    // Note: `server/pdf-linearize.ts` has a private copy that replaces with "?"
    // (intentional, keeps qpdf stderr readable). Do NOT fold it into this helper.
    export function sanitizeForLog(s: string, maxLen = 500): string {
      return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "").slice(0, maxLen);
    }
    ```

2. Add `startPruneInterval` to `apps/web-platform/server/rate-limiter.ts`, placed near the top of the file after the `SlidingWindowCounter` class (before the first singleton definition at the current line 197):

    ```typescript
    /**
     * Start a periodic prune interval for a SlidingWindowCounter and mark the
     * timer as unref'd so it never blocks process exit. Dedupes the pattern
     * used for shareEndpointThrottle, invoiceEndpointThrottle, connectionThrottle,
     * sessionThrottle (this file) and analyticsTrackThrottle (app/api/analytics/
     * track/throttle.ts). Single-instance-assumption caveat on line 213-218 still
     * applies to every caller.
     */
    export function startPruneInterval(
      counter: SlidingWindowCounter,
      ms = 60_000,
    ): NodeJS.Timeout {
      const handle = setInterval(() => counter.prune(), ms);
      handle.unref();
      return handle;
    }
    ```

3. Replace the four inline blocks in `rate-limiter.ts` with one-liner assignments. Preserve variable names:
   - `const pruneShareInterval = startPruneInterval(shareEndpointThrottle);`
   - `const pruneInvoiceInterval = startPruneInterval(invoiceEndpointThrottle);`
   - `const pruneConnectionInterval = startPruneInterval(connectionThrottle);`
   - `const pruneSessionInterval = startPruneInterval(sessionThrottle, 300_000);`
4. Add the two JSDoc blocks above `extractClientIp` and `extractClientIpFromHeaders`.
5. Update `app/api/analytics/track/sanitize.ts` to re-export the shared helper.
6. Update `app/api/analytics/track/throttle.ts` to use `startPruneInterval`.
7. Update `lib/auth/validate-origin.ts` — import + call swap.
8. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/log-sanitize.test.ts test/rate-limiter.test.ts test/api-analytics-track.test.ts`. All tests MUST pass, including the migrated T2b (Layer 1 `throttle.ts` matches `/startPruneInterval\(\s*analyticsTrackThrottle\s*\)/`, Layer 2 `rate-limiter.ts` matches the helper-body regex). Confirm GREEN.

### Phase 3: Regression pass

1. Run the two full test files that exercise all affected modules plus any test that imports from them:

    ```bash
    cd apps/web-platform && ./node_modules/.bin/vitest run \
      test/rate-limiter.test.ts \
      test/log-sanitize.test.ts \
      test/share-links.test.ts \
      test/api-analytics-track.test.ts \
      test/shared-page-binary.test.ts \
      test/shared-token-content-hash.test.ts \
      test/shared-token-verdict-cache.test.ts \
      test/ws-resume-by-context-path.test.ts \
      test/ws-deferred-creation.test.ts
    ```

    All must pass. The mock patterns in `ws-resume-by-context-path.test.ts:70` and `ws-deferred-creation.test.ts:63` rely on `extractClientIp` being importable — our JSDoc-only change doesn't affect export signatures, so they continue to work unchanged.

2. Run typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. No new errors expected.

3. Run lint on changed files: `cd apps/web-platform && ./node_modules/.bin/next lint --file <changed-files>` (or project-standard lint command). Fix any complaints.

### Phase 4: Optional follow-up — fifth-file fold-in decision

Currently excluded from scope. Document in PR description that `server/pdf-linearize.ts:26` has a third `sanitizeForLog` copy using `"?"` replacement and why it's NOT folded in (different replacement character, serves qpdf stderr readability, not log injection defense).

## Acceptance Criteria

- [x] `apps/web-platform/lib/log-sanitize.ts` exists and exports `sanitizeForLog(s, maxLen=500)`.
- [x] `apps/web-platform/app/api/analytics/track/sanitize.ts` re-exports `sanitizeForLog` from the shared helper (no body).
- [x] `apps/web-platform/lib/auth/validate-origin.ts` `rejectCsrf` uses `sanitizeForLog(origin ?? "none", 100)`.
- [x] `apps/web-platform/server/rate-limiter.ts` exports `startPruneInterval` and has 4 one-line call sites instead of 4 inline `setInterval + unref` blocks.
- [x] `apps/web-platform/app/api/analytics/track/throttle.ts` uses `startPruneInterval(analyticsTrackThrottle)`.
- [x] JSDoc blocks exist on both `extractClientIp` (IncomingMessage variant, `remoteAddress` fallback) and `extractClientIpFromHeaders` (Headers variant, `"unknown"` fallback) explaining the intentional asymmetry.
- [x] `route.ts:6` import `import { sanitizeProps, sanitizeForLog } from "./sanitize"` is unchanged (re-export preserves it).
- [x] `route.ts` has zero exported non-HTTP symbols (`cq-nextjs-route-files-http-only-exports` preserved).
- [x] Unit tests added for `sanitizeForLog` (control-char strip, U+2028/29 strip, maxLen default + custom) and `startPruneInterval` (Node Timeout handle with `.unref`, fires `prune` on default + custom cadence, Layer-2 helper-invariant source regex).
- [x] T2b in `test/api-analytics-track.test.ts` migrated to the two-layer pattern (delegation check on `throttle.ts` + invariant check on `rate-limiter.ts`).
- [x] All existing tests for affected modules pass without modification (T2a behavioral test unchanged; `extractClientIp` tests unchanged; `share-links.test.ts` `extractClientIpFromHeaders` tests unchanged).
- [ ] PR body contains three separate lines: `Closes #2459`, `Closes #2460`, `Closes #2461`. Neither in the title nor qualified with "partially".
- [ ] PR description references PR #2486 as the batched-cleanup pattern AND the 2026-04-15 negative-space-tests-must-follow-extracted-logic learning (as the reason T2b changed).
- [x] No edits to any file outside the 7 files listed in Files to Create / Files to Edit (enforced by `git diff --name-only main...HEAD` prior to push). The 7th file (`test/api-analytics-track.test.ts`) changes MUST be limited to T2b's two regex assertions.
- [ ] `npx markdownlint-cli2 --fix` clean on the plan file and on any new .md docs.

## Test Scenarios

### `sanitizeForLog` (new unit tests — `test/log-sanitize.test.ts`)

| # | Input | Args | Expected |
|---|---|---|---|
| 1 | `"a\x00b\x1fc\x7fd"` | default | `"abcd"` |
| 2 | `"a\u2028b\u2029c"` | default | `"abc"` |
| 3 | `"x".repeat(1000)` | default | length 500 |
| 4 | `"x".repeat(200)` | `maxLen: 100` | length 100 |
| 5 | `"hello world"` | default | `"hello world"` unchanged |

### `startPruneInterval` (new cases in `test/rate-limiter.test.ts`)

| # | Scenario | Expected |
|---|---|---|
| 1 | `startPruneInterval(counter)` — inspect the returned handle without fake timers; `clearInterval(handle)` at end | `typeof handle.unref === "function"` (Node Timeout invariant); no throw |
| 2 | Under `vi.useFakeTimers()`, `vi.spyOn(counter, "prune")`; call `startPruneInterval(counter)`; `await vi.advanceTimersByTimeAsync(60_000)` twice | `prune` called twice, in order |
| 3 | Same setup, pass `ms = 5_000`; advance `4_999` ms → prune NOT called; advance `1` ms → called once; advance `5_000` → called twice | Interval cadence respects custom `ms` argument exactly |
| 4 | Source-level (Layer 2): read `server/rate-limiter.ts`, regex match `/export function startPruneInterval[\s\S]*setInterval\([\s\S]*\.prune\(\)[\s\S]*\.unref\(\)/` | Helper body still contains `setInterval`, `.prune()`, and `.unref()` — prevents silent regression where the helper drops invariants |

### Migrated T2b (in `test/api-analytics-track.test.ts`)

| # | Scenario | Expected |
|---|---|---|
| T2b-L1 | Read `throttle.ts`, regex match `/startPruneInterval\(\s*analyticsTrackThrottle\s*\)/` | `throttle.ts` proves it delegates to the helper with the correct counter |
| T2b-L2 | Read `rate-limiter.ts`, regex match helper-body regex (same as Test 4 above) | Shared helper still carries the invariant |

### Regression coverage (existing tests must continue to pass)

- `test/rate-limiter.test.ts` — 6 tests for `SlidingWindowCounter`, 5 for `PendingConnectionTracker`, 6 for `extractClientIp`.
- `test/share-links.test.ts` — 4 tests for `extractClientIpFromHeaders`.
- `test/api-analytics-track.test.ts` — all tests other than T2b unchanged (the `sanitizeForLog` re-export in `sanitize.ts` preserves the named import at `route.ts:6`, so behavioral tests continue to exercise the shared helper). **T2b is migrated** to the two-layer delegation + invariant pattern.
- WS mock tests — unchanged (mocks return a fixed IP string, the extractor signatures don't change).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Regex widening at `rejectCsrf` call site changes a log line consumers depend on | Low | Low | Structured log field; consumers parse JSON, not line format. U+2028/29 removal doesn't affect JSON grammar. |
| `maxLen = 500` default changes an existing callsite's behavior | Very low | None | The previous `sanitize.ts` `sanitizeForLog` had NO cap. Inputs are already capped upstream (`parsed.goal` ≤ 100, `err` ≤ `MAX_ERR_LOG_LEN`). A 500-char cap is strictly larger than any current input. |
| `re-export` from `sanitize.ts` breaks tree-shaking or module resolution | Very low | Low | Next.js + TS `export { x } from "..."` is canonical; confirmed by checking similar patterns elsewhere in the codebase. Typecheck + vitest run catches any issue. |
| Next.js route-file validator rejects one of our edits | Very low | High | Only files edited are (a) a server/ module, (b) a lib/ module, (c) an App-Router sibling (sanitize.ts, throttle.ts — neither is a `route.ts`). Blast radius matches PR #2401's fix: no `route.ts` edits. |
| `startPruneInterval` changes prune cadence for session throttle | Very low | Medium | Session throttle currently uses 300_000 ms interval. Explicitly pass `300_000` as second arg, do not rely on default. Covered by explicit-ms test case. |
| `setInterval`-spy test strategy is brittle / diverges from codebase convention | N/A | N/A | **Eliminated by deepening.** Replaced with idiomatic `vi.spyOn(counter, "prune") + vi.advanceTimersByTimeAsync` (the pattern used in `test/ws-subscription-refresh.test.ts`) plus a `typeof handle.unref === "function"` check. No brittle returned-handle spy. |
| Negative-space test T2b in `api-analytics-track.test.ts:289-308` silently breaks after extraction | High (would block CI) | Medium (requires plan rework mid-implementation) | **Caught during deepening.** Plan now explicitly migrates T2b in Phase 1 RED alongside the other test edits, using the two-layer pattern from the 2026-04-15 negative-space learning. |
| Helper body regresses later (someone removes `.unref()` from `startPruneInterval` during a future refactor) | Low | Medium | Layer-2 helper-invariant test (Test 4 above) asserts the helper source still contains `setInterval + prune + unref`. A future edit that drops `.unref()` fails this test. |

## Verification Commands

```bash
# Phase 1 (RED) — run before implementation
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cleanup-analytics-rate-limiter-infra/apps/web-platform && \
  ./node_modules/.bin/vitest run test/log-sanitize.test.ts test/rate-limiter.test.ts

# Phase 2 (GREEN) — run after implementation
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cleanup-analytics-rate-limiter-infra/apps/web-platform && \
  ./node_modules/.bin/vitest run test/log-sanitize.test.ts test/rate-limiter.test.ts

# Phase 3 (regression)
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cleanup-analytics-rate-limiter-infra/apps/web-platform && \
  ./node_modules/.bin/vitest run \
    test/rate-limiter.test.ts \
    test/log-sanitize.test.ts \
    test/share-links.test.ts \
    test/api-analytics-track.test.ts \
    test/shared-page-binary.test.ts \
    test/shared-token-content-hash.test.ts \
    test/shared-token-verdict-cache.test.ts \
    test/ws-resume-by-context-path.test.ts \
    test/ws-deferred-creation.test.ts

# Typecheck
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cleanup-analytics-rate-limiter-infra/apps/web-platform && \
  ./node_modules/.bin/tsc --noEmit

# Scope fence verification (before push)
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cleanup-analytics-rate-limiter-infra && \
  git diff --name-only main...HEAD | sort
# Expected set (exactly):
#   apps/web-platform/app/api/analytics/track/sanitize.ts
#   apps/web-platform/app/api/analytics/track/throttle.ts
#   apps/web-platform/lib/auth/validate-origin.ts
#   apps/web-platform/lib/log-sanitize.ts
#   apps/web-platform/server/rate-limiter.ts
#   apps/web-platform/test/api-analytics-track.test.ts   # T2b migration only
#   apps/web-platform/test/log-sanitize.test.ts
#   apps/web-platform/test/rate-limiter.test.ts
#   knowledge-base/project/plans/2026-04-17-refactor-cleanup-analytics-rate-limiter-infra-plan.md
#   knowledge-base/project/specs/feat-cleanup-analytics-rate-limiter-infra/tasks.md

# T2b diff-scope check — the only allowed change in api-analytics-track.test.ts is T2b's two expect().toMatch(...) lines
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cleanup-analytics-rate-limiter-infra && \
  git diff main...HEAD -- apps/web-platform/test/api-analytics-track.test.ts | grep -E '^[+-]' | grep -vE '^(---|\+\+\+)' | wc -l
# Expected: <= ~10 lines (two replaced regexes + small delta). Anything larger = scope creep — investigate.
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure infrastructure/refactor change with no user-facing surface, no product flow impact, no marketing signal, no ops/legal/finance angle. Reviewers: DHH, Kieran, code-simplicity (run via `plan-review` in Phase 5).

## PR Metadata

- **Title:** `refactor: dedupe analytics-track / rate-limiter infra (closes 3 scope-outs)`
- **Body MUST contain** (separate lines, in body not title):

    ```text
    Closes #2459
    Closes #2460
    Closes #2461
    ```

- **Pattern reference (in body):** "Follows the batched-cleanup pattern from PR #2486."
- **Labels:** `type/chore`, `domain/engineering`, `priority/p3-low` (verify exact names with `gh label list --limit 100 | grep -i -E 'chore|engineering|p3'` before running `gh issue/pr create`).
- **Partial fold-in note (in body):** "Partially addresses #2196 item 1 (prune-interval helper). Items 2-5 of #2196 remain open and tracked separately."

## Post-Generation Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-17-refactor-cleanup-analytics-rate-limiter-infra-plan.md. Branch: feat-cleanup-analytics-rate-limiter-infra. Worktree: .worktrees/feat-cleanup-analytics-rate-limiter-infra/. Issues: #2459, #2460, #2461. Plan written + reviewed; implementation next (RED tests first, then GREEN, then regression pass).
```
