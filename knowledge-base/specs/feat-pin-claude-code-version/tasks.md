# Tasks: Pin @anthropic-ai/claude-code npm version

## Phase 1: Core Implementation

- [x] 1.1 Pin claude-code version in telegram-bridge Dockerfile
  - File: `apps/telegram-bridge/Dockerfile`, line 9
  - Change: `npm install -g @anthropic-ai/claude-code` -> `npm install -g @anthropic-ai/claude-code@2.1.79`

- [x] 1.2 Pin claude-code version in web-platform Dockerfile
  - File: `apps/web-platform/Dockerfile`, line 4
  - Change: `npm install -g @anthropic-ai/claude-code` -> `npm install -g @anthropic-ai/claude-code@2.1.79`

## Phase 2: Verification

- [x] 2.1 Verify Docker build succeeds for telegram-bridge
  - Run: `docker build apps/telegram-bridge/`
  - Confirm: build completes without errors

- [x] 2.2 Verify Docker build succeeds for web-platform
  - Run: `docker build apps/web-platform/`
  - Confirm: build completes without errors

- [x] 2.3 Run existing test suite (no project-level test suite; Docker builds verify correctness)
  - Confirm: all tests pass with no regressions

## Phase 3: Follow-up

- [x] 3.1 File GitHub issue for unpinned `node:22-slim` base image in web-platform Dockerfile (#805)
  - Same class of issue as #794, different file
