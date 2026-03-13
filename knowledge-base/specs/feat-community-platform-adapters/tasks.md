# Tasks: Community Platform Adapter Interface

**Issue:** #470
**Branch:** feat/community-platform-adapters
**Plan:** `knowledge-base/plans/2026-03-13-refactor-community-platform-adapter-interface-plan.md`

## Phase 1: Foundation

- [ ] 1.1 Merge `origin/main` into worktree to bring `hn-community.sh`
- [ ] 1.2 Create `community-common.sh` with shared helpers
  - [ ] 1.2.1 `require_jq()` — extracted from discord/x/bsky/hn
  - [ ] 1.2.2 `require_curl()` — new, same pattern
  - [ ] 1.2.3 `parse_curl_response()` — wraps curl + tail + sed
  - [ ] 1.2.4 `validate_json()` — normalized jq check
  - [ ] 1.2.5 `retry_guard()` — depth >= 3 check
- [ ] 1.3 Add `BASH_SOURCE[0]` guard to discord, github, bsky scripts
- [ ] 1.4 Update all 5 scripts to source `community-common.sh` and replace inline duplicates
- [ ] 1.5 Verify all existing commands work after extraction

## Phase 2: Adapter Functions

- [ ] 2.1 discord-community.sh
  - [ ] 2.1.1 Add `cmd_capabilities` (fetch-mentions, fetch-metrics)
  - [ ] 2.1.2 Add `cmd_check_auth` (DISCORD_BOT_TOKEN + DISCORD_GUILD_ID)
  - [ ] 2.1.3 Add `cmd_fetch_mentions` → delegates to `cmd_messages`
  - [ ] 2.1.4 Add `cmd_fetch_metrics` → delegates to `cmd_guild_info`
- [ ] 2.2 github-community.sh
  - [ ] 2.2.1 Add `cmd_capabilities` (fetch-mentions, fetch-metrics, fetch-timeline)
  - [ ] 2.2.2 Add `cmd_check_auth` (gh CLI + auth status)
  - [ ] 2.2.3 Add `cmd_fetch_mentions` → delegates to `cmd_activity`
  - [ ] 2.2.4 Add `cmd_fetch_metrics` → delegates to `cmd_contributors`
  - [ ] 2.2.5 Add `cmd_fetch_timeline` → delegates to `cmd_activity`
- [ ] 2.3 x-community.sh
  - [ ] 2.3.1 Add `cmd_capabilities` (fetch-mentions, fetch-metrics, post-reply, fetch-timeline)
  - [ ] 2.3.2 Add `cmd_check_auth` (4 X API env vars)
  - [ ] 2.3.3 Alias `cmd_post_reply` → `cmd_post_tweet`
- [ ] 2.4 bsky-community.sh
  - [ ] 2.4.1 Add `cmd_capabilities` (fetch-mentions, fetch-metrics, post-reply)
  - [ ] 2.4.2 Add `cmd_check_auth` (BSKY_HANDLE + BSKY_APP_PASSWORD)
  - [ ] 2.4.3 Add `cmd_fetch_mentions` → delegates to `cmd_get_notifications`
  - [ ] 2.4.4 Add `cmd_fetch_metrics` → delegates to `cmd_get_metrics`
  - [ ] 2.4.5 Add `cmd_post_reply` → delegates to `cmd_post`
- [ ] 2.5 hn-community.sh
  - [ ] 2.5.1 Add `cmd_capabilities` (fetch-mentions, fetch-metrics, fetch-timeline)
  - [ ] 2.5.2 Add `cmd_check_auth` (always exit 0)
  - [ ] 2.5.3 Add `cmd_fetch_mentions` → delegates to `cmd_mentions`
  - [ ] 2.5.4 Add `cmd_fetch_metrics` → delegates to `cmd_trending`
  - [ ] 2.5.5 Add `cmd_fetch_timeline` → delegates to `cmd_mentions`
- [ ] 2.6 Add `capabilities` and `check-auth` to case dispatch in all 5 scripts

## Phase 3: Router

- [ ] 3.1 Create `community-router.sh` with main structure
- [ ] 3.2 Implement `discover_platforms()` — glob, exclude common, extract names
- [ ] 3.3 Implement `check_platform_auth()` — call script check-auth
- [ ] 3.4 Implement `get_platform_capabilities()` — parse space-separated output
- [ ] 3.5 Implement `dispatch_single()` — transparent stderr forwarding
- [ ] 3.6 Implement `dispatch_all()` — JSON envelope aggregation, partial failure handling
- [ ] 3.7 Implement `cmd_platforms()` — formatted platform/capabilities/auth listing
- [ ] 3.8 Add `--platform` flag parsing and `post-reply` guard
- [ ] 3.9 Test router with mock platform script for auto-discovery

## Phase 4: Integration

- [ ] 4.1 Update `SKILL.md` — replace inline platform detection with router commands
- [ ] 4.2 Update `community-manager.md` — replace hardcoded paths with router dispatch
- [ ] 4.3 Update `scheduled-community-monitor.yml` — replace inline logic with router
- [ ] 4.4 End-to-end verification of `digest`, `health`, `platforms`, `engage` sub-commands
- [ ] 4.5 Verify X API stderr contract preserved through router
