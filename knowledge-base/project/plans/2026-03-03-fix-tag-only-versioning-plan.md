---
title: "fix: tag-only versioning"
type: fix
date: 2026-03-03
semver: patch
---

# Tag-Only Versioning Implementation Plan

**Issue:** #410
**Spec:** [spec.md](../specs/feat-tag-only-versioning/spec.md)
**Brainstorm:** [2026-03-03-tag-only-versioning-brainstorm.md](../brainstorms/2026-03-03-tag-only-versioning-brainstorm.md)
**Branch:** feat-tag-only-versioning
**PR:** #412

## Overview

Migrate from CI-committed version files to tag-only versioning. The release workflow will create GitHub Releases (with tags) via API — no push to `refs/heads/main`, bypassing the CLA Required ruleset.

**Version baseline:** Latest release tag is `v3.9.0` (created 2026-03-03), matching `plugin.json`. No version regression risk.

## Non-Goals

- Changing the PR workflow (authors still write `## Changelog` in PR body)
- Changing how semver labels work (`/ship` still sets `semver:*` labels)
- Enabling merge queues (separate future improvement)
- Paginating the full release history in the docs changelog (show recent 30, link to GitHub for older)

## Phase 1: Simplify release workflow and delete CHANGELOG.md

**Goal:** Remove all commit/push logic. Keep version computation, release creation, Discord, and docs deploy. Delete the committed changelog.

### File: `.github/workflows/version-bump-and-release.yml`

1. **Change version computation** (lines 130-148): Instead of reading `plugin.json`, derive the current version from the latest release using `gh release view`:
   ```bash
   CURRENT=$(gh release view --json tagName --jq '.tagName // "v0.0.0"' | sed 's/^v//')
   ```
   **Why `gh release view` not `gh release list`:** `gh release list` sorts by creation date, not semver. If someone manually creates a hotfix release `v3.8.5` after `v3.9.0`, `gh release list --limit 1` returns the hotfix. `gh release view` (no tag arg) returns GitHub's designated "latest" release, which respects semver ordering.

2. **Delete steps:** "Configure git" (lines 34-37), "Compute component counts" (lines 198-211), "Update version files" (lines 213-257), "Verify version consistency" (lines 258-292), "Commit and push" (lines 294-308).

3. **Remove explicit docs deploy trigger** (lines 356-362): The `workflow_run` trigger in `deploy-docs.yml` already fires when this workflow completes — the explicit `gh workflow run` dispatch is redundant and causes double deploys (the concurrency group serializes them but wastes a runner).

4. **Keep `fetch-depth: 2`** for the `git diff HEAD~1` plugin-change check.

5. **Keep unchanged:** "Check if plugin files changed", "Find merged PR", "Determine bump type", "Check idempotency", "Extract changelog from PR body", "Create GitHub Release", "Post to Discord".

### File: `plugins/soleur/CHANGELOG.md`

`git rm plugins/soleur/CHANGELOG.md` — GitHub Releases is the changelog source of truth.

### File: `.github/workflows/deploy-docs.yml`

- Remove `'plugins/soleur/CHANGELOG.md'` from `paths:` trigger (file deleted)
- Remove `'plugins/soleur/.claude-plugin/plugin.json'` from `paths:` trigger (now static)
- Add `GITHUB_TOKEN` env var to the Eleventy build step:
  ```yaml
  - name: Build docs
    run: npx @11ty/eleventy
    env:
      GITHUB_TOKEN: ${{ github.token }}
  ```

### Resulting workflow structure:
```
checkout → check_plugin → find_pr → bump_type → compute_version → idempotency → extract_changelog → create_release → discord
```

## Phase 2: Rewrite docs data files

**Goal:** Docs site derives version and changelog from GitHub Releases API at build time.

### File: `plugins/soleur/docs/_data/github.js` (NEW — replaces separate changelog.js and plugin.js API calls)

Single shared data file that fetches the releases list once:
- Fetch `GET /repos/jikig-ai/soleur/releases?per_page=30`
- Use `GITHUB_TOKEN` if available (1000 req/hr in CI vs 60 unauthenticated)
- **In CI** (`process.env.CI`): throw on non-200 response — a blank changelog is a broken build
- **In local dev**: warn and return empty data
- Filter out draft releases
- Return `{ version, changelog: { html } }` — version from `releases[0].tag_name`, changelog rendered via markdown-it

### File: `plugins/soleur/docs/_data/changelog.js`

Rewrite to delegate to `github.js`:
```javascript
import github from "./github.js";
export default async function () {
  const data = await github();
  return data.changelog;
}
```

### File: `plugins/soleur/docs/_data/plugin.js`

Read `plugin.json` for all fields, overlay version from `github.js`:
```javascript
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import github from "./github.js";

export default async function () {
  const plugin = JSON.parse(readFileSync(resolve("plugins/soleur/.claude-plugin/plugin.json"), "utf-8"));
  const data = await github();
  if (data.version) plugin.version = data.version;
  return plugin;
}
```

