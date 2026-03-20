# Tasks: fix web-platform HEALTHCHECK missing curl

## Phase 1: Core Fix

- [ ] 1.1 Replace `curl -f` HEALTHCHECK with `node -e "fetch(...)"` in `apps/web-platform/Dockerfile` (lines 31-32)

## Phase 2: Verification

- [ ] 2.1 Build the Docker image locally to verify Dockerfile syntax is valid
- [ ] 2.2 Confirm no other files in `apps/web-platform/` reference `curl` that would need updating
