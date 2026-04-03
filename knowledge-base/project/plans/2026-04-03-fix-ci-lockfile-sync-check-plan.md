---
title: "fix(ci): add lockfile sync check to PR CI"
type: fix
date: 2026-04-03
---

# fix(ci): add lockfile sync check to PR CI

## Enhancement Summary

**Deepened on:** 2026-04-03
**Sections enhanced:** 3 (Proposed Solution, Implementation Detail, Test Scenarios)
**Research sources:** npm CLI docs (Context7), existing CI workflow analysis, project learnings

### Key Improvements

1. Added concrete YAML implementation with pinned action SHAs from existing CI
2. Verified `npm install --package-lock-only` uses the same peer dep resolver as `npm ci` (both use Arborist)
3. Added edge case for `.npmrc` flag mismatch (verified: no `.npmrc` in project, so default behavior is consistent)
4. Added npm version compatibility note (node 22 in both Docker and CI = same npm 10.x)

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
3. `npm install --package-lock-only` in `apps/web-platform/` (uses default npm peer resolution to match Docker `npm ci` behavior)
4. `git diff --exit-code apps/web-platform/package-lock.json` -- if this exits non-zero, the lockfile is out of sync
5. On failure: print a clear error message with remediation instructions

**Critical YAML rule (from AGENTS.md):** Do not use heredocs in GitHub Actions `run:` blocks. Use `{ echo "..."; }` or shell variables for multi-line output.

**npm registry note:** `npm install --package-lock-only` resolves the full dependency tree against the npm registry (network I/O), but does not write `node_modules/`. Execution time is typically 5-15 seconds.

### Concrete YAML implementation

```yaml
  lockfile-sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Setup Node.js
        uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: 22

      - name: Regenerate package-lock.json
        working-directory: apps/web-platform
        run: npm install --package-lock-only

      - name: Check lockfile sync
        run: |
          if ! git diff --exit-code apps/web-platform/package-lock.json; then
            echo "::error::package-lock.json is out of sync with package.json in apps/web-platform/."
            echo "::error::Run 'npm install' in apps/web-platform/ and commit the updated package-lock.json."
            exit 1
          fi
```

### Research insights

**Peer dependency resolution parity:** `npm install --package-lock-only` uses the same Arborist resolver as `npm ci`. Both detect ERESOLVE peer conflicts identically. The only difference is that `--package-lock-only` updates the lockfile to match `package.json`, while `npm ci` rejects any mismatch. This makes `--package-lock-only` + `git diff` the correct detection strategy: it regenerates what the lockfile *should* be, then checks if it matches what is committed.

**`.npmrc` flag consistency:** If the lockfile was generated with `--legacy-peer-deps`, the CI check must also use that flag (per npm docs). Verified: no `.npmrc` exists in the project, so default strict peer resolution is used consistently across local dev, CI, and Docker.

**npm version alignment:** The Docker image (`node:22-slim`) and CI (`setup-node` with node 22) both bundle npm 10.x, ensuring identical resolution behavior. No version skew risk.

**No `node_modules` side effects:** The `--package-lock-only` flag explicitly skips writing `node_modules/`, making this job fast and side-effect-free. No caching needed.

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
- Given a PR where `package.json` adds a dependency with an incompatible peer constraint, when CI runs, then `npm install --package-lock-only` itself fails with ERESOLVE (catching the conflict even earlier than the lockfile diff check)

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
