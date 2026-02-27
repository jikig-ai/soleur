---
title: "security: Pin mutable GitHub Actions tags to commit SHAs"
type: fix
date: 2026-02-27
issue: "#343"
version_bump: PATCH
---

# security: Pin mutable GitHub Actions tags to commit SHAs

## Overview

Three GitHub Actions workflows use mutable version tags (`@v4`, `@v2`, `@v1`) instead of pinned commit SHAs. This is a supply-chain security risk -- the action publisher can silently redirect the tag to a different commit. Two other workflows (`scheduled-competitive-analysis.yml`, `review-reminder.yml`) already follow the correct pinning pattern.

## Problem Statement

Mutable tags in GitHub Actions are a supply-chain attack vector. An upstream action publisher (or attacker who compromises their account) can force-push the tag to a malicious commit. Pinning to a commit SHA makes the action immutable -- any change requires an explicit update in the workflow file, which appears in a pull request diff.

Evidence that the risk is real: `actions/checkout@v4` currently resolves to commit `34e114876b...` (v4.3.1), but the SHAs pinned in `review-reminder.yml` reference `11bd71901b...` (v4.2.2). The tag has already moved since those pins were set.

The `claude-code-review.yml` workflow is particularly high-risk: `anthropics/claude-code-action@v1` runs with `id-token: write` and `pull-requests: write` permissions -- a compromised action could exfiltrate secrets or modify PR content.

## Proposed Solution

Replace all mutable tags with pinned commit SHAs using the format:

```yaml
uses: <org>/<action>@<full-sha> # <version-tag>
```

The trailing comment preserves version traceability for future updates.

### SHA Mapping (current as of 2026-02-27)

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

### `.github/workflows/scheduled-competitive-analysis.yml` (existing pin update)

- Line 28: `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`

### `.github/workflows/review-reminder.yml` (existing pin update)

- Line 22: `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` -> `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`

## Non-goals

- Upgrading actions to newer major versions (e.g., checkout v4 -> v6). That is a separate task with potential breaking changes.
- Adding Dependabot or Renovate for automated SHA updates. Worth considering separately but out of scope.
- Adding a CI check that enforces pinned SHAs. Could be a follow-up issue.

## Acceptance Criteria

- [ ] All `uses:` directives in all 5 workflow files reference commit SHAs, not mutable tags
- [ ] Each pinned SHA has a trailing `# vX.Y.Z` comment for version traceability
- [ ] All SHAs are verified to resolve to the expected version tag
- [ ] CI workflows still pass after the changes (checkout, build, test, deploy all functional)
- [ ] No mutable tags (`@v1`, `@v2`, `@v3`, `@v4`) remain in any workflow file

## Test Scenarios

- Given the three unpinned workflow files, when SHAs are substituted, then `grep -rE '@v[0-9]+' .github/workflows/` returns zero matches
- Given the updated `ci.yml`, when a PR is opened, then the CI job runs successfully with the pinned checkout and setup-bun actions
- Given the updated `deploy-docs.yml`, when pushed to main with a docs change, then the Pages deployment completes successfully
- Given the updated `claude-code-review.yml`, when a PR is opened, then the Claude review action runs successfully

## Context

### Existing patterns (reference implementations)

- `.github/workflows/scheduled-competitive-analysis.yml:28` -- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`
- `.github/workflows/scheduled-competitive-analysis.yml:39` -- `anthropics/claude-code-action@1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63`
- `.github/workflows/review-reminder.yml:22` -- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`

### Institutional knowledge

- Learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md` -- documents the SHA pinning pattern as pattern #1 of four GitHub Actions security patterns
- Constitution: `knowledge-base/overview/constitution.md` -- no explicit rule about SHA pinning, but the learning establishes it as a project convention

## References

- Issue: #343
- Learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- GitHub docs: [Using third-party actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)
