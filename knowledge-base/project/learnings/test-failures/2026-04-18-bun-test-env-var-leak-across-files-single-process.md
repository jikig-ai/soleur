---
module: plugins/soleur/test/ux-audit
date: 2026-04-18
problem_type: test_failure
component: bun_test
symptoms:
  - "Integration test fails with 'Unable to connect https://project-ref.supabase.co'"
  - "Subprocess spawned by test exits non-zero with env-var-related error"
  - "Test that imports a real module silently picks up another test's stub"
root_cause: shared_process_env_mutation
severity: high
tags: [bun-test, test-isolation, env-vars, integration-tests, supabase]
synced_to: [work]
---

# bun:test env-var mutation leaks across files in a single process

## Problem

`bun test plugins/soleur/` runs **all test files in one OS process**. Any test
that mutates `process.env` or `globalThis.*` leaks those mutations to every
other test file in the same run — including subprocesses spawned after the
mutation (they inherit `process.env` at spawn time).

**Real incident (PR #2579):** new `bot-fixture-helpers.test.ts` added
`beforeEach` that set `process.env.SUPABASE_URL = "https://project-ref.supabase.co"`
and `SUPABASE_SERVICE_ROLE_KEY = "service-role-key-stub"` to exercise `sbDelete`
against a mocked `globalThis.fetch`. On the next file (`bot-fixture.test.ts`),
the integration `spawnSync("bun", [SCRIPT, "seed"])` inherited the stub URL and
hit `project-ref.supabase.co` instead of prod — 4 tests failed with opaque
ConnectionRefused errors. The bot-signin test exited status 1 for the same
reason (its `env("SUPABASE_URL")` saw the stub).

## Solution

Capture originals at **module top-level** (executed once at file import) and
restore in `afterEach`. Use `delete` when the original was unset — assigning
`undefined` leaves the key in `process.env` as the literal string `"undefined"`:

```ts
const ORIGINAL_FETCH = globalThis.fetch;
const ORIGINAL_SUPABASE_URL = process.env.SUPABASE_URL;
const ORIGINAL_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe("sbDelete helper", () => {
  beforeEach(() => {
    process.env.SUPABASE_URL = "https://project-ref.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key-stub";
  });

  afterEach(() => {
    globalThis.fetch = ORIGINAL_FETCH;
    if (ORIGINAL_SUPABASE_URL === undefined) {
      delete process.env.SUPABASE_URL;
    } else {
      process.env.SUPABASE_URL = ORIGINAL_SUPABASE_URL;
    }
    if (ORIGINAL_SERVICE_KEY === undefined) {
      delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    } else {
      process.env.SUPABASE_SERVICE_ROLE_KEY = ORIGINAL_SERVICE_KEY;
    }
  });
});
```

Module-top capture is critical: if you grab originals inside `beforeEach`, you
capture the stub from the previous iteration, not the real value. Other test
files must also be `const`-captured at import time (file-load order matters).

## Key Insight

bun:test ≠ vitest. Vitest runs each test file in an isolated worker by default
— env-var mutations don't leak. bun:test runs everything in one process, and
has no built-in `vi.stubEnv`/`vi.unstubAllEnvs` equivalent. Plan for single-
process semantics from the first test file that mutates global state.

## Prevention

- Grep the test directory for `process.env.X = ` before adding a new global
  mutation. If another file reads the same key at module load, you have a
  leak vector.
- Prefer `const client = new Client({ url: stub })` constructor-injection over
  `process.env` mutation when the SUT supports it.
- When the SUT reads env vars at function-call time (not import time), the
  save/restore pattern above is correct.
- The helper test framework will not warn you. Integration failures in a
  sibling file are the only signal.

## Session Errors

- **Test env-var leak hit on first integration run** — Recovery: captured
  `ORIGINAL_*` at module top, added afterEach delete-or-restore. Prevention:
  skill instruction in work Phase 2 — "When a test mutates `process.env` or
  `globalThis.*` in a bun-test file, save originals at module-top and restore
  in afterEach; bun:test shares one process across all files in the run."

## Related

- `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md`
  (bun:test is bun-only, different process model than vitest)
- PR #2579 (fix commit for this incident)
