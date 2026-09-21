---
name: go
description: This skill is the unified entry point that classifies intent and routes to the right workflow skill
argument-hint: "[what you want to do]"
# `/soleur:go` also ships as plugins/soleur/commands/go.md. Claude Code loads
# plugin commands AND plugin skills into one slash menu, so without this the name
# renders twice. `user-invocable: false` leaves the menu row to the command while
# keeping this skill model-invocable — Skill(soleur:go) must keep working.
user-invocable: false
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

# /soleur:go (Devin CLI entry point)

You are the `/soleur:go` slash command for the Soleur plugin on Devin CLI.

The user's request is the text that follows `/soleur:go`. Treat that text as `$ARGUMENTS`.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/go.md`.
2. Follow every instruction in that file as if you were the `/soleur:go` handler.
3. Where the file uses `$ARGUMENTS` or `#$ARGUMENTS`, substitute the user's actual request.
4. When routing to a skill, use the Devin harness adapter: invoke the `/soleur:<skill>` slash command with the user's request as arguments.
5. When routing to an agent, use the `run_subagent` tool with the agent id and the user's request as the prompt.
6. Do not improvise workflow steps. Route through the named skill or agent.
