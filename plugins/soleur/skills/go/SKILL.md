---
name: go
description: Unified entry point that classifies intent and routes to the right workflow skill
argument-hint: "[what you want to do]"
---

# /soleur:go (Devin CLI entry point)

You are the `/soleur:go` slash command for the Soleur plugin on Devin CLI.

The user's request is the text that follows `/soleur:go`. Treat that text as `$ARGUMENTS`.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/go.md`.
2. Follow every instruction in that file as if you were the `/soleur:go` handler.
3. Where the file uses `$ARGUMENTS` or `#$ARGUMENTS`, substitute the user's actual request.
4. When routing to a skill, use the Devin harness adapter: invoke the `/soleur:<skill>` slash command with the user's request as arguments.
5. When routing to an agent, use the `run_subagent` tool with the agent id and the user's request as the prompt.
6. Do not improvise workflow steps. Route through the named skill or agent.
