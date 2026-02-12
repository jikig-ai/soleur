---
name: release-announce
description: This skill should be used when announcing a new plugin release to Discord and GitHub Releases. It parses CHANGELOG.md, generates an AI-powered summary, and posts to configured channels. Triggers on "announce release", "post release", "release announcement", "/release-announce".
---

# release-announce Skill

**Purpose:** Generate a release announcement from CHANGELOG.md and post it to Discord (webhook) and GitHub Releases (`gh release create`).

## Step 1: Read Version, Changelog, and Generate Summary

1. Read the current version from `plugins/soleur/.claude-plugin/plugin.json`:

   ```bash
   VERSION=$(cat plugins/soleur/.claude-plugin/plugin.json | grep '"version"' | sed 's/.*"version": "\(.*\)".*/\1/')
   echo "Version: $VERSION"
   ```

2. Extract the `## [$VERSION]` section from `plugins/soleur/CHANGELOG.md`. Parse from the `## [$VERSION]` heading to the next `## [` heading (exclusive). If no matching section exists, error with "Changelog section for v$VERSION not found" and stop.

3. Generate a detailed summary of the extracted changelog section:
   - Include all categories present (Added, Changed, Fixed, Removed)
   - Tone: enthusiastic but professional
   - This summary is used for both Discord (truncated) and GitHub Release (full)

## Step 2: Post to Discord

1. Check for the `DISCORD_WEBHOOK_URL` environment variable:

   ```bash
   echo "${DISCORD_WEBHOOK_URL:-(not set)}"
   ```

2. If `DISCORD_WEBHOOK_URL` is not set: warn "DISCORD_WEBHOOK_URL not set, skipping Discord" and continue to Step 3.

3. Build the Discord message. Truncate the summary to 1900 characters if needed, then format:

   ```text
   **Soleur vX.Y.Z released!**

   <summary, max 1900 chars>

   Full release notes: https://github.com/jikig-ai/soleur/releases/tag/vX.Y.Z
   ```

4. Post via curl:

   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     -H "Content-Type: application/json" \
     -d '{"content": "<message>"}' \
     "$DISCORD_WEBHOOK_URL"
   ```

5. If the HTTP response is not 2xx: warn with the status code and continue to Step 3.

## Step 3: Create GitHub Release

1. Check if a release for this version already exists:

   ```bash
   gh release view "v$VERSION" 2>/dev/null
   ```

2. If the release already exists: warn "Release v$VERSION already exists, skipping" and continue to results.

3. Create the release:

   ```bash
   gh release create "v$VERSION" --title "v$VERSION" --notes "<full summary>"
   ```

4. If the command fails: warn with the error message.

5. Report results:
   - Print status for each channel: posted / skipped / failed
   - Print the GitHub Release URL if created
