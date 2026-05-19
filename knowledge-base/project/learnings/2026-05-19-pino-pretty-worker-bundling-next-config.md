---
date: 2026-05-19
category: build-errors
component: apps/web-platform
tags: [next.js, pino, bundling, worker-threads, ci, e2e]
related_pr: 3984
related_files:
  - apps/web-platform/next.config.ts
  - apps/web-platform/server/logger.ts
---

# Learning: pino-pretty worker thread MODULE_NOT_FOUND under Next.js bundling

## Problem

PR #3984 (PR-G cohort onboarding) e2e job died with:

```
[WebServer] [Error: Cannot find module '/__w/soleur/soleur/apps/web-platform/.next/server/vendor-chunks/lib/worker.js'] {
  code: 'MODULE_NOT_FOUND',
  requireStack: []
}
[WebServer] [Error: the worker thread exited]
[WebServer] Error: the worker has exited
    at reportSilentFallback (server/observability.ts:139:60)
    at GET$1 (app/(auth)/callback/route.ts:138:89)
```

The auth callback's `exchangeCodeForSession` failed, calling `reportSilentFallback` → `logger.error` → pino spawns its `pino-pretty` transport worker → worker's `require("./lib/worker.js")` (relative to pino's own dir under `node_modules`) misses because Next.js bundled pino into `.next/server/vendor-chunks/`. Every subsequent server route that touches `logger.error` re-triggered the same uncaught exception, cascading the WebServer.

## Root cause

`server/logger.ts` configures `transport: { target: "pino-pretty" }` whenever `NODE_ENV !== "production"` — so the transport is live in dev, test, AND CI's e2e job. The transport executes in a `worker_thread`, and pino resolves the worker entry by walking its own `node_modules/pino/lib/worker.js`. When Next.js webpack bundles pino into a vendor chunk, the resolved path becomes `.next/server/vendor-chunks/lib/worker.js`, which doesn't actually exist on disk — pino-pretty isn't in that chunk and the path layout is wrong.

`next.config.ts` already had `serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"]` for the same class of "library uses dynamic worker resolution from its own node_modules dir" — pino just wasn't on the list.

## Solution

Add `"pino"` and `"pino-pretty"` to `serverExternalPackages` in `apps/web-platform/next.config.ts`. This tells Next.js to leave both packages as runtime `require(...)` calls resolved from `node_modules` instead of bundling them, so the worker can find `pino/lib/worker.js` at its expected on-disk location.

```ts
serverExternalPackages: [
  "@anthropic-ai/claude-agent-sdk",
  "ws",
  "pino",
  "pino-pretty",
],
```

Safe because all pino consumers in this repo are server-only (under `apps/web-platform/server/**`) — no client-bundle cost.

## Key insight

**Any library that uses `new Worker(new URL(...))` or otherwise resolves files by walking its own `node_modules` path must be in `serverExternalPackages`**, not bundled. The symptom is always a `MODULE_NOT_FOUND` for a sub-path of the library inside `.next/server/vendor-chunks/`. The fix is mechanical once the worker-resolution pattern is recognized.

Contrast: `pdfjs-dist` is deliberately *kept out* of `serverExternalPackages` because its client-side `new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url)` reference would break at `next build` time — the externalization decision is per-package and depends on whether the worker URL is resolved from a server runtime context (externalize) or a client build-time context (do NOT externalize). See the pre-existing comment block above the `serverExternalPackages` line in `next.config.ts` for the canonical reasoning.

## Prevention

- When adding a new server-side dependency that uses worker_threads or dynamic `require` against its own files, check whether its worker is loaded via a relative path inside its package dir. If yes, add it to `serverExternalPackages` before shipping.
- Watch for `MODULE_NOT_FOUND` errors against `.next/server/vendor-chunks/` paths during e2e/dev runs — that path prefix is the signature of this bug class.

## Session Errors

- **Wrong file paths on first Read attempts** — Read of `lib/supabase/tenant.ts` and the failing test failed initially because I omitted the `apps/web-platform/` prefix in the worktree path. Recovery: ran `find` to locate the real paths, then re-Read. Prevention: when working in this repo's worktrees, all Next.js app code lives under `apps/web-platform/` — start there, not at the worktree root.
- **Bash `cd` state confusion** — A `cd apps/web-platform && ...` failed with "No such file or directory" because the previous Bash call had already cd'd into `apps/web-platform`. Recovery: used absolute paths in the next call. Prevention: bash state persists across tool calls; prefer absolute paths or `pwd` checks over relative `cd` sequences when uncertain.

## Cross-references

- PR #3984 (PR-G cohort onboarding) — the PR where the e2e failure surfaced
- PR #3983 (Resolution C — Supabase asymmetric JWT substrate) — concurrent merge that also exposed `tenant-integration` 429s; separate fix
- `apps/web-platform/next.config.ts` lines 15-26 — existing pdfjs-dist counter-example comment block
