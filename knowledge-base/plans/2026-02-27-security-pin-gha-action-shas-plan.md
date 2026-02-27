---
title: "security: Pin mutable GitHub Actions tags to commit SHAs"
type: fix
date: 2026-02-27
issue: "#343"
version_bump: PATCH
deepened: 2026-02-27
---

# security: Pin mutable GitHub Actions tags to commit SHAs

## Enhancement Summary

**Deepened on:** 2026-02-27
**Sections enhanced:** 5 (Problem Statement, Files Changed, Non-goals, Acceptance Criteria, References)

### Key Improvements

1. **Discovered a missed workflow:** `auto-release.yml` also uses unpinned `actions/checkout@v4` -- not listed in the original issue #343. Total affected files: 4 (not 3).
2. **Documented Dependabot tradeoff:** SHA pinning disables Dependabot vulnerability alerts for pinned actions. The version comment format enables Dependabot to propose SHA updates, but security advisories will not trigger alerts automatically.
3. **Verified all SHAs against the GitHub API** using `git/refs/tags` dereferencing to confirm each mutable tag's current commit. All SHAs in the mapping table are API-verified.
4. **Added real-world attack context:** The tj-actions/changed-files incident (March 2025) compromised 23,000+ repositories via tag repointing -- the exact attack vector this fix mitigates.

### New Considerations Discovered

- GitHub now offers org/repo-level policy enforcement for SHA pinning (August 2025 changelog). Could be a follow-up.
- `claude-code-review.yml` is also missing `timeout-minutes` (constitution rule). Noted but out of scope.

---

## Overview

Four GitHub Actions workflows use mutable version tags (`@v4`, `@v2`, `@v1`) instead of pinned commit SHAs. This is a supply-chain security risk -- the action publisher can silently redirect the tag to a different commit. Three other workflows (`scheduled-competitive-analysis.yml`, `review-reminder.yml`, `cla.yml`) already follow the correct pinning pattern.

## Problem Statement

Mutable tags in GitHub Actions are a supply-chain attack vector. An upstream action publisher (or attacker who compromises their account) can force-push the tag to a malicious commit. Pinning to a commit SHA makes the action immutable -- any change requires an explicit update in the workflow file, which appears in a pull request diff.

Evidence that the risk is real: `actions/checkout@v4` currently resolves to commit `34e114876b...` (v4.3.1), but the SHAs pinned in `review-reminder.yml` reference `11bd71901b...` (v4.2.2). The tag has already moved since those pins were set.

The `claude-code-review.yml` workflow is particularly high-risk: `anthropics/claude-code-action@v1` runs with `id-token: write` and `pull-requests: write` permissions -- a compromised action could exfiltrate secrets or modify PR content.

### Research Insights

**Real-world precedent:** In March 2025, the `tj-actions/changed-files` action was compromised. An attacker gained access and updated more than 350 Git tags to point to a malicious commit that dumped runner secrets. Over 23,000 repositories were affected. Pinning to commit SHAs would have been fully protective.

**GitHub's own guidance:** "Pinning an action to a full-length commit SHA is currently the only way to use an action as an immutable release." -- [GitHub Security Hardening docs](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)

**Enforcement options (August 2025):** GitHub now supports org/repo-level policies that require all workflow action references to use full-length commit SHAs. This could be enabled as a follow-up to prevent regressions.

## Proposed Solution

Replace all mutable tags with pinned commit SHAs using the format:

```yaml
uses: <org>/<action>@<full-sha> # <version-tag>
```

The trailing comment preserves version traceability for future updates and enables Dependabot to propose SHA updates when new versions are released.

### SHA Mapping (API-verified 2026-02-27)

All SHAs verified via `gh api repos/<org>/<action>/git/refs/tags/<tag>` with annotated tag dereferencing where needed.

| Action | Current Tag | Pin To SHA | Version |
|--------|-------------|-----------|---------|
| `actions/checkout` | `@v4` | `34e114876b0b11c390a56381ad16ebd13914f8d5` | v4.3.1 |
| `oven-sh/setup-bun` | `@v2` | `3d267786b128fe76c2f16a390aa2448b815359f3` | v2.1.2 |
| `actions/setup-node` | `@v4` | `49933ea5288caeca8642d1e84afbd3f7d6820020` | v4.4.0 |
| `actions/configure-pages` | `@v4` | `1f0c5cde4bc74cd7e1254d0cb4de8d49e9068c7d` | v4.0.0 |
| `actions/upload-pages-artifact` | `@v3` | `56afc609e74202658d3ffba0e8f6dda462b719fa` | v3.0.1 |
| `actions/deploy-pages` | `@v4` | `d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e` | v4.0.5 |
| `anthropics/claude-code-action` | `@v1` | `1dd74842e568f373608605d9e45c9e854f65f543` | v1.0.63 |

### Decision: Update checkout SHA across all workflows

The existing pins in `scheduled-competitive-analysis.yml` and `review-reminder.yml` use `actions/checkout@11bd71901b... # v4.2.2`. The current `@v4` tag now points to `34e114876b... # v4.3.1`. Two options:

1. **Pin all to v4.2.2** (match existing pins) -- keeps all files consistent but uses an older version.
2. **Pin all to v4.3.1** (match current `@v4` tag) -- uses the latest v4 release but creates a diff in the already-pinned files.

