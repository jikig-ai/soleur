---
title: "chore: Document environment constraints (Warp terminal, no-sudo)"
type: chore
date: 2026-03-03
issue: "#394"
version_bump: none
---

# chore: Document environment constraints (Warp terminal, no-sudo)

## Overview

Claude occasionally assumes standard tool behaviors that do not hold in the project environment -- such as terminal escape sequences in Warp or sudo in non-interactive shells -- leading to dead-end attempts before falling back to manual instructions. This plan adds explicit environment constraints to the project's instruction files so Claude avoids these dead ends on every turn.

## Problem Statement

Two specific failure patterns have been observed (source: Claude Code Insights report, 2026-02-02 to 2026-03-03):

1. **Warp terminal escape sequences**: Claude used standard ANSI escape sequences to rename a terminal tab, which silently fail in Warp. The session ended as `not_achieved` because Claude did not know the sequences would be swallowed.
2. **Non-interactive sudo**: A `sudo` command could not execute in the non-interactive shell, forcing manual steps for a PATH precedence fix. Claude wasted turns attempting elevated commands before realizing it needed to print manual instructions instead.

Both are recoverable -- Claude eventually finds the right approach -- but they cost time and occasionally result in `not_achieved` sessions that should have been `achieved`.

## Proposed Solution

Add environment constraints as rules in the project instruction files. The constraints must be placed where Claude reads them on every turn (AGENTS.md) or on-demand (constitution.md), depending on violation frequency.

### Where to place each constraint

| Constraint | File | Rationale |
|-----------|------|-----------|
| Warp terminal: no escape sequences for tab manipulation | `AGENTS.md` (Hard Rules) | Violates without being told -- matches AGENTS.md purpose |
| Non-interactive shell: no `sudo` | `AGENTS.md` (Hard Rules) | Violates without being told -- matches AGENTS.md purpose |
| Extensibility pattern for future constraints | `knowledge-base/overview/constitution.md` | Prefer section in constitution.md so future constraints have a defined home |

### Why not `.claude/settings.json`?

The `env` field in settings.json sets environment variables -- it does not accept free-text instructions. There is no Claude Code configuration field for "behavioral constraints." The instruction files (AGENTS.md, constitution.md) are the correct mechanism.

### Why not CLAUDE.md?

CLAUDE.md in this project is a pointer file (`@AGENTS.md`). Adding content directly to CLAUDE.md would break the existing delegation pattern. The constraints belong in AGENTS.md (loaded every turn) since Claude violates them without being told.

## Acceptance Criteria

- [ ] AGENTS.md Hard Rules section includes a rule about Warp terminal escape sequences
- [ ] AGENTS.md Hard Rules section includes a rule about non-interactive shell / no `sudo`
- [ ] Constitution.md Architecture section includes an "Environment Constraints" subsection under "Always" for future extensibility
- [ ] No plugin files modified (no version bump needed)
- [ ] Existing AGENTS.md rules are not disrupted or reworded

## Non-goals

- Detecting the terminal type programmatically at session start
- Adding PreToolUse hooks to block escape sequences or sudo commands
- Documenting every possible environment quirk (only observed failures are worth documenting)

## Test Scenarios

- Given Claude is operating in Warp terminal, when it needs to rename or manipulate a terminal tab, then it should skip the attempt and explain that Warp does not support standard escape sequences for tab manipulation
- Given Claude needs elevated privileges to run a command, when `sudo` is unavailable in the non-interactive shell, then it should immediately provide manual instructions instead of attempting sudo
- Given a future session discovers a new environment constraint, when a contributor wants to document it, then the constitution.md Environment Constraints section provides a clear home for the new rule with an established pattern

## Technical Considerations

- **AGENTS.md token budget**: Adding two one-line rules is negligible. The current AGENTS.md is ~30 lines of hard rules. Two more lines will not materially affect system prompt size.
- **Enforcement level**: Documentation-only for now. The constitution.md principle "Never state conventions without tooling enforcement" applies to code conventions, not environment facts. Environment constraints are inherently informational -- there is no hook that can intercept "thinking about using escape sequences." If sudo-blocking proves necessary later, a PreToolUse hook matching `Bash(sudo *)` could be added.
- **Existing patterns**: The codebase already handles sudo gracefully in `check_deps.sh` (the ffmpeg/rclone install plan uses `sudo -n true` inline checks). The AGENTS.md rule reinforces this pattern at the instruction level.

## MVP

### AGENTS.md changes

Add two rules to the Hard Rules section:

```markdown
## Hard Rules

...existing rules...
- The host terminal is Warp. Standard ANSI escape sequences for tab renaming and manipulation do not work. Do not attempt automated terminal tab manipulation.
- The Bash tool runs in a non-interactive shell without `sudo` access. Do not attempt commands requiring elevated privileges -- provide manual instructions instead.
```

### constitution.md changes

Add a new subsection under Architecture > Always:

```markdown
## Architecture

### Always

...existing rules...
- Document environment-specific constraints (terminal capabilities, shell limitations) in AGENTS.md Hard Rules when Claude violates them without being told -- these are loaded every turn and prevent dead-end attempts
```

## References

- Issue: #394
- Source: Claude Code Insights report (2026-02-02 to 2026-03-03)
- Related pattern: `knowledge-base/plans/2026-02-27-feat-install-ffmpeg-rclone-on-demand-plan.md` (sudo handling)
- Files to modify:
  - `AGENTS.md`
  - `knowledge-base/overview/constitution.md`
