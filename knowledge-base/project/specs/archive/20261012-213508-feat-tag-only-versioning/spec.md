# Tag-Only Versioning

**Issue:** #410
**Branch:** feat-tag-only-versioning
**Brainstorm:** [2026-03-03-tag-only-versioning-brainstorm.md](../../brainstorms/2026-03-03-tag-only-versioning-brainstorm.md)

## Problem Statement

The `version-bump-and-release.yml` workflow fails to push version bump commits to main because `github-actions[bot]` is blocked by the CLA Required repository ruleset. Rather than adding bypass mechanisms, we eliminate the push-to-main requirement entirely by deriving version from git tags.

## Goals

- G1: CI workflow creates GitHub Releases (with tags) without pushing commits to main
- G2: Docs site displays accurate version and changelog from GitHub Releases API
- G3: Component counts are computed at docs build time, not maintained in committed files
- G4: No new infrastructure (no GitHub Apps, no PATs, no new secrets)

## Non-Goals

- NG1: Changing the PR workflow (authors still write `## Changelog` in PR body)
- NG2: Changing how semver labels work (`/ship` still sets `semver:*` labels)
- NG3: Enabling merge queues (separate future improvement)
- NG4: Changing the CLA Required ruleset configuration

## Functional Requirements

- FR1: `version-bump-and-release.yml` creates a GitHub Release with tag `vX.Y.Z` and release notes extracted from the merged PR's `## Changelog` section
- FR2: The workflow does NOT commit or push to main
- FR3: `changelog.js` fetches release data from the GitHub API at Eleventy build time and renders it as HTML
- FR4: `plugin.js` derives the current version from the latest GitHub Release tag
- FR5: README.md displays a dynamic version badge via shields.io
- FR6: `CHANGELOG.md` is deleted from the repository
- FR7: `plugin.json` version field is set to a static sentinel value
- FR8: `bug_report.yml` removes the version placeholder or links to latest release

## Technical Requirements

- TR1: GitHub API calls at build time must handle rate limits gracefully (fallback to empty/cached data)
- TR2: Component counts (agents, skills, commands, MCP servers) are computed from filesystem at build time
- TR3: The workflow retains the concurrency group (`version-bump`) and idempotency check (tag-exists guard)
- TR4: Discord notification and docs deploy trigger remain unchanged
- TR5: The `workflow_dispatch` escape hatch remains functional for manual releases
