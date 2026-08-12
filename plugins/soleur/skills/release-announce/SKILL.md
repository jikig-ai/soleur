---
name: release-announce
description: "This skill should be used when announcing a new release. It parses CHANGELOG.md, generates a summary, and creates a GitHub Release. Manual releases do not trigger the CI Slack notification."
---

# release-announce Skill

> **Manual fallback only.** The `version-bump-and-release.yml` GitHub Action now handles version bumping and GitHub Release creation automatically at merge time. This skill is only needed if the Action fails or for manual re-announcements of existing versions.

**Purpose:** Generate a release announcement from CHANGELOG.md and create a GitHub Release. The Slack notification is an inline step inside `reusable-release.yml` and fires only on CI-driven releases — GITHUB_TOKEN-created releases don't emit `release: published` events, so no separate workflow can (or does) trigger on publish. A release created manually via this skill therefore gets NO automatic Slack notification.

## Step 1: Read Version and Changelog

1. Determine the version to announce. **Do not read it from `plugins/soleur/.claude-plugin/plugin.json` — that manifest carries no `version` key**, deliberately (a `version` key suppresses `gitCommitSha` tracking and breaks update delivery, #7471). Release versions live in git tags:

   ```bash
   # The version already released (latest tag), for the already-exists check in Step 2
   gh release list --limit 1 --json tagName --jq '.[0].tagName'   # → vX.Y.Z
   git describe --tags --abbrev=0                                  # offline equivalent
   ```

   If the operator named a version, use that. Otherwise announce the version the operator is releasing now — this skill is the fallback for when `version-bump-and-release.yml` did not create the release, so the tag may not exist yet. Confirm the version with the operator before creating anything; never infer it from a manifest.

2. Assemble the release body from the merged PRs since the previous tag — the CI path uses each PR body's `## Changelog` section, and this fallback must produce the same thing:

   ```bash
   gh pr list --state merged -L 200 --search "merged:>=<previous-tag-date>" --json number,title,body
   ```

   **Note:** earlier revisions of this step read `plugins/soleur/CHANGELOG.md`. That file does not exist in this repository — GitHub Releases are the changelog (`plugins/soleur/docs/_data/github.js` renders the docs changelog straight from the Releases API). Do not error out looking for it.

3. Generate a detailed summary of the collected changelog entries:
   - Include all categories present (Added, Changed, Fixed, Removed)
   - Tone: enthusiastic but professional
   - This summary is used as the GitHub Release body

## Step 2: Create GitHub Release

1. Check if a release for this version already exists:

   ```bash
   gh release view "v<version>" 2>/dev/null
   ```

   Replace `<version>` with the actual version number (e.g., `2.32.1`).

2. If the release already exists: warn "Release v<version> already exists, skipping" and stop.

3. Create the release:

   ```bash
   gh release create "v<version>" --title "v<version>" --notes "<full summary>"
   ```

4. If the command fails: warn with the error message.

5. Report results:
   - Print the GitHub Release URL if created
   - Note that manually created releases do NOT trigger the CI Slack notification (it is an inline step in `reusable-release.yml`, secret `SLACK_RELEASES_WEBHOOK_URL`). If the announcement matters, post the release link to the Slack release channel manually. Slack does not render GitHub-flavored Markdown — for parity with the CI path, run the changelog body through the shared converter first: `node scripts/md-to-mrkdwn.mjs --max 3000 < notes.md` (see the Slack mrkdwn formatting section in `plugins/soleur/skills/ship/references/ci-workflow-authoring.md`).
