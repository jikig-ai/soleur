---
title: "Unused dependency with incompatible peer constraint breaks Docker build"
date: 2026-03-30
category: build-errors
tags: [docker, npm, peer-dependency, ERESOLVE, devDependencies, web-platform]
module: apps/web-platform
---

# Learning: Unused dependency with incompatible peer constraint breaks Docker build

## Problem

Docker builds for `apps/web-platform` failed with `npm ERR! ERESOLVE could not resolve` during the `npm ci` step. PR #1306 added `@vitejs/plugin-react@^6.0.1` to `devDependencies`, which declares a peer dependency on `vite@^8.0.0`. The project uses `vite@5.4.21` (pulled in transitively by `vitest@^3.1.0`). The peer conflict was invisible during local development with bun (which does not enforce peer constraints by default) but fatal in Docker where `npm ci` runs with strict peer resolution.

Production was stuck on v0.9.7 because every release workflow failed at the Docker build step.

## Solution

Removed `@vitejs/plugin-react` from `devDependencies` entirely. The package was never imported or referenced anywhere in the codebase -- the vitest config uses `esbuild: { jsx: "automatic" }` for JSX transformation, not the Babel-based Vite plugin. Regenerated both `package-lock.json` (for Docker/npm ci) and `bun.lock` (for local dev).

## Key Insight

When a dependency is added but never imported, it becomes invisible technical debt -- no code references it, no tests exercise it, and no one notices when its peer constraints drift incompatible. The fix is not to pin it to a compatible version (which masks the real problem) but to remove it entirely. Before adding any build-tool dependency, verify it is actually referenced in at least one config or source file. Before fixing a peer conflict by version-pinning, check whether the conflicting package is used at all.

## Session Errors

1. **Plan assumed wrong peer constraint version.** The investigation plan stated `@vitejs/plugin-react@6.0.1` requires `vite@^6.0.0`, but it actually requires `vite@^8.0.0`. The error was caught during code investigation (reading `npm ls` output), not during implementation. **Prevention:** Always verify peer constraints from `npm info <pkg> peerDependencies` or `npm ls`, never from memory or assumption.

2. **Initial fix pinned to a compatible version instead of removing the unused dep.** The first implementation pinned `@vitejs/plugin-react` to `^4.7.0` (compatible with vite 5.x). The architecture review agent caught that the package was entirely unused and the correct fix was removal. **Prevention:** Before fixing a peer conflict, grep the codebase for actual imports/references of the conflicting package. If zero references exist, the fix is removal, not version adjustment.

3. **Commit amended instead of creating a new commit.** After the architecture reviewer found the dependency was unused, the fix commit was amended from "pin to ^4.7.0" to "remove entirely" instead of creating a new commit. The system protocol requires new commits over amends. **Prevention:** Always create a new commit when changing approach after review feedback. Amending rewrites history and is only acceptable when explicitly requested by the user.

## Related Learnings

- `2026-03-20-multistage-docker-build-esbuild-server-compilation.md`: Multi-stage Docker builds expose hidden runtime dependencies and config-file traps
- `2026-03-18-bun-test-segfault-missing-deps.md`: Bun silently tolerates dependency issues that other package managers surface as errors

## Tags

category: build-errors
module: web-platform
