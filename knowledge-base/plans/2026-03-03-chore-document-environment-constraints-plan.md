---
title: "chore: Document environment constraints (Warp terminal, no-sudo)"
type: chore
date: 2026-03-03
issue: "#394"
version_bump: none
deepened: 2026-03-03
---

# chore: Document environment constraints (Warp terminal, no-sudo)

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Technical Considerations, MVP)
**Research sources:** Warp GitHub issues, Claude Code issues, Claude Code hooks documentation, AGENTS.md best practices research, project learnings

### Key Improvements

1. **Warp constraint scoped more precisely**: Research revealed that Warp *does* support `\033]0;...\007` for tab title setting. The actual limitation is cursor position queries (`ESC[6n`) and other TUI escape sequences that Warp's tmux control mode intercepts. The rule wording is broadened to "automated terminal manipulation" rather than claiming tab renaming specifically fails.
2. **Sudo guard hook identified as future enhancement**: The existing guardrails.sh pattern (4 guards) can be extended with a Guard 5 matching `(^|&&|\|\||;)\s*sudo\s+` to make sudo blocking enforceable rather than advisory. This is documented as a follow-up, not an immediate requirement.
3. **Learnings integration**: Three institutional learnings directly apply -- "lean AGENTS.md" (token budget), "agent prompts: sharp edges only" (only what the model would get wrong), and "worktree enforcement hook" (documentation-then-hook progression pattern).

### New Considerations Discovered

- The constitution.md principle "Never state conventions without tooling enforcement" has a documented progression pattern in this project: document first (AGENTS.md rule), then add a hook when violations persist. The sudo constraint fits this pattern -- document now, add Guard 5 later if needed.
- AGENTS.md is currently ~30 lines of hard rules. ETH Zurich research shows context files increase reasoning tokens by 10-22%. Two additional one-line rules are within budget, but future constraints should be evaluated against cumulative cost.

## Overview

Claude occasionally assumes standard tool behaviors that do not hold in the project environment -- such as terminal escape sequences in Warp or sudo in non-interactive shells -- leading to dead-end attempts before falling back to manual instructions. This plan adds explicit environment constraints to the project's instruction files so Claude avoids these dead ends on every turn.

## Problem Statement

Two specific failure patterns have been observed (source: Claude Code Insights report, 2026-02-02 to 2026-03-03):

1. **Warp terminal escape sequences**: Claude used standard ANSI escape sequences to manipulate a terminal tab, which silently fail in Warp. The session ended as `not_achieved` because Claude did not know the sequences would be swallowed.
2. **Non-interactive sudo**: A `sudo` command could not execute in the non-interactive shell, forcing manual steps for a PATH precedence fix. Claude wasted turns attempting elevated commands before realizing it needed to print manual instructions instead.

Both are recoverable -- Claude eventually finds the right approach -- but they cost time and occasionally result in `not_achieved` sessions that should have been `achieved`.

### Research Insights: Warp Escape Sequence Behavior

Research into Warp's actual escape sequence support revealed a more nuanced picture:

