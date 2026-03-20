# Tasks: Docker Multi-Stage Build for Web Platform

## Phase 1: Setup

- [x] 1.1 Verify current Docker build works (`docker build -t test-before apps/web-platform/`) to establish baseline
- [x] 1.2 Record current image size for comparison (`docker images test-before`)

## Phase 2: Core Implementation

- [x] 2.1 Rewrite `apps/web-platform/Dockerfile` as a 3-stage multi-stage build
  - [x] 2.1.1 Stage 1 (`deps`): `FROM node:22-slim`, copy `package.json` + `package-lock.json`, run `npm ci`
  - [x] 2.1.2 Stage 2 (`builder`): extend `deps`, copy source, accept `NEXT_PUBLIC_*` ARGs, run `npm run build`, run esbuild to compile `server/` to `dist/server/index.js`, compile `next.config.ts` to `.mjs`
  - [x] 2.1.3 Stage 3 (`runner`): fresh `FROM node:22-slim`, install `@anthropic-ai/claude-code@2.1.79` globally, install `git` with `--no-install-recommends`, copy `package.json` + `package-lock.json`, run `npm ci --omit=dev`, copy `.next/`, `dist/server/`, `next.config.mjs` from builder, add `USER node` for non-root execution
- [x] 2.2 Update `apps/web-platform/package.json`
  - [x] 2.2.1 Add `build:server` script with explicit `--external:` flags
  - [x] 2.2.2 Update `start` script from `NODE_ENV=production tsx server/index.ts` to `NODE_ENV=production node dist/server/index.js`
  - [x] 2.2.3 Add `esbuild` to devDependencies and run `npm install` to update lockfile
- [x] 2.3 Replace `curl`-based healthcheck with `node -e "fetch(...)"`
- [x] 2.4 Update `CMD` from `["npm", "run", "start"]` to `["node", "dist/server/index.js"]`
- [x] 2.5 Add `USER node` before `EXPOSE` in runner stage

## Phase 3: Testing

- [x] 3.1 Build the multi-stage image locally
- [x] 3.2 Verify no devDependencies in production image (vitest, tsc, eslint absent)
- [x] 3.3 Verify specific devDep binaries are absent
- [x] 3.4 Verify `claude` CLI is available (v2.1.79)
- [x] 3.5 Verify `git` is available
- [x] 3.6 Image size: 1.29GB (production only)
- [x] 3.7 Verify container runs as non-root (`whoami` → `node`)
- [x] 3.8 Verify esbuild output has no unresolved `@/` aliases (0 matches)
- [x] 3.9 Verify externals are not bundled (`require("next")` present)
- [x] 3.10 Start container and verify `/health` endpoint responds `{"status":"ok"}`
- [x] 3.11 Verify healthcheck passes (`healthy`)
- [ ] 3.12 Signal handling: `docker stop` takes 10s (pre-existing — server lacks SIGTERM handler, out of scope for #808)
