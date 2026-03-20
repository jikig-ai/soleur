---
title: "chore(web-platform): multi-stage Docker build to remove devDependencies from production image"
type: chore
date: 2026-03-20
issue: "#808"
---

# chore(web-platform): multi-stage Docker build to remove devDependencies from production image

## Overview

The `apps/web-platform/Dockerfile` installs devDependencies (`npm ci --production=false`) in the production image. This ships test frameworks (vitest), linters (eslint), type definitions, and build tools (typescript, tailwindcss, postcss) into production, increasing the attack surface and image size. A multi-stage build should compile everything in a build stage and copy only production artifacts to the final image.

## Problem Statement / Motivation

Found during security review of #803. The current Dockerfile has three problems:

1. **DevDependencies in production** -- `npm ci --production=false` on line 13 installs vitest, eslint, typescript, tailwindcss, postcss, and type packages into the final image. These are only needed at build time.
2. **Custom server requires `tsx` at runtime** -- The `start` script runs `tsx server/index.ts`, but `tsx` is a devDependency. This is why `--production=false` was likely added in the first place -- without it, `npm start` would fail. A multi-stage build must solve this by pre-compiling the server.
3. **`curl` used in healthcheck but not installed** -- `node:22-slim` does not include `curl`. The healthcheck on line 31-32 silently fails. This should be replaced with a Node.js-based check.

## Proposed Solution

Convert to a 3-stage Docker build:

### Stage 1: `deps` -- Install all dependencies

```dockerfile
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
```

### Stage 2: `builder` -- Build Next.js + compile custom server

```dockerfile
FROM deps AS builder
WORKDIR /app
COPY . .
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
RUN npm run build
# Compile custom server from TypeScript to JavaScript
RUN npx tsc --project tsconfig.server.json
```

The custom server (`server/index.ts`, `server/ws-handler.ts`, `server/agent-runner.ts`, etc.) must be compiled to JavaScript so the production image can run it without `tsx`. This requires a dedicated `tsconfig.server.json` that:
- Targets ES2022 + NodeNext modules (the server is pure Node.js, no JSX)
- Sets `outDir` to `dist/server/`
- Uses `noEmit: false` (overriding the base tsconfig which has `noEmit: true`)
- Includes only `server/**/*.ts`

### Stage 3: `runner` -- Production image

```dockerfile
FROM node:22-slim AS runner
RUN npm install -g @anthropic-ai/claude-code@2.1.79
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production

# Production dependencies only
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Next.js build output
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public

# Compiled custom server
COPY --from=builder /app/dist/server ./dist/server

# Config files needed at runtime
COPY --from=builder /app/next.config.ts ./next.config.ts

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>{process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"

CMD ["node", "dist/server/index.js"]
```

### Key design decisions

1. **Pre-compile server with `tsc`** rather than moving `tsx` to production dependencies. `tsx` is a JIT TypeScript compiler -- shipping it to production adds unnecessary complexity and attack surface. Pre-compilation is the standard approach.
2. **`npm ci --omit=dev`** in the runner stage installs only production dependencies (next, react, ws, supabase, stripe, claude-agent-sdk).
3. **Replace `curl` healthcheck with `node -e fetch(...)`** -- Node 22 has native `fetch`. No extra binary needed.
4. **Keep `@anthropic-ai/claude-code` as a global install** in the runner stage -- it's needed at runtime by the Agent SDK.
5. **Keep `git` in the runner stage** -- needed for workspace provisioning at runtime.
6. **Change `CMD` from `npm run start` to `node dist/server/index.js`** -- eliminates the npm process wrapper and the `tsx` dependency.

## Technical Considerations

### Path alias resolution (`@/*`)

The custom server uses `@/*` path aliases (e.g., `import { KeyInvalidError } from "@/lib/types"`). When compiling with `tsc`, these aliases are NOT resolved in the output -- `tsc` preserves them verbatim. Options:

- **Option A: Use `tsc-alias`** -- a post-compilation tool that rewrites path aliases to relative paths. Add `&& npx tsc-alias -p tsconfig.server.json` after `tsc`.
- **Option B: Use `esbuild` instead of `tsc`** -- bundles the server into a single file with all imports resolved. Simpler, faster, and eliminates the alias problem entirely. Preferred approach.
- **Option C: Replace `@/*` imports in server files with relative paths** -- manual refactoring, fragile.

**Recommendation: Option B (esbuild).** It's already proven in the Node.js ecosystem for server bundling, resolves all path aliases and imports, and produces a single output file. The build command becomes:

```dockerfile
RUN npx esbuild server/index.ts --bundle --platform=node --target=node22 \
    --outfile=dist/server/index.js \
    --external:next --external:react --external:react-dom \
    --external:@supabase/supabase-js --external:@supabase/ssr \
    --external:ws --external:stripe \
    --external:@anthropic-ai/claude-agent-sdk
```

