---
title: "chore(web-platform): multi-stage Docker build to remove devDependencies from production image"
type: chore
date: 2026-03-20
issue: "#808"
deepened: 2026-03-20
---

# chore(web-platform): multi-stage Docker build to remove devDependencies from production image

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 7
**Research sources:** Next.js deployment docs (Context7), esbuild API docs (Context7), Docker security hardening guides, web search (5 queries), 3 institutional learnings

### Key Improvements
1. **esbuild path alias resolution confirmed** -- `@/*` aliases are automatically resolved when using `--bundle` mode; no plugins or extra tooling needed
2. **`--packages=external` default was reverted** -- esbuild 0.22 briefly defaulted to externalizing all packages for `--platform=node`, but this was reverted due to AWS CDK breakage; explicit `--external:` flags remain necessary
3. **Non-root user added** -- production image should run as non-root for defense-in-depth, following the telegram-bridge pattern
4. **`--no-install-recommends` for apt packages** -- reduces attack surface by skipping unnecessary transitive packages
5. **`.next/static` must be copied separately** -- Next.js serves static assets from `.next/static/` which must be present in the runner stage
6. **Healthcheck improved** -- using `node -e` with native `fetch` is the recommended approach for `node:22-slim`; `http` module fallback documented as alternative

### New Considerations Discovered
- esbuild automatically reads `tsconfig.json` `paths` during bundling -- the `@/*` alias concern is a non-issue
- The `--packages=external` default was reverted in esbuild -- explicit externals are required
- `node:22-slim` images include a built-in `node` user (uid 1000) -- no need to `useradd`
- Docker BuildKit secret mounts should be considered for any future secrets (not needed for this change since `NEXT_PUBLIC_*` vars are intentionally public)

---

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
# Compile custom server: esbuild resolves @/* path aliases automatically
RUN npx esbuild server/index.ts --bundle --platform=node --target=node22 \
    --outfile=dist/server/index.js \
    --external:next --external:react --external:react-dom \
    --external:@supabase/supabase-js --external:@supabase/ssr \
    --external:ws --external:stripe \
    --external:@anthropic-ai/claude-agent-sdk
```

### Stage 3: `runner` -- Production image

```dockerfile
FROM node:22-slim AS runner
RUN npm install -g @anthropic-ai/claude-code@2.1.79
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
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

