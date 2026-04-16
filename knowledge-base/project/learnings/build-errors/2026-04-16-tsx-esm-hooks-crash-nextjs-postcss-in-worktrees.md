---
title: "tsx ESM hooks crash Next.js PostCSS loader with ERR_INVALID_URL_SCHEME in worktrees"
date: 2026-04-16
category: build-errors
module: apps/web-platform
tags:
  - tsx
  - nextjs
  - postcss
  - tailwind
  - esm-hooks
  - worktrees
  - dev-server
  - esbuild
severity: high
related_issues: []
---

# Learning: tsx ESM hooks crash Next.js PostCSS loader in worktrees

## Problem

Next.js dev server crashes with `TypeError [ERR_INVALID_URL_SCHEME]: The URL must be of scheme file` in the PostCSS loader when started via `tsx server/index.ts` inside a git worktree. Pages return HTTP 500 with a blank body. The error originates in `finalizeResolution` -> `fileURLToPath` called from tsx's ESM resolver hooks (`resolveExtensions` -> `resolveBase` -> `resolveDirectory` -> `resolveTsPaths`).

## Root Cause

tsx v4 registers ESM loader hooks globally via `--import tsx/esm`. These hooks intercept Node's module resolution for ALL `import()` and `require()` calls in the process — including webpack's internal resolver. When webpack's PostCSS loader resolves `@tailwindcss/postcss`, the resolution goes through tsx's hook chain, which passes a non-`file://` URL scheme to Node's `fileURLToPath`, crashing with `ERR_INVALID_URL_SCHEME`.

`node --import tsx/esm server/index.ts` exhibits the same failure — the hooks are registered regardless of invocation style.

## Solution

Replace tsx with esbuild pre-compilation in `package.json`:

**Before:** `"dev": "tsx server/index.ts"`

**After:** `"dev": "esbuild server/index.ts --bundle --platform=node --target=node22 --format=esm --packages=external --outfile=.next/dev-server.mjs && node .next/dev-server.mjs"`

Key flags:

- `--format=esm` — native ESM output so ESM-only deps (e.g. `@anthropic-ai/claude-agent-sdk`) load correctly
- `--packages=external` — keeps all `node_modules` external, avoiding dynamic-require conflicts with Node builtins
- `--platform=node --target=node22` — suppresses browser shims

Also updated `playwright.config.ts` webServer commands from `tsx server/index.ts` to `npm run dev`.

esbuild is already a devDependency. `.next/dev-server.mjs` is covered by the existing `.next/` gitignore entry. Build time: ~22ms.

## Investigation Steps

1. `tsx server/index.ts` — `ERR_INVALID_URL_SCHEME` in PostCSS loader
2. `node --import tsx/esm server/index.ts` — same failure; ESM hooks still registered globally
3. `esbuild --format=cjs` — `ERR_REQUIRE_ESM` because `@anthropic-ai/claude-agent-sdk` is ESM-only
4. `esbuild --format=esm` (full bundle) — `Dynamic require of "crypto" is not supported`; esbuild's ESM bundler rejects dynamic `require()` of Node builtins from bundled CJS deps
5. `esbuild --format=esm --packages=external` — success; TypeScript stripped, all deps external, plain `node` launch

## Key Insight

Any tool that installs Node.js ESM loader hooks (`tsx`, `ts-node/esm`, `@swc-node/register`) will interfere with framework internals that do their own module resolution (webpack, PostCSS, Vite). The esbuild-then-node pattern (strip TypeScript at build time, run with plain Node) is the canonical defense. This applies to any custom Next.js server.

## Prevention Strategies

1. The `dev` script should never use a TypeScript runtime that installs global ESM hooks. esbuild pre-compilation is the safe pattern.
2. `playwright.config.ts` webServer commands should use `npm run dev` (not `tsx` directly) to stay aligned with the dev script.
3. The production `build:server` outputs CJS with ESM-only externals. This works in production (Node 22 supports `require()` of ESM natively) but would fail locally on Node 21.x. If the local Node version is upgraded to 22+, this becomes a non-issue.

## Session Errors

1. **Worktree-manager script not found from bare root** — `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` failed because the bare repo has no working tree. Recovery: used `git show main:... > /tmp/wt-mgr.sh`. Prevention: the cleanup-merged workflow gate already handles this at session start; the error was a one-off from mid-session worktree creation.
2. **CJS esbuild output failed with ESM-only dependency** — First esbuild attempt produced CJS that can't `require()` ESM-only `@anthropic-ai/claude-agent-sdk`. Recovery: switched to ESM format. Prevention: when bundling for Node with externalized deps, always check if any external has `"type": "module"` — if so, output must be ESM.
3. **ESM esbuild bundle with inlined deps failed on Node builtins** — `Dynamic require of "crypto" is not supported` because esbuild's ESM bundle converts `require()` to a synthetic function. Recovery: used `--packages=external` to avoid inlining deps. Prevention: for server-side ESM bundles that mix CJS and ESM deps, use `--packages=external` instead of listing individual externals.

## Related Learnings

- `knowledge-base/project/learnings/2026-04-15-next-server-actions-allowed-origins-port-fallback.md` — Documents `scripts/dev.sh` wrapper and tsx PATH issues
- `knowledge-base/project/learnings/2026-03-20-multistage-docker-build-esbuild-server-compilation.md` — esbuild compilation pattern for production
- `knowledge-base/project/learnings/2026-02-26-worktree-missing-node-modules-silent-hang.md` — Worktree dependency issues

## Tags

category: build-errors
module: apps/web-platform
