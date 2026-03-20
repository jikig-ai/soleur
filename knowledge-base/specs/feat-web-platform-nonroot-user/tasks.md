# Tasks: security(web-platform) non-root USER directive

## Phase 1: Core Implementation

- [ ] 1.1 Add `RUN useradd --uid 1001 -m soleur` to `apps/web-platform/Dockerfile` after `RUN npm run build` (UID 1001 avoids conflict with node:22-slim's built-in `node` user at UID 1000)
- [ ] 1.2 Add `chown -R soleur:soleur .next` to transfer ownership of Next.js build output (not `/app` -- `node_modules` is read-only at runtime and chown-ing it wastes build time)
- [ ] 1.3 Combine 1.1 and 1.2 into a single `RUN` layer: `RUN useradd --uid 1001 -m soleur && chown -R soleur:soleur .next`
- [ ] 1.4 Add `USER soleur` directive before the production `ENV`/`EXPOSE`/`CMD` block

## Phase 2: Deploy Script Update

- [ ] 2.1 Add `chown -R 1001:1001 /mnt/data/workspaces` to `.github/workflows/web-platform-release.yml` deploy step before `docker run` (UID 1001, not 1000)

## Phase 3: Verification

- [ ] 3.1 Build the Docker image locally (`docker build -t soleur-web-test apps/web-platform/`)
- [ ] 3.2 Verify the process runs as `soleur` with UID 1001 (`docker run --rm soleur-web-test id` -- expect `uid=1001(soleur)`)
- [ ] 3.3 Verify `.next/` is owned by soleur (`docker run --rm soleur-web-test ls -la /app/.next/`)
- [ ] 3.4 Verify `.next/cache/` is writable (`docker run --rm soleur-web-test touch /app/.next/cache/test`)
- [ ] 3.5 Verify HEALTHCHECK works (`curl` is pre-installed in `node:22-slim` -- no additional install needed)
- [ ] 3.6 Verify `git` works as non-root (`docker run --rm soleur-web-test git config --global user.name test`)
