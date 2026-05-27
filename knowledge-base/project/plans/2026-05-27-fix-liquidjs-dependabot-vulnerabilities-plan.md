---
title: "fix: Resolve 2 moderate Dependabot vulnerabilities in liquidjs"
type: fix
date: 2026-05-27
lane: single-domain
classification: lockfile-only
---

# fix: Resolve 2 moderate Dependabot vulnerabilities in liquidjs

Two moderate Dependabot alerts (#85 and #87) flag vulnerabilities in liquidjs <= 10.25.7:

1. **Alert #85 -- XSS via `strip_html` filter bypass:** The `strip_html` filter in liquidjs <= 10.25.7 can be bypassed to inject script content.
2. **Alert #87 -- `ownPropertyOnly` bypass in `render` tag:** The `render` tag in liquidjs <= 10.25.7 does not properly enforce the `ownPropertyOnly` option, allowing access to prototype properties.

liquidjs is a transitive dependency of `@11ty/eleventy@3.1.5` (devDependency in root `package.json`). Eleventy requires `liquidjs ^10.25.0`. Current installed version is **10.25.2**. Versions **10.26.0** and **10.27.0** are available and within the `^10.25.0` semver range.

**Fix:** Run `npm update liquidjs` to update the lockfile resolution to 10.27.0. No code changes needed -- lockfile-only fix.

## User-Brand Impact

- **If this lands broken, the user experiences:** No user-facing impact. liquidjs is a devDependency used only during docs site build (Eleventy). A broken update would manifest as a docs build failure caught by CI before merge.
- **If this leaks, the user's data / workflow / money is exposed via:** Not applicable -- liquidjs processes only static docs templates committed to the repo. No user data flows through liquidjs at runtime.
- **Brand-survival threshold:** `none`

## Research Insights

- **Current state:** `npm ls liquidjs` shows `liquidjs@10.25.2` as a transitive dep of `@11ty/eleventy@3.1.5`
- **Semver range:** Eleventy declares `"liquidjs": "^10.25.0"` -- versions 10.26.0 and 10.27.0 are within range
- **Available versions:** 10.25.0 through 10.25.7, 10.26.0, 10.27.0 (confirmed via `npm view liquidjs versions`)
- **Relevant learning:** `knowledge-base/project/learnings/2026-03-30-npm-latest-tag-crosses-major-versions.md` -- never use `@latest`; pin to major. For this case, `npm update liquidjs` is correct since we are updating within the already-declared semver range, not installing a new version
- **Dev-only dependency:** liquidjs is used exclusively for Eleventy docs builds. It does not ship to production runtime

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `npm ls liquidjs` shows `liquidjs@10.27.0` (or latest available within `^10.25.0` that is >= 10.26.0)
- [x] AC2: `npm audit --audit-level=moderate` exits 0 (no moderate+ vulnerabilities remain)
- [x] AC3: Docs build succeeds: `npm run docs:build` exits 0
- [x] AC4: Only `package-lock.json` is modified: `git diff --name-only` returns only `package-lock.json`

## Test Scenarios

- Given the lockfile pins liquidjs@10.25.2, when `npm update liquidjs` runs, then `npm ls liquidjs` shows >= 10.26.0
- Given the updated lockfile, when `npm run docs:build` runs, then build completes with exit code 0
- Given the updated lockfile, when `npm audit` runs, then no moderate+ findings for liquidjs

## Open Code-Review Overlap

None

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- lockfile-only transitive dependency update for a devDependency.

## Implementation Phases

### Phase 1: Update lockfile

**Files to edit:**
- `package-lock.json` (automated by `npm update`)

**Steps:**

1. Run `npm update liquidjs`
2. Verify with `npm ls liquidjs` -- expect 10.27.0
3. Verify with `npm audit --audit-level=moderate` -- expect no liquidjs findings
4. Run `npm run docs:build` -- expect exit 0
5. Commit `package-lock.json`

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| liquidjs 10.27.0 introduces breaking Liquid template behavior | Low -- semver minor/patch within ^10.25.0 | AC3 docs build validates all existing templates |
| npm update pulls more than just liquidjs | Low -- `npm update liquidjs` targets only that package | AC4 verifies only lockfile changed |

## Context

- Dependabot alerts: #85, #87
- liquidjs changelog: Versions 10.26.0 and 10.27.0 contain security fixes for the `strip_html` filter XSS and `ownPropertyOnly` render tag bypass
- This is a docs-toolchain-only dependency -- zero production runtime exposure

## References

- [npm update docs](https://docs.npmjs.com/cli/v10/commands/npm-update)
- Learning: `knowledge-base/project/learnings/2026-03-30-npm-latest-tag-crosses-major-versions.md`
