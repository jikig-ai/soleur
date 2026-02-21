---
name: release-announce
description: This skill should be used when announcing a new release. It parses CHANGELOG.md, generates a summary, and creates a GitHub Release. Discord notification is handled automatically by CI on release publish. Triggers on "announce release", "post release", "release announcement", "/release-announce".
---

# release-announce Skill

**Purpose:** Generate a release announcement from CHANGELOG.md and create a GitHub Release. Discord notification is handled by the `release-announce` GitHub Actions workflow, triggered automatically when the release is published.

## Step 1: Read Version and Changelog

1. Read the current version from `plugins/soleur/.claude-plugin/plugin.json`:

   ```bash
   VERSION=$(cat plugins/soleur/.claude-plugin/plugin.json | grep '"version"' | sed 's/.*"version": "\(.*\)".*/\1/')
   echo "Version: $VERSION"
   ```

2. Extract the `## [$VERSION]` section from `plugins/soleur/CHANGELOG.md`. Parse from the `## [$VERSION]` heading to the next `## [` heading (exclusive). If no matching section exists, error with "Changelog section for v$VERSION not found" and stop.

3. Generate a detailed summary of the extracted changelog section:
   - Include all categories present (Added, Changed, Fixed, Removed)
   - Tone: enthusiastic but professional
   - This summary is used as the GitHub Release body

## Step 2: Create GitHub Release

1. Check if a release for this version already exists:

   ```bash
   gh release view "v$VERSION" 2>/dev/null
   ```

2. If the release already exists: warn "Release v$VERSION already exists, skipping" and stop.

3. Create the release:

   ```bash
   gh release create "v$VERSION" --title "v$VERSION" --notes "<full summary>"
   ```

4. If the command fails: warn with the error message.

5. Report results:
   - Print the GitHub Release URL if created
   - Note that Discord notification will be posted automatically by CI (requires `DISCORD_WEBHOOK_URL` repository secret)
