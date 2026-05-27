---
title: "Tasks: fix gh ENOENT in cron-follow-through-monitor"
date: 2026-05-27
plan: knowledge-base/project/plans/2026-05-27-fix-gh-enoent-cron-follow-through-monitor-plan.md
---

# Tasks: fix gh ENOENT in cron-follow-through-monitor

## Phase 1: Add gh CLI to Dockerfile

- [x] 1.1 Add GitHub CLI apt repository setup to `apps/web-platform/Dockerfile` runner stage
  - [x] 1.1.1 Add `curl` to the apt-get install list (needed for keyring fetch)
  - [x] 1.1.2 Fetch GitHub CLI GPG keyring via curl
  - [x] 1.1.3 Add GitHub CLI apt source list
  - [x] 1.1.4 Add `gh` to the apt-get install block
  - [x] 1.1.5 Set `chmod go+r` on the keyring file (official docs best practice)
  - [x] 1.1.6 Clean up apt lists

## Phase 2: Verification

- [x] 2.1 Run lightweight QA verification via `docker run --rm node:22-slim bash -c '...'` (see plan Research Insights for exact command)
- [x] 2.2 Verify `gh --version` returns a valid version string in the isolated test (2.92.0)
- [x] 2.3 Verify no other files are modified beyond the Dockerfile
