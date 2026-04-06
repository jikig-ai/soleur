---
module: System
date: 2026-04-06
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Discord release announcements stopped after PR #1578 notification migration"
  - "DISCORD_RELEASES_WEBHOOK_URL secret unused since migration"
  - "Stale references in skill docs claiming Discord notifications work"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [discord, github-actions, ci-cd, release-announcements, notification-migration]
---

# Troubleshooting: Discord Release Announcements Removed by Notification Migration

## Problem

PR #1578 (resolving #1420) migrated all GitHub Actions workflow notifications from Discord to email. The migration correctly moved ops alerts to email but incorrectly removed the Discord release announcement step from `reusable-release.yml`. Release announcements are community content and belong in Discord alongside the ops email notification.

## Environment

- Module: System (CI/CD pipeline)
- Affected Component: `.github/workflows/reusable-release.yml`
- Date: 2026-04-06

## Symptoms

- Discord #releases channel received no announcements after PR #1578 merged
- `DISCORD_RELEASES_WEBHOOK_URL` and `DISCORD_WEBHOOK_URL` GitHub secrets remained configured but unused
- Multiple skill docs (`release-announce/SKILL.md`, `ship/SKILL.md`, `plugins/soleur/AGENTS.md`) still referenced Discord release notifications as functional

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. Git history analysis (`git diff f14469e3^..f14469e3`) confirmed the exact commit that removed the Discord step, and the AGENTS.md rule text ("Discord channels are for community content only") confirmed the misapplication.

## Solution

Restored the "Post to Discord (release)" step in `reusable-release.yml` after the existing "Email notification (release)" step. Both notifications now fire when a release is created (dual notification: email to ops + Discord to community).

**Code changes:**

```yaml
# Before (broken): Only email notification
- name: Email notification (release)
  if: steps.create_release.outputs.released == 'true'
  continue-on-error: true
  uses: ./.github/actions/notify-ops-email
  # ... email config

# After (fixed): Email + Discord
- name: Email notification (release)
  # ... email config (unchanged)

- name: Post to Discord (release)
  if: steps.create_release.outputs.released == 'true'
  continue-on-error: true
  env:
    DISCORD_RELEASES_WEBHOOK_URL: ${{ secrets.DISCORD_RELEASES_WEBHOOK_URL }}
    DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
    # ... other env vars
  run: |
    WEBHOOK="${DISCORD_RELEASES_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"
    # ... webhook fallback, body truncation, jq payload, curl post
```

Key implementation details:

- **Webhook fallback:** `DISCORD_RELEASES_WEBHOOK_URL` with fallback to `DISCORD_WEBHOOK_URL` (matches project convention from bot identity learning)
- **Sol bot identity:** `username: "Sol"` + `avatar_url` pointing to `logo-mark-512.png` on raw.githubusercontent.com
- **Truncation:** Body capped at 1800 chars (not 2000) to leave headroom for the message envelope (component name, version, release URL)
- **Safety:** `allowed_mentions: {parse: []}` prevents accidental @everyone pings from release notes content
- **Non-blocking:** `continue-on-error: true` so Discord failures don't fail the release
- **JSON construction:** `jq -n` with `--arg` for safe payload construction (no heredocs per AGENTS.md rule)

Also clarified the AGENTS.md notification rule with parenthetical examples distinguishing community content (release announcements, blog posts) from ops alerts (CI failures, drift detection).

## Why This Works

1. **Root cause:** PR #1578 applied a blanket "Discord -> email" migration without distinguishing community content from ops alerts. The AGENTS.md rule "Discord channels are for community content only" was meant to prevent ops alerts from leaking to community channels -- not to remove community-facing content from Discord.
2. **Architectural constraint:** The Discord step must be inline in `reusable-release.yml` because GitHub Actions does not fire `release: published` events for releases created by `GITHUB_TOKEN`. A separate `release-announce.yml` workflow (which existed in earlier iterations) cannot be triggered by the current release mechanism.
3. **Dual notification is correct:** Ops email notifies the maintainer that a release shipped. Discord notifies the community that a new version is available. These serve different audiences and should both fire.

## Prevention

- When performing bulk notification migrations, classify each notification by audience (ops vs community) before applying changes. Release announcements, blog posts, and community updates are community content -- they belong in Discord.
- The AGENTS.md rule now includes explicit examples to prevent future misapplication during sweep migrations.
- The inline Discord step pattern (not a separate workflow) is an architectural requirement due to GITHUB_TOKEN release event limitations -- document this in the workflow file comments to prevent future "cleanup" attempts from extracting it.

## Related Issues

- See also: [discord-allowed-mentions-for-webhook-sanitization](../2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md) -- `allowed_mentions` pattern used in the restored step
- See also: [discord-bot-identity-and-webhook-behavior](../2026-02-19-discord-bot-identity-and-webhook-behavior.md) -- Sol bot identity and webhook fallback conventions
- See also: [reusable-workflow-monorepo-releases](../2026-03-19-reusable-workflow-monorepo-releases.md) -- `reusable-release.yml` architecture and Discord notification as shared logic
