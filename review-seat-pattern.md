# Review Seat: pattern-recognition-specialist — PR #11780 (#11772)

Diff reviewed: `git diff origin/main...HEAD` (12 files, +920/−51).
Seat focus: predicate/branch pattern match vs existing handler, test-arm consistency
with suite conventions, near-miss copy drift.

## Verdict: FINDINGS — 0 P1, 1 P2, 4 P3

All settled rulings (exact-pair scope, prod-wide, warnSilentFallback, team_names
deferral, defense-in-depth) are honored by the diff as written — none contradicted.
Verified green locally: `vitest run test/crash-handlers.test.ts` 10/10,
`test/egress-audit-ingest.test.ts` 50/50, `assert-dependabot-drain.py` live
(36 rows / 36 resolved, `next 16 >=16.4.1 ['16.4.3'] OK`).

## P2

1. **Stale fixture comment — copy drift.** `scripts/assert-dependabot-drain.test.sh:105-106`
   still reads "`next` is not in WATCHED_PACKAGES, so the completeness sweep does not
   require a covering row." This PR adds `"next"` to `WATCHED_PACKAGES`
   (`assert-dependabot-drain.py:53`), so the premise is now false. Behavior is still
   correct (the new `("web-platform","next",16,"16.4.1")` row covers the fixture's
   `("next", 16)` entry at line 94), but in this file comments are load-bearing
   documentation — a future maintainer relying on the stale claim would misdiagnose a
   completeness-sweep failure. Reword to "`next` is watched and the web-platform row
   covers it."

## P3

2. **Missing negative assertion on one near-miss arm.**
   `test/crash-handlers.test.ts:180-190` ("Error('aborted') without .code still exits")
   asserts `exitSpy` + `captureException` but omits
   `expect(warnSilentFallback).not.toHaveBeenCalled()` — the assertion its three
   sibling fatal-path arms (lines 192-220) all carry. A warn-then-exit regression
   would pass this arm while failing its siblings; one line restores parity.

3. **Mixed async style within one describe.** Arms at lines 144 and 162 use
   `return listeners().then(({ uncaught }) => ...)` while arms 180-220 use
   `await listeners()`. Same-describe convention split; trivial.

4. **Real `process.on` listener accumulation in tests.** The `listeners()` helper
   (lines 124-136) spies on `process.on` without `mockImplementation`, so
   `installCrashHandlers()` registers real handlers that are never removed —
   7 `uncaughtException` + 7 `unhandledRejection` pairs accumulate across the file
   (pre-existing test at 104-112 already contributed 1). Under Node's default cap of
   10 today, but +3 future arms trips `MaxListenersExceededWarning`, and a stray real
   rejection landing after `exitSpy.mockRestore()` would run 7 stacked fatal handlers
   → real `process.exit` killing the test worker. Convention-consistent as written;
   worth a `process.removeAllListeners` in `afterEach` if arms grow.

5. **Plan-doc vs code drift (two spots).**
   `knowledge-base/project/plans/2026-11-01-fix-next-16-4-1-e2e-dev-server-crash-plan.md`
   (a) lines ~76/~590 claim `dsar-export.ts` throws `new Error("aborted")` at
   "35 sites" — actual count is 48 (all `throw new Error("aborted")`; co-uploader +4
   is correct); the "CTO-verified" measurement is stale though the conclusion holds.
   (b) Guard-2 matrix row 2 claims an `includes("abort")` widening is "pinned by a
   same-code-different-message arm", but the armed near-miss message is
   `"socket hang up"` — no "abort" substring — so that exact mutation would survive
   undetected (arm a message like `"request aborted by peer"` to pin it).

## Clean patterns confirmed

- **Zero branch copy drift:** the two classify-and-return blocks
  (`crash-handlers.ts:84-90`, `:94-100`) are byte-identical modulo the pre-existing
  param names (`err`/`reason`), exactly mirroring the sibling handlers' shape.
- **Predicate ordering correct:** `instanceof Error` short-circuits non-Error
  rejection reasons before `.message`/`.code` reads; `err is Error` type-predicate
  accurate; exact-pair honored (code-less `aborted`, wrong-message ECONNRESET,
  DOMException AbortError all stay fatal — armed).
- **`warnSilentFallback` usage matches contract:** `(rawErr: unknown, options:
  SilentFallbackOptions)` with `{feature:"crash-handlers", op:"client-abort"}` —
  kebab-case tags identical to the ~40 existing call sites; mock wiring
  (`const warnSilentFallback = vi.fn()` + forwarder factory) byte-identical to
  `ws-boundary.test.tsx:26-29` convention; `mockClear()` added to `beforeEach`.
- **Drain-guard arithmetic internally consistent:** 27 prior + 8 batch + 1 next =
  36; `MIN_ROWS`/`MIN_RESOLVED` 35→36, `MIN_ASSERTIONS` 33→34, spec-grep arm
  `next:16:16.4.1`, `WATCHED_PACKAGES` alphabetical placement, `FLOOR_ANCHORS`
  comment style matches siblings, REQUIRED comment narrative updated.
- **Completeness sweep safe:** `next` appears only in `apps/web-platform`'s lockfile
  (root/pencil-setup/pen-cli/spike all 0); single covering row suffices.
- **Cross-file pins:** egress `^16\.4\.` pin updated with the 16.4.3 re-measurement
  comment preserved; no other stale `16.3` pins; `server/index.ts:83` registers the
  handlers before `app.prepare()` (line 90); boot-pin test mocks only
  `installCrashHandlers` and index.ts imports nothing else from the module — no
  mock-surface drift.
- **ADR-062 amendment** matches the shipped predicate verbatim (exact pair,
  `feature=crash-handlers`, `op=client-abort`) and records rejected alternatives.
