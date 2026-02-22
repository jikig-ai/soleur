---
title: Bundle External Plugin into Soleur via Hook + Script
category: implementation-patterns
module: soleur-plugin
severity: medium
tags: [plugin-architecture, hooks, bundling, one-shot]
symptoms: [external-plugin-dependency, one-shot-failure]
date: 2026-02-22
---

# Bundle External Plugin into Soleur via Hook + Script

## Problem

`/soleur:one-shot` depended on the external `ralph-loop` plugin. If that plugin was not installed, one-shot failed at step 1. The goal was to make one-shot self-contained.

## Solution

Ported the essential mechanism (stop hook + setup script) into Soleur's `hooks/` and `scripts/` directories. The one-shot command uses a `!` code block to run the setup script directly at command load time, avoiding the need for a separate command.

### Key Pattern: `!` Code Block for Script Execution

Commands can embed script execution using triple-backtick blocks with `!`:

```markdown
\`\`\`!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" "args here"
\`\`\`
```

This executes at command load time (before the LLM processes instructions). The script output becomes part of the prompt context. `${CLAUDE_PLUGIN_ROOT}` is expanded by the plugin loader.

### Files Added

- `plugins/soleur/hooks/hooks.json` -- Hook configuration (Stop event)
- `plugins/soleur/hooks/stop-hook.sh` -- Intercepts session exit, feeds prompt back
- `plugins/soleur/scripts/setup-ralph-loop.sh` -- Creates state file, parses args

### Files Modified

- `plugins/soleur/commands/soleur/one-shot.md` -- Uses `!` block instead of external command

## Key Insight

When bundling external plugins, prefer embedding the mechanism (hooks, scripts) over creating new user-facing commands. The user asked for "one-shot to work without external dependencies" -- not "expose ralph-loop as new commands." Internal infrastructure does not need user-facing surface area.

## Session Errors

1. **Over-scoped without confirmation** -- Created 2 new commands that the user did not ask for. Had to revert. Automated pipelines suppress design checkpoints; always confirm scope-expanding decisions.
2. **`$?` check under `set -e` is dead code** -- In the original ralph-loop stop-hook.sh, `$?` after a command substitution with `2>&1` is always 0 under `set -e`. Fixed by using `|| true` and checking emptiness instead.

## Prevention

- When porting external code, distinguish between "what's needed for the mechanism" (hooks, scripts) and "what creates user-facing surface area" (commands, skills). Only add the mechanism.
- In automated pipelines (one-shot), still pause for scope decisions if the implementation adds new user-facing components.
