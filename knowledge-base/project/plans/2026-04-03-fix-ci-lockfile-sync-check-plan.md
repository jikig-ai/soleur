---
title: "fix(ci): add lockfile sync check to PR CI"
type: fix
date: 2026-04-03
---

# fix(ci): add lockfile sync check to PR CI

## Overview

Add a CI job that detects when `package-lock.json` is out of sync with `package.json` in `apps/web-platform/`. This prevents the recurring failure pattern where dependency changes pass PR CI (which uses `bun install`) but break the release Docker build (which uses `npm ci`).

## Problem Statement

The project uses dual lockfiles: `bun.lock` for local development and PR CI, `package-lock.json` for Docker builds via `npm ci`. When a developer adds or modifies a dependency in `package.json` and runs `bun install`, only `bun.lock` is updated. `package-lock.json` is silently left stale. PR CI passes because it runs `bun install --frozen-lockfile`. The Docker build in the release workflow fails because `npm ci` rejects the stale lockfile.

This has caused two production outages:

- PR #1275: Added `@playwright/test` without regenerating `package-lock.json` -- 5 consecutive release failures, production stuck on v0.8.6
- PR #1306: Added `@vitejs/plugin-react` without regenerating `package-lock.json` -- release failures, production stuck on v0.9.7

The parent plan (`2026-03-30-fix-deploy-verification-docker-build-plan.md`) identified this as Task 3. Tasks 1 (lockfile fix) and 2 (deploy gating on `docker_pushed`) are already merged.

## Proposed Solution

Add a new job `lockfile-sync` to `.github/workflows/ci.yml` that:

1. Runs `npm install --package-lock-only` in `apps/web-platform/` to regenerate `package-lock.json` from `package.json` without modifying `node_modules/`
2. Checks `git diff --exit-code apps/web-platform/package-lock.json` for uncommitted changes
3. Fails with a clear error message if changes are detected, explaining that the developer must run `npm install` in the app directory and commit the updated lockfile

### Trigger scope

The job should run on all PRs (not gated by path filter). Rationale: root-level `package.json` changes or transitive dependency changes can also affect the lockfile. The `npm install --package-lock-only` command is fast (no `node_modules` writes) so the overhead is minimal.

### Implementation detail

**File:** `.github/workflows/ci.yml`

**New job: `lockfile-sync`**

Steps:

1. `actions/checkout` (same pinned SHA as other jobs)
2. `actions/setup-node` with node 22 (required for `npm install`)
3. `npm install --package-lock-only` in `apps/web-platform/`
4. `git diff --exit-code apps/web-platform/package-lock.json` -- if this exits non-zero, the lockfile is out of sync
5. On failure: print a clear error message with remediation instructions

**Critical YAML rule (from AGENTS.md):** Do not use heredocs in GitHub Actions `run:` blocks. Use `{ echo "..."; }` or shell variables for multi-line output.

## Acceptance Criteria

- [ ] New `lockfile-sync` job added to `.github/workflows/ci.yml`
- [ ] Job runs `npm install --package-lock-only` in `apps/web-platform/`
- [ ] Job fails when `package-lock.json` has uncommitted changes after regeneration
- [ ] Job passes when `package-lock.json` is already in sync
- [ ] Error message clearly explains what went wrong and how to fix it
- [ ] Job uses pinned action SHAs consistent with existing CI jobs

## Test Scenarios

- Given a PR where `package.json` has a new dependency and `package-lock.json` is stale, when CI runs, then the `lockfile-sync` job fails with a message instructing the developer to run `npm install` and commit the updated lockfile
- Given a PR where `package.json` and `package-lock.json` are in sync, when CI runs, then the `lockfile-sync` job passes
- Given a PR that does not change `package.json` at all, when CI runs, then the `lockfile-sync` job passes (lockfile unchanged)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CI infrastructure change with no user-facing, legal, marketing, or financial impact.

## References

- Issue: [#1318](https://github.com/jikig-ai/soleur/issues/1318)
- Parent issue: [#1307](https://github.com/jikig-ai/soleur/issues/1307)
- Parent plan: `knowledge-base/project/plans/2026-03-30-fix-deploy-verification-docker-build-plan.md` (Task 3)
- Learning: `knowledge-base/project/learnings/2026-03-29-post-merge-release-workflow-verification.md`
- Learning: `knowledge-base/project/learnings/2026-03-30-unused-dep-peer-conflict-docker-build.md`
- Previous lockfile fix PR: [#1293](https://github.com/jikig-ai/soleur/pull/1293)
- Previous lockfile fix PR: [#1308](https://github.com/jikig-ai/soleur/pull/1308)
