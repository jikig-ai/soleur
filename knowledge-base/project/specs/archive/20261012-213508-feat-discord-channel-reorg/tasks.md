# Tasks: Discord Channel Reorganization

## Phase 1: Setup

- [ ] 1.1 Create #releases channel in Discord server (manual)
- [ ] 1.2 Create webhook in #releases channel, copy URL (manual)
- [ ] 1.3 Create #blog channel in Discord server (manual)
- [ ] 1.4 Create webhook in #blog channel, copy URL (manual)
- [ ] 1.5 Add `DISCORD_RELEASES_WEBHOOK_URL` repository secret in GitHub (manual)
- [ ] 1.6 Add `DISCORD_BLOG_WEBHOOK_URL` repository secret in GitHub (manual)

## Phase 2: Core Implementation

- [ ] 2.1 Update `version-bump-and-release.yml` to use `DISCORD_RELEASES_WEBHOOK_URL` with fallback to `DISCORD_WEBHOOK_URL`
  - [ ] 2.1.1 Add `DISCORD_RELEASES_WEBHOOK_URL` to the "Post to Discord" step env block
  - [ ] 2.1.2 Update the webhook URL selection logic: `WEBHOOK="${DISCORD_RELEASES_WEBHOOK_URL:-$DISCORD_WEBHOOK_URL}"`
  - [ ] 2.1.3 Update the empty-check to test the resolved variable
- [ ] 2.2 Update `content-publisher.sh` to use `DISCORD_BLOG_WEBHOOK_URL` with fallback to `DISCORD_WEBHOOK_URL`
  - [ ] 2.2.1 Update `post_discord()` to resolve `${DISCORD_BLOG_WEBHOOK_URL:-$DISCORD_WEBHOOK_URL}`
  - [ ] 2.2.2 Update the env var documentation comment at the top of the file
  - [ ] 2.2.3 Update `create_discord_fallback_issue()` to mention the correct channel
- [ ] 2.3 Update `scheduled-content-publisher.yml` to pass `DISCORD_BLOG_WEBHOOK_URL` secret
  - [ ] 2.3.1 Add `DISCORD_BLOG_WEBHOOK_URL: ${{ secrets.DISCORD_BLOG_WEBHOOK_URL }}` to the "Publish content" step
- [ ] 2.4 Update `social-distribute` skill to reference `DISCORD_BLOG_WEBHOOK_URL`
  - [ ] 2.4.1 Update prerequisite section to check `DISCORD_BLOG_WEBHOOK_URL` first, then fallback
  - [ ] 2.4.2 Update webhook posting instructions to prefer `DISCORD_BLOG_WEBHOOK_URL`
- [ ] 2.5 Update `discord-setup.sh write-env` to support new optional webhook variables
  - [ ] 2.5.1 Add optional prompts/params for releases and blog webhook URLs
  - [ ] 2.5.2 Update the env file cleanup section to handle new variable names

## Phase 3: Testing

- [ ] 3.1 Update `test/content-publisher.test.ts` with tests for the new fallback logic
  - [ ] 3.1.1 Test: `DISCORD_BLOG_WEBHOOK_URL` is used when set
  - [ ] 3.1.2 Test: Falls back to `DISCORD_WEBHOOK_URL` when `DISCORD_BLOG_WEBHOOK_URL` is not set
  - [ ] 3.1.3 Test: Skips Discord when neither variable is set
- [ ] 3.2 Verify all existing CI workflows still reference `DISCORD_WEBHOOK_URL` for failure notifications (no changes needed for failure notification steps)
- [ ] 3.3 Run `bun test` to verify all tests pass

## Phase 4: Documentation

- [ ] 4.1 Update `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` to document the multi-webhook channel architecture
- [ ] 4.2 Verify webhook payloads in all modified files include `username`, `avatar_url`, and `allowed_mentions: {parse: []}`
