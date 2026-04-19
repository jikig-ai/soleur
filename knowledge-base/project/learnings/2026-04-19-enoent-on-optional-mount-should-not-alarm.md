---
title: ENOENT on an optional mount is expected, not a silent fallback
date: 2026-04-19
pr: 2653
issue: 1052
problem_type: runtime_error
component: server
tags: [observability, sentry, silent-fallback, filesystem, enoent]
category: best-practices
severity: medium
synced_to: [work, qa]
---

# Learning: ENOENT on an optional mount is expected, not a silent fallback

## Problem

In PR #2653 (host resource monitoring), `server/session-metrics.ts`
`getActiveWorkspaceCount()` read `readdirSync(WORKSPACES_ROOT)` and
routed any error through `reportSilentFallback(err, { feature: "resource-monitoring" })`
per `cq-silent-fallback-must-mirror-to-sentry`.

On a local dev machine without `/workspaces` mounted, the new
`/internal/metrics` endpoint crashed on first request:

```text
⨯ unhandledRejection: TypeError: Sentry2.captureException is not a function
  at reportSilentFallback (.next/dev-server.mjs:1947:13)
  at getActiveWorkspaceCount (.next/dev-server.mjs:5227:5)
  at buildInternalMetricsResponse (.next/dev-server.mjs:5302:24)
```

Two compounding failures:

1. `readdirSync("/workspaces")` threw `ENOENT` — expected on any
   environment that doesn't have the prod volume.
2. The alarm path `reportSilentFallback` → `Sentry.captureException` crashed
   in the esbuild dev bundle (`Sentry2.captureException is not a function`).
   This is pre-existing infrastructure, but only ever surfaced because #1
   sent every dev-mode `/internal/metrics` request through it.

Unit tests did NOT catch this: the session-metrics tests mocked
`reportSilentFallback` with a `vi.fn()`, so the stub never exercised the
Sentry bundle. QA (functional probe against the running dev server) caught
it on the first `curl http://127.0.0.1:3000/internal/metrics`.

## Root Cause

`reportSilentFallback` is designed for _silent_ fallbacks — the caller
swallowed a real error that should still reach on-call. ENOENT on an
**optional** mount is not a silent fallback; it is a documented degraded
state ("no workspace volume → zero workspaces, nothing to count"). Routing
expected-state errors through the alarm pipeline creates noise AND exposes
the caller to any bug in the alarm pipeline itself.

## Solution

Gate the Sentry page on non-ENOENT errors. ENOENT-on-the-configured-root
becomes a silent zero; anything else (EACCES, I/O, pathologic) keeps its
trip to Sentry per the original rule.

```ts
} catch (err) {
  // ENOENT on the configured root is "this env has no mounted volume yet"
  // (local dev, CI, fresh provisioning) — expected degraded state, don't
  // page on it. Any other readdir error (EACCES, I/O) IS a real silent
  // fallback and goes to Sentry per cq-silent-fallback-must-mirror-to-sentry.
  if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
    reportSilentFallback(err, {
      feature: "resource-monitoring",
      op: "getActiveWorkspaceCount",
      extra: { workspacesRoot: WORKSPACES_ROOT },
    });
  }
  return 0;
}
```

Added test coverage for both branches:

```ts
it("returns 0 and DOES NOT alarm on ENOENT (expected in dev/CI)", async () => {
  const err = Object.assign(new Error("ENOENT"), { code: "ENOENT" });
  mockFs.readdirSync.mockImplementation(() => { throw err; });
  const { getActiveWorkspaceCount } = await import("../../server/session-metrics");
  expect(getActiveWorkspaceCount()).toBe(0);
  expect(mockReportSilentFallback).not.toHaveBeenCalled();
});

it("returns 0 AND reports to Sentry on non-ENOENT errors", async () => {
  const err = Object.assign(new Error("EACCES"), { code: "EACCES" });
  mockFs.readdirSync.mockImplementation(() => { throw err; });
  const { getActiveWorkspaceCount } = await import("../../server/session-metrics");
  expect(getActiveWorkspaceCount()).toBe(0);
  expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
});
```

## Key Insight

**Expected degraded states are not silent fallbacks.** Before routing an
error through `reportSilentFallback`, ask: "In what environment does this
code path execute? Is this error expected in any of those environments?"

- If "yes, in dev/CI/fresh-provisioning," filter by error code before paging.
- If "no, this would be a real surprise," page away.

The generalizable rule: `cq-silent-fallback-must-mirror-to-sentry`
intentionally says "silent fallback" — not "any caught error". A caught
error in an expected-degraded branch isn't silent; the code is
deliberately returning a known sentinel (`0`, `null`, etc.) and the
operator knows why.

