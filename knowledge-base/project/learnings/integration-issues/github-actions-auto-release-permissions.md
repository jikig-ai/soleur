---
title: GitHub Actions Auto-Release Workflow Permissions and Cascading Limitations
date: 2026-02-12
category: integration-issues
tags: [github-actions, ci, releases, discord, permissions, automation]
module: ci
symptoms:
  - GitHub Release not created after merge to main
  - Discord notification not posted after merge
  - HTTP 403 "Resource not accessible by integration" from gh release create
  - Manual /release-announce required as workaround
---

# GitHub Actions Auto-Release Workflow Permissions and Cascading Limitations

## Problem

v2.3.0 was merged to main without a GitHub Release or Discord notification. The release step was manual -- it depended on someone running `/release-announce` after merge (ship skill Phase 8). Nobody ran it, so nothing happened.

## Investigation

1. The `release-announce.yml` workflow triggers on `release: published`, not on push to main
2. No release existed for v2.3.0, so the workflow never fired
3. The `/ship` skill Phase 8 instructed users to run `/release-announce` manually -- error-prone

## Root Cause

Two issues:

1. **No automation for release creation.** The entire flow depended on a manual step after merge.
2. **GITHUB_TOKEN cannot cascade workflows.** When we added `auto-release.yml`, releases created by `GITHUB_TOKEN` do NOT trigger other workflows (GitHub security measure to prevent infinite loops). So even with automated release creation, `release-announce.yml` won't fire.

## Solution

Created `auto-release.yml` with two key design decisions:

1. **Trigger on push to main with path filter** for `plugins/soleur/.claude-plugin/plugin.json` -- only runs when version changes
2. **Handle both release creation AND Discord notification** in the same workflow, bypassing the cascade limitation

Required fix: explicit `permissions: contents: write` -- without it, `gh release create` fails with HTTP 403.

```yaml
permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      # ... read version, check idempotency, extract changelog ...
      - name: Create GitHub Release
        run: gh release create "$TAG" --notes-file /tmp/release-notes.md
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ steps.version.outputs.tag }}
      # Post to Discord directly (can't rely on release-announce.yml)
      - name: Post to Discord
        # ... same Discord webhook logic ...
```

## Key Insights

1. **GITHUB_TOKEN releases don't trigger other workflows.** This is a deliberate GitHub security measure. If workflow A creates a release and workflow B triggers on releases, B won't fire if A used `GITHUB_TOKEN`. Workaround: do everything in one workflow, or use a PAT.
2. **Always add explicit permissions.** Default `GITHUB_TOKEN` permissions vary by repository settings. Explicit `permissions: contents: write` ensures the workflow works regardless of repo defaults.
3. **Path filters on push events work with squash merges.** The squash commit includes all file changes from the PR, so `paths: ['plugins/soleur/.claude-plugin/plugin.json']` correctly matches.

## Prevention

- Automate post-merge steps in CI rather than relying on manual skill invocations
- When a workflow creates GitHub objects (releases, issues, deployments), handle downstream effects in the same workflow
- Always declare explicit permissions in workflow files

## Related

- [CI for notifications and infrastructure setup](../implementation-patterns/2026-02-12-ci-for-notifications-and-infrastructure-setup.md)
- [Ship integration pattern for post-merge steps](../2026-02-12-ship-integration-pattern-for-post-merge-steps.md)
