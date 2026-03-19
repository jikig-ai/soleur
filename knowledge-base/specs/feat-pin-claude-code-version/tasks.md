# Tasks: Pin @anthropic-ai/claude-code npm version

## Phase 1: Core Implementation

- [ ] 1.1 Pin claude-code version in telegram-bridge Dockerfile
  - File: `apps/telegram-bridge/Dockerfile`, line 9
  - Change: `npm install -g @anthropic-ai/claude-code` -> `npm install -g @anthropic-ai/claude-code@2.1.79`

- [ ] 1.2 Pin claude-code version in web-platform Dockerfile
  - File: `apps/web-platform/Dockerfile`, line 4
  - Change: `npm install -g @anthropic-ai/claude-code` -> `npm install -g @anthropic-ai/claude-code@2.1.79`

## Phase 2: Verification

- [ ] 2.1 Verify Docker build succeeds for telegram-bridge
  - Run: `docker build apps/telegram-bridge/`
  - Confirm: build completes without errors

- [ ] 2.2 Verify Docker build succeeds for web-platform
  - Run: `docker build apps/web-platform/`
  - Confirm: build completes without errors

- [ ] 2.3 Run existing test suite
  - Confirm: all tests pass with no regressions

## Phase 3: Follow-up

- [ ] 3.1 File GitHub issue for unpinned `node:22-slim` base image in web-platform Dockerfile
  - Same class of issue as #794, different file
