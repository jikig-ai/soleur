---
title: "fix: restore Discord release announcements removed by #1420 migration"
type: fix
date: 2026-04-06
---

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 5
**Research sources:** 4 institutional learnings, git history analysis, workflow YAML review, Discord API patterns

### Key Improvements

1. Added verification that `tmpfiles` temp file is available when the Discord step runs (dependency chain confirmed)
2. Confirmed avatar URL accessibility and raw.githubusercontent.com caching behavior (300s max-age)
3. Grounded `allowed_mentions` pattern in institutional learning from 2026-03-05 security audit
4. Added edge case for Discord webhook token rotation and secret validation
5. Confirmed all stale references will self-heal after Phase 1 (no documentation changes needed)

### Learnings Applied

- `2026-02-12-ci-for-notifications-and-infrastructure-setup.md`: Secrets check must be inside step script, not job-level `if`
- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`: `allowed_mentions: {parse: []}` is mandatory for untrusted content
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md`: Webhook payloads must include explicit `username` and `avatar_url` -- webhook defaults are unreliable
- `github-actions-audit-methodology.md`: Confirmed the `release-announce.yml` -> `auto-release.yml` -> `version-bump-and-release.yml` lineage

# fix: restore Discord release announcements removed by #1420 migration

PR #1578 (resolving #1420) migrated all GitHub Actions workflow notifications from Discord to email via the `notify-ops-email` composite action. The migration correctly moved ops alerts (drift detection, CI failures, scheduled workflow failures) to email, but incorrectly removed the Discord release announcement step from `reusable-release.yml`. Release announcements are community content -- they belong in the Discord #releases channel, not just in ops email.

## Root Cause

In commit `f14469e3`, the "Post to Discord" step in `.github/workflows/reusable-release.yml` (lines 313-346) was replaced wholesale with the `notify-ops-email` action. The original step posted to `DISCORD_RELEASES_WEBHOOK_URL` (falling back to `DISCORD_WEBHOOK_URL`) with release notes, a branded Sol avatar, and a link to the GitHub release.

The AGENTS.md rule says: "Discord channels are for community content only." Release announcements are community content -- the rule was meant to prevent ops alerts from leaking to community channels, not to remove community-facing content from Discord.

### Research Insights

**Workflow lineage:** The Discord release posting has migrated through three workflow generations:

1. `release-announce.yml` (deleted in `167ee418`, Feb 21) -- standalone workflow on `release: published`
2. `auto-release.yml` (deleted in `0d34f143`, Mar 3) -- inline Discord step because GITHUB_TOKEN releases don't trigger `release:` events
3. `reusable-release.yml` (current) -- inherited the inline Discord step from `auto-release.yml`, then lost it in `f14469e3` (Apr 6)

The reason the Discord step must be inline (not a separate workflow) is architectural: GitHub Actions does not fire `release: published` events for releases created by `GITHUB_TOKEN`. This was documented in `release-announce.yml`'s own comments before it was deleted. The alternative approach table in this plan captures this constraint.

**Timing confirmation:** The `tmpfiles` step (line 99) creates a temp file path; the `changelog` step (line 235) populates it. Both have `if: steps.check_changed.outputs.changed == 'true'`. Since `create_release.outputs.released == 'true'` is a strict subset of that condition, the `RELEASE_NOTES_FILE` is guaranteed to exist when the Discord step evaluates.

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

Add a "Post to Discord" step **after** the existing "Email notification (release)" step (line 320). Restore the original logic from before commit `f14469e3` with the same structure.

**File:** `.github/workflows/reusable-release.yml`

**Insertion point:** After line 320 (the `resend-api-key` line of the email step). The file currently ends at line 321.

**Critical patterns from institutional learnings:**

- Secret empty-check MUST be inside the step `run:` block, not a job-level `if:` -- secrets are masked before condition evaluation ([learning: 2026-02-12-ci-for-notifications-and-infrastructure-setup](../../learnings/implementation-patterns/2026-02-12-ci-for-notifications-and-infrastructure-setup.md))
- `allowed_mentions: {parse: []}` is mandatory -- release notes contain user-generated PR content that could contain `@everyone` or `<@USER_ID>` mentions ([learning: 2026-03-05-discord-allowed-mentions](../../learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md))
- Webhook payloads must include explicit `username` and `avatar_url` -- relying on webhook defaults causes inconsistent identity across channels ([learning: 2026-02-19-discord-bot-identity](../../learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md))

Add this step:

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

### Verification Commands

After merging, trigger a manual release to verify Discord posting:

```bash
# Trigger a manual release (workflow_dispatch)
gh workflow run version-bump-and-release.yml -f bump_type=patch

# Watch the run
gh run list --workflow=version-bump-and-release.yml --limit 1 --json databaseId,status,conclusion

# After completion, check the Discord #releases channel for the announcement
# Also verify email was sent to ops@jikigai.com via Resend dashboard
```

### Edge Cases

- **Avatar URL caching:** `raw.githubusercontent.com` returns `Cache-Control: max-age=300` (5 min). Discord caches webhook avatars server-side, so the URL only needs to be reachable on first use per webhook. Verified accessible as of plan creation.
- **Multi-component releases:** Both `version-bump-and-release.yml` (plugin) and `web-platform-release.yml` use `reusable-release.yml`. The fix applies to both -- web platform releases will also post to Discord, which is correct behavior (they are also community content).
- **Concurrent releases:** The `concurrency` group (`release-${{ inputs.component }}`) prevents concurrent runs per component. Two different components releasing simultaneously will each post to Discord independently, which is the expected behavior.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CI/workflow bug fix restoring existing functionality.

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
