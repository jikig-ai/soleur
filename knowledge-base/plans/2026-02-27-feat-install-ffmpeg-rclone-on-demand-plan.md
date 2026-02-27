---
title: "feat: Install ffmpeg and rclone on demand for feature-video pipeline"
type: feat
date: 2026-02-27
version_bump: PATCH
---

# feat: Install ffmpeg and rclone on demand for feature-video pipeline

## Overview

Extend the `feature-video` skill's Phase 0 dependency check to offer automatic installation of ffmpeg and rclone when they are missing, rather than silently degrading. PR #331 (v3.5.2) added preflight detection with graceful degradation. This is part 2: converting that detection into an install-or-skip prompt so new users get full pipeline capability without manual setup.

## Problem Statement / Motivation

Currently, when ffmpeg or rclone are missing, `check_deps.sh` prints `[skip]` and the skill degrades silently. This means:

- New Soleur users get screenshots-only output with no explanation of what they are missing
- The user must read the script output, find the install command, run it manually, and re-run the skill
- The one-shot pipeline produces lower-quality PR descriptions (no embedded demo videos) on fresh machines
- The rclone skill has its own separate `check_setup.sh` with overlapping install instructions

The pencil-setup skill (v3.6.0) established a pattern for auto-detection and installation of external dependencies. This plan follows that pattern for ffmpeg and rclone.

## Proposed Solution

Enhance `check_deps.sh` to offer installation of missing soft dependencies and verify success. The script accepts a `--auto` flag for non-interactive pipeline use (one-shot).

### Architecture

**Single script enhancement** -- modify the existing `check_deps.sh` rather than creating new scripts. The script already owns the dependency check responsibility; adding installation is a natural extension.

**No new skills or agents** -- this is a script-level change plus a SKILL.md Phase 0 update. The rclone skill's `check_setup.sh` remains separate (it handles configuration, not installation).

### Key Design Decisions

1. **Interactive by default, auto-install with `--auto` flag** -- when called from SKILL.md interactively, prompt the user. When called from one-shot pipeline, pass `--auto` to install without prompting. The `--auto` flag IS the consent mechanism -- no state tracking needed.

2. **Two OS families: Debian/Ubuntu (apt-get) and macOS (brew)** -- covers the actual user base. Falls back to manual instructions for unsupported systems. Fedora/RHEL support deferred until a user requests it.

3. **No `sudo` assumption** -- check `sudo -n true` inline before install commands. If no sudo, print the command they need to run and continue with `[skip]`.

4. **Package manager install for both tools in auto mode** -- use `sudo apt-get install -y rclone` on Debian and `brew install rclone` on macOS. The `curl | sudo bash` method is reserved for manual install instructions only (not safe for unattended auto mode). Users who want the latest rclone version can run the official script manually.

5. **Verification after install** -- re-run `command -v` after installation to confirm success. Print `[ok]` on success, `[FAILED]` with troubleshooting on failure.

6. **No `set -euo pipefail`** -- the script intentionally omits `set -e` because install failures and soft dependency checks must not abort the script. A header comment documents this exception to the constitution convention. Individual install commands use explicit `if`/`then` checks instead.

## Technical Considerations

- **Idempotency**: Running the script twice is safe -- `apt-get install` and `brew install` are idempotent.
- **No configuration**: This plan covers installation only. rclone configuration (setting up R2 remotes) remains in the rclone skill's `check_setup.sh` and SKILL.md.
- **SKILL.md code blocks**: All prompting and install logic lives in the shell script. SKILL.md Phase 0 references the script with `--auto` flag via an angle-bracket placeholder, not shell variable expansion.
- **One-shot mechanism**: SKILL.md Phase 0 detects pipeline mode via `$ARGUMENTS` containing `--auto` or equivalent, and conditionally passes the flag to the script invocation.

## Non-Goals

- Configuring rclone remotes (handled by rclone skill)
- Installing agent-browser (hard dependency, separate concern)
- Building a general-purpose package manager abstraction
- Supporting Windows/WSL or Fedora/RHEL (no current user base)
- Updating the rclone skill's `check_setup.sh` (installation vs configuration boundary)

