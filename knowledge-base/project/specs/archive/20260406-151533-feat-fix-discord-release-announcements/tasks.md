# Tasks: fix-discord-release-announcements

## Phase 1: Restore Discord Step

- [ ] 1.1 Read `.github/workflows/reusable-release.yml`
- [ ] 1.2 Add "Post to Discord (release)" step after the existing "Email notification (release)" step
  - [ ] 1.2.1 Use `DISCORD_RELEASES_WEBHOOK_URL` with fallback to `DISCORD_WEBHOOK_URL`
  - [ ] 1.2.2 Include Sol bot identity (username: "Sol", avatar_url: logo-mark-512.png)
  - [ ] 1.2.3 Truncate release body to 1900 chars for Discord limit
  - [ ] 1.2.4 Use `continue-on-error: true` so Discord failures don't block releases
  - [ ] 1.2.5 Use `allowed_mentions: {parse: []}` to prevent @everyone pings
  - [ ] 1.2.6 Use `jq -n` for safe JSON payload construction

## Phase 2: Clarify AGENTS.md Rule

- [ ] 2.1 Read `AGENTS.md`
- [ ] 2.2 Update the Discord/email notification rule to clarify community vs ops content distinction
  - [ ] 2.2.1 Add parenthetical with examples: release announcements = community, CI failures = ops

## Phase 3: Verification

- [ ] 3.1 Verify YAML syntax is valid (no heredoc issues per AGENTS.md rule)
- [ ] 3.2 Verify no stale references remain that claim Discord notifications are broken
- [ ] 3.3 Run markdownlint on changed `.md` files
