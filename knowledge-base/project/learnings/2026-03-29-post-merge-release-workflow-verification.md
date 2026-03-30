# Learning: Post-Merge Release Workflow Verification

## Problem

PR #1275 added `@playwright/test` to `apps/web-platform/package.json` and updated `bun.lock`, but did not regenerate `package-lock.json`. PR CI passed because it uses `bun test`, not `npm ci`. However, the Docker build in the release workflow uses `npm ci`, which requires `package-lock.json` to be in sync with `package.json`.

Five consecutive release runs failed silently after the merge. Production stayed on v0.8.6 while the codebase moved to v0.9.4. No one was paged because the health check returned "ok" (old version was healthy) — only the version mismatch check in the deploy step caught it, and that check only runs as part of the release workflow (which was already failing).

## Solution

Two fixes applied:

### Immediate fix (PR #1293)

Regenerated `package-lock.json` by running `npm install` in `apps/web-platform/`. This synced the lockfile with the Playwright dependency added in `package.json`.

### Systemic fix (this PR)

Added a post-merge release workflow verification gate to `/ship` Phase 7:

- After merge confirmation, detect all CI/CD runs triggered by the push to main
- Poll until all complete
- Report success/failure
- On failure: investigate and fix before ending the session

Also added:

- AGENTS.md hard rule requiring post-merge release verification
- Strengthened the lockfile sync rule to explicitly require both `bun.lock` AND `package-lock.json` regeneration when both exist

## Key Insight

PR CI and release CI test different things. PR CI runs `bun test` (unit tests). Release CI runs `npm ci` inside a Docker build (dependency installation). A dependency change can pass PR CI while breaking release CI. The gap was that `/ship` verified PR merge but not release success — it assumed merge = deploy.

The dual-lockfile problem (`bun.lock` for local dev, `package-lock.json` for Docker) is a recurring hazard in projects that use bun locally but npm in production containers. Both must be updated atomically when dependencies change.

## Tags

category: workflow-patterns
module: plugins/soleur/skills/ship
