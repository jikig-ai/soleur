---
category: test-failures
module: pre-merge-rebase-hook-tests
date: 2026-04-22
pr: 2816
issue: 2801
tags: [bun-test, path-stubbing, gh-cli, ci-flake, signal-drift]
---

# Learning: PATH-prefix gh stubs must touch sentinels inside recognized dispatch branches, not before

## Problem

Two tests in `test/pre-merge-rebase.test.ts` intermittently timed out at bun-test's 5000ms
default on CI. The hook at `.claude/hooks/pre-merge-rebase.sh` shells out to
`gh issue list --label code-review --search "PR #N" ...` on its Signal 3 code path, and
the combination of (a) authenticated GitHub API rate-limit backoff and (b) shared CI
runner contention pushed the subprocess past 5s often enough to matter.

## Solution

Two layers:

1. **PATH-prefix stub.** In `beforeAll`, `mkdtempSync` a `hook-test-bin-` dir, write a
   bash shim named `gh`, `chmodSync(..., 0o755)`, and prepend the dir to the env object
   that Bun.spawn receives (`GIT_ENV.PATH = \`${binDir}:${originalPath}\``). The stub
   echoes empty stdout and exits 0 — the hook's downstream `jq '.[0].number // empty'`
   yields `""`, which the hook treats as "no review issue found" (matching the live-API
   behavior minus the wall-clock variance).

2. **Sentinel inside the recognized branch, not before the case.** The stub's `touch
   .gh-called` goes inside `"issue list")` only. A catch-all `*)` branch warns to stderr
   and exits 0 **without** touching the sentinel. A per-test `assertStubConsulted()`
   expects the sentinel to exist after the hook runs — so if a future hook change adds
   a new `gh api ...` or `gh repo ...` invocation, the catch-all fires, the sentinel
   stays absent, and the test fails loudly instead of silently accepting the no-op.

Defense-in-depth: per-test timeout raised to 15000ms on only the two Signal-3 tests,
with a named constant `SIGNAL_3_TEST_TIMEOUT_MS` and an inline rationale comment.
Other tests keep the 5s default so real regressions still surface.

```ts
// test/pre-merge-rebase.test.ts beforeAll (abridged)
binDir = mkdtempSync(join(tmpdir(), "hook-test-bin-"));
ghCalledSentinel = join(binDir, ".gh-called");
const ghStub = `#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    touch "$(dirname "$0")/.gh-called"
    exit 0
    ;;
  *)
    echo "[test stub] unexpected gh invocation: $*" >&2
    exit 0
    ;;
esac
`;
writeFileSync(join(binDir, "gh"), ghStub);
chmodSync(join(binDir, "gh"), 0o755);
originalPath = GIT_ENV.PATH ?? "";
GIT_ENV.PATH = `${binDir}:${originalPath}`;
```

## Key Insight

**Sentinel placement matters more than sentinel existence.** A sentinel that fires
unconditionally (before the case dispatch) proves "something invoked gh" but does NOT
prove "the hook's currently-intended code path invoked gh." When the hook evolves, the
unconditional sentinel silently accepts the new shape — the test stays green while the
contract drifts. Moving the sentinel inside the recognized branch turns the stub into
a **contract assertion**: "hook must call `gh issue list` with a shape this stub
recognizes, or the test fails."

Generalizable: any test that stubs a subprocess to isolate it from an external service
should put the "I was consulted" breadcrumb **after** the shape check, not before.
Otherwise the stub degenerates to "anything goes, exit 0" — the exact failure mode the
stub was meant to prevent.

## Related Patterns

- `knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md`
  — established the module-top env-capture discipline this PR extends to `GIT_ENV.PATH`.
- `cq-preflight-fetch-sweep-test-mocks` (AGENTS.md) — same class of "stub must be
  shape-aware, not single-response" pattern, applied to HEAD-vs-GET mocks.
- `cq-raf-batching-sweep-test-helpers` (AGENTS.md) — same class of "when SUT behavior
  changes, test helpers must change in the same edit."

## Session Errors

- **TDD-gate slip (main agent).** Wrote the GREEN version of the stub (with `touch`) on
  the first edit, then had to back the `touch` line out to produce proper RED. Recovery:
  removed touch → RED observed (sentinel missing, both target tests fail) → re-added
  touch → GREEN observed (21/21 pass). **Prevention:** when creating test infrastructure
  that depends on a sentinel-based assertion, write the stub WITHOUT the side effect the
  assertion checks for, verify RED, then add the side effect. This is the same
  RED-first-then-GREEN discipline `cq-write-failing-tests-before` mandates, applied to
  test-infrastructure work (which TDD can rationalize as "exempt").

- **Fragile acceptance-criterion in plan.** Plan included
  `bun test test/pre-merge-rebase.test.ts --timeout=1` as an acceptance check to verify
  inline timeouts override the CLI flag. `--timeout=1` is too tight for `beforeAll`'s
  filesystem + spawn setup — the whole suite failed in `beforeAll` before any test ran.
  **Prevention:** CLI-flag acceptance checks should pick timeouts generous enough to
  not break suite setup. Under 100ms is almost always too aggressive for any bun-test
  suite that uses `Bun.spawn`. Prefer verifying override behavior via a minimal smoke
  test (one test with a sleep + expected timeout) rather than clobbering the suite.

- **Standalone `tsc` reflex (main agent).** Ran `bunx tsc --noEmit
  test/pre-merge-rebase.test.ts` and got 19 noise errors (no tsconfig, missing
  `@types/node`, `@types/bun`, `bun:test` module). This repo has no root tsconfig —
  type-checking happens via bun's built-in inference at test time. **Prevention:** before
  running standalone `tsc`, check if a `tsconfig.json` exists at the expected root. If
  not, rely on the test runner as the type-check.

- **Full-suite 20/22 initial confusion.** `scripts/test-all.sh` reported two failing
  suites (`kb-chat-sidebar`, `chat-surface-sidebar`). Momentary concern that my change
  caused them — resolved by `git diff --name-only origin/main...HEAD` showing only 3
  touched files, none in `apps/web-platform/` where the failures live. Already tracked
  in #2594 (chat-surface / kb-chat-sidebar vitest parallel flake) and #2505.
  **Prevention:** when test-all shows a non-100% pass rate, immediately verify whether
  the failing suites map to files the branch touched. One grep, one minute saved.

- **Planning subagent self-correction (forwarded from session-state.md).** Plan's
  initial claim that `test(name, fn, { timeout: N })` was a vitest-ism that wouldn't
  work in bun-test was falsified by a bun 1.3.11 smoke test in the deepen pass. Plan
  was corrected in-place. **Prevention:** N/A — the deepen pass caught it, which is
  exactly the gate's purpose. Working as intended.
