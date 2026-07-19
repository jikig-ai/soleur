# Tasks — eliminate Inngest ctx-logger receiver loss at the middleware boundary

---
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-inngest-ctx-logger-receiver-loss-typeerror-plan.md
branch: feat-one-shot-6703-inngest-logger-proxylogger-crash
refs: ["#6703", "#6657"]
---

> **Read the plan's Overview + Research Reconciliation before starting.** The brief's
> prescribed fix (wire the client `logger` to pino) is **falsified** and must NOT be
> implemented. See `decision-challenges.md` in this directory.

## Phase 0 — Preconditions (verify; halt on mismatch)

- [ ] 0.1 Confirm `6496e3398` (PR #6705) is an ancestor of HEAD:
      `git merge-base --is-ancestor 6496e3398 HEAD && echo IN-BRANCH`
- [ ] 0.2 Re-read the pinned vendor files — do NOT trust the plan's quotes:
  - [ ] 0.2.1 `grep -n '"version"' apps/web-platform/node_modules/inngest/package.json` → `3.54.2`. If not, **halt**.
  - [ ] 0.2.2 `sed -n '27,40p' apps/web-platform/node_modules/inngest/middleware/logger.js` — `enabled = false` instance field.
  - [ ] 0.2.3 `sed -n '660,690p' apps/web-platform/node_modules/inngest/components/Inngest.js` — confirm inngest calls `enable()`/`flush()`/`error()` on **its own closure reference** (`:673`), not on the transformed ctx. **VERIFIED at plan time** against inngest 3.54.2 — this re-check exists only to catch a version drift. If the SDK now reads the logger back off ctx, the approach is unworkable; halt and re-plan.
  - [ ] 0.2.4 Confirm the built-in logger middleware is **prepended** so ours runs after and sees the real `ProxyLogger`: `grep -n 'builtInMiddleware' apps/web-platform/node_modules/inngest/components/Inngest.js` → expect `[...builtInMiddleware, ...middleware || []]` (`:162`). **VERIFIED at plan time.**
  - [ ] 0.2.5 Confirm `transformInput` ctx merging is a shallow spread in array order (last write wins), so returning `{ ctx: { logger } }` clobbers nothing else: `sed -n '1085,1100p' apps/web-platform/node_modules/inngest/components/execution/v1.js`. **VERIFIED at plan time.**
- [ ] 0.3 Confirm zero existing detachment sites (both greps must return empty):
  - [ ] `grep -rnE "(const|let|var)\s+\w+\s*=\s*\w*[Ll]ogger\.(info|warn|error|debug)\s*[;,)]" apps/web-platform/server apps/web-platform/app`
  - [ ] `grep -rnE "\(\s*\w*[Ll]ogger\.(info|warn|error|debug)\s*\)" apps/web-platform/server`
- [ ] 0.4 Baseline green: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0.

> Runner forms: typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
> (**never** `npm run -w …` — no root `workspaces`). Tests are **vitest**
> (`./node_modules/.bin/vitest run <path>`), **never** `bun test`.

## Phase 1 — RED (write the failing test first)

- [ ] 1.1 Create `apps/web-platform/test/server/inngest/bound-logger-middleware.test.ts`.
- [ ] 1.2 Build a `ProxyLoggerLike` **class** fake — `enabled` as an initialized instance field, each method opening `if (!this.enabled) return;`. **Must be a class**; an object literal cannot reproduce receiver loss.
- [ ] 1.3 Assert the RED on the raw logger: detached `raw.info` throws `/Cannot read properties of undefined \(reading 'enabled'\)/`.
- [ ] 1.4 Assert the target behaviour (fails today — no middleware exists): detached `bound.info` does **not** throw **and** the call still reaches the underlying logger.
- [ ] 1.5 Add the five-shape loop: extract, destructure, `forEach`, `setTimeout`, `.catch` — none throw.
- [ ] 1.5a **Fail-open cases:** `applyBoundLogger(undefined)` / `applyBoundLogger(null)` do not throw and leave ctx untouched.
- [ ] 1.5b **Surface-preservation cases:** a logger with `debug` + a non-function `level` exposes both through the facade; `const d = bound.debug; d("x")` does not throw.
- [ ] 1.5c **Anti-vacuity mutation control:** replace `v.bind(target)` with `v` and confirm the suite goes **RED**. Record the result in the PR body. A suite that stays green with the bind deleted is measuring nothing.
- [ ] 1.6 Add the gate-preservation case: with `enabled === false`, a bound call delivers **zero** calls to the underlying logger.
- [ ] 1.7 **Run it and capture the failure output** — this is the AC3 evidence quoted in the PR body.

## Phase 2 — GREEN (bind at the boundary)

- [ ] 2.1 Create `apps/web-platform/server/inngest/middleware/bound-logger.ts` exporting `boundLoggerMiddleware`, mirroring `run-log.ts`'s `InngestMiddleware` → `init()` → `onFunctionRun()` → `transformInput({ ctx })` structure.
- [ ] 2.2 Return `{ ctx: { logger: new Proxy(raw, { get(target, prop, receiver) { const v = Reflect.get(target, prop, receiver); return typeof v === "function" ? v.bind(target) : v; } }) } }`.
  - [ ] 2.2-i **Do NOT use three arrow closures** (`{ info: (...a) => raw.info(...a), … }`). `ProxyLogger`'s constructor Proxy forwards unknown props to the underlying logger, so the real ctx logger also carries `debug`, `child`, `trace`, `fatal`, `level`. A three-method object drops them all → `TypeError: logger.debug is not a function`. That trades one crash for another.
  - [ ] 2.2-ii Bind to `target`, **not** `receiver` — binding to the outer Proxy re-enters the trap on every internal `this.*` access inside `ProxyLogger`.
- [ ] 2.2a ‼️ **Capture `ctx.logger` inside `transformInput`, NEVER inside `onFunctionRun`.** `run-log.ts` documents that `onFunctionRun`'s ctx is Inngest's `InitialRunInfo` (`{ event, runId }` only); the full run ctx reaches `transformInput` alone. Reading `logger` off the `onFunctionRun` ctx yields `undefined` and the facade forwards to nothing — **silent log loss across all 60+ crons with no error to detect it.**
- [ ] 2.2c ‼️ **FAIL-OPEN guard — load-bearing.** `if (!raw || typeof raw !== "object") return;` BEFORE constructing the Proxy. `new Proxy(undefined, …)` **throws**, and a throw in `transformInput` would **red every cron on the surface**. Returning `undefined` makes the waterfall pass `prev` through unchanged. Comment it as the sanctioned observability-of-observability exemption to `cq-silent-fallback-must-mirror-to-sentry` (same call as `cert-reissue-marker.ts:34-37`).
- [ ] 2.2b Scope the middleware to **all** functions — do NOT copy `run-log.ts`'s `if (!(fnId in ROUTINE_METADATA)) return {};` gate. Scoping would leave the un-scoped majority exposed to the bug being eliminated.
- [ ] 2.3 Register in `apps/web-platform/server/inngest/client.ts`: append `boundLoggerMiddleware` **last** in the `middleware` array.
- [ ] 2.4 Comment the ordering rationale (it wraps an already-composed ctx).
- [ ] 2.5 **Do NOT** add a `logger:` option to `new Inngest({...})`.
- [ ] 2.6 **Do NOT** modify `_cron-shared.ts` — `HandlerArgs["logger"]` needs no change.
- [ ] 2.7 Re-run Phase 1 tests → all green.

## Phase 3 — Fleet-wide verification

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0.
- [ ] 3.2 Record covered surface: `grep -rl "inngest.createFunction" apps/web-platform/server/inngest/functions/ | wc -l` → note in PR body.
- [ ] 3.3 `./node_modules/.bin/vitest run test/server/inngest/` → green.
- [ ] 3.4 Confirm `sentry-correlation` + `run-log` suites pass **unmodified**: `git diff --name-only $(git merge-base origin/main HEAD) -- 'apps/web-platform/test/server/inngest/*sentry*' 'apps/web-platform/test/server/inngest/*run-log*'` → empty.
- [ ] 3.5 Full-suite exit gate: `cd apps/web-platform && ./node_modules/.bin/vitest run` → green.

## Phase 4 — Correct the record (do NOT close anything)

- [ ] 4.1 Comment on #6703 recording the falsification (see plan Phase 4 for required content).
- [ ] 4.2 Confirm #6703 and #6657 are both still `OPEN`.
- [ ] 4.3 PR body uses `Ref #6703` / `Ref #6657` — **no** closing keyword for either.
- [ ] 4.4 PR body states the non-overclaim (AC10): client logger deliberately not wired; `enabled` gate still suppresses ctx logs on replay passes; observability class **not** fixed.
- [ ] 4.5 Ensure `decision-challenges.md` is surfaced by `/soleur:ship` (DC-1 and DC-2 are user-challenges needing an operator decision).

## Phase 5 — Learnings

- [ ] 5.1 Capture a learning: *"`enabled === false` is not `enabled === undefined`"* — a plausible causal chain that nobody compiled, propagated from a live incident into an issue body into a task brief.
- [ ] 5.2 Capture: *elimination beats detection* — a ~20-line binding Proxy removed a class that a `this`-parameter type guard could only partially detect (it misses `p.catch(logger.error)` and `setTimeout(logger.info, 0)`), while guarding a type severed from the SDK by 65 `as unknown as` casts.
- [ ] 5.3 Capture: *the obvious facade drops the passthrough surface* — three arrow closures would have traded `Cannot read properties of undefined (reading 'enabled')` for `logger.debug is not a function`, because `ProxyLogger`'s constructor Proxy forwards unknown props to the underlying logger. Wrapping a Proxy needs a Proxy, not a literal.
