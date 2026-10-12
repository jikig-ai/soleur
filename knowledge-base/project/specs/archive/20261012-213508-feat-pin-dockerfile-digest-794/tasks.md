# Tasks: Pin Dockerfile Base Image to Specific Digest

## Phase 1: Implementation

- [ ] 1.1 Update `apps/telegram-bridge/Dockerfile` line 1: replace `FROM oven/bun:latest` with `FROM oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7`

## Phase 2: Verification

- [ ] 2.1 Run `docker build apps/telegram-bridge/` to verify the pinned image builds successfully
- [ ] 2.2 Verify no other Dockerfile lines were modified (single-line change only)

## Phase 3: Follow-Up

- [ ] 3.1 File GitHub issue for `apps/web-platform/Dockerfile` base image pinning (`FROM node:22-slim` lacks digest)
