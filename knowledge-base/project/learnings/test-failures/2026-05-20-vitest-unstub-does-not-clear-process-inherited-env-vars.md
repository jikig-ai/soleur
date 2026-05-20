---
title: "vitest: `unstubAllEnvs()` does not delete process-inherited env vars (Doppler/CI leak class)"
date: 2026-05-20
category: test-failures
module: apps/web-platform
tags:
  - vitest
  - doppler
  - env-vars
  - test-isolation
  - flake-class
related-prs:
  - 4141
related-issues:
  - 4128
  - 4155
---

# Learning: vitest `unstubAllEnvs()` does not delete process-inherited env vars

## Problem

A vitest test asserting a default-OFF code path passed in plain `npx vitest run …` but failed deterministically under `doppler run -p soleur -c dev -- npx vitest run …`.

Concrete shape from `apps/web-platform/test/cc-dispatcher.test.ts > T-W4-basic-off`:

- `apps/web-platform/server/cc-dispatcher.ts:425` reads `process.env.CC_PERSIST_USAGE === "true"` to gate a usage-cost INSERT on assistant rows.
- The test scrubs prior stubs via `vi.unstubAllEnvs()` in `beforeEach` and never re-stubs — the default-off path should fire.
- `doppler secrets get CC_PERSIST_USAGE -p soleur -c dev --plain` returns `true`.
- Repro:
  - `CC_PERSIST_USAGE='' npx vitest run test/cc-dispatcher.test.ts` → 42/42
  - `doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts` → 41/42 (T-W4-basic-off only)

The failure looked like a flaky test but was 100% deterministic given the env.

## Root Cause

`vi.unstubAllEnvs()` reverts `vi.stubEnv(...)` writes only. It restores `process.env` to the value it held **at vitest module-load time**. If a value was inherited from the parent process (Doppler injecting `CC_PERSIST_USAGE=true` at `doppler run` spawn, CI runner secrets, dev-shell `export`), `unstubAllEnvs` cannot delete it — there is no "delete" semantic, only "revert to load-time value." The load-time value WAS `"true"`.

Test code authors reading `vi.unstubAllEnvs()` reasonably assume "reset env to a clean default" semantics. The vitest docs make the distinction (`unstubAllEnvs` reverts "stubs"), but the trap surface is large because the failure mode is silent until a specific env injection kicks in (production CI, Doppler dev).

## Solution

Explicit force-empty in `beforeEach` AFTER `unstubAllEnvs`:

```ts
beforeEach(() => {
  // existing scrubs
  vi.unstubAllEnvs();

  // Doppler `dev` injects CC_PERSIST_USAGE=true at process spawn.
  // unstubAllEnvs() reverts stubEnv writes only; it cannot delete a
  // process-inherited env var. Force-empty here so default-off tests
  // see a falsy value at the strict `=== "true"` check downstream.
  vi.stubEnv("CC_PERSIST_USAGE", "");
});
```

Tests that need the flag ON continue to call `vi.stubEnv("CC_PERSIST_USAGE", "true")` in their own bodies. `vi.stubEnv` is overwrite-semantics, so the local "true" wins over the beforeEach "" default. Validated empirically: 42/42 pass; pre-fix was 41/42.

The empty-string value works because the runtime check is strict `=== "true"`. For checks using `Boolean(process.env.X)` truthy-coercion, force to `"false"` or `"0"` instead — any non-empty string is truthy in coercion.

## Key Insight

**`vi.unstubAllEnvs()` is a "revert" operation, not a "clean" operation.** Tests asserting a default-off path under any env-injection environment (Doppler, CI secrets, `direnv`, devcontainer envs) must explicitly force the off-value via `vi.stubEnv(KEY, "")` in `beforeEach`. The trap surface is widest for boolean flags read as strings (`=== "true"`) because the default-off path *looks* unset in unit tests but *is* set in integration runs.

Cheapest detection: when adding a `process.env.X`-gated code path, grep tests asserting the off-path for an explicit `stubEnv(X, "")` in their `beforeEach`. If absent, the test's signal under Doppler/CI is unreliable.

## Prevention

- **For any test asserting a `process.env.X === "true"`-gated off-path:** add `vi.stubEnv("X", "")` to `beforeEach` regardless of whether the local Doppler config currently injects the var. The Doppler config can change; the test should be hermetic against any parent-process env.
- **When designing the runtime flag:** prefer strict `=== "true"` over `Boolean(process.env.X)`. Strict comparison lets tests force-off with `""`; truthy coercion would treat `""` as falsy too, so behaviour is equivalent — but strict comparison is also greppable for the literal `"true"` and is harder to mis-read.
- **When debugging a "test passes in CI but fails under `doppler run`" (or vice-versa) shape:** check the test's `beforeEach` for `unstubAllEnvs()` without a corresponding `stubEnv(KEY, "")` BEFORE assuming a runtime bug. The Doppler-vs-plain divergence is a leading indicator.

## Session Errors

Session error inventory: none material.

- One empty `Edit` tool call with no parameters during compound's plan-checkbox marking phase produced an `InputValidationError`. Recovered immediately by issuing the next Edit with full parameters. **Prevention:** ensure every Edit invocation carries `file_path`, `old_string`, `new_string` — never close a parallel Edit batch with a placeholder/empty call.

## Related

- `apps/web-platform/server/cc-dispatcher.ts:425` — strict `=== "true"` flag-read site
- `apps/web-platform/test/cc-dispatcher.test.ts` — `beforeEach` scrub pattern
- `apps/web-platform/vitest.config.ts` — `testTimeout: 16_000` + `hookTimeout: 20_000` (the second half of #4128's fix; flake-class not env-leak)
- [`2026-04-18-bun-test-env-var-leak-across-files-single-process.md`](2026-04-18-bun-test-env-var-leak-across-files-single-process.md) — bun-test sibling, single-process leak
- [`2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`](2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md) — module-scope stub leakage
- [`2026-05-05-weakset-shared-dag-over-skip-recursive-scrubber.md`](../2026-05-05-weakset-shared-dag-over-skip-recursive-scrubber.md) — inverse leak class (test SETS var, sibling reads stale)
- Issue #4128 — pre-existing apps/web-platform suite failures
- Issue #4155 — ECONNREFUSED-on-127.0.0.1:3000 transient (separate flake class, scoped out of #4128)
- PR #4097 — prior stabilization (`pool: "forks"` + `isolate: true`)
