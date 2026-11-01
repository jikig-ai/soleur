# Code Quality Review — PR #11780 (feat-one-shot-11772-next-dev-server-crash)

Seat: `soleur:engineering:review:code-quality-analyst` (Fowler smell catalog, detection + recommendation only — no code modified).
Scope: `git diff origin/main...HEAD`; focus areas per dispatch: duplicated classify branch, comment quality, test structure (`listeners()` helper, `waitFor` vs sync asserts), readability, dead code. Settled rulings (exact-pair scope, prod-wide, `warnSilentFallback`, team_names deferral, defense-in-depth) checked for contradiction — none found.

## Executive Summary

- Smells: **0 High (P1) / 1 Medium (P2) / 4 Low (P3)**
- Overall quality: **8/10** — tight predicate, exemplary rationale comments, thorough ADR amendment, consistent guard-constant discipline across three files.
- Top recommendations: (1) extract the duplicated classify-and-return block in `installCrashHandlers`; (2) normalize the two `.then()`-style tests to `async/await`; (3) replace the vacuous sync `exitSpy` negative assert with a flushed-tick assert.

## Detailed Findings

### P2-1 — Duplicate Code: identical classify-and-return block in both handlers

- **Location:** `apps/web-platform/server/crash-handlers.ts:84-90` and `:94-100`
- **Smell:** Dispensables › Duplicate Code. Before this PR each listener body was a single `void reportFatalAndExit(...)` call — no duplication. The new 7-line guard clause (`isBenignClientAbort` → `warnSilentFallback(err, {feature:"crash-handlers", op:"client-abort"})` → `return`) is now pasted verbatim into both branches.
- **Severity:** Medium — not causing failures, but the warn-mirror context (`feature`/`op` literals) and the early-return shape are now two-site state: a future change to the non-fatal sink or its tags requires identical edits in both places (shotgun surgery on a 2-site scale).
- **Recommended refactoring:** Extract Method — e.g.
  `function classify(err: unknown, kind: FatalKind): void { if (isBenignClientAbort(err)) { warnSilentFallback(err, { feature: "crash-handlers", op: "client-abort" }); return; } void reportFatalAndExit(err, kind); }`
  then each listener is `process.on("uncaughtException", (err) => classify(err, "uncaughtException"))`. Preserves channel attribution via the existing `FatalKind` parameter.
- **Risk:** Low. **Dependencies:** none. **Effort:** Small.

### P3-1 — Inconsistent test style: `.then()` vs `async/await` in one describe

- **Location:** `apps/web-platform/test/crash-handlers.test.ts:144-160` and `:162-178`
- The first two arms return `listeners().then(({ uncaught }) => { ... })` while the four siblings use `await listeners()` + sync asserts. Same describe, two idioms. No correctness impact; minor readability friction.
- **Fix:** convert both to `async`/`await` to match. **Effort:** Small.

### P3-2 — Synchronous `exitSpy` negative assert cannot observe the failure it names

- **Location:** `crash-handlers.test.ts:158` and `:176` (`expect(exitSpy).not.toHaveBeenCalled()` run synchronously after `uncaught(err)`)
- `reportFatalAndExit` reaches `process.exit(1)` only after `await Sentry.close(...)`, so at the moment these asserts run `exitSpy` could not have been called even on the buggy path — the assert is vacuous for the "would exit later" mutation. The arm is still covered: `captureException`/`close` are invoked synchronously inside `reportFatalAndExit`, so a missing `return` fails those asserts. But the named contract ("does NOT exit") is asserted at a point where it cannot yet be false.
- **Fix (optional):** flush microtasks (`await new Promise(setImmediate)` or `await vi.waitFor(() => expect(warnSilentFallback).toHaveBeenCalled())` then re-check) before the negative assert. **Effort:** Small. **Severity rationale:** Low — coverage hole is nominal because the sibling asserts carry the mutation.

### P3-3 — `find(...)![1]` non-null assertion degrades failure diagnostics

- **Location:** `crash-handlers.test.ts:128-129`
- `onSpy.mock.calls.find((c) => c[0] === name)![1]` throws a bare `TypeError` (reading `[1]` of `undefined`) if registration is ever dropped, instead of a useful "listener not registered" message.
- **Fix:** `expect`-guard the find or throw with the event name. **Effort:** Small.

### P3-4 — `err is Error` under-specifies the predicate; unused `export`

- **Location:** `crash-handlers.ts:74`
- The type predicate narrows to `Error`, but the actual guarantee is `Error & { code: "ECONNRESET" }`. Callers only use it as a boolean so there is no live cost; a `code`-branded predicate type would be self-documenting. Related: the `export` has no consumer outside this file (verified by grep — tests exercise it through the listeners, `index.ts:83` imports only `installCrashHandlers`). Defensible as seam-for-future-tests and the ADR cites it by name (`crash-handlers.ts › isBenignClientAbort`), so keep, but it is nominally Speculative Generality.
- **Fix:** none required; optionally tighten the predicate type. **Effort:** Small.

## Non-findings (checked, clean)

- **Comment quality:** the `isBenignClientAbort` block comment (`crash-handlers.ts:63-73`) is exemplary — mechanism, upstream citation, DoS consequence, and the exact-match-only boundary rationale all present. ADR-062 amendment is consistent with code (predicate shape, sink, tags, deferral to #11783, rejected alternatives).
- **`waitFor` vs sync asserts on fatal paths:** correct — `vi.waitFor` on `exitSpy` is required because `reportFatalAndExit` exits only after the `close()` microtask; using sync asserts there would be the bug, and the author got it right.
- **`listeners()` helper:** sound — spy installed after module import, restored before return, so no real `process.on` listeners accumulate across the 6 arms.
- **Dead code:** none introduced; `log`, `FATAL_FLUSH_MS`, both imports all still live.
- **Guard constants:** `MIN_ROWS`/`MIN_RESOLVED` 35→36, `MIN_ASSERTIONS` 33→34, WATCHED_PACKAGES/`REQUIRED`/`FLOOR_ANCHORS` `next` row, and the test.sh pin list all moved in lockstep — the three-file drift convention is honored.
- **Mock hoist:** `warnSilentFallback` forwarding factory avoids the TDZ-on-hoisted-factory trap; pattern is consistent with the existing `@/server/logger` mock.
- **Settled rulings:** exact-pair predicate matches the CTO ruling verbatim; applied prod-wide to both channels; sink is `warnSilentFallback`; no team_names mock added; no revert hook — all consistent.

## Refactoring Roadmap

1. P2-1 extract classify helper (Small, Low risk) — do first; it shrinks the surface the P3 test nits assert against.
2. P3-1 + P3-2 test-style normalization (Small, Low risk) — one edit pass over the describe.
3. P3-3, P3-4 (Small, Low risk) — opportunistic, can ride along or defer.

Expected quality after roadmap: 8.5–9/10.
