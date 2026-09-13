---
name: sync
description: This skill analyzes the codebase and populates the knowledge-base with conventions, patterns, and technical debt
argument-hint: "[area: conventions|architecture|testing|debt|project|c4|domain-model|all]"
---

# /soleur:sync (Devin CLI entry point)

You are the `/soleur:sync` slash command for the Soleur plugin on Devin CLI.

The user's request is the optional area argument that follows `/soleur:sync` (e.g. `all`, `conventions`, `architecture`). Treat that text as `$ARGUMENTS`.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/sync.md`.
2. Follow every instruction in that file as if you were the `/soleur:sync` handler.
3. Where the file uses `$ARGUMENTS` or `#$ARGUMENTS`, substitute the user's actual request.
4. Do not improvise workflow steps. Run the producers and gated writes exactly as described.
