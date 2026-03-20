# Tasks: security(web-platform): pin Dockerfile base image node:22-slim to specific digest

## Phase 1: Implementation

- [ ] 1.1 Update `apps/web-platform/Dockerfile` line 1 from `FROM node:22-slim AS base` to `FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS base`

## Phase 2: Verification

- [ ] 2.1 Run `docker build apps/web-platform/` locally to verify the build succeeds with the pinned digest
- [ ] 2.2 Verify the pulled base image resolves correctly for the current platform (`docker inspect` to confirm image ID matches expected platform manifest)

## Phase 3: Ship

- [ ] 3.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #805` in body
- [ ] 3.4 Verify CI release workflow builds successfully with pinned base image
