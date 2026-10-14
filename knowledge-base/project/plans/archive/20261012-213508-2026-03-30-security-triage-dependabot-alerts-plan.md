---
title: "security: triage Dependabot alerts surfaced by dependency graph enablement"
type: fix
date: 2026-03-30
---

# security: triage Dependabot alerts surfaced by dependency graph enablement

## Overview

Enabling the Dependency Graph (#1294) surfaced 15 open Dependabot alerts (7 high, 8 medium). This plan triages every alert for applicability (runtime vs dev-only, code path reachability), then prescribes upgrade or dismiss with justification. The dependency-review workflow (`fail-on-severity: high`, `fail-on-scopes: runtime`) already blocks new high-severity runtime introductions on PRs -- this triage addresses the existing backlog.

## Alert Inventory

### Open Alerts (15 total)

| # | Package | Version | Severity | Manifest | Scope | GHSA | Summary | Fix Available |
|---|---------|---------|----------|----------|-------|------|---------|---------------|
| 24 | path-to-regexp | 8.3.0 | **HIGH** | `pencil-setup/scripts/package-lock.json` | runtime | GHSA-j3q9-mxjg-w52f | DoS via sequential optional groups | 8.4.0 |
| 23 | pillow | 11.3.0 | **HIGH** | `gemini-imagegen/requirements.txt` | runtime | GHSA-cfh3-3jmp-rvhc | OOB write loading PSD images | 12.1.1 |
| 16 | liquidjs | 10.24.0 | **HIGH** | `package-lock.json` | dev | GHSA-6q5m-63h6-5x4v | Exponential memory via replace_first | None (<=10.24.0) |
| 15 | liquidjs | 10.24.0 | **HIGH** | `package-lock.json` | dev | GHSA-9r5m-9576-7f6x | memoryLimit bypass via negative range | None (<=10.24.0) |
| 14 | liquidjs | 10.24.0 | **HIGH** | `package-lock.json` | dev | GHSA-wmfp-5q7x-987x | Path traversal fallback | 10.25.0 |
| 13 | minimatch | 3.1.2 | **HIGH** | `package-lock.json` | dev | GHSA-7r86-cg39-jmmj | ReDoS via GLOBSTAR segments | 3.1.3 |
| 3 | flatted | 3.4.1 | **HIGH** | `apps/web-platform/package-lock.json` | dev | GHSA-rf6f-7fwh-wjgh | Prototype pollution via parse() | 3.4.2 |
| 25 | path-to-regexp | 8.3.0 | medium | `pencil-setup/scripts/package-lock.json` | runtime | GHSA-27v5-c462-wpq7 | ReDoS via multiple wildcards | 8.4.0 |
| 21 | picomatch | 2.3.1 | medium | `package-lock.json` | dev | GHSA-3v7f-55p6-f55p | Method injection in POSIX classes | 2.3.2 |
| 20 | picomatch | 4.0.3 | medium | `package-lock.json` | dev | GHSA-3v7f-55p6-f55p | Method injection in POSIX classes | 4.0.4 |
| 8 | picomatch | 2.3.1 | medium | `apps/web-platform/package-lock.json` | dev | GHSA-3v7f-55p6-f55p | Method injection in POSIX classes | 2.3.2 |
| 7 | picomatch | 4.0.3 | medium | `apps/web-platform/package-lock.json` | dev | GHSA-3v7f-55p6-f55p | Method injection in POSIX classes | 4.0.4 |
| 4 | next | 15.5.12 | medium | `apps/web-platform/package-lock.json` | runtime | GHSA-3x4c-7xq6-9pq8 | Unbounded next/image disk cache growth | 15.5.14 |
| 2 | next | 15.5.12 | medium | `apps/web-platform/package-lock.json` | runtime | GHSA-ggv3-7p47-pfv8 | HTTP request smuggling in rewrites | 15.5.13 |
| 1 | esbuild | 0.21.5 | medium | `apps/web-platform/package-lock.json` | dev | GHSA-67mh-4wv8-2f99 | Dev server sends requests to any website | 0.25.0 |

### Auto-Dismissed by Dependabot (10 additional, no action needed)

Alerts #5, #6, #9, #10, #11, #12, #17, #18, #19, #22 were auto-dismissed by Dependabot (dev-scope with no exploit path).

## Triage Decisions

### Phase 1: Runtime Alerts -- Upgrade (4 alerts)

These are runtime dependencies with available patches. Upgrade immediately.

#### 1.1 Next.js 15.5.12 -> 15.5.14+ (alerts #2, #4)

- **Package:** `next` in `apps/web-platform/package.json`
- **Current:** 15.5.12, **Target:** latest 15.5.x (>=15.5.14)
- **Alerts fixed:** GHSA-ggv3-7p47-pfv8 (HTTP request smuggling in rewrites), GHSA-3x4c-7xq6-9pq8 (unbounded next/image disk cache)
- **Applicability:** Both are runtime in a production web platform. Request smuggling is exploitable if rewrites are configured. Disk cache exhaustion is a DoS vector. Both warrant patching.
- **Action:** `cd apps/web-platform && npm install next@latest` then regenerate lockfiles in order: `bun install` first, then `npm install` to regenerate `package-lock.json` (Dockerfile uses `npm ci`).
- **Risk:** Minor -- patch-level Next.js update within the 15.5.x line.
- **Files:** `apps/web-platform/package.json`, `apps/web-platform/package-lock.json`, `apps/web-platform/bun.lock`

#### 1.2 Pillow 11.3.0 -> 12.1.1+ (alert #23)

- **Package:** `pillow` in `plugins/soleur/skills/gemini-imagegen/requirements.txt`
- **Current:** 11.3.0, **Target:** >=12.1.1
- **Alert fixed:** GHSA-cfh3-3jmp-rvhc (OOB write when loading PSD images)
- **Applicability:** Runtime dependency used for image processing. Although PSD loading may not be a primary use case, the OOB write is a memory safety issue. Major version bump (11->12) requires testing.
- **Action:** Update `requirements.txt` pin from `Pillow==11.3.0` to `Pillow==12.1.1`.
- **Risk:** Medium -- major version bump. Test `gemini-imagegen` skill after upgrade. Review [Pillow 12.x release notes](https://pillow.readthedocs.io/en/stable/releasenotes/) for breaking API changes before upgrading.
- **Files:** `plugins/soleur/skills/gemini-imagegen/requirements.txt`

#### 1.3 path-to-regexp 8.3.0 -> 8.4.0 (alerts #24, #25)

- **Package:** `path-to-regexp` in `plugins/soleur/skills/pencil-setup/scripts/package-lock.json`
- **Current:** 8.3.0, **Target:** 8.4.0
- **Alerts fixed:** GHSA-j3q9-mxjg-w52f (DoS via sequential optional groups), GHSA-27v5-c462-wpq7 (ReDoS via multiple wildcards)
- **Applicability:** Runtime dependency of the pencil-setup MCP adapter. Transitive via `@modelcontextprotocol/sdk`. Both are DoS vectors through crafted route patterns.
- **Action:** `cd plugins/soleur/skills/pencil-setup/scripts && npm update path-to-regexp` to pull 8.4.0. If the lockfile pins it transitively, delete lockfile and regenerate.
- **Risk:** Low -- minor patch within 8.x.
- **Files:** `plugins/soleur/skills/pencil-setup/scripts/package-lock.json`

### Phase 2: Dev-Only Alerts -- Dismiss or Upgrade (11 alerts)

These are dev-scope dependencies. The `dependency-review.yml` workflow already uses `fail-on-scopes: runtime` so dev-scope vulnerabilities do not block PRs. However, upgrading where easy is good hygiene.

#### 2.1 liquidjs (alerts #14, #15, #16) -- Upgrade via Eleventy

- **Package:** `liquidjs` transitive via `@11ty/eleventy` in root `package.json`
- **Current:** 10.24.0, **Target:** 10.25.0+ (fixes #14, path traversal). Alerts #15 and #16 have no patch yet (<=10.24.0 affected).
- **Applicability:** Dev-only (docs build). Path traversal (#14) could matter if untrusted Liquid templates are processed, but Eleventy only processes local project templates. Memory amplification (#15, #16) is DoS on the build machine.
- **Action:** Check if a newer `@11ty/eleventy` pulls `liquidjs>=10.25.0`. If yes, update the Eleventy dependency. If not, the alert cannot be resolved at this time -- dismiss #15 and #16 with "no patch available; dev-only scope; templates are trusted local files." Dismiss #14 if Eleventy update resolves it; otherwise same treatment.
- **Risk:** Low -- Eleventy is a dev/build tool.
- **Files:** `package.json`, `package-lock.json`

#### 2.2 minimatch 3.1.2 (alert #13) -- Upgrade

- **Package:** `minimatch` transitive in root `package-lock.json`
- **Current:** 3.1.2, **Target:** 3.1.3
- **Applicability:** Dev-only. ReDoS in glob matching. Only affects build tooling.
- **Action:** `npm update minimatch` or regenerate lockfile. The fix is a patch bump.
- **Risk:** None.
- **Files:** `package-lock.json`

#### 2.3 flatted 3.4.1 (alert #3) -- Upgrade via eslint chain

- **Package:** `flatted` transitive via `eslint -> file-entry-cache -> flat-cache -> flatted` in `apps/web-platform/package-lock.json`
- **Current:** 3.4.1, **Target:** 3.4.2
- **Applicability:** Dev-only (ESLint). Prototype pollution via `parse()` -- only exploitable if untrusted input is passed to flatted, which ESLint does not do.
- **Action:** Regenerate `apps/web-platform/package-lock.json`. The fix is a patch bump in a transitive dependency. Check if `npm update flatted` pulls 3.4.2 through.
- **Risk:** None.
- **Files:** `apps/web-platform/package-lock.json`, `apps/web-platform/bun.lock`

#### 2.4 picomatch (alerts #7, #8, #20, #21) -- Upgrade

- **Package:** `picomatch` in root and `apps/web-platform` lockfiles
- **Current:** 2.3.1 and 4.0.3, **Target:** 2.3.2 and 4.0.4
- **Applicability:** Dev-only. Method injection in POSIX character classes. Only affects glob matching in dev tooling.
- **Action:** Regenerate lockfiles. `npm update picomatch` in both root and `apps/web-platform/`.
- **Risk:** None.
- **Files:** `package-lock.json`, `apps/web-platform/package-lock.json`, `apps/web-platform/bun.lock`

#### 2.5 esbuild 0.21.5 (alert #1) -- Dismiss

- **Package:** `esbuild` transitive via `vite` in `apps/web-platform/package-lock.json`
- **Current:** 0.21.5 (transitive via vite), **Direct:** 0.25.12 (root dep)
- **Applicability:** Dev-only. The vulnerability allows any website to send requests to the esbuild dev server. This only affects local development, not production. The direct dependency is already on 0.25.x. The 0.21.5 is a transitive pin from vite.
- **Action:** Dismiss with "dev-only scope; affects local dev server only; not exposed in production; direct dependency already patched." If vite releases an update pulling esbuild >=0.25.0, it will resolve automatically.
- **Risk:** None for production.

## Proposed Solution

### Implementation Phases

#### Phase 1: Runtime Upgrades (high priority)

1. Upgrade Next.js to >=15.5.14 in `apps/web-platform/`
2. Upgrade Pillow to 12.1.1 in `plugins/soleur/skills/gemini-imagegen/requirements.txt`
3. Regenerate `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` to pull path-to-regexp 8.4.0
4. Regenerate both `bun.lock` and `package-lock.json` in `apps/web-platform/` (per constitution: Dockerfiles use `npm ci`)

#### Phase 2: Dev-Only Upgrades (medium priority)

1. Update `@11ty/eleventy` in root `package.json` if a newer version pulls liquidjs >=10.25.0
2. Regenerate root `package-lock.json` to pull minimatch 3.1.3 and picomatch 2.3.2/4.0.4
3. Regenerate `apps/web-platform/package-lock.json` to pull flatted 3.4.2 and picomatch patches

#### Phase 3: Dismissals

1. Dismiss esbuild alert #1 (dev-only, local dev server only)
2. Dismiss liquidjs alerts #15, #16 if no patch available (dev-only, trusted templates)
3. Consider adding `allow-ghsas` to `dependency-review.yml` for dismissed advisories only if they cause PR failures (GHSA-67mh-4wv8-2f99 for esbuild, GHSA-6q5m-63h6-5x4v and GHSA-9r5m-9576-7f6x for liquidjs if no patch available). Defer if no PR is actually blocked.

#### Phase 4: Verification

1. Run `gh api repos/jikig-ai/soleur/dependabot/alerts --jq '[.[] | select(.state == "open")] | length'` -- expect 0 or only dismissed alerts remaining
2. Verify `apps/web-platform` builds successfully: `cd apps/web-platform && npm run build`
3. Verify gemini-imagegen works: `pip install -r plugins/soleur/skills/gemini-imagegen/requirements.txt`
4. Verify docs build: `npm run docs:build`

## Acceptance Criteria

- [x] All 7 high-severity alerts resolved (upgraded or dismissed with documented justification)
- [x] All 8 medium-severity alerts triaged (upgraded, dismissed, or tracked)
- [x] No runtime-scope alerts remain open
- [x] Both lockfiles regenerated in `apps/web-platform/` (bun.lock + package-lock.json)
- [x] `apps/web-platform` builds successfully after upgrades
- [x] Docs site builds successfully after root dependency updates
- [x] Each dismissal includes a GHSA ID, reason, and scope justification

## Test Scenarios

- Given Next.js is upgraded to >=15.5.14, when `npm run build` is run in `apps/web-platform/`, then build succeeds without errors
- Given Pillow is upgraded to 12.1.1, when `pip install -r requirements.txt` is run in `gemini-imagegen/`, then installation succeeds
- Given path-to-regexp is upgraded to 8.4.0, when `npm ls path-to-regexp` is run in `pencil-setup/scripts/`, then version shows 8.4.0
- Given all upgrades are applied, when `gh api repos/jikig-ai/soleur/dependabot/alerts --jq '[.[] | select(.state == "open")] | length'` is run, then the count is 0 (or only known-dismissed dev alerts remain)
- Given dismissed alerts have justifications, when the PR is reviewed, then each dismissal references the GHSA ID and explains why the vulnerability is not applicable

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change (dependency security maintenance).

## Context

- Related: #1294 (dependency graph enablement), #1174 (supply chain security)
- The `dependency-review.yml` workflow blocks new high-severity runtime introductions on PRs but does not address existing backlog
- This triage aligns with Phase 2 milestone ("Secure for Beta") exit criteria: "0 critical/high security findings"

## References

- [GitHub Advisory Database](https://github.com/advisories)
- `apps/web-platform/package.json` -- Next.js, esbuild direct dependencies
- `plugins/soleur/skills/gemini-imagegen/requirements.txt` -- Pillow pin
- `plugins/soleur/skills/pencil-setup/scripts/package.json` -- MCP adapter dependencies
- `.github/workflows/dependency-review.yml` -- PR-level vulnerability blocking
