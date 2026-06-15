# Learning: split new tests by import-weight, not by the plan's "single file" directive

## Problem

PR #5373 (cc-soleur-go durability: schedule the idle reaper + drain `activeQueries`
on SIGTERM) added five tests. The plan prescribed putting all of them in the
existing `test/soleur-go-runner-lifecycle.test.ts` ("no new file; same fixtures").
Three of the tests are runner-level contract tests (`closeAllForShutdown` behavior:
no-checkpoint reason, idempotent-against-grace-abort, drains `awaitingUser`) and
use `createSoleurGoRunner(...)` directly with a spy `onCloseQuery` — **zero module
mocks**. Two of the tests exercise the cc-dispatcher accessors
(`reapIdleCcQueries`/`drainCcQueriesForShutdown` null-guard; `startCcIdleReaper`
scheduling) and must import `@/server/cc-dispatcher`.

Importing `cc-dispatcher` is expensive: its sibling tests pull in a whole
`vi.mock(...)` harness (`@anthropic-ai/claude-agent-sdk`, observability,
ws-handler, logger, inflight-checkpoint, conversation-writer, …). Adding those
`vi.mock` calls to the clean runner-lifecycle file would hoist them to the top of
the file and contaminate the 6 existing mock-free runner tests.

## Solution

Split by import-weight, deviating from the plan's "single file":
- Runner-level contract tests (no mocks) → `soleur-go-runner-lifecycle.test.ts`.
- Dispatcher-accessor tests → `cc-dispatcher-checkpoint-on-disconnect.test.ts`,
  the lightweight #5356 sibling that already carries the minimal cc-dispatcher
  mock set + `__resetDispatcherForTests`/`__setCcRunnerForTests` hooks.

Both files stayed green; the 6 pre-existing runner tests never gained a mock.

## Key Insight

A plan's "put the tests in file X" is authoritative for *intent* (reuse fixtures,
no redundant scaffolding), never for the *physical placement* when X is mock-free
and the new test needs a heavy `vi.mock` harness. `vi.mock` hoists to the top of
the whole file, so co-locating a mock-heavy test with mock-free tests is a
contamination hazard (the documented vitest-hoisting class). Route mock-heavy
tests to the lightest existing sibling that already declares the needed mocks;
keep mock-free contract tests separate. The plan's "no new file" goal is still
honored — neither test created a new file.

Secondary: an exported-but-never-scheduled method (`reapIdle()` here) is a silent
prod gap that `tsc` and unit tests cannot catch — it's the review "method with no
scheduler outside tests" defect class. The cheapest gate is a wiring grep
(`git grep -n 'startCcIdleReaper' apps/web-platform/server/index.ts`) in the AC,
which the architecture review independently confirmed.

## Session Errors

- **Bash CWD non-persistence** — ran `vitest`/`test-all.sh` without `cd` into the
  worktree app dir → `EXIT=127`. Recovery: prefix `cd <worktree-abs> && cmd`.
  Prevention: already covered by existing AGENTS/constitution guidance; one-off
  here, no new rule.
- **Edit "string not found"** — first attempt to strip a `≤`-prefixed comment
  anchor misremembered the line-wrap. Recovery: re-read exact text, then matched.
  Prevention: Read the precise lines before constructing an Edit `old_string`
  spanning a wrapped comment.
- **Read offset past EOF** — requested offset 213 on a 173-line file. Recovery:
  re-read from a valid offset. Prevention: one-off; no rule.

## Tags
category: best-practices
module: apps/web-platform/test