This bug was invisible to unit tests because we mocked the exact function
that was crashing. A functional QA probe against the running server caught
it on the first request. **Mocking the alarm path in tests is fine for
assertion clarity, but QA must exercise the real path.**

## Session Errors

**cpu_pct_1m named for intent, not implementation** — field implied
1-minute CPU utilization window but computed `loadavg / nproc * 100`, a
proxy. **Recovery:** renamed to `cpu_load_pct` in review phase. **Prevention:**
field names must describe what is computed, not what the caller imagined.

**session-metrics pulled full ws-handler module graph** — importing
`sessions` from `ws-handler.ts` transitively loaded Supabase client,
Sentry, agent-runner just to read `.size`. **Recovery:** extracted to
`session-registry.ts`; ws-handler re-exports for backcompat. **Prevention:**
module-level shared state used by multiple subsystems should live in its
own thin module with zero runtime imports.

**Range-only test assertions pass on degenerate output** — `expect(x).toBeGreaterThanOrEqual(0).toBeLessThanOrEqual(100)` would pass
even if the implementation returned a constant 0. **Recovery:** mocked
`node:fs` `/proc/*` reads and `node:os` `cpus()` to pin exact expected
values (50%, 75%, 2.0). **Prevention:** when asserting a computed value,
mock inputs and pin the exact output — same class as
`cq-mutation-assertions-pin-exact-post-state`.

**Moved `sessions` binding broke internal consumers of ws-handler** — replaced `export const sessions = ...` with `export { sessions } from "./session-registry"`, but ws-handler's own functions still referenced the local `sessions`. `tsc --noEmit` caught it. **Recovery:** added
`import { sessions } from "./session-registry"` alongside the re-export.
**Prevention:** when extracting a module-level binding to a new module,
grep the source file for internal usages before deleting the local
declaration — the re-export alone doesn't put the name back in scope.

**Proposed scope-out filing flipped by second reviewer** — initial
triage framed the `/health` capacity-exposure finding as
contested-design; `code-simplicity-reviewer` DISSENT'd correctly because
the security agent didn't recommend "a design cycle outside this PR" (the
required third conjunct of criterion 2). **Recovery:** fix-inline via
endpoint split (`/internal/metrics` with loopback Host gate). **Prevention:**
contested-design requires all three conjuncts — multiple valid approaches,
≥2 concrete named by the reviewer, AND the reviewer's own recommendation
for a separate cycle. Triaging author's interpretation of "this deserves a
separate cycle" doesn't count.

**Workspace.ts dedup re-coupled to heavy imports** — first attempt to
dedupe `WORKSPACES_ROOT` imported `getWorkspacesRoot` from `workspace.ts`,
which transitively loads `github-app`. That undid the architecture
decoupling we just completed. **Recovery:** reverted to inline literal
with a sync comment pointing at `workspace.ts`. **Prevention:** before
importing a helper, `head` the source file — shared utilities often pull
in heavy dependencies that aren't obvious from the helper name.

**Plan-doc stale after review-phase renames** — reviewer renamed
`cpu_pct_1m` → `cpu_load_pct` and split `/health` → `/internal/metrics`,
but the plan-doc kept the old shape. **Recovery:** added a
`## Review-Phase Addendum` section. **Prevention:** review-phase changes
that rename plan-documented fields or endpoints need a plan-doc edit in
the same commit — future planners read the plan, not the review thread.

**Initial `terraform fmt -check` ran from wrong cwd** — exited 0 with
no output (deceptive). **Recovery:** re-ran from worktree root with
`-recursive apps/web-platform/infra/`. **Prevention:** always pass an
explicit directory to `terraform fmt -check`; don't rely on implicit cwd
after `cd` in the previous bash call since the Bash tool doesn't persist
cwd across invocations.

**`| tail -10` on background test output discarded failing-test names** — bg vitest reported `2 failed` but not which tests. Forced a full re-run.
**Recovery:** re-ran without the tail pipe. **Prevention:** default to
`| tail -30` or `| grep -E "FAIL|Test Files|Tests "` so failing names
survive truncation (already an AGENTS.md rule; was violated here).

## References

- PR #2653 (this change)
- Rule `cq-silent-fallback-must-mirror-to-sentry` — the rule this learning
  narrows the scope of.
- `apps/web-platform/server/observability.ts` — `reportSilentFallback`
  implementation.
- `apps/web-platform/server/session-metrics.ts` — the consumer this
  learning modifies.