# Non-root user (node:22-slim includes a 'node' user at uid 1000)
USER node

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>{process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"

CMD ["node", "dist/server/index.js"]
```

### Key design decisions

1. **Pre-compile server with esbuild** rather than `tsc` or moving `tsx` to production dependencies. esbuild bundles the server into a single file, automatically resolves `@/*` path aliases from `tsconfig.json`, and runs in milliseconds. `tsc` would require additional tooling (`tsc-alias`) to resolve path aliases. `tsx` in production adds unnecessary attack surface.
2. **`npm ci --omit=dev`** in the runner stage installs only production dependencies (next, react, ws, supabase, stripe, claude-agent-sdk).
3. **Replace `curl` healthcheck with `node -e fetch(...)`** -- Node 22 has native `fetch`. No extra binary needed. This avoids the anti-pattern of installing curl in slim images solely for healthchecks.
4. **Keep `@anthropic-ai/claude-code` as a global install** in the runner stage -- it's needed at runtime by the Agent SDK.
5. **Keep `git` in the runner stage** -- needed for workspace provisioning at runtime. Use `--no-install-recommends` to minimize transitive packages.
6. **Change `CMD` from `npm run start` to `node dist/server/index.js`** -- eliminates the npm process wrapper and the `tsx` dependency. Node receives SIGTERM directly, enabling clean shutdown.
7. **Run as non-root user** -- `node:22-slim` includes a built-in `node` user (uid 1000). Use `USER node` after all root-level operations complete.

### Research Insights: Proposed Solution

**esbuild path alias resolution (confirmed):**
esbuild automatically reads `compilerOptions.paths` from `tsconfig.json` when bundling. The `@/*` alias concern from the initial analysis is a non-issue -- `--bundle` mode resolves all import paths, including TypeScript path aliases, without requiring plugins or additional configuration. This was confirmed via [esbuild issue #394](https://github.com/evanw/esbuild/issues/394) and [Context7 esbuild docs](/evanw/esbuild).

**`--packages=external` default was reverted:**
esbuild 0.22.0 briefly made `--packages=external` the default for `--platform=node` (automatically externalizing all npm packages). This was reverted in a subsequent release due to [AWS CDK breakage](https://github.com/evanw/esbuild/issues/3817). The current default is `--packages=bundle`, meaning explicit `--external:` flags are necessary. Do NOT rely on automatic externalization.

**Non-root user best practice:**
Running containers as root is a security anti-pattern. If an attacker gains shell access, they have full administrative privileges. The `node:22-slim` image includes a pre-created `node` user (uid 1000, gid 1000) -- no `useradd` needed. Add `USER node` after all `RUN` commands that require root (package installs, apt-get).

**Node.js process signals:**
Using `CMD ["node", ...]` instead of `CMD ["npm", "run", "start"]` ensures Node.js receives SIGTERM directly from Docker. The npm process wrapper absorbs signals, which can cause ungraceful shutdowns with a 10-second kill timeout.

## Technical Considerations

### Path alias resolution (`@/*`)

The custom server uses `@/*` path aliases (e.g., `import { KeyInvalidError } from "@/lib/types"`). When compiling with `tsc`, these aliases are NOT resolved in the output -- `tsc` preserves them verbatim.

**Resolution: esbuild handles this automatically.** When using `--bundle`, esbuild reads `tsconfig.json` and resolves all `paths` entries. No plugins, no `tsc-alias`, no manual refactoring needed. This is the primary reason to prefer esbuild over `tsc` for this use case.

### Research Insights: Path Aliases

**esbuild bundling resolves all imports:**
Per [esbuild documentation](https://esbuild.github.io/getting-started/), `--bundle` mode inlines all imported files into the output. Since esbuild reads `tsconfig.json` `paths` during resolution, `@/*` aliases are resolved to their actual file paths before bundling. The output `dist/server/index.js` contains no unresolved aliases.

**Alternative approaches (not recommended):**
- `tsc-alias` post-processor: adds a build step and a devDependency
- `esbuild-plugin-tsconfig-paths`: unnecessary when `--bundle` is used (only needed for non-bundled builds)
- Manual relative path refactoring: fragile and degrades DX

### `next.config.ts` at runtime

Next.js reads `next.config.ts` at startup even when running via a custom server. The runner stage must include this file. Since it's TypeScript, Next.js handles its own config loading (it has built-in support for `.ts` config files since v12).

### `postcss.config.mjs` and `tailwind.config.*`

These are build-time only. They should NOT be copied to the runner stage. `next build` processes all CSS during the build stage.

### Docker build context

No `.dockerignore` exists. There is a separate worktree (`feat/web-platform-dockerignore`) that may address this. This plan should not conflict with that work, but should note that `.dockerignore` is recommended to reduce build context size (exclude `node_modules/`, `.next/`, `.git/`, etc.).

### CI workflow compatibility

The `reusable-release.yml` workflow uses `docker/build-push-action` with `context: apps/web-platform` and passes `NEXT_PUBLIC_*` as `build-args`. Multi-stage builds are fully compatible with this setup -- no workflow changes needed since `ARG` declarations in the build stage receive the values correctly.

### Research Insights: Docker Hardening

**`--no-install-recommends` for apt packages:**
Debian's `apt-get install` pulls "recommended" packages by default, which can add tens of MB of unnecessary binaries. Using `--no-install-recommends` installs only the explicitly requested package and its hard dependencies. This is especially important in slim images where every MB counts.

**Layer ordering for cache efficiency:**
The proposed stage ordering maximizes Docker layer cache hits:
1. `deps` stage: Only invalidated when `package.json` or `package-lock.json` changes (rare)
2. `builder` stage: Invalidated on any source change (frequent), but deps layer is cached
3. `runner` stage: Production deps (`npm ci --omit=dev`) cached independently from build deps

**Selective COPY over COPY . .:**
The runner stage uses explicit `COPY --from=builder` for each artifact rather than `COPY . .`. This ensures only production-necessary files enter the final image. Per [Docker best practices](https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/), this can reduce image size by 50-90%.

**Image size expectations:**
Based on comparable Next.js multi-stage builds, expect a reduction from ~1.5-2GB (all deps + build tools) to ~500-700MB (production deps + build output + Claude Code CLI + git). The Claude Code CLI and git are the largest contributors to the production image; without them, a typical Next.js multi-stage image is ~300MB.

### Research Insights: Healthcheck

**Why not curl:**
Per [Docker Healthchecks: Why Not To Use curl or iwr](https://blog.sixeyed.com/docker-healthchecks-why-not-to-use-curl-or-iwr/), using external tools for healthchecks adds attack surface, image size, and maintenance burden. Custom healthchecks using the app's native runtime are preferred.

**Node.js native fetch:**
Node 22 includes a stable, unflagged `fetch` API (based on undici). The one-liner `node -e "fetch(...).then(...).catch(...)"` is the cleanest approach for `node:22-slim` images.

**Alternative (http module) for broader compatibility:**
```dockerfile
HEALTHCHECK CMD node -e "require('http').get('http://localhost:3000/health',r=>{process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"
```
This works on all Node.js versions (including those without native fetch). Not needed here since we target Node 22, but documented for reference.

## Acceptance Criteria

- [ ] Production Docker image does NOT contain devDependencies (vitest, eslint, typescript, tailwindcss, postcss, tsx, type packages)
- [ ] `npm run build` (Next.js) succeeds in the build stage
- [ ] Custom server compiles to JavaScript via esbuild in the build stage
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
- [ ] Container runs as non-root user (`node`, uid 1000)
- [ ] `@/*` path aliases in server code are resolved in bundled output (no runtime import errors)

## Test Scenarios

- Given a clean build, when `docker build` runs, then all three stages complete without errors
- Given the built image, when `docker run` starts the container, then the custom server starts and logs "Ready on http://localhost:3000"
- Given a running container, when `GET /health` is requested, then it returns `{"status":"ok"}`
- Given a running container, when the Docker healthcheck runs, then `node -e fetch(...)` succeeds (exit 0)
- Given a running container, when a WebSocket connection is opened to `/ws`, then the upgrade succeeds
- Given the production image, when `npm ls --omit=dev` is run inside, then no devDependency packages appear
- Given the production image, when `claude` CLI is invoked, then it is available at the expected version
- Given the CI workflow, when a release triggers `docker/build-push-action`, then the multi-stage build succeeds with `NEXT_PUBLIC_*` args
- Given the production image, when `whoami` is run inside, then it returns `node` (not `root`)
- Given the bundled server, when `grep "@/" dist/server/index.js` is run, then no unresolved `@/` path aliases appear
- Given a failed esbuild bundle (e.g., missing external), when the Docker build runs, then it fails at the builder stage with a clear error (not silently at runtime)

### Research Insights: Test Scenarios

**Verify no devDependencies leak:**
Beyond `npm ls --omit=dev`, also check that specific binary entrypoints are absent:
```bash
docker run --rm <image> sh -c "which vitest || echo 'vitest not found: OK'"
docker run --rm <image> sh -c "which tsc || echo 'tsc not found: OK'"
docker run --rm <image> sh -c "which eslint || echo 'eslint not found: OK'"
```

**Verify esbuild output correctness:**
The bundled `dist/server/index.js` should import from `next`, `ws`, `@supabase/supabase-js`, etc. (external requires) but NOT contain inlined copies of those packages. Check with:
```bash
docker run --rm <image> head -20 dist/server/index.js
# Should see require("next"), require("ws"), etc. -- not inlined module code
```

**Verify signal handling:**
```bash
docker run --rm -d --name test-signals <image>
docker stop test-signals  # Should stop within 1-2 seconds (not 10s timeout)
```

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Path alias (`@/*`) not resolved in compiled output | ~~High~~ **Eliminated** | esbuild `--bundle` resolves `tsconfig.json` `paths` automatically |
| `next.config.ts` not loadable without TypeScript tooling | Low | Next.js has built-in `.ts` config support since v12 |
| Missing runtime files in runner stage | Medium | Test locally with `docker build && docker run` before pushing |
| esbuild bundles something that should be external | Medium | Explicitly list all production deps as `--external:`; verify with `head -20 dist/server/index.js` |
| Server imports from Next.js internal modules | Low | The custom server only imports `next` public API |
| Non-root user can't write to `/app` | Low | WORKDIR ownership is set before `USER node`; app doesn't write to `/app` at runtime (writes to mounted volumes) |
| `node` user can't bind port 3000 | **None** | Ports above 1024 don't require root |
| esbuild version drift between local dev and Docker | Low | esbuild is invoked via `npx` from the locked `package-lock.json` -- same version in both environments |

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/Dockerfile` | Replace with 3-stage multi-stage build |
| `apps/web-platform/package.json` | Update `start` script to `node dist/server/index.js`; add `build:server` script for esbuild; add `esbuild` to devDependencies |

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
- `apps/telegram-bridge/Dockerfile` -- reference single-stage Dockerfile with non-root user pattern
- `.github/workflows/reusable-release.yml:273-286` -- Docker build-push step with build-args
- `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md` -- consider adding digest pin in follow-up
- `knowledge-base/learnings/2026-03-19-npm-global-install-version-pinning.md` -- `@anthropic-ai/claude-code@2.1.79` is already pinned
- `knowledge-base/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md` -- healthcheck `--start-period` pattern

### External References

- [Next.js Deployment Docs](https://nextjs.org/docs/app/getting-started/deploying) -- Docker section recommends multi-stage builds
- [Next.js Custom Server Docs](https://nextjs.org/docs/app/guides/custom-server) -- `node server.js` pattern for production
- [esbuild Getting Started](https://esbuild.github.io/getting-started/) -- `--platform=node` and `--bundle` flags
- [esbuild Changelog (packages=external revert)](https://github.com/evanw/esbuild/blob/main/CHANGELOG.md) -- 0.22.0 default change and revert
- [esbuild Issue #394](https://github.com/evanw/esbuild/issues/394) -- tsconfig paths handled during bundling
- [Docker Healthchecks: Why Not curl](https://blog.sixeyed.com/docker-healthchecks-why-not-to-use-curl-or-iwr/) -- native runtime healthchecks
- [Docker Multi-Stage Builds Docs](https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/) -- official best practices
- [Next.js Docker + Custom Server (hmos.dev)](https://hmos.dev/en/nextjs-docker-standalone-and-custom-server) -- standalone mode + custom server patterns
- [Dockerize Next.js (johnnymetz.com)](https://johnnymetz.com/posts/dockerize-nextjs-app/) -- multi-stage build reference
- [Docker Security Hardening 2026](https://zeonedge.com/blog/docker-security-best-practices-2026-hardening-containers-build-runtime) -- non-root user, minimal images
- [Node.js Docker Healthchecks (mattknight.io)](https://www.mattknight.io/blog/docker-healthchecks-in-distroless-node-js) -- Node-native healthcheck patterns

### Related Issues/PRs

- #808 -- This issue (devDependencies in production image)
- #803 -- Security review that discovered this issue
- #801 -- Digest pinning for telegram-bridge Dockerfile (similar security pattern)
- `feat/web-platform-dockerignore` worktree -- parallel work on Docker build context