- **Tab title setting works**: Warp supports `echo -ne "\033]0;MyTabName\007"` for setting tab titles ([Warp Tabs docs](https://docs.warp.dev/terminal/windows/tabs)). The Claude Code feature request ([#20441](https://github.com/anthropics/claude-code/issues/20441)) explicitly lists Warp as a compatible terminal for this sequence.
- **Cursor position queries fail**: Warp's tmux control mode (`-CC`) intercepts `ESC[6n` (Cursor Position Request) and does not forward responses to applications ([Warp #7739](https://github.com/warpdotdev/warp/issues/7739)). This breaks TUI frameworks (crossterm, ratatui, bubbletea, rich, textual).
- **Some ANSI sequences render as ASCII**: Certain escape sequences (e.g., from direnv) appear as literal `^[i` text instead of being processed ([Warp #4835](https://github.com/warpdotdev/Warp/issues/4835)).

**Implication for the rule wording**: The constraint should say "Do not attempt automated terminal manipulation via escape sequences" (broad) rather than "tab renaming does not work" (incorrect). The actual failure surface is cursor position queries and TUI rendering, not OSC title sequences.

## Proposed Solution

Add environment constraints as rules in the project instruction files. The constraints must be placed where Claude reads them on every turn (AGENTS.md) or on-demand (constitution.md), depending on violation frequency.

### Where to place each constraint

| Constraint | File | Rationale |
|-----------|------|-----------|
| Warp terminal: no automated terminal manipulation | `AGENTS.md` (Hard Rules) | Violates without being told -- matches AGENTS.md purpose |
| Non-interactive shell: no `sudo` | `AGENTS.md` (Hard Rules) | Violates without being told -- matches AGENTS.md purpose |
| Extensibility pattern for future constraints | `knowledge-base/overview/constitution.md` | Prefer section in constitution.md so future constraints have a defined home |

### Research Insights: Placement Decision

The "lean AGENTS.md" learning (2026-02-25) established the principle: "Keep only rules the agent would violate without being told on every turn." Both constraints pass this litmus test -- Claude has no way to discover Warp limitations or the lack of sudo without being told.

The "agent prompts: sharp edges only" learning reinforces this: "Only embed what the model would get wrong without explicit instruction." Claude's training data includes general terminal knowledge that assumes standard ANSI support and sudo availability. These environment-specific deviations are exactly the "sharp edges" that need documenting.

### Why not `.claude/settings.json`?

The `env` field in settings.json sets environment variables -- it does not accept free-text instructions. There is no Claude Code configuration field for "behavioral constraints." The instruction files (AGENTS.md, constitution.md) are the correct mechanism.

### Why not CLAUDE.md?

CLAUDE.md in this project is a pointer file (`@AGENTS.md`). Adding content directly to CLAUDE.md would break the existing delegation pattern. The constraints belong in AGENTS.md (loaded every turn) since Claude violates them without being told.

### Why not a PreToolUse hook (yet)?

The project follows a documented progression pattern: documentation first, then tooling enforcement when violations persist (see "worktree enforcement" learning, 2026-02-26). The worktree write guard followed this exact path -- AGENTS.md rule first, then PreToolUse hook when agents kept violating it.

For the sudo constraint specifically, a Guard 5 could be added to `guardrails.sh`:

```bash
# Guard 5: Block sudo commands in non-interactive shell
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*sudo\s+'; then
  echo '{"decision":"block","reason":"BLOCKED: sudo is not available in non-interactive shell. Provide manual instructions instead."}'
  exit 0
fi
```

This is deferred to a follow-up if documentation alone proves insufficient. The escape sequence constraint cannot be enforced via hook (there is no tool call to intercept -- the sequences would be embedded in `echo` or `printf` arguments within a Bash command, making regex matching unreliable).

## Acceptance Criteria

- [x] AGENTS.md Hard Rules section includes a rule about Warp terminal escape sequences
- [x] AGENTS.md Hard Rules section includes a rule about non-interactive shell / no `sudo`
- [x] Constitution.md Architecture > Always section includes a principle about documenting environment-specific constraints in AGENTS.md
- [x] No plugin files modified (no version bump needed)
- [x] Existing AGENTS.md rules are not disrupted or reworded

## Non-goals

- Detecting the terminal type programmatically at session start
- Adding PreToolUse hooks for sudo or escape sequences (follow-up if documentation is insufficient)
- Documenting every possible environment quirk (only observed failures are worth documenting)
- Fixing Warp's escape sequence handling upstream

## Test Scenarios

- Given Claude is operating in Warp terminal, when it needs to manipulate the terminal (cursor position, TUI rendering, tab control), then it should skip the attempt and explain that Warp does not reliably support automated terminal manipulation via escape sequences
- Given Claude needs elevated privileges to run a command, when `sudo` is unavailable in the non-interactive shell, then it should immediately provide manual instructions instead of attempting sudo
- Given a future session discovers a new environment constraint, when a contributor wants to document it, then the constitution.md principle directs them to add it to AGENTS.md Hard Rules with the established pattern
- Given the AGENTS.md token budget, when the two new rules are added, then the total Hard Rules section should remain under 35 lines (currently ~30)

## Technical Considerations

- **AGENTS.md token budget**: Adding two one-line rules is negligible. The current AGENTS.md is ~30 lines of hard rules. Per ETH Zurich research (Feb 2026), context files increase reasoning tokens by 10-22%, but the marginal cost of two additional lines is within acceptable bounds. The "lean AGENTS.md" learning reduced the file from 127 to 26 lines -- these two additions will not undo that work.

- **Enforcement level**: Documentation-only for now, following the project's documented progression pattern:
  1. Document the constraint in AGENTS.md (this PR)
  2. If violations persist, add a PreToolUse hook (future PR)

  The guardrails.sh already has 4 guards following this pattern. Guard 5 (sudo) is ready to add if needed.

- **Existing patterns**: The codebase already handles sudo gracefully in `check_deps.sh` (the ffmpeg/rclone install plan uses `sudo -n true` inline checks). The AGENTS.md rule reinforces this pattern at the instruction level.

- **Rule wording precision**: The Warp constraint must be broad enough to catch the actual failure (TUI escape sequences, cursor position queries) but not overclaim (tab title setting via OSC actually works). "Do not attempt automated terminal manipulation via escape sequences" is precise without being fragile.

## MVP

### AGENTS.md changes

Add two rules to the Hard Rules section, grouped together at the end:

```markdown
## Hard Rules

...existing rules...
- The host terminal is Warp. Do not attempt automated terminal manipulation via escape sequences (cursor position queries, TUI rendering, and similar sequences are intercepted by Warp's tmux control mode and silently fail).
- The Bash tool runs in a non-interactive shell without `sudo` access. Do not attempt commands requiring elevated privileges -- provide manual instructions instead.
```

### constitution.md changes

Add one principle to Architecture > Always:

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

### External References

- [Warp Tabs documentation](https://docs.warp.dev/terminal/windows/tabs) -- Tab title escape sequences
- [Warp #7739: Cursor position query failure](https://github.com/warpdotdev/warp/issues/7739) -- ESC[6n interception
- [Warp #4835: ANSI sequences rendered as ASCII](https://github.com/warpdotdev/Warp/issues/4835) -- direnv escape sequence failure
- [Claude Code #20441: Tab title sync](https://github.com/anthropics/claude-code/issues/20441) -- Confirms Warp supports OSC title
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) -- PreToolUse hook mechanism
- [AGENTS.md best practices](https://www.humanlayer.dev/blog/writing-a-good-claude-md) -- Context file optimization
- [ETH Zurich: Evaluating AGENTS.md](https://arxiv.org/abs/2602.11988) -- Token cost research

### Institutional Learnings Applied

- `knowledge-base/learnings/2026-02-25-lean-agents-md-gotchas-only.md` -- Token budget and "gotchas-only" principle
- `knowledge-base/learnings/agent-prompt-sharp-edges-only.md` -- Only document what the model would get wrong
- `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md` -- Documentation-then-hook progression pattern
- `knowledge-base/learnings/2026-02-24-guardrails-chained-commit-bypass.md` -- Guard regex pattern for chained commands
- `knowledge-base/learnings/2026-02-24-effortlevel-not-valid-settings-field.md` -- settings.json env field precedent
