# Spec: Auto Mode as Default Permission Mode

**Date:** 2026-03-24
**Branch:** auto-mode-default
**Brainstorm:** [2026-03-24-auto-mode-default-brainstorm.md](../../brainstorms/2026-03-24-auto-mode-default-brainstorm.md)

## Problem Statement

Soleur CLI users currently operate in `default` permission mode, which prompts for permission on first use of each tool. This creates friction for experienced users running long tasks. Claude Code's auto mode provides a safer middle ground between constant prompting and `--dangerously-skip-permissions`.

## Goals

- G1: Make auto mode the default permission mode for all Soleur CLI users
- G2: Maintain all existing safety guardrails (PreToolUse hooks, allow rules)

## Non-Goals

- Modifying the web platform's permission model (Agent SDK)
- Replacing `--dangerously-skip-permissions` on the Telegram bridge
- Changing GitHub Actions permission configuration
- Shipping `autoMode.environment` configuration (cannot be read from shared settings by design)

## Functional Requirements

- FR1: `.claude/settings.json` sets `defaultMode` to `"auto"`
- FR2: Existing `permissions.allow` rules remain unchanged
- FR3: Existing PreToolUse hooks remain unchanged

## Technical Requirements

- TR1: Single field addition to `.claude/settings.json` — no new files
- TR2: No changes to any hook scripts
- TR3: No changes to plugin code
