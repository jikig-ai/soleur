---
title: Supabase helpers must import createServiceClient from @/lib/supabase/service (not @/lib/supabase/server) when reachable from the non-Next WS server bundle
date: 2026-04-18
category: build-errors
tags: [bundling, esbuild, next-headers, supabase, server-bundle]
pr: "#2571"
---

# Server-bundle transitive `next/headers` leak via `@/lib/supabase/server`

## Problem

PR #2571's e2e CI job failed with:

```text
Error [ERR_MODULE_NOT_FOUND]: Cannot find module
'/home/runner/work/soleur/soleur/apps/web-platform/node_modules/next/headers'
imported from
'/home/runner/work/soleur/soleur/apps/web-platform/.next/dev-server.mjs'
Did you mean to import "next/headers.js"?
```

The app built fine via `next build`; the failure was specifically in the **esbuild-built custom WS dev server** (`apps/web-platform/server/index.ts` bundled to `.next/dev-server.mjs` via `esbuild --packages=external`). Unit tests, type checks, and `web-platform-build` CI all passed — only e2e (which actually runs the dev-server binary) caught it.

## Root cause

`@/lib/supabase/server.ts` has two responsibilities that its path does not distinguish:

1. An async `createClient()` that needs `next/headers` `cookies()` — only valid inside App Router request context.
2. A pass-through re-export of `createServiceClient` from the standalone `@/lib/supabase/service.ts` — safe to use anywhere.

```ts
// apps/web-platform/lib/supabase/server.ts
import { cookies } from "next/headers"; // module-level side effect
// ...
export { serverUrl, createServiceClient } from "./service";
```

The top-level `import { cookies }` runs at module load, so ANY importer — even one that only uses the `createServiceClient` re-export — transitively loads `next/headers`. In Next.js contexts `next/headers` resolves; in the esbuild dev-server bundle it doesn't, and the module fails to load.

Before PR #2571, `server/lookup-conversation-for-path.ts` imported `createServiceClient` from `@/lib/supabase/server`. The helper was only reachable from route handlers — which ARE a Next.js context — so the leak was silent. PR #2571 added `server/conversations-tools.ts`, wired into `server/agent-runner.ts`, which is loaded by `server/ws-handler.ts`, which is loaded by `server/index.ts` (the esbuild-bundled WS dev server). The import chain made `lookup-conversation-for-path` transitively reachable from the non-Next bundle, exposing the leak.

## Solution

Import `createServiceClient` directly from `@/lib/supabase/service`:

```ts
// Before
import { createServiceClient } from "@/lib/supabase/server";

// After
import { createServiceClient } from "@/lib/supabase/service";
```

The repo already documents this pattern in a comment at `@/lib/supabase/server.ts:6`:

> `@/lib/supabase/service directly to avoid pulling in next/headers`

But the comment is advisory — nothing enforces it. Also update the test mock path (`vi.mock("@/lib/supabase/service", ...)`) so the mock covers the new import site.

## Prevention

When a helper may be reached from both Next.js route context AND a non-Next bundle entry (the WS dev server, an esbuild CLI, a background worker), import from `@/lib/supabase/service` by default. Reserve `@/lib/supabase/server` for files that ONLY run in Next.js request context (route handlers, server components, middleware, server actions).

Detection heuristic at code-review time: if a `server/` module that imports `@/lib/supabase/server` is reachable from `server/index.ts` via `ws-handler → agent-runner → ...`, the import path is wrong. Grep:

```bash
# From apps/web-platform/
grep -rln "from [\"']@/lib/supabase/server[\"']" server/
```

Any hit under `server/` (not `app/api/`) is a candidate for review.

Longer-term: a PreToolUse hook or a test that asserts `server/**/*.ts` (excluding `lib/supabase/server.ts` itself) never imports from `@/lib/supabase/server` would be the mechanical enforcement. Filed as a follow-up concern; low priority until a second instance occurs.

Class relationship: same family as `cq-nextjs-route-files-http-only-exports` — the Next.js runtime's module-resolution boundaries are not captured by `tsc --noEmit` or vitest. Only `next build` validates App Router route files; only running the bundled dev-server catches transitive `next/headers` reachability. E2E is the canonical signal.

## Session Errors

1. **Shipped a PR where four CI checks passed but e2e failed with a module-resolution error** — caused by pulling `lookup-conversation-for-path` into the WS server's reachability graph. **Recovery:** Switched the import from `@/lib/supabase/server` to `@/lib/supabase/service`. **Prevention:** see the grep heuristic above; consider promoting to a test or hook if this recurs.
