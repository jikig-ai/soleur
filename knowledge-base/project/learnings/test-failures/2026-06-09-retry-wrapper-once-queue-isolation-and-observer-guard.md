# Learning: Retry-wrapper review patterns — once-queue test isolation and diagnostic-observer guards

## Problem

PR #5084 added a Supabase Storage transient-retry leaf (`server/storage-retry.ts`)
wired into the workspace-logo upload route. Implementation and 44 tests shipped
green, but the 10-agent review surfaced two defect classes invisible to the
passing suite:

1. **`vi.clearAllMocks()` does not drain `mockResolvedValueOnce` queues.** The
   route suite's `beforeEach` used `clearAllMocks` (clears call history only)
   while the new retry tests enqueued `mockResolvedValueOnce` fixtures. If a
   test fails before consuming its once-values, the leftover once-impl shadows
   the re-set persistent default in the NEXT test — confusing cascade failures
   whose root cause is two tests away. The inline comment "(keeps no stale
   impls)" was factually wrong about clearAllMocks semantics.
2. **Unguarded diagnostic callback inside a retry loop alters control flow.**
   `opts.onRetry?.(attempt, error)` ran bare inside `withStorageRetry`; a
   throwing observer (observability code) would abort the remaining retries and
   convert a recoverable transient into an unhandled route 500 — bypassing the
   terminal `reportSilentFallback` breadcrumb too. Two agents (architecture +
   security) independently flagged it.

## Solution

- `beforeEach` switched to `vi.resetAllMocks()` (drains once-queues; safe
  because persistent defaults are re-set immediately after) + corrected comment.
- `onRetry` wrapped in try/catch with a comment stating the invariant:
  diagnostic observers must not alter retry control flow. Unit test added that
  drives a throwing observer through the loop and asserts the retry still
  recovers.
- Also added: a throw-propagation test (documented contract "non-StorageError
  throws propagate unchanged" had zero coverage — a catch-everything regression
  would have passed the suite).

## Key Insight

When a test file mixes `mockResolvedValueOnce` fixtures with a
`clearAllMocks`-based `beforeEach`, isolation is already broken — it just
hasn't fired yet. Use `resetAllMocks` + re-set defaults. And any retry/loop
primitive that accepts an observer callback (`onRetry`, `onProgress`,
`onAttempt`) must invoke it inside try/catch: the callback is diagnostic-only
by contract, so a throw from it must never change the primitive's semantics.
Pair every documented "X propagates unchanged" contract line with a test —
contract prose without coverage is a regression invitation.

## Session Errors

1. **Vitest exit 127 from CWD drift** — ran `./node_modules/.bin/vitest` while
   the persistent Bash CWD sat at the worktree root (a prior call had `cd`'d
   there), so the relative binary path resolved nowhere. Recovery: re-ran as
   `cd <app-dir> && ./node_modules/.bin/vitest ...` in a single call.
   **Prevention:** already covered by the work-skill rule "chain
   `cd <worktree-abs-path> && <cmd>` in a single Bash call" — the rule works;
   the failure was skipping it once.
2. **Stale local `main` ref in the GDPR-gate diff** — work Phase 2's gate
   prescribes `git diff main...HEAD`, but in a bare-repo worktree the local
   `main` ref lags origin, so the diff showed unrelated merged branches' files.
   Recovery: re-diffed against freshly fetched `origin/main`.
   **Prevention:** route-to-definition edit applied — work SKILL.md GDPR-gate
   step now prescribes `origin/main...HEAD` (same class as the one-shot
   bare-repo stale-ref guard, #4587).

## Tags

category: test-failures
module: web-platform (storage-retry, workspace-logo route)
pr: #5084
