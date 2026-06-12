---
name: release-announce
description: "This skill should be used when announcing a new release. It parses CHANGELOG.md, generates a summary, and creates a GitHub Release. Manual releases do not trigger the CI Slack notification."
---

# release-announce Skill

> **Manual fallback only.** The `version-bump-and-release.yml` GitHub Action now handles version bumping and GitHub Release creation automatically at merge time. This skill is only needed if the Action fails or for manual re-announcements of existing versions.

**Purpose:** Generate a release announcement from CHANGELOG.md and create a GitHub Release. The Slack notification is an inline step inside `reusable-release.yml` and fires only on CI-driven releases — GITHUB_TOKEN-created releases don't emit `release: published` events, so no separate workflow can (or does) trigger on publish. A release created manually via this skill therefore gets NO automatic Slack notification.

## Step 1: Read Version and Changelog

1. Read the current version from `plugins/soleur/.claude-plugin/plugin.json`:

   Read `plugins/soleur/.claude-plugin/plugin.json` and extract the `version` field value.

2. Extract the `## [<version>]` section from `plugins/soleur/CHANGELOG.md`. Parse from the `## [<version>]` heading to the next `## [` heading (exclusive). If no matching section exists, error with "Changelog section for v<version> not found" and stop. Replace `<version>` with the actual version from step 1.

3. Generate a detailed summary of the extracted changelog section:
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
