---
title: refactor(community): platform adapter interface
type: refactor
date: 2026-03-13
---

# refactor(community): platform adapter interface

[Updated 2026-03-13] Radically simplified after plan review. Cut: community-common.sh, cmd_capabilities, cmd_check_auth, standardized command wrappers, JSON envelope, dynamic glob discovery. Followed the "thin router" learning literally.

## Overview

Create a thin dispatch router (`community-router.sh`, ~50 lines) with a hardcoded platform table. Update 3 callers (SKILL.md, community-manager agent, scheduled workflow) to use the router instead of duplicating platform detection logic. No changes to the platform scripts themselves.

## Problem Statement / Motivation

Adding HN as platform #5 required updating 3 separate files with overlapping platform detection logic. The "thin router over migration" learning applies — add a facade, don't reorganize internals.

## Proposed Solution

**One new file: `community-router.sh`** (~50 lines). Contains:

1. A hardcoded platform table: name, script filename, required env vars
2. A `platforms` command that checks auth status and prints enabled/disabled
3. A `--platform <name> <command> [args]` dispatch that `exec`s the target script
4. Transparent stderr passthrough (preserves X API contract string)

```bash
# community-router.sh — thin dispatch
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Platform registry: name|script|env_vars (comma-separated)|auth_command
PLATFORMS=(
  "discord|discord-community.sh|DISCORD_BOT_TOKEN,DISCORD_GUILD_ID|"
  "github|github-community.sh||gh auth status"
  "x|x-community.sh|X_API_KEY,X_API_SECRET,X_ACCESS_TOKEN,X_ACCESS_TOKEN_SECRET|"
  "bsky|bsky-community.sh|BSKY_HANDLE,BSKY_APP_PASSWORD|"
  "hn|hn-community.sh||"
)
```

Adding platform #6 = add one line to the `PLATFORMS` array + create the script.

**Existing scripts are untouched.** No adapter functions, no shared library, no source guards, no command renaming. Each script keeps its existing command names. The callers (SKILL.md, agent, workflow) reference platform-native command names via the router.

## Technical Considerations

- **X API cross-file contract**: `x-community.sh:201` — stderr string `"This endpoint requires paid API access."` matched by community-manager agent for 403 fallback. Router uses `exec` for single-platform dispatch, preserving stderr exactly.
- **GitHub outlier**: Uses `gh api` not curl. Auth check is `gh auth status` instead of env vars. The router's platform table accommodates this with an `auth_command` field.
- **HN always-on**: No env vars needed, no auth command. Empty fields in the table mean always enabled.
- **No fan-out**: The router dispatches to one platform at a time. Callers that need all-platform data iterate the `platforms` output and call each one. This matches how all 3 callers work today.

## Acceptance Criteria

- [ ] `community-router.sh platforms` lists 5 platforms with enabled/disabled status
- [ ] `community-router.sh discord messages <channel_id>` dispatches to discord-community.sh
- [ ] `community-router.sh x fetch-mentions` dispatches with transparent stderr
- [ ] `community-router.sh bsky post "test"` dispatches to bsky-community.sh
- [ ] `community-router.sh unknown-platform` exits 1 with error
- [ ] SKILL.md references router for platform detection instead of inline table
- [ ] Community-manager agent uses `community-router.sh <platform> <command>` syntax
- [ ] Scheduled workflow uses router instead of inline platform logic
- [ ] X API stderr contract preserved (test: free tier 403 produces exact contract string)
- [ ] All existing community skill sub-commands still work: digest, health, platforms, engage

## Test Scenarios

- Given no credentials, when `platforms`, then Discord/X/Bluesky show disabled; GitHub/HN show enabled
- Given X free tier, when `community-router.sh x fetch-mentions`, then stderr contains exact string `"This endpoint requires paid API access."`
- Given valid Discord creds, when `community-router.sh discord guild-info`, then returns guild JSON
- Given unknown platform, when `community-router.sh reddit activity`, then exit 1 with "Unknown platform: reddit"

## Implementation

Single phase, single commit target:

1. Merge `origin/main` to bring `hn-community.sh` into worktree
2. Create `community-router.sh` with hardcoded platform table, `platforms` command, and `exec` dispatch
3. Update `SKILL.md` — replace inline platform detection with "run `community-router.sh platforms`"
4. Update `community-manager.md` — replace hardcoded script paths with `community-router.sh <platform> <command>`
5. Update `scheduled-community-monitor.yml` — replace inline platform logic with router calls
6. Verify end-to-end: digest, health, platforms, engage

## What Was Cut (and Why)

| Cut Feature | Why |
|-------------|-----|
| `community-common.sh` shared library | Extracts ~20 lines of duplication (require_jq). Not worth the coupling. |
| `cmd_capabilities` per script | No caller queries capabilities programmatically. The router hardcodes the table. |
| `cmd_check_auth` per script | Scripts already validate on entry. Pre-checking is redundant. |
| Standardized command wrappers | LLM callers can use platform-native names. No rename needed. |
| JSON envelope output | No caller does multi-platform fan-out. All iterate one-at-a-time. |
| Dynamic glob discovery | 5 scripts, quarterly additions. A case statement takes 5 seconds to update. |
| Exit code 2 (partial failure) | No fan-out means no partial failure state. |
| BASH_SOURCE guards | Good hygiene but unrelated to this refactor. Separate PR if desired. |

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-13-community-platform-adapters-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-community-platform-adapters/spec.md`
- Learning — scope calibration: `knowledge-base/project/learnings/2026-03-09-external-api-scope-calibration.md`
- Learning — thin router: `knowledge-base/project/learnings/2026-02-22-simplify-workflow-thin-router-over-migration.md`
- X API contract: `plugins/soleur/skills/community/scripts/x-community.sh:201`
- Parent issue: #127 | This issue: #470 | Draft PR: #605
