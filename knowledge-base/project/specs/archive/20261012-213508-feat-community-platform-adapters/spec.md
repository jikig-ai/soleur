# Spec: Community Platform Adapter Interface

**Issue:** #470
**Branch:** feat/community-platform-adapters
**Date:** 2026-03-13

## Problem Statement

Community platform scripts (Discord, GitHub, X/Twitter, Bluesky, HN) evolved independently with inconsistent command names, duplicated helpers, and platform detection logic replicated across three files (SKILL.md, community-manager agent, scheduled workflow). Adding a new platform requires updating all three locations and copy-pasting boilerplate.

## Goals

- G1: Single source of truth for platform discovery and dispatch
- G2: Standardized command interface across all platform scripts
- G3: Shared helper library eliminating duplicated code
- G4: Adding a new platform requires creating one script file only

## Non-Goals

- TypeScript adapter layer or formal interface types
- Standardizing setup scripts (`*-setup.sh`)
- Migrating content-publisher pipeline (`scripts/content-publisher.sh`)
- Reddit automation
- LinkedIn script creation (remains manual-only)

## Functional Requirements

- **FR1:** `community-router.sh platforms` lists all enabled platforms and their capabilities
- **FR2:** `community-router.sh <command> [--platform <name>]` dispatches to all or one platform
- **FR3:** Each platform script exposes `cmd_capabilities` returning supported operations
- **FR4:** Standardized commands: `fetch-mentions`, `fetch-metrics`, `post-reply`, `fetch-timeline`
- **FR5:** Router skips unsupported operations gracefully (no error for capability gaps)
- **FR6:** Router detects enabled platforms via auth check without full script execution
- **FR7:** `post-reply` requires explicit `--platform` flag (no broadcast posting)

## Technical Requirements

- **TR1:** Shared library `community-common.sh` sourced by all platform scripts
- **TR2:** 5-layer hardening: input validation, curl stderr suppression, JSON validation, jq fallback chains, float-safe retry clamping
- **TR3:** Depth-limited retry (max 3) matching existing convention
- **TR4:** Exit codes: 0 success, 1 failure, 2 partial failure
- **TR5:** Platform scripts discovered by glob `*-community.sh` in scripts directory
- **TR6:** SKILL.md, community-manager agent, and scheduled workflow updated to use router
- **TR7:** Existing command aliases preserved during transition (backward compat)

## Acceptance Criteria

- [ ] `community-router.sh platforms` shows 5 platforms with correct capabilities
- [ ] `community-router.sh fetch-metrics` collects metrics from all enabled platforms
- [ ] `community-router.sh fetch-mentions --platform x` fetches X mentions only
- [ ] `community-router.sh post-reply --platform bsky "test"` posts to Bluesky
- [ ] Adding a mock platform script with `cmd_capabilities` is auto-discovered
- [ ] SKILL.md no longer contains per-platform detection logic
- [ ] Community-manager agent dispatches via router, not hardcoded script paths
- [ ] Scheduled workflow calls router instead of inline platform logic
- [ ] All existing community skill functionality preserved (digest, health, engage)
