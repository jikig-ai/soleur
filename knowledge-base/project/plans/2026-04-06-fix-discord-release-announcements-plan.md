---
title: "fix: restore Discord release announcements removed by #1420 migration"
type: fix
date: 2026-04-06
---

# fix: restore Discord release announcements removed by #1420 migration

PR #1578 (resolving #1420) migrated all GitHub Actions workflow notifications from Discord to email via the `notify-ops-email` composite action. The migration correctly moved ops alerts (drift detection, CI failures, scheduled workflow failures) to email, but incorrectly removed the Discord release announcement step from `reusable-release.yml`. Release announcements are community content -- they belong in the Discord #releases channel, not just in ops email.

## Root Cause

In commit `f14469e3`, the "Post to Discord" step in `.github/workflows/reusable-release.yml` (lines 313-346) was replaced wholesale with the `notify-ops-email` action. The original step posted to `DISCORD_RELEASES_WEBHOOK_URL` (falling back to `DISCORD_WEBHOOK_URL`) with release notes, a branded Sol avatar, and a link to the GitHub release.

The AGENTS.md rule says: "Discord channels are for community content only." Release announcements are community content -- the rule was meant to prevent ops alerts from leaking to community channels, not to remove community-facing content from Discord.

## Evidence

- **Deleted code:** `git diff f14469e3^..f14469e3 -- .github/workflows/reusable-release.yml` shows the full Discord step removed
- **Secrets still exist:** `DISCORD_RELEASES_WEBHOOK_URL` and `DISCORD_WEBHOOK_URL` are both configured as GitHub repo secrets
- **Stale references:** Multiple files still reference Discord release notifications as if they work:
  - `plugins/soleur/skills/release-announce/SKILL.md` line 3: "Discord notification is handled automatically by CI on release publish"
  - `plugins/soleur/skills/release-announce/SKILL.md` line 47: "Discord notification will be posted automatically by CI"
  - `plugins/soleur/skills/ship/SKILL.md` line 590: "posts to Discord"
  - `plugins/soleur/AGENTS.md` line 11: "creates a GitHub Release, and posts to Discord"

## Acceptance Criteria

- [ ] `reusable-release.yml` posts release announcements to Discord `DISCORD_RELEASES_WEBHOOK_URL` (with fallback to `DISCORD_WEBHOOK_URL`) when a release is created
- [ ] `reusable-release.yml` retains the existing email notification step (both email AND Discord for releases)
- [ ] Discord message includes: component name, version, release notes (truncated to 1900 chars), release URL, Sol bot identity (username + avatar)
- [ ] Discord step uses `continue-on-error: true` (non-blocking -- a Discord failure should not fail the release)
- [ ] Discord step uses `allowed_mentions: {parse: []}` to prevent accidental @everyone/@here pings
- [ ] `release-announce/SKILL.md` description remains accurate (it already says Discord is handled by CI -- this will be true again after the fix)
- [ ] No other stale references remain in skill/agent files

## Implementation

### Phase 1: Restore Discord step in `reusable-release.yml`

Add a "Post to Discord" step **after** the existing "Email notification (release)" step. Restore the original logic from before commit `f14469e3` with the same structure:

**File:** `.github/workflows/reusable-release.yml`

After the email notification step (line 320), add:

```yaml
      - name: Post to Discord (release)
        if: steps.create_release.outputs.released == 'true'
        continue-on-error: true
        env:
          DISCORD_RELEASES_WEBHOOK_URL: ${{ secrets.DISCORD_RELEASES_WEBHOOK_URL }}
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
          TAG: ${{ steps.version.outputs.tag }}
          VERSION: ${{ steps.version.outputs.next }}
          COMPONENT_DISPLAY: ${{ inputs.component_display }}
          RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}
        run: |
          WEBHOOK="${DISCORD_RELEASES_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"
          if [ -z "$WEBHOOK" ]; then
            echo "No Discord webhook URL configured, skipping"
            exit 0
          fi

          BODY=$(cat "$RELEASE_NOTES_FILE")
          REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
          RELEASE_URL="${REPO_URL}/releases/tag/${TAG}"

          if [ ${#BODY} -gt 1900 ]; then
            BODY="${BODY:0:1897}..."
          fi

          MESSAGE=$(printf '**%s v%s released!**\n\n%s\n\nFull release notes: %s' \
            "$COMPONENT_DISPLAY" "$VERSION" "$BODY" "$RELEASE_URL")

          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "$WEBHOOK")

          if [[ "$HTTP_CODE" =~ ^2 ]]; then
            echo "Discord notification sent (HTTP $HTTP_CODE)"
          else
            echo "::warning::Discord notification failed (HTTP $HTTP_CODE)"
          fi
```

### Phase 2: Update AGENTS.md rule clarification

The AGENTS.md rule "Discord channels are for community content only" is correct but was misapplied during the #1420 sweep. Add a parenthetical clarification to prevent future regressions:

**File:** `AGENTS.md`

In the notification rule, add a parenthetical after "Discord channels are for community content only":

> Discord channels are for community content only (release announcements, blog posts, community updates -- NOT ops alerts like CI failures, drift detection, or workflow errors).

### Phase 3: Fix stale documentation references

No file changes needed -- the references in `release-announce/SKILL.md`, `ship/SKILL.md`, and `plugins/soleur/AGENTS.md` all say Discord notifications happen automatically via CI. After Phase 1, these statements will be true again.

## Test Scenarios

- Given `DISCORD_RELEASES_WEBHOOK_URL` is set, when a release is created via `reusable-release.yml`, then a Discord message is posted to the releases webhook AND an email is sent via Resend
- Given `DISCORD_RELEASES_WEBHOOK_URL` is NOT set but `DISCORD_WEBHOOK_URL` is set, when a release is created, then the Discord message falls back to the default webhook
- Given neither Discord webhook is set, when a release is created, then the Discord step is skipped with a log message (not a failure)
- Given the Discord webhook returns a non-2xx status, when a release is created, then a warning annotation is logged but the workflow succeeds (continue-on-error)
- Given the release notes exceed 1900 characters, when posted to Discord, then the body is truncated to 1897 chars with "..." appended

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/reusable-release.yml` | Add Discord post step after email notification |
| `AGENTS.md` | Clarify Discord rule with examples of community vs ops content |

## Related Issues

- #1420 -- Original issue that triggered the Discord-to-email migration
- #1578 -- PR that implemented the migration (introduced this regression)
- #1595 -- Separate issue for disk-monitor Discord-to-email migration (not affected by this fix)

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Create a separate `release-announce.yml` workflow triggered on `release: published` | Rejected | GITHUB_TOKEN-created releases don't trigger the release event for other workflows -- this was the original reason `auto-release.yml` had the Discord step inline |
| Use a GitHub Actions marketplace action for Discord | Rejected | The inline curl approach is simpler, has no supply-chain risk, and matches the pattern that worked before |
| Only send email, skip Discord entirely | Rejected | Release announcements are community content and Discord is where the community is |
