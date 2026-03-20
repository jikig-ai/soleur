# Learning: Multi-stage Docker build with esbuild server compilation

## Problem
The `apps/web-platform/Dockerfile` used a single-stage build with `npm ci --production=false`, shipping all devDependencies (vitest, eslint, typescript, tailwindcss, postcss, tsx) into the production image. This existed because the custom server was launched via `tsx server/index.ts` at runtime, and `tsx` is a devDependency -- removing devDeps would break `npm start`. The result was an inflated image size and increased attack surface.

## Solution
Converted to a 3-stage Docker build:
1. **deps** -- installs all dependencies (cached when lockfile unchanged)
2. **builder** -- builds the Next.js app, compiles the custom server to JS via esbuild (resolving `@/*` path aliases automatically), and compiles `next.config.ts` to `next.config.mjs` so TypeScript is not needed at runtime
3. **runner** -- starts from a clean `node:22-slim` image, runs `npm ci --omit=dev` for production deps only, and copies in `.next/`, `dist/server/`, and `next.config.mjs` from the builder stage. Runs as non-root `node` user with a `node -e fetch()` healthcheck (replacing the broken `curl`-based one, since `node:22-slim` does not include `curl`).

## Session Errors
1. **Docker build failed: COPY public/ but no public/ directory exists** -- The plan specified `COPY --from=builder /app/public ./public` but `apps/web-platform/` has no `public/` directory. Docker COPY fails when the source path does not exist. Fix: removed the COPY line and added a comment noting it should be added when `public/` is created.

2. **Container startup failed: next.config.ts requires TypeScript at runtime** -- Next.js auto-detects `.ts` config files and tries to install TypeScript if it is missing. In the runner stage, TS is absent (devDependency) and the non-root `node` user cannot write to `node_modules`, causing an EACCES crash. Fix: added an esbuild step in the builder stage to compile `next.config.ts` to `next.config.mjs`, and copied only the `.mjs` file to the runner stage.

3. **Wrong env var name during smoke test** -- During manual container testing, `SUPABASE_URL` was passed instead of `NEXT_PUBLIC_SUPABASE_URL`. Operator error, not a code bug.

4. **Digest pin regression** -- The initial multi-stage rewrite dropped the `@sha256:...` digest pin from the `FROM node:22-slim` lines. Review agents caught that the original Dockerfile pinned to a specific digest for supply-chain security. Fix: restored the digest pin on both `FROM` lines.

5. **Missing git config regression** -- The original Dockerfile included `git config --global user.name` and `user.email` for workspace provisioning. The multi-stage rewrite dropped these. Review agents caught the missing config. Fix: restored `git config --global` commands after the `USER node` directive.

## Key Insight
Multi-stage Docker builds expose hidden runtime dependencies on build tools. The obvious ones (tsx, typescript) surface quickly, but config files with build-tool extensions (.ts, .jsx) are a subtle trap -- frameworks silently auto-install missing toolchains, which fails in locked-down production images. When converting to multi-stage: (1) audit every file the runner stage touches for build-tool extensions and pre-compile them, (2) diff the old and new Dockerfiles line-by-line against origin/main to catch dropped security hardening (digest pins, non-root users, git config), and (3) test with the exact `docker build` + `docker run` cycle, not just `docker build`, since startup failures from missing runtime deps only appear when the container actually starts.

## Related Learnings
- `2026-03-19-docker-base-image-digest-pinning.md`: Pin Docker FROM images to digest for supply-chain protection
- `2026-03-19-npm-global-install-version-pinning.md`: Pin global npm installs to exact versions
- `2026-03-19-docker-healthcheck-start-period-for-slow-init.md`: Use --start-period for slow-starting containers
- `2026-03-19-bulk-rename-semantic-and-architectural-pitfalls.md`: Plan file lists are incomplete -- always verify with grep

## Prevention Strategies
1. Before implementing any COPY in a Dockerfile rewrite, verify the source path exists (`test -d <path>`)
2. Before committing a Dockerfile rewrite, run `git diff origin/main -- <Dockerfile>` and verify every non-trivial line is accounted for
3. For any config file written in TypeScript that is loaded at runtime, add a verification step in the runner stage or pre-compile to .mjs

## Tags
category: build-errors
module: web-platform