**Chosen: Option 2 (pin to v4.3.1).** Rationale: the purpose of pinning is to lock to a known-good commit. Using the current release across all workflows brings them to a consistent state at the latest patch level. The diff in the two already-pinned files is a one-line SHA change each and creates a clean audit trail showing the update.

## Files Changed

### `.github/workflows/ci.yml`

- Line 14: `actions/checkout@v4` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
- Line 17: `oven-sh/setup-bun@v2` -> `oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2`

### `.github/workflows/deploy-docs.yml`

- Line 33: `actions/checkout@v4` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
- Line 36: `actions/setup-node@v4` -> `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0`
- Line 63: `actions/configure-pages@v4` -> `actions/configure-pages@1f0c5cde4bc74cd7e1254d0cb4de8d49e9068c7d # v4.0.0`
- Line 66: `actions/upload-pages-artifact@v3` -> `actions/upload-pages-artifact@56afc609e74202658d3ffba0e8f6dda462b719fa # v3.0.1`
- Line 72: `actions/deploy-pages@v4` -> `actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e # v4.0.5`

### `.github/workflows/claude-code-review.yml`

- Line 30: `actions/checkout@v4` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
- Line 36: `anthropics/claude-code-action@v1` -> `anthropics/claude-code-action@1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63`

### `.github/workflows/auto-release.yml` (discovered during deepen -- not in original issue)

- Line 17: `actions/checkout@v4` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`

### `.github/workflows/scheduled-competitive-analysis.yml` (existing pin update)

- Line 28: `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`

### `.github/workflows/review-reminder.yml` (existing pin update)

- Line 22: `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`

## Non-goals

- Upgrading actions to newer major versions (e.g., checkout v4 -> v6). That is a separate task with potential breaking changes.
- Adding Dependabot or Renovate for automated SHA updates. Worth considering separately but out of scope. **Note:** Dependabot does not create vulnerability alerts for SHA-pinned actions -- only for semantically-versioned ones. The trailing `# vX.Y.Z` comment enables Dependabot to propose version update PRs, but security advisories will not trigger alerts automatically.
- Adding a CI check or org-level policy that enforces pinned SHAs. GitHub supports this since August 2025. Could be a follow-up issue.
- Adding `timeout-minutes` to `claude-code-review.yml` (separate concern, separate issue).

## Acceptance Criteria

- [x] All `uses:` directives in all 7 workflow files reference commit SHAs, not mutable tags
- [x] Each pinned SHA has a trailing `# vX.Y.Z` comment for version traceability
- [x] All SHAs are verified to resolve to the expected version tag
- [ ] CI workflows still pass after the changes (checkout, build, test, deploy all functional)
- [x] No mutable tags (`@v1`, `@v2`, `@v3`, `@v4`) remain in any workflow file

## Test Scenarios

- Given all workflow files, when SHAs are substituted, then `grep -rE '@v[0-9]+' .github/workflows/` returns zero matches
- Given the updated `ci.yml`, when a PR is opened, then the CI job runs successfully with the pinned checkout and setup-bun actions
- Given the updated `deploy-docs.yml`, when pushed to main with a docs change, then the Pages deployment completes successfully
- Given the updated `claude-code-review.yml`, when a PR is opened, then the Claude review action runs successfully
- Given the updated `auto-release.yml`, when pushed to main with a plugin.json version change, then the release workflow runs successfully

## Context

### Workflow inventory (complete as of 2026-02-27)

| Workflow | Status Before | Actions Count |
|----------|--------------|---------------|
| `ci.yml` | **Unpinned** | 2 |
| `deploy-docs.yml` | **Unpinned** | 5 |
| `claude-code-review.yml` | **Unpinned** | 2 |
| `auto-release.yml` | **Unpinned** | 1 |
| `scheduled-competitive-analysis.yml` | Pinned (v4.2.2) | 2 |
| `review-reminder.yml` | Pinned (v4.2.2) | 1 |
| `cla.yml` | Pinned | 1 |

### Existing patterns (reference implementations)

- `.github/workflows/scheduled-competitive-analysis.yml:28` -- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`
- `.github/workflows/scheduled-competitive-analysis.yml:39` -- `anthropics/claude-code-action@1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63`
- `.github/workflows/review-reminder.yml:22` -- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`
- `.github/workflows/cla.yml:26` -- `contributor-assistant/github-action@ca4a40a7d1004f18d9960b404b97e5f30a505a08 # v2.6.1`

### Institutional knowledge

- Learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md` -- documents the SHA pinning pattern as pattern #1 of four GitHub Actions security patterns
- Constitution: `knowledge-base/overview/constitution.md` -- no explicit rule about SHA pinning, but the learning establishes it as a project convention

## References

- Issue: #343
- Learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- GitHub docs: [Using third-party actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)
- [GitHub Actions policy now supports SHA pinning enforcement (August 2025)](https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/)
- [StepSecurity: Pinning GitHub Actions for Enhanced Security](https://www.stepsecurity.io/blog/pinning-github-actions-for-enhanced-security-a-complete-guide)
- [Why you should pin actions by commit-hash](https://blog.rafaelgss.dev/why-you-should-pin-actions-by-commit-hash)
- tj-actions/changed-files compromise (March 2025) -- 23,000+ repositories affected by tag repointing attack
