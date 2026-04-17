---
module: web-platform
date: 2026-04-17
problem_type: test_failure
component: vitest_mock
symptoms:
  - "Tests see empty event data even though fake child explicitly writes it"
  - "Tests time out with 'unhandled error' thrown outside any listener"
  - "Non-deterministic failures that only reproduce with specific test ordering"
root_cause: mock_return_value_captures_eager_value
severity: high
tags: [vitest, mocking, async-events, event-emitter, child_process, queueMicrotask]
synced_to: [work]
---

# vi.fn().mockReturnValue(factory(...)) eagerly evaluates the factory — async-event test doubles must use mockImplementation

## Problem

A vitest-based helper test for `server/pdf-linearize.ts` used a `fakeChild()` helper that returns an `EventEmitter` with a `queueMicrotask` pending to emit `'data'` on stderr and `'close'` on the child. Two of six tests failed:

1. **non_zero_exit test** — asserted `result.detail` matched `/encrypted/`; got `exit=3 stderr=` (empty).
2. **spawn_error test** — timed out at 5000ms; vitest reported `Uncaught Exception: Error: ENOENT`.

Code (the prescribed pattern from the plan):

```ts
mockSpawn.mockReturnValue(
  fakeChild({ exitCode: 3, stderrChunks: [Buffer.from("qpdf: file is encrypted")] }),
);
// ...
const result = await linearizePdf(Buffer.from("%PDF"));
```

## Investigation

- Helper code registers `child.stderr.on("data", ...)` and `child.on("error"/"close", ...)` synchronously after `spawn()` returns. Microtasks scheduled via `queueMicrotask` should fire AFTER the synchronous listener attachment — so chunks should reach the handler.
- Switched from PassThrough streams to direct `EventEmitter.emit("data", ...)` in fakeChild to avoid PassThrough's own asynchronous data-emit semantics. Still failed.
- Added logs: confirmed `queueMicrotask` callback fired BEFORE `child.stderr.on("data")` was registered. The race was pre-SUT, not in the stream layer.

## Root Cause

`vi.fn().mockReturnValue(value)` captures `value` eagerly. The argument expression is evaluated once at the line where `mockReturnValue` is called, not lazily on each invocation of the mock. For plain return values this is correct. For **factories that schedule async side effects**, it is wrong:

```ts
// At test setup time:
mockSpawn.mockReturnValue(fakeChild({...}));
//                       ^^^^^^^^^^^^^^^^
//                       fakeChild runs NOW.
//                       Its queueMicrotask is scheduled NOW.
```

By the time the SUT later calls `spawn(...)` and attaches listeners, the pending microtasks from the fakeChild constructor have already fired. The `'error'` event emitted on an `EventEmitter` with no `'error'` listener crashes Node; the `'close'` event emitted without a `'close'` listener is silently dropped; `'data'` emissions on a `stderr` EventEmitter with no `'data'` listener are also dropped.

**Symptom:** empty event data in assertions OR an uncaught 'error' that vitest reports as "Unhandled Exception."

## Solution

Use `mockImplementation(() => factory(...))` so the factory is called lazily on each `spawn(...)` invocation, AFTER the SUT has registered its listeners:

```ts
mockSpawn.mockImplementation(() =>
  fakeChild({ exitCode: 3, stderrChunks: [Buffer.from("qpdf: file is encrypted")] }),
);
```

For tests that need to retain a reference to the fake (e.g., to assert `child.kill` was called), capture the child inside the implementation:

```ts
let child!: ReturnType<typeof fakeChild>;
mockSpawn.mockImplementation(() => {
  child = fakeChild({ holdOpen: true });
  return child;
});
// ... exercise SUT ...
expect(child.kill).toHaveBeenCalledWith("SIGKILL");
```

## Prevention

- **Rule of thumb:** if the factory schedules ANY async work (`queueMicrotask`, `setImmediate`, `setTimeout`, `process.nextTick`, Promise resolution) before returning, use `mockImplementation`, never `mockReturnValue`.
- `mockReturnValue` is safe for pure values: strings, numbers, plain objects, already-resolved Promises of values.
- When mocking `child_process.spawn`, `fetch`, `WebSocket`, or any constructor-style API that returns an event-emitter-like object, default to `mockImplementation` unless you've confirmed the returned object has no async side effects.

## Related

- `test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` — related vitest timing gotcha (factory closures vs hoisted declarations).
- `test-failures/2026-04-06-vitest-module-level-supabase-mock-timing.md` — another mock-timing issue.

## Session Errors

This learning also captures unrelated errors from the PR #2457 session (PDF linearization on upload) per the session-error workflow rule (`wg-every-session-error-must-produce-either`).

- **Plan-prescribed `fakeChild` used `opts.exitCode ?? 0` which coerces explicit `null` to `0`.** The OS-killed test case (`exitCode: null, exitSignal: "SIGKILL"`) fell through the nullish-coalescing guard and emitted `close(0, "SIGKILL")` instead of `close(null, "SIGKILL")`, so the helper resolved `ok:true` instead of `ok:false`. Recovery: replaced with `opts.exitCode === undefined ? 0 : opts.exitCode`. **Prevention:** when reviewing plan-prescribed JS or TS that branches on nullable values, trace each `?.` / `??` chain for null-vs-undefined semantics — in this case the plan writer intended "preserve explicit null" but the operator collapsed it to 0.

