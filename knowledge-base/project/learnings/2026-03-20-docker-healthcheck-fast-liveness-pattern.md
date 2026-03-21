# Learning: Docker fast-liveness pattern for slow-starting Bun containers

## Problem

The telegram-bridge container health check failed in CI because `Bun.serve()` cannot bind the health HTTP listener until ALL top-level `import` statements in the entrypoint resolve. grammY and transitive deps take >120s on Hetzner CI runners. Docker HEALTHCHECK and the deploy script both timeout before the endpoint exists.

Four attempts at increasing timeouts (PRs #761, #790, #800) treated the symptom. The root cause was architectural: the health server lifecycle was coupled to the application module resolution.

## Solution

Two-file entrypoint pattern ("fast liveness"):

1. `main.ts` imports only a zero-dep health module, binds `Bun.serve()` within milliseconds
2. Heavy app code loads via `await import("./index")` after the health server is already responding
3. `boot()` wires live state via `Object.defineProperty` getters
4. HEALTHCHECK accepts both 200 and 503 (degraded-but-alive)

## Key Insight

When a Bun entrypoint has heavy static imports, NO code in that file executes until all imports resolve. Dynamic `import()` defers resolution to after the event loop starts. The pattern: put the fast-responding server in a thin entrypoint with zero/minimal deps, then dynamically import the heavy application.

Also: `curl -f` rejects HTTP 503 (exit code 22). If your health endpoint returns 503 during loading, use `curl -s -o /dev/null -w '%{http_code}' ... | grep -qE '^(200|503)$'` instead.

Also: `Object.defineProperty` creates getter-only properties by default (no setter). In ESM strict mode, assigning to such a property throws TypeError rather than silently failing. Always use defensive try/catch when writing to properties that may have been replaced with getters.

## Session Errors

1. **Incomplete refactoring left in worktree** — health.ts signature changed to callback pattern but main.ts and tests not updated, creating type mismatch. Always complete ALL callsite updates when changing a function signature.
2. **Shell glob in mv created literal asterisks** — `mv file*.md newname*.md` with no matching glob creates files with `*` in the name. Always quote shell arguments.
3. **Plan-to-implementation drift** — Plan said keep `--start-period=120s`, implementation reduced to 10s without fixing `curl -f`. Review agents caught it. Always verify implementation matches plan decisions.

## Tags

category: integration-issues
module: telegram-bridge
