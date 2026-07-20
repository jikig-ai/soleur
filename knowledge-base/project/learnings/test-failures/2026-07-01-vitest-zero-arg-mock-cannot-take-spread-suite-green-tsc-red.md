---
title: "vi.fn(() => x) with a zero-param impl rejects a `...args` spread (TS2556) — suite-green, tsc-red"
date: 2026-07-01
category: test-failures
module: apps/web-platform/test
tags: [vitest, typescript, mocks, tsc, ts2556]
issue: 5817
---

# Learning: a `vi.fn(() => value)` mock with a zero-parameter implementation cannot be invoked with a `...args` spread

## Problem

`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` failed with:

```
test/git-data-replication.test.ts(23,58): error TS2556: A spread argument must
either have a tuple type or be passed to a rest parameter.
```

The offending fixture:

```ts
const execFileSyncMock = vi.fn(() => Buffer.from(""));            // zero-param impl
// …
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: (...args: unknown[]) => execFileSyncMock(...args), // TS2556 here
}));
```

The full **vitest suite passed** (36/36) while standalone `tsc` failed. That
asymmetry is the trap: vitest type-checks test files **lazily** (it transpiles,
it does not `tsc` them), so a type error in a `.test.ts` ships green in the
suite and only a standalone `./node_modules/.bin/tsc --noEmit` catches it.

## Root cause

`vi.fn(impl)` infers the mock's call signature from `impl`. A `() => Buffer`
implementation infers a **zero-parameter** signature, so `execFileSyncMock(...args)`
spreads a `unknown[]` into a function that declares no rest parameter → TS2556.
Sibling mocks in the same file did NOT trip it because they were declared as
`vi.fn()` (no impl → `(...args: any[]) => any`) or `vi.fn((...args) => …)`.

## Solution

Give the mock a rest parameter so its inferred signature accepts the spread —
matching how the sibling mocks are declared:

```ts
const execFileSyncMock = vi.fn((..._args: unknown[]) => Buffer.from(""));
```

## Key Insight

When a `vi.fn(impl)` mock is invoked via a `(...args) => mock(...args)`
forwarder (the standard `vi.mock` factory shape), the impl MUST carry a rest
parameter (`(..._args: unknown[]) => …`), or `tsc` rejects the spread — even
though the vitest run is green. Always gate test-file type-safety with the
project's pinned `./node_modules/.bin/tsc --noEmit`, never trust the suite pass
alone.

## Session Errors

- **vitest zero-arg mock + `...args` spread TS2556 (suite-green, tsc-red)** —
  Recovery: added a `(..._args: unknown[])` rest param to the mock impl.
  Prevention: this learning + a bullet in the work skill's vitest-mock guidance;
  the standing `tsc --noEmit` work-phase gate is what surfaced it.

## Tags
category: test-failures
module: apps/web-platform/test