- **`NodeJS.ProcessEnv` requires `NODE_ENV` (Next.js augmentation).** First helper implementation typed `env` as a structural object literal and hit `Property 'NODE_ENV' is missing in type ... but required in type 'ProcessEnv'`. Recovery: `env: env as NodeJS.ProcessEnv` cast. **Prevention:** existing rule `hr-when-a-command-exits-non-zero-or-prints` already covers investigating type errors; no new rule needed.

- **`Buffer.concat` returns `Buffer<ArrayBuffer>` but helper return type is plain `Buffer<ArrayBufferLike>`.** Upload route's `payloadBuffer = result.buffer` hit `Type 'Buffer<ArrayBufferLike>' is not assignable to type 'Buffer<ArrayBuffer>'`. Recovery: explicit `let payloadBuffer: Buffer`. **Prevention:** when a `let` variable initialized from `Buffer.concat` needs to be reassigned from a less-specific `Buffer`-returning helper, annotate explicitly to widen.

- **`new File([new Uint8Array(...)], ...)` fails typecheck with `Type 'Uint8Array<ArrayBufferLike>' is not assignable to type 'BlobPart'`.** Parameter typed `Uint8Array` widens to the generic `ArrayBufferLike` backing, which includes `SharedArrayBuffer`, not accepted by `BlobPart`. Recovery: `new File([content as BlobPart], ...)`. **Prevention:** when a test-helper accepts `Uint8Array` and forwards it to a Web API that requires `BlobPart`, either narrow the parameter type to `Uint8Array<ArrayBuffer>` (preferred) or cast at the boundary.

- **qpdf 11.x does not support `-` as stdin marker.** Plan's core Task 2.0 preflight caught this — `qpdf --help=usage` explicitly states "reading from stdin is not supported." Recovery: pivoted helper to tempfile I/O per plan Task 2.0.1. **Prevention:** already captured in `knowledge-base/project/learnings/best-practices/2026-04-17-plan-preflight-cli-form-verification.md`.

- **`setupFullMocks` didn't default-configure `mockLinearize`.** An unrelated 11MB upload test used filename `large-doc.pdf` (just to test size limits); once the route started calling `linearizePdf`, the unmocked return value (undefined) caused `TypeError: Cannot read properties of undefined (reading 'ok')`. Recovery: default pass-through `mockLinearize.mockImplementation((buf) => ({ok:true, buffer:buf}))` in `setupFullMocks`. **Prevention:** when extending a route with a new server-module dependency, audit the test file's setup helpers for tests that use filenames/extensions that now trigger the new code path.

- **Edit on Dockerfile rejected without prior Read.** First attempt to modify `apps/web-platform/Dockerfile` failed because the Edit tool rejects unread files. Recovery: `Read` first. **Prevention:** already covered by `hr-always-read-a-file-before-editing-it`.

- **Pre-existing flaky test `chat-input-attachments.test.tsx` (50% progress text).** Fails in full-suite run, passes in isolation. Order-dependent / shared-state flake. Recovery: filed #2470 per `wg-when-tests-fail-and-are-confirmed-pre`. **Prevention:** existing rule already handles this case.

- **CWD mismatch — first `git status --short` at the bare repo root returned `fatal: this operation must be run in a work tree`.** Recovery: `cd` into `.worktrees/pdf-linearization`. **Prevention:** already covered by `wg-at-session-start-run-bash-plugins-soleur`.

- **Lost CWD between Bash calls.** After `cd apps/web-platform` in one Bash call, the next call's bare `./node_modules/.bin/vitest run` failed with "No such file or directory." Recovery: included the full `cd` in every bash call. **Prevention:** already covered by `cq-for-local-verification-of-apps-doppler` (failure mode c — "relying on CWD from a prior Bash call").

## Workflow Change Proposals

Only errors NOT already covered by existing rules warrant new workflow changes.

- **Proposal 1 (vi.fn eager-evaluation race — this learning's primary insight).** Enforcement tier: skill instruction. Target: `plugins/soleur/skills/work/SKILL.md` (or a new bullet under the work-skill's test-practice section). Rationale: prose rule is the right tier because this is a code-review judgment call — a PreToolUse hook cannot detect "factory with async side effects passed to mockReturnValue." Skill instruction level because this is guidance the model applies when writing vitest test doubles. Proposed bullet: "When mocking `child_process.spawn`, `fetch`, or any constructor returning an event-emitter, use `mockImplementation(() => factory(...))` — `mockReturnValue(factory(...))` eagerly evaluates the factory at setup and fires async side effects before listeners attach. See `2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race.md`."

- **Proposal 2 (nullish-coalescing trace on plan-prescribed code).** Enforcement tier: skill instruction in the plan-review skills. Target: `plugins/soleur/skills/plan-review/` (or inline in the plan skill). Prose rule ("trace null-vs-undefined semantics in `??` chains") is too narrow for AGENTS.md; better as a plan-review reviewer's sharp-edge. Proposed: add to plan-review or `review` skill references — "When reviewing prescribed JS/TS that branches on nullable values, trace each `??` / `?.` chain for null-vs-undefined semantics; `null ?? 0` is `0`, which may drop an intentional explicit null."

- **No proposal for other errors** — they are already covered by existing rules (`hr-always-read-a-file-before-editing-it`, `wg-at-session-start-run-bash-plugins-soleur`, `cq-for-local-verification-of-apps-doppler`, `wg-when-tests-fail-and-are-confirmed-pre`).
