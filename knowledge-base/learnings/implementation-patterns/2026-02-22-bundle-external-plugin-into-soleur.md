---
title: Bundle External Plugin into Soleur via Hook + Script
category: implementation-patterns
module: soleur-plugin
severity: medium
tags: [plugin-architecture, hooks, bundling, one-shot]
symptoms: [external-plugin-dependency, one-shot-failure]
date: 2026-02-22
synced_to: [soleur:compound, constitution]
---

# Bundle External Plugin into Soleur via Hook + Script

## Problem

`/soleur:one-shot` depended on the external `ralph-loop` plugin. If that plugin was not installed, one-shot failed at step 1. The goal was to make one-shot self-contained.

## Solution

Ported the essential mechanism (stop hook + setup script) into Soleur's `hooks/` and `scripts/` directories. The one-shot command instructs the LLM to run the setup script as its first step via the Bash tool.

### Key Pattern: LLM-Executed Script in Command Instructions

Commands should instruct the LLM to run scripts via the Bash tool rather than using `!` code blocks. The `!` block syntax triggers auto-execution at command load time, which fails permission checks because it bypasses the normal tool approval flow. The `allowed-tools` frontmatter field also does not resolve this.

**Do NOT use (fails permission check even with allowed-tools):**

```markdown
\`\`\`!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" "args here"
\`\`\`
```

**Use instead (LLM runs via Bash tool with normal approval):**

```markdown
**Step 0: Setup.** Run this command via the Bash tool:
\`\`\`bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh "args here"
\`\`\`
```

`${CLAUDE_PLUGIN_ROOT}` is expanded by the plugin loader in all command/skill text, not just `!` blocks.

### Files Added

- `plugins/soleur/hooks/hooks.json` -- Hook configuration (Stop event)
- `plugins/soleur/hooks/stop-hook.sh` -- Intercepts session exit, feeds prompt back
- `plugins/soleur/scripts/setup-ralph-loop.sh` -- Creates state file, parses args

### Files Modified

- `plugins/soleur/commands/soleur/one-shot.md` -- Explicit LLM step instead of `!` block

## Key Insight

When bundling external plugins, prefer embedding the mechanism (hooks, scripts) over creating new user-facing commands. The user asked for "one-shot to work without external dependencies" -- not "expose ralph-loop as new commands." Internal infrastructure does not need user-facing surface area.

## Session Errors

1. **Over-scoped without confirmation** -- Created 2 new commands that the user did not ask for. Had to revert. Automated pipelines suppress design checkpoints; always confirm scope-expanding decisions.
2. **`$?` check under `set -e` is dead code** -- In the original ralph-loop stop-hook.sh, `$?` after a command substitution with `2>&1` is always 0 under `set -e`. Fixed by using `|| true` and checking emptiness instead.
3. **`!` code block fails permission check** -- The `!` auto-execution syntax bypasses the normal Bash tool approval flow. Claude Code's permission system blocks it with "This command requires approval". Two prior fixes (#225 `$()` removal, #241 `allowed-tools` frontmatter) did not resolve this. Fixed by converting to an explicit LLM instruction step that runs via the Bash tool.

## Prevention

- When porting external code, distinguish between "what's needed for the mechanism" (hooks, scripts) and "what creates user-facing surface area" (commands, skills). Only add the mechanism.
- In automated pipelines (one-shot), still pause for scope decisions if the implementation adds new user-facing components.
