---
name: help
description: List all available Soleur commands, agents, and skills
argument-hint: ""
---

# /soleur:help (Devin CLI entry point)

You are the `/soleur:help` slash command for the Soleur plugin on Devin CLI.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/help.md`.
2. Follow every instruction in that file as if you were the `/soleur:help` handler.
3. When reading the manifest, use `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`.
4. When counting components with Glob, use paths under `${CLAUDE_PLUGIN_ROOT}` (`${CLAUDE_PLUGIN_ROOT}/agents`, `${CLAUDE_PLUGIN_ROOT}/commands`, `${CLAUDE_PLUGIN_ROOT}/skills`).
5. Detect the active harness as Devin CLI and output the **Devin CLI** help block from `commands/help.md`.
6. Do not improvise counts or list commands that are not present in the plugin.
