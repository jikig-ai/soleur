# Community Platform Adapter Interface Brainstorm

**Date:** 2026-03-13
**Issue:** #470
**Branch:** feat/community-platform-adapters
**Status:** Decided

## What We're Building

A thin router and shared library layer for the community platform scripts that:

1. **Eliminates triple-duplication** of platform detection and dispatch logic across SKILL.md, community-manager agent, and scheduled workflow YAML
2. **Standardizes commands** across all 5 platform scripts to a shared interface (`fetch-mentions`, `fetch-metrics`, `post-reply`, `fetch-timeline`)
3. **Extracts shared helpers** (retry logic, `require_jq`, `urlencode`, response handling) into a common library

## Why This Approach

The YAGNI trigger has been met: 5 scripted platforms (Discord, GitHub, X/Twitter, Bluesky, HN) plus LinkedIn (manual-only). Adding HN required updating 3 separate files with overlapping platform detection logic. The cost of duplication now exceeds the cost of abstraction.

The "thin router over migration" learning (2026-02-22) directly applies: add a facade, don't reorganize the internals. Each script stays self-contained; the router is a new entry point, not a rewrite.

The "external API scope calibration" learning (2026-03-09) warns against overscoping this exact refactor -- it was cut as YAGNI during X/Twitter integration when the plan was 3x overscoped. Keeping to shell and convention-enforced interfaces avoids that trap.

## Key Decisions

### 1. Shell-first architecture (no TypeScript adapter layer)

All existing scripts are bash. A TS layer would fight the architecture and risk the same 3x overscoping that got this deferred in the first place. Shell conventions are sufficient.

### 2. Two new files

- **`community-common.sh`** -- Shared library sourced by all platform scripts. Extracts: `require_jq()`, `urlencode()`, `validate_env()`, response handling with depth-limited retry (max 3), curl stderr suppression, JSON validation, jq fallback chains, float-safe retry_after clamping. Follows the 5-layer hardening pattern from learnings.
- **`community-router.sh`** -- Single entry point for discovery and dispatch. Auto-discovers `*-community.sh` scripts in the scripts directory, queries each for capabilities, routes standardized commands.

### 3. Standardized command interface

All platform scripts implement a subset of:
- `capabilities` -- Returns supported operations (required for all)
- `fetch-mentions` -- Fetch recent mentions/notifications
- `fetch-metrics` -- Fetch account/profile metrics
- `post-reply` -- Post a reply or new content
- `fetch-timeline` -- Fetch own recent posts/activity

Not all platforms support all ops (HN is read-only, GitHub has no post-reply). Each script implements `cmd_capabilities` returning its supported ops; the router skips unsupported ops gracefully.

### 4. Script-driven discovery (no config file)

The router discovers platforms by globbing `*-community.sh` in the scripts directory and querying each script's `cmd_capabilities`. No separate `platforms.json` -- the scripts are the source of truth. This prevents config drift.

### 5. Single entry point for agent and CI

SKILL.md, community-manager agent, and scheduled workflow all call `community-router.sh` instead of hardcoding per-platform logic. Adding platform #6 = one new `<name>-community.sh` script with `cmd_capabilities`. No other files need updating for basic support.

## Architecture

```
community-router.sh (entry point)
  |-- discovers *-community.sh scripts
  |-- queries cmd_capabilities per script
  |-- dispatches: router.sh <command> [--platform <name>] [args...]
  |
  |-- community-common.sh (shared library, sourced by all)
  |     |-- require_jq(), require_curl()
  |     |-- urlencode()
  |     |-- api_request() with depth-limited retry
  |     |-- handle_response()
  |     |-- validate_env()
  |
  |-- discord-community.sh   (capabilities: fetch-mentions, fetch-metrics)
  |-- github-community.sh    (capabilities: fetch-mentions, fetch-metrics, fetch-timeline)
  |-- x-community.sh         (capabilities: fetch-mentions, fetch-metrics, post-reply, fetch-timeline)
  |-- bsky-community.sh      (capabilities: fetch-mentions, fetch-metrics, post-reply)
  |-- hn-community.sh        (capabilities: fetch-mentions, fetch-metrics, fetch-timeline)
```

### Router dispatch modes

- `community-router.sh platforms` -- List enabled platforms and their capabilities
- `community-router.sh fetch-metrics [--platform discord]` -- Run fetch-metrics on all (or one) enabled platform(s)
- `community-router.sh fetch-mentions [--platform x]` -- Run fetch-mentions on all (or one)
- `community-router.sh post-reply --platform x <text>` -- Post requires explicit platform

## Open Questions

1. **How to handle platform auth detection in the router?** Currently each script validates its own env vars. The router needs to know which platforms are "enabled" (have credentials) without running each script. Options: each script has a `cmd_check-auth` that exits 0/1 quickly, or the router sources each script's env var requirements from a comment/function.

2. **Should setup scripts (`discord-setup.sh`, `x-setup.sh`, `bsky-setup.sh`) also be standardized?** They follow similar patterns but are run infrequently. Likely out of scope for this PR.

3. **How much of the community-manager agent's prose logic should move into the router vs. stay as agent instructions?** The agent currently has detailed per-platform data collection steps. The router can handle dispatch, but the agent still needs to know how to interpret and aggregate results.

## Constraints

- Follow the 5-layer shell API hardening pattern (input validation, curl stderr suppression, JSON validation, jq fallback chains, float-safe retry clamping)
- Depth-limited retry: max 3, matching existing convention
- Exit codes: 0 success, 1 failure, 2 partial failure
- Discord webhook mentions: always set `allowed_mentions: {parse: []}`
- X API: handle HTTP 402 distinctly from 401/403/429
- HN: read-only by design, no posting capability
- Do not automate Reddit (irreversible domain reputation risk)
