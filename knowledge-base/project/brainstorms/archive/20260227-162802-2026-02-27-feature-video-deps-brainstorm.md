# Brainstorm: Feature Video Dependency Checking

**Date:** 2026-02-27
**Issue:** #325
**Status:** Decided

## What We're Building

A dedicated preflight dependency check script for the `feature-video` skill that validates external tool dependencies (agent-browser, ffmpeg, rclone) before the recording flow starts. The skill currently fails silently when dependencies are missing -- the script will report what's available and the skill will gracefully degrade based on what's installed.

### The Problem

The `feature-video` skill chains three external dependencies:
1. **agent-browser** -- captures browser screenshots
2. **ffmpeg** -- converts screenshots to video/GIF
3. **rclone** -- uploads video to Cloudflare R2

When any dependency is missing, the skill either fails with a raw shell error or silently skips steps, giving the user no indication of what went wrong or how to fix it.

### Scope

- Narrow fix on the `feature-video` skill only
- No shared dependency framework (evaluated and deferred as YAGNI)
- Follows the existing `rclone/scripts/check_setup.sh` pattern

## Why This Approach

### Dedicated preflight script (`check-deps.sh`)

A bash script in `skills/feature-video/scripts/` that validates all three dependencies and reports status. Chosen because:

- **Follows existing precedent:** The rclone skill already has `scripts/check_setup.sh` with the same three-layer validation pattern (binary present, config valid, connectivity)
- **Independently runnable:** Users can run `bash check-deps.sh` to diagnose their setup outside of the skill
- **Clean separation:** The SKILL.md calls the script as Phase 0, keeping the skill readable

### Graceful degradation model

Rather than hard-stopping when any dependency is missing, the skill continues with whatever it can do:

| Missing | Behavior |
|---------|----------|
| agent-browser | Skip recording entirely, inform user with install instructions |
| ffmpeg | Screenshots captured but no video/GIF created, warn user |
| rclone | Video created locally but upload skipped, warn user |

All three scenarios print clear warnings with platform-specific install instructions.

### Alternatives considered

1. **Inline SKILL.md checks only** -- Simpler but no independent runnable script. Less thorough.
2. **Shared dependency system** -- `dependencies:` field in SKILL.md frontmatter with automatic enforcement. Evaluated and rejected: no skill runner exists in Claude Code's plugin model to intercept and auto-check. Would require building enforcement in orchestrators (one-shot, go, work). YAGNI for now -- only one skill has this problem.
3. **Eager bootstrap script** -- Install all optional deps at plugin setup time. Rejected: no plugin install hook exists, installs tools user may never use.

## Key Decisions

1. **Scope:** Fix feature-video only, no shared framework
2. **Pattern:** Dedicated `check-deps.sh` script following rclone's `check_setup.sh` precedent
3. **Failure mode:** Graceful degradation -- continue with whatever tools are available
4. **Install method:** Print platform-specific install instructions (no auto-install with sudo)
5. **rclone config:** Check for configured remotes separately from binary installation. Config requires secrets that can't be automated.

## CTO Assessment Summary

- **Real bug** is the silent skip, not the missing install
- Static binaries exist for both ffmpeg and rclone that can install to `~/.local/bin` without sudo
- `sudo` in agent context is a security concern -- print instructions instead
- rclone configuration (R2 credentials) is a separate problem from binary installation
- No new agents, skills, or architectural concepts needed

## Research Findings

### Existing dependency patterns in the plugin

| Pattern | Skills Using It | Behavior |
|---------|----------------|----------|
| Inline `command -v` | agent-browser, rclone, feature-video | Print message |
| Dedicated check script | rclone, community | Print instructions + exit 1 |
| Auto-install inline | test-browser | Install without asking |
| MCP tool probe | xcode-test | Hard stop |
| Env var check | gemini-imagegen, deploy | Error/stop |
| Graceful skip | review (semgrep) | Continue without |

### Relevant learnings

- **Pencil MCP binary constraint:** Not all tools can be auto-provisioned. Always include (1) runtime check, (2) graceful degradation, (3) install instructions.
- **Bundle external plugin:** Silent failures from missing dependencies are the most common pain point.
- **Worktree missing node_modules:** Silent hangs from missing deps are worse than errors. Defensive `command -v` checks should run before any dep-dependent operation.

## Open Questions

1. Should the check-deps.sh script also verify ffmpeg has the required codecs (libx264, lanczos filter)? Or is binary presence sufficient?
2. Should the script output a machine-readable format (exit codes per dep) or just human-readable text?
