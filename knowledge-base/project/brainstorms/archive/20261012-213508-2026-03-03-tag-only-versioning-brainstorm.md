# Tag-Only Versioning

**Date:** 2026-03-03
**Status:** Decided
**Issue:** #410

## What We're Building

Migrate from CI-committed version files to tag-only versioning. The version-bump-and-release workflow currently computes the version, updates 6 files, commits, and pushes to main. This push fails because the CLA Required ruleset blocks `github-actions[bot]`. Instead of fixing the bypass, we eliminate the push entirely.

**After this change:**

- Version is derived from git tags / GitHub Releases, not committed files
- CI never pushes commits to main
- The docs site computes version and component counts at build time
- `CHANGELOG.md` is deleted; GitHub Releases is the changelog source of truth

## Why This Approach

### Options Explored

| Option | Verdict | Reason |
|--------|---------|--------|
| Create a GitHub App for CI bypass | Rejected | Adds infrastructure for a problem we can eliminate architecturally |
| Use a PAT | Rejected | Security liability, tied to human account, rotation burden |
| Disable CLA ruleset | Rejected | Removes legal compliance control |
| Use existing bypass app (`actions/create-github-app-token`) | Rejected | No access to private keys for either bypass integration (Claude app, unknown app) |
| Migrate to `claude-code-action` | Rejected | Adds AI API dependency to a deterministic mechanical task |
| Enable merge queues + pre-merge bump | Rejected | Merge group branches are immutable; pre-queue bump reintroduces version serialization conflicts |
| Tag-only versioning | **Selected** | Eliminates push-to-main entirely, architecturally cleaner |

### Why Not Just Fix the Bypass?

The push-to-main pattern is the root problem, not the CLA ruleset. Any bypass fix (GitHub App, PAT) treats the symptom. Tag-only versioning:

- Eliminates the need for CI to write to main at all
- Removes 6 files from version drift risk
- Simplifies the release workflow (fewer steps, no commit/push)
- Aligns with common OSS patterns (version from tags, not files)

### CTO Assessment

The CTO assessment confirmed that `github-actions[bot]` cannot be added as a ruleset bypass actor (it's a platform builtin, not an installed app). The assessment rated the GitHub App approach as the pragmatic fix but agreed that eliminating the push-to-main requirement is architecturally superior.

## Key Decisions

1. **Version source of truth: git tags via GitHub Releases API.** The `gh release create vX.Y.Z` command creates both the tag and release via API -- it does NOT push to `refs/heads/main`. The CLA ruleset only protects `refs/heads/main`.

2. **Delete CHANGELOG.md entirely.** GitHub Releases is the changelog source of truth. PR authors already write `## Changelog` in PR bodies; this content goes into release notes. The docs site will render changelog from the GitHub Releases API.

3. **Compute component counts at docs build time.** Agent/skill/command counts are derived from the filesystem during Eleventy build, not maintained in committed files.

4. **README badge becomes dynamic.** Replace the static `version-X.Y.Z-blue` badge with a shields.io badge that reads from the GitHub Releases API.

5. **plugin.json version field becomes static.** Set to `"0.0.0-dev"` or similar sentinel. Claude Code does not use this field for runtime behavior.

## Scope of Changes

### Workflow (`version-bump-and-release.yml`)

- Remove: "Update version files" step
- Remove: "Verify version consistency" step
- Remove: "Commit and push" step
- Keep: version computation, GitHub Release creation, Discord notification, docs deploy trigger

### Files to Delete

- `plugins/soleur/CHANGELOG.md`

### Files to Modify

- `plugins/soleur/docs/_data/changelog.js` -- rewrite to fetch from GitHub Releases API
- `plugins/soleur/docs/_data/plugin.js` -- add version derivation from latest release tag
- `plugins/soleur/.claude-plugin/plugin.json` -- freeze version to sentinel value
- `.claude-plugin/marketplace.json` -- freeze version or derive at build time
- `README.md` -- dynamic shields.io badge
- `.github/ISSUE_TEMPLATE/bug_report.yml` -- remove version placeholder
- `plugins/soleur/README.md` -- freeze counts (docs computes them)
- `plugins/soleur/AGENTS.md` -- update "Versioning Requirements" section

### Docs Site Changes

- `changelog.js`: Fetch releases from `https://api.github.com/repos/jikig-ai/soleur/releases` at build time
- `plugin.js`: Derive version from latest release tag
- Add build-time component count computation

## Open Questions

1. **GitHub API rate limits at docs build time.** Unauthenticated GitHub API allows 60 requests/hour. Docs builds are infrequent, but we should consider caching or using a `GITHUB_TOKEN` in the build environment.

2. **Does Claude Code require the `version` field in `plugin.json`?** If it does, we set it to `"0.0.0-dev"`. If not, we can remove it entirely.

3. **Existing learnings that reference the old workflow.** Several files in `knowledge-base/project/learnings/` reference the 6-file version bump pattern. These should be updated or archived.
