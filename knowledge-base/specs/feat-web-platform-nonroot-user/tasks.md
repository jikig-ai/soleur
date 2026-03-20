# Tasks: security(web-platform) non-root USER directive

## Phase 1: Core Implementation

- [ ] 1.1 Add `RUN useradd -m soleur` to `apps/web-platform/Dockerfile` after `RUN npm run build`
- [ ] 1.2 Add `RUN chown -R soleur:soleur /app` to transfer ownership of build artifacts
- [ ] 1.3 Add `USER soleur` directive before the production `ENV`/`EXPOSE`/`CMD` block

## Phase 2: Deploy Script Update

- [ ] 2.1 Add `chown -R 1000:1000 /mnt/data/workspaces` to `.github/workflows/web-platform-release.yml` deploy step before `docker run`

## Phase 3: Verification

- [ ] 3.1 Build the Docker image locally (`docker build -t soleur-web-test apps/web-platform/`)
- [ ] 3.2 Verify the process runs as `soleur` (`docker run --rm soleur-web-test whoami`)
- [ ] 3.3 Verify `npm run start` succeeds (`.next/` readable by non-root user)
- [ ] 3.4 Verify HEALTHCHECK works (`curl` accessible to `soleur` user)