### File: `plugins/soleur/docs/_data/stats.js`

**No changes.** Already computes counts from filesystem at build time.

### File: `plugins/soleur/docs/pages/changelog.njk`

Add a "View all releases on GitHub" link at the bottom of the changelog page.

## Phase 3: Update static files and documentation

### File: `plugins/soleur/.claude-plugin/plugin.json`

- Set `"version": "0.0.0-dev"` (sentinel — never updated by CI)
- Remove hardcoded counts from `"description"`:
  ```
  "A full AI organization across engineering, finance, marketing, legal, operations, product, sales, and support that compounds your company knowledge over time."
  ```

### File: `.claude-plugin/marketplace.json`

- Set `"version": "0.0.0-dev"` for `plugins[0].version` (the top-level `"version": "1.0.0"` is the manifest format version — leave it)

### File: `README.md`

- Replace static version badge with dynamic shields.io:
  ```
  [![Version](https://img.shields.io/github/v/release/jikig-ai/soleur)](https://github.com/jikig-ai/soleur/releases)
  ```

### File: `plugins/soleur/AGENTS.md`

Rewrite "Versioning Requirements" and "Pre-Commit Checklist" sections:
- Version derived from git tags / GitHub Releases (no committed version files)
- CI creates `vX.Y.Z` tags via `gh release create` (no push to main)
- PR authors still write `## Changelog` in PR body
- `/ship` still sets `semver:*` labels
- Do NOT edit: `plugin.json` version field (sentinel, intentionally frozen)

### File: `AGENTS.md`

Update "Workflow Gates" bullet about version bumping to reflect tag-only approach.

### File: `knowledge-base/overview/constitution.md`

Update references to "6 files at merge time" pattern (lines 65, 68, 165).

### Learnings files to delete (obsolete):

1. `knowledge-base/learnings/plugin-versioning-requirements.md`
2. `knowledge-base/learnings/2026-02-13-version-bump-cascades-to-html-badges.md`
3. `knowledge-base/learnings/2026-02-26-version-bump-after-compound-ordering.md`

### Learnings file to rewrite:

4. `knowledge-base/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md` — Update to describe tag-only approach

### Pre-existing issue to file:

- Discord webhook payload missing `username` and `avatar_url` fields (constitution violation, unrelated to this PR)

## Test Scenarios

**Given** a PR with `semver:minor` label merges to main with plugin file changes,
**When** `version-bump-and-release.yml` runs,
**Then** a GitHub Release `v3.10.0` is created with release notes from the PR's `## Changelog` section, and no commit is pushed to main.

**Given** `workflow_dispatch` is triggered with `bump_type: patch`,
**When** the latest release tag is `v3.10.0`,
**Then** a release `v3.10.1` is created with title "Manual version bump".

**Given** two PRs merge within seconds,
**When** both trigger the release workflow,
**Then** the concurrency group queues the second run, and the second run reads the first run's release tag to compute the correct next version.

**Given** the GitHub API is unreachable during a CI docs build,
**When** `npx @11ty/eleventy` runs,
**Then** the build fails (non-zero exit) rather than silently shipping a blank changelog.

**Given** a developer runs `npx @11ty/eleventy` locally without internet,
**When** the GitHub API call fails,
**Then** the build succeeds with an empty changelog and sentinel version, with a console warning.

**Given** `gh release view` returns no releases (empty repo),
**When** the release workflow runs,
**Then** the version defaults to `0.0.0` and increments from there.

## Rollback Plan

If the migration causes release failures:

1. Revert the PR (single squash commit — clean revert)
2. Restore `CHANGELOG.md` from git history: `git checkout HEAD~1 -- plugins/soleur/CHANGELOG.md`
3. Set `plugin.json` version back to the latest tag value
4. The next merge to main triggers the old workflow, which will attempt the commit/push (and fail due to CLA — but that is the pre-existing state)

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| GitHub API rate limit in CI | Authenticated token (1000/hr), hard fail in CI on API error |
| Local dev without internet | Graceful fallback to empty data with console warning |
| Version regression after migration | Confirmed: latest tag `v3.9.0` matches `plugin.json` |
| `plugin.json` sentinel confuses contributors | Description field explains plugin, AGENTS.md documents sentinel |
| Concurrent merge race | Idempotency guard + concurrency group; queued run reads first run's tag |
| `gh release create` failure | `workflow_dispatch` escape hatch for manual recovery |

## Verification Checklist

- [ ] `workflow_dispatch` with `patch` creates a new release with correct version
- [ ] Docs site builds locally with `npx @11ty/eleventy`
- [ ] Changelog page shows releases from GitHub API
- [ ] Homepage JSON-LD has correct `softwareVersion`
- [ ] shields.io badge resolves to latest release
- [ ] Discord notification fires on release
- [ ] Build fails in CI when GitHub API is mocked as unreachable
