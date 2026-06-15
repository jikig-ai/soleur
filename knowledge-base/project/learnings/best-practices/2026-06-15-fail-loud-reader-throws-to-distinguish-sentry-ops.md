---
title: "A fail-loud DB reader should THROW (not return null) on read error when the caller must distinguish error-class Sentry ops"
date: 2026-06-15
category: best-practices
module: apps/web-platform/server
tags: [observability, error-handling, fail-loud, sentry, plan-tension]
pr: 5338
issue: 5240
---

# Fail-loud reader: throw on read error to preserve the two-op observability contract

## Problem

PR #5338 (AC4 of #5240) added a durable workspace-binding resolver. Its DB reader
`readWorkspaceIdFromDb` is a fail-loud sibling of `resolveCurrentWorkspaceId`
(which `?? userId` solo-falls-back — the cross-tenant-write hazard #5256 removed).

The plan text said the reader should "return `?? null` on success **and `null` on
read error**." But the plan's own `## Observability` section required the durable
resolver to fire **two distinct** Sentry ops:
- `resolveUserWorkspaceBinding.unresolvable` — user genuinely has no binding (DB row absent / column null)
- `resolveUserWorkspaceBinding.db-read` — a transient DB read failure

If the reader collapses both "absent" and "read error" into `null`, the resolver
sees only `null` and **cannot** distinguish the two — the two-op contract becomes
one op, and a transient infra blip gets mislabeled as "user genuinely unbound."

## Solution

Make the reader **throw** on `result.error` and return `?? null` ONLY on the
success path. The caller's `try/catch` then distinguishes:
- closure throws → catch → Sentry op `db-read` → rethrow (fail loud)
- closure returns `null` → Sentry op `unresolvable` → throw (fail loud)

This also honors the plan's "do NOT swallow" directive (returning `null` on an
error IS swallowing). The fail-loud *decision* still lives in one place (the
resolver); the reader just surfaces the error/absent distinction the resolver
needs.

## Key Insight

When a plan prescribes a reader's return shape (`?? null`) AND a separate
Observability section requires the caller to emit **distinct error-class signals**,
the two can conflict. The Observability contract wins: a reader that flattens
"absent" and "errored" into one sentinel destroys the caller's ability to label
them differently. Prefer **throw-on-error + null-on-absent** so the boundary stays
information-preserving. Verify the distinction with tests that assert the exact
Sentry `op` slug per branch (`mock.calls[0][1].op`), not just "it threw."

## Session Errors

All recurring items below are already covered by existing work/review-skill
guidance — no new rule warranted; listed for completeness.

1. **`vi.mock` factory referenced a top-level spy → `ReferenceError: Cannot access before initialization`.** Recovery: wrap the spy in `vi.hoisted(() => ({ spy: vi.fn() }))`. Prevention: existing work-skill rule — "use `vi.hoisted()` from the start; vitest hoists `vi.mock` above `const`/`let`."
2. **Source-swapping a registry function consumers call broke a test that only stubbed the OLD function** (`ws-deferred-creation.test.ts`: stubbed `getUserWorkspace`, not the new `resolveUserWorkspaceBinding`). Recovery: add the new function to the same registry mock. Prevention: existing work-skill rules — "hook-source-swap sweep all real renderers" / "wrapper-extension test-mock-chain sweep" — when a consumer switches to a new registry export, grep every test mocking that registry and stub the new export.
3. **Bash tool CWD drifted across calls → `No such file or directory` on relative paths.** Recovery: use absolute paths or single-call `cd <abs> && cmd` chains. Prevention: existing rule — "the Bash tool does NOT persist CWD across calls."
4. **A review agent (`data-integrity-guardian`) read the stale bare-root mirror** (paths without `.worktrees/`) and false-flagged an already-removed import. Recovery: re-verify against the worktree file before accepting. Prevention: existing bare-repo-grep learnings — verify agent file-path provenance is the worktree, not the bare-root sync mirror.
5. **Planning subagent `Write` blocked by the bare-root-protection hook, auto-re-targeted.** One-off; hook worked as intended.

## Tags
category: best-practices
module: apps/web-platform/server
