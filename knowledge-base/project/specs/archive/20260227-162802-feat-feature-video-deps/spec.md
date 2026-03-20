# Spec: Feature Video Dependency Checking

**Issue:** #325
**Branch:** feat-feature-video-deps
**Status:** Draft

## Problem Statement

The `feature-video` skill silently fails when external dependencies (ffmpeg, rclone) are missing. Users get no error message and no video output. The skill should check for dependencies before starting and gracefully degrade when tools are unavailable.

## Goals

- G1: Eliminate silent failures in the feature-video pipeline
- G2: Provide clear, actionable install instructions when dependencies are missing
- G3: Allow the skill to produce partial output (screenshots, local video) when not all tools are available

## Non-Goals

- Shared dependency framework for all skills (deferred as YAGNI)
- Auto-installation of system packages (security concern with sudo)
- rclone remote configuration automation (requires secrets)

## Functional Requirements

- FR1: A `check-deps.sh` script that checks for agent-browser, ffmpeg, and rclone
- FR2: Platform-specific install instructions (Linux apt, macOS brew) displayed when tools are missing
- FR3: The script reports a summary of available/missing tools with clear status indicators
- FR4: The SKILL.md calls the check script as Phase 0 before any recording steps
- FR5: Graceful degradation -- skill continues with available tools:
  - No agent-browser: skip recording, inform user
  - No ffmpeg: capture screenshots only, skip video conversion
  - No rclone: create video locally, skip upload

## Technical Requirements

- TR1: Script uses `command -v` (POSIX-portable) for binary detection
- TR2: Script checks rclone remote configuration separately from installation
- TR3: Script exits with informative output, not non-zero codes (since the skill continues regardless)
- TR4: Follow the existing `rclone/scripts/check_setup.sh` pattern

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/feature-video/scripts/check-deps.sh` | Create | Preflight dependency checker |
| `skills/feature-video/SKILL.md` | Modify | Add Phase 0 dependency check, update requirements section, add graceful degradation logic to steps 4-6 |

## Acceptance Criteria

- [ ] Running `bash check-deps.sh` on a machine without ffmpeg prints install instructions
- [ ] Running `bash check-deps.sh` on a machine with all tools shows all-green status
- [ ] The feature-video skill with ffmpeg missing captures screenshots but skips video creation with a warning
- [ ] The feature-video skill with rclone missing creates video locally but skips upload with a warning
- [ ] No `sudo` commands are executed automatically
