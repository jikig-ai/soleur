---
title: "fix: resolve Dependabot security alerts for vite"
type: fix
date: 2026-04-07
---

# fix: Resolve Dependabot Security Alerts for Vite

## Overview

Three open Dependabot security alerts target `vite` in `apps/web-platform/package-lock.json`. All three are resolved by updating vite from `7.3.1` to `7.3.2`. Vite is a transitive dependency pulled in by `vitest ^3.1.0` (devDependencies), not a direct dependency.

## Problem Statement

The following Dependabot alerts are open on the repository:

| Alert | Severity | CVE / GHSA | Summary | Fix |
|-------|----------|------------|---------|-----|
| #28 | High | CVE-2026-39363 / GHSA-p9ff-h696-f583 | Arbitrary File Read via Vite Dev Server WebSocket | vite >= 7.3.2 |
| #27 | Medium | GHSA-4w7w-66w2-5vf9 | Path Traversal in Optimized Deps `.map` Handling | vite >= 7.3.2 |
| #26 | High | GHSA-v2wj-q39q-566r | `server.fs.deny` bypassed with queries | vite >= 7.3.2 |

All three alerts affect the `apps/web-platform/package-lock.json` manifest. The vulnerable version range is `>= 7.0.0, <= 7.3.1`.

### Risk Assessment

These vulnerabilities affect the Vite dev server, not the production build. The production app uses Next.js with a custom Express server (see `apps/web-platform/Dockerfile`). However:

- Developers running `npm run dev` locally are exposed to the arbitrary file read and path traversal vulnerabilities.
- The `server.fs.deny` bypass could leak sensitive files during local development.
- Keeping known high-severity alerts open degrades the security posture signal for the repository.

## Proposed Solution

Update vite from `7.3.1` to `7.3.2` by regenerating both lockfiles in `apps/web-platform/`:

1. `package-lock.json` (used by `npm ci` in the Dockerfile)
2. `bun.lock` (used by local development)

No changes to `package.json` are needed -- vite is not a direct dependency. The `vitest` peer dependency constraint (`^5.0.0 || ^6.0.0 || ^7.0.0-0`) already accepts `7.3.2`.

## Technical Considerations

### Dual Lockfile Constraint

Per AGENTS.md, `apps/web-platform` has both `bun.lock` and `package-lock.json`. The Dockerfile uses `npm ci` which requires `package-lock.json` to be in sync. Both lockfiles must be regenerated:

1. Run `npm update vite` in `apps/web-platform/` to update `package-lock.json`
2. Run `bun install` in `apps/web-platform/` to update `bun.lock`

### Version Pinning

The fix targets `vite@7.3.2` specifically (within the `^7.0.0-0` peer constraint). Do not use `@latest` which could cross major version boundaries.

### No Direct Dependency Change

`vite` is pulled in transitively by `vitest`. The `package.json` does not list `vite` as a dependency. The lockfile update is sufficient.

## Acceptance Criteria

- [ ] `apps/web-platform/package-lock.json` resolves vite to `>= 7.3.2`
- [ ] `apps/web-platform/bun.lock` resolves vite to `>= 7.3.2`
- [ ] `package.json` is unchanged (no direct vite dependency added)
- [ ] `npm ci` succeeds in `apps/web-platform/` (validates lockfile integrity)
- [ ] `npm run typecheck` passes in `apps/web-platform/`
- [ ] `npm run test` passes in `apps/web-platform/` (vitest still works with updated vite)
- [ ] All 3 Dependabot alerts (#26, #27, #28) auto-close after merge to main
- [ ] Docker build succeeds (CI validates this)

## Test Scenarios

- Given the updated lockfiles, when `npm ci` runs in `apps/web-platform/`, then it succeeds without errors
- Given the updated vite version, when `vitest` runs the test suite, then all existing tests pass
- Given the updated lockfiles, when `npx tsc --noEmit` runs, then type checking passes
- Given the PR merges to main, when Dependabot re-scans, then alerts #26, #27, #28 close automatically

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- dev dependency security patch.

## MVP

### Phase 1: Update Lockfiles

```bash
# In apps/web-platform/
npm update vite
bun install
```

### Phase 2: Verify

```bash
# In apps/web-platform/
npm ci
npm run typecheck
npm run test
```

### Phase 3: Validate Alert Resolution

After merge, verify via:

```bash
gh api repos/jikig-ai/soleur/dependabot/alerts \
  --jq '[.[] | select(.state == "open")] | length'
# Expected: 0 (or fewer than current 3)
```

## References

- Dependabot alerts: <https://github.com/jikig-ai/soleur/security/dependabot>
- Vite 7.3.2 release: <https://github.com/vitejs/vite/releases/tag/v7.3.2>
- GHSA-p9ff-h696-f583: <https://github.com/advisories/GHSA-p9ff-h696-f583>
- GHSA-4w7w-66w2-5vf9: <https://github.com/advisories/GHSA-4w7w-66w2-5vf9>
- GHSA-v2wj-q39q-566r: <https://github.com/advisories/GHSA-v2wj-q39q-566r>
