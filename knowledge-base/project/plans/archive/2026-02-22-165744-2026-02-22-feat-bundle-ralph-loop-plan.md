---
title: Bundle ralph-loop into Soleur Plugin
type: feat
date: 2026-02-22
issue: "#221"
---

# Bundle ralph-loop into Soleur Plugin

## Overview

The `/soleur:one-shot` command depends on the external `ralph-loop` plugin (Apache 2.0, by Anthropic). If that plugin is not installed, one-shot fails at step 1. Bundle ralph-loop's 3 commands, 1 hook, and 1 script directly into Soleur so one-shot works out of the box.

## Problem Statement

`one-shot.md:11` calls `/ralph-loop:ralph-loop` -- a command from a separate marketplace plugin. Users who install Soleur but not ralph-loop get a silent failure on one-shot's first step.

## Proposed Solution

Port the ralph-loop plugin (3 commands, 1 stop hook, 1 setup script) into `plugins/soleur/` under the `soleur:` namespace. Update one-shot to reference the bundled version.

## Technical Approach

### Files to Create

| File | Source | Purpose |
|------|--------|---------|
| `plugins/soleur/hooks/hooks.json` | New | Hook configuration for stop hook |
| `plugins/soleur/hooks/stop-hook.sh` | Port from `ralph-loop/hooks/stop-hook.sh` | Core loop mechanism -- intercepts session exit |
| `plugins/soleur/scripts/setup-ralph-loop.sh` | Port from `ralph-loop/scripts/setup-ralph-loop.sh` | Creates state file, parses args |
| `plugins/soleur/commands/soleur/ralph-loop.md` | Port from `ralph-loop/commands/ralph-loop.md` | `/soleur:ralph-loop` command |
| `plugins/soleur/commands/soleur/cancel-ralph.md` | Port from `ralph-loop/commands/cancel-ralph.md` | `/soleur:cancel-ralph` command |

### Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/commands/soleur/one-shot.md:11` | `/ralph-loop:ralph-loop` -> `/soleur:ralph-loop` |
| `plugins/soleur/commands/soleur/help.md` | Add ralph-loop commands to help output |
| `plugins/soleur/.claude-plugin/plugin.json` | Bump version 2.23.15 -> 2.24.0, update command count (8 -> 10) |
| `plugins/soleur/CHANGELOG.md` | Add entry for v2.24.0 |
| `plugins/soleur/README.md` | Update command count, add ralph-loop to commands table |

### Files NOT Ported

- `ralph-loop/commands/help.md` -- Merged into existing `/soleur:help` instead of creating `/soleur:help-ralph` (avoids command proliferation)
- `ralph-loop/LICENSE` -- Soleur already uses Apache 2.0; add attribution comment in ported scripts
- `ralph-loop/README.md` -- Content absorbed into CHANGELOG and help command

### Porting Notes

1. **Namespace change:** Commands move from `ralph-loop:*` to `soleur:*`. The `name:` frontmatter field in each command.md controls this.
2. **`${CLAUDE_PLUGIN_ROOT}`:** Already used in the original; will resolve to Soleur's plugin root automatically.
3. **Hook discovery:** The `hooks/hooks.json` file follows Claude Code's plugin hook API. The `Stop` event type intercepts session exit.
4. **State file path:** Stays at `.claude/ralph-loop.local.md` (already `.gitignore`d by naming convention `.local.`).
5. **Shell scripts:** Add `set -euo pipefail` (already present in originals). Add attribution header per Apache 2.0.

## Acceptance Criteria

- [x] `/soleur:one-shot` works without the external ralph-loop plugin installed
- [x] `/soleur:ralph-loop "test" --completion-promise "DONE"` starts a loop
- [x] `/soleur:cancel-ralph` cancels an active loop
- [x] `/soleur:help` documents the new ralph-loop commands
- [x] Stop hook intercepts session exit and feeds prompt back
- [ ] Version bumped to 2.24.0 across plugin.json, CHANGELOG.md, README.md

## Test Scenarios

- Given no external ralph-loop plugin, when running `/soleur:one-shot`, then step 1 activates the bundled ralph-loop
- Given an active ralph-loop, when Claude outputs `<promise>DONE</promise>`, then the loop exits cleanly
- Given an active ralph-loop, when running `/soleur:cancel-ralph`, then the state file is removed and loop stops
- Given `--max-iterations 3`, when 3 iterations complete, then loop auto-stops

## Context

- Source: `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/ralph-loop/`
- License: Apache 2.0 (Anthropic) -- compatible with Soleur's Apache 2.0
- Version bump: MINOR (new commands) -- 2.23.15 -> 2.24.0
- Issue: #221
