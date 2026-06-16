---
title: Extracting a route's inline helper pulls the heavy module graph into its static imports — and a new file is a new write-boundary surface
date: 2026-06-16
category: best-practices
module: apps/web-platform
tags: [refactor, static-imports, service-role-allowlist, tdd, extraction, byok-lease]
pr: 5409
---

# Extracting inline logic into a new module: two recurring traps

## Problem

FIX 3 of PR #5409 extracted the post-clone auto-sync block out of
`app/api/repo/setup/route.ts` into a new `server/auto-sync-trigger.ts`. The
extraction was behavior-preserving and its OWN new test passed + `tsc` was clean,
but the **full-suite exit gate** (`test-all.sh` exited 1, 118/119 suites) caught
two regressions the new-file-only checks missed:

1. **`auto-sync-trigger.ts` statically imported `ByokLeaseError` from the heavy
   `byok-lease.ts`.** That import dragged `byok-lease`'s module-init side effect
   (`const log = createChildLogger("byok-lease")` at top level, plus a tenant
   client + crypto graph) into `/api/repo/setup`'s **static** collection graph.
   Previously the route reached byok code only via a *dynamic* `await import()`
   inside a `.then()`, so it never loaded at test-collection. After the static
   import, every setup-route test with an incomplete `@/server/logger` mock
   crashed at collection ("No `createChildLogger` export is defined on the mock").

2. **The route imported `@/server/agent-runner` (the `@anthropic-ai/claude-agent-sdk`
   graph) unconditionally** — `const { startAgentSession } = await import(...)` ran
   *before* `triggerHeadlessSync`'s keyless presence-gate. The pre-extraction code
   only imported agent-runner *after* the key check, so a keyless test never loaded
   it. Two `setup-route-health-scanner` assertions (userHasEffectiveByokKey called,
   conversation INSERT) broke because the `.then()` now threw at the eager import
   before reaching the trigger.

3. **A new `createServiceClient` importer is a new write-boundary surface.** The
   extracted file imports `createServiceClient` and was NOT added to
   `apps/web-platform/.service-role-allowlist` — a CI-blocking `service-role-allowlist-gate.sh`
   failure (P1 at review), and a bypass of the CODEOWNERS security review the
   allowlist exists to force. The *privilege* was not new (it moved verbatim from
   route.ts) but the gate requires it to be **re-declared at its new location**.

## Solution

- **Keep heavy modules off the consumer's static graph when you only need a small
  symbol.** For an error class used only in `instanceof`/`catch` discrimination,
  use a `type`-only import (erased at compile time) and **duck-type** at runtime
  by the constructor-pinned `.name` + discriminant: `err instanceof Error &&
  err.name === "ByokLeaseError" && (err as {cause?:unknown}).cause === "escape"`.
  There is precedent in-repo (`agent-on-spawn-requested.ts classifyAnthropicOrLeaseError`).
- **Lazy-load a heavy SDK behind a thunk** so it loads only when actually invoked:
  `startAgentSession: async (...a) => { const { startAgentSession } = await
  import("@/server/agent-runner"); return startAgentSession(...a); }`. This
  restores the pre-extraction "keyless users never pull the SDK" ordering.
- **Add the new file to `.service-role-allowlist` in the same commit** with a
  justifying comment, mirroring the entry of the file it was extracted from.

## Key Insight

Extraction is never purely mechanical at the import boundary. A new module's
**static** import graph is loaded wherever the new module is statically imported —
so a symbol that used to be reached lazily (`await import`) becomes eager, pulling
module-init side effects (top-level `createChildLogger`, `promisify(execFile)`,
client construction) into every consumer's collection graph. And a new file is a
new **write-boundary / capability surface**: any allowlist, drift-guard, or
CODEOWNERS gate keyed on a per-file grep must be re-satisfied at the new path.
**The new file's own test passing + `tsc` clean is NOT sufficient — run the
EXISTING tests that exercise the extracted code path** (here: `setup-route-*`),
which the full-suite exit gate is designed to surface.

## Prevention

- When extracting code that references a symbol from a heavy module, prefer
  `import type` + duck-type, or a lazy `await import`, over a static value import —
  verify with `grep -rn "@/server/<heavy>" <new-file>`.
- When a new `server/**` file imports `createServiceClient`/`getServiceClient`,
  add it to `.service-role-allowlist` in the same commit (the gate greps every
  `server/**/*.ts`).
- After any extraction, run the **existing** suite for the donor file
  (`vitest run test/<donor>-*.test.ts`) plus the full-suite exit gate, not just
  the new file's test.

## Related
- [[2026-06-10-bot-cron-safe-commit-substrate-symlink-removal]] — top-level
  `promisify(execFile)` in a newly-shared module broke 28 sibling tests at load
  (same static-import-weight class).
- `apps/web-platform/scripts/service-role-allowlist-gate.sh` — the per-file gate.

## Session Errors
1. **Auto-sync extraction broke 2 setup-route test files.** Recovery: type-only +
   duck-typed `ByokLeaseError`, lazy `agent-runner` thunk. Prevention: the import-
   boundary rules above; run existing donor-file tests.
2. **New `createServiceClient` importer not allowlisted (P1).** Recovery: added to
   `.service-role-allowlist`. Prevention: same-commit allowlist entry.
3. **AC1b test pre-staged `.git` and tested the refusal path, not the success
   landing (title oversold).** Recovery: split into a genuine `.git`-lands success
   test (seam performs a real on-disk landing, assert `existsSync` flips
   false→true) + a named refusal test. Prevention: a test asserting an invariant
   that requires a real side effect must drive the seam to produce it, never
   pre-stage the post-state.
4. **Lock predicate `repo_last_synced_at < now() - 5min` on a nullable column
   couldn't recover a NULL-clock `cloning` row and could disturb a reconnect
   clone.** Recovery: add an `IS NULL` arm AND stamp `repo_last_synced_at = now()`
   on every `cloning` flip. Prevention: a staleness predicate over a nullable
   timestamp must handle NULL explicitly and every writer must stamp the clock.
5. **`test-all.sh` exit masking** — wrapping `grep|tail` reported exit 0 while the
   runner exited 1; the `rc=$?` capture surfaced the real failure. (Known class.)
6. **Stale `ScheduleWakeup` prompt** fired referencing an already-completed task.
   One-off — re-point the wakeup prompt to the current task/phase each turn.