## Acceptance Criteria

- [ ] `check_deps.sh` offers to install ffmpeg when missing (interactive prompt)
- [ ] `check_deps.sh` offers to install rclone when missing (interactive prompt)
- [ ] `check_deps.sh --auto` installs without prompting (for pipeline use)
- [ ] Installation is verified after each tool install (re-check `command -v`)
- [ ] Script prints `[ok]` with version after successful install
- [ ] Script prints `[FAILED]` with manual instructions if install fails
- [ ] Script handles missing `sudo` gracefully (prints command, continues with `[skip]`)
- [ ] SKILL.md Phase 0 updated to pass `--auto` when invoked from one-shot
- [ ] Existing `[skip]` behavior preserved when user declines installation
- [ ] Version bumped (PATCH) in plugin.json, CHANGELOG.md, README.md, marketplace.json, bug_report.yml

## Test Scenarios

### Installation flow

- Given ffmpeg is not installed, when `check_deps.sh` runs interactively, then user is prompted "Install ffmpeg? (y/N)" and installation proceeds on "y"
- Given rclone is not installed, when `check_deps.sh` runs interactively, then user is prompted "Install rclone? (y/N)" and installation proceeds on "y"
- Given `--auto` flag is passed, when ffmpeg is missing, then ffmpeg is installed without prompting
- Given both tools are already installed, when `check_deps.sh` runs, then both show `[ok]` with no install prompts

### OS detection

- Given running on Debian/Ubuntu, when installing ffmpeg, then `sudo apt-get install -y ffmpeg` is used
- Given running on macOS, when installing ffmpeg, then `brew install ffmpeg` is used
- Given running on unsupported OS, when tools are missing, then manual install instructions are printed

### Error handling

- Given user has no sudo access, when install is attempted, then script prints the command needed and continues with `[skip]`
- Given network is unavailable, when install fails, then script prints `[FAILED]` and continues
- Given install command succeeds but binary not found, then script prints `[FAILED]` with troubleshooting steps

### Pipeline integration

- Given one-shot pipeline calls `check_deps.sh --auto`, when ffmpeg is missing, then ffmpeg is installed silently and pipeline continues
- Given one-shot pipeline calls `check_deps.sh --auto`, when install fails, then pipeline degrades gracefully (same as current behavior)

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| `sudo` not available in CI/container | Detect inline and skip with clear message |
| `apt` lock contention | Use `apt-get` with `-y` flag, no interactive prompts |
| Homebrew not installed on macOS | Detect and print Homebrew install instructions |
| Older rclone version from apt | Acceptable for auto mode; manual instructions reference official script for latest |

## Implementation Plan

### Phase 1: Script Enhancement (`check_deps.sh`)

1. Add `--auto` flag parsing at top of script
2. Add `install_ffmpeg` function with Debian/macOS branches and inline sudo check
3. Add `install_rclone` function with Debian/macOS branches and inline sudo check
4. Wire install functions into existing missing-tool branches with interactive prompt (or auto-install with `--auto`)
5. Add post-install verification (`command -v` + version output)
6. Update header comment documenting the `set -e` exception

### Phase 2: SKILL.md Update

1. Update Phase 0 to document the `--auto` flag via angle-bracket placeholder
2. Add note about one-shot pipeline passing `--auto`
3. Update the capability variable section to reflect auto-install

### Phase 3: Version Bump

1. Bump version (PATCH) across all five files
2. Add CHANGELOG entry under `### Changed`

## References

- PR #331: Preflight dependency check (part 1) -- `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- Issue #325: Original ffmpeg/rclone installation request
- Learning: `knowledge-base/learnings/2026-02-27-feature-video-graceful-degradation.md`
- Pattern: `plugins/soleur/skills/pencil-setup/SKILL.md` -- auto-detection and installation pattern
- Pattern: `plugins/soleur/skills/rclone/scripts/check_setup.sh` -- rclone check pattern
- rclone official install: https://rclone.org/install.sh