Externals are packages in production `dependencies` -- they're available via `node_modules` at runtime and should NOT be bundled.

### `next.config.ts` at runtime

Next.js reads `next.config.ts` at startup even when running via a custom server. The runner stage must include this file. Since it's TypeScript, Next.js handles its own config loading (it has built-in support for `.ts` config files).

### `postcss.config.mjs` and `tailwind.config.*`

These are build-time only. They should NOT be copied to the runner stage. `next build` processes all CSS during the build stage.

### Docker build context

No `.dockerignore` exists. There is a separate worktree (`feat/web-platform-dockerignore`) that may address this. This plan should not conflict with that work, but should note that `.dockerignore` is recommended to reduce build context size (exclude `node_modules/`, `.next/`, `.git/`, etc.).

### CI workflow compatibility

The `reusable-release.yml` workflow uses `docker/build-push-action` with `context: apps/web-platform` and passes `NEXT_PUBLIC_*` as `build-args`. Multi-stage builds are fully compatible with this setup -- no workflow changes needed since `ARG` declarations in the build stage receive the values correctly.

## Acceptance Criteria

- [ ] Production Docker image does NOT contain devDependencies (vitest, eslint, typescript, tailwindcss, postcss, tsx, type packages)
- [ ] `npm run build` (Next.js) succeeds in the build stage
- [ ] Custom server compiles to JavaScript in the build stage
- [ ] Production image starts successfully with `node dist/server/index.js`
- [ ] WebSocket connections work (server/ws-handler.ts functionality preserved)
- [ ] Agent SDK sessions work (server/agent-runner.ts functionality preserved)
- [ ] `/health` endpoint responds with 200
- [ ] Healthcheck uses `node -e` instead of `curl`
- [ ] `@anthropic-ai/claude-code` CLI available in production image
- [ ] `git` available in production image
- [ ] `NEXT_PUBLIC_*` build args still work for client-side inlining
- [ ] CI workflow (`web-platform-release.yml`) builds and pushes successfully without changes
- [ ] Image size is smaller than the current single-stage image

## Test Scenarios

- Given a clean build, when `docker build` runs, then all three stages complete without errors
- Given the built image, when `docker run` starts the container, then the custom server starts and logs "Ready on http://localhost:3000"
- Given a running container, when `GET /health` is requested, then it returns `{"status":"ok"}`
- Given a running container, when the Docker healthcheck runs, then `node -e fetch(...)` succeeds (exit 0)
- Given a running container, when a WebSocket connection is opened to `/ws`, then the upgrade succeeds
- Given the production image, when `npm ls --omit=dev` is run inside, then no devDependency packages appear
- Given the production image, when `claude` CLI is invoked, then it is available at the expected version
- Given the CI workflow, when a release triggers `docker/build-push-action`, then the multi-stage build succeeds with `NEXT_PUBLIC_*` args

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Path alias (`@/*`) not resolved in compiled output | High (if using `tsc`) | Use esbuild which resolves all imports |
| `next.config.ts` not loadable without TypeScript tooling | Low | Next.js has built-in `.ts` config support since v12 |
| Missing runtime files in runner stage | Medium | Test locally with `docker build && docker run` before pushing |
| esbuild bundles something that should be external | Medium | Explicitly list all production deps as `--external` |
| Server imports from Next.js internal modules | Low | The custom server only imports `next` public API |

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/Dockerfile` | Replace with 3-stage multi-stage build |
| `apps/web-platform/package.json` | Update `start` script to `node dist/server/index.js`; add `build:server` script for esbuild |

## Files to Create

| File | Purpose |
|------|---------|
| None | esbuild is invoked via `npx` in the Dockerfile -- no config file needed |

## References & Research

### Internal References

- `apps/web-platform/Dockerfile` -- current single-stage Dockerfile
- `apps/web-platform/package.json` -- dependencies and scripts
- `apps/web-platform/server/index.ts` -- custom server entry point (uses `tsx` today)
- `apps/web-platform/server/ws-handler.ts` -- WebSocket handler with Supabase auth
- `apps/web-platform/server/agent-runner.ts` -- Agent SDK integration with BYOK
- `apps/web-platform/next.config.ts` -- `output: undefined` (no standalone), `serverExternalPackages`
- `apps/telegram-bridge/Dockerfile` -- reference single-stage Dockerfile (no multi-stage needed since Bun runs TS natively)
- `.github/workflows/reusable-release.yml:273-286` -- Docker build-push step with build-args
- `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md` -- consider adding digest pin in follow-up
- `knowledge-base/learnings/2026-03-19-npm-global-install-version-pinning.md` -- `@anthropic-ai/claude-code@2.1.79` is already pinned

### Related Issues/PRs

- #808 -- This issue (devDependencies in production image)
- #803 -- Security review that discovered this issue
- #801 -- Digest pinning for telegram-bridge Dockerfile (similar security pattern)
- `feat/web-platform-dockerignore` worktree -- parallel work on Docker build context
