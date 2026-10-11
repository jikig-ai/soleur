# Cursor CLI

This file is the surface matrix for the Soleur plugin on the local Cursor CLI.

This plugin file registers no hook events. The manifest points `hooks` at `cursor/hooks-empty.json`, and that file's `hooks` object is empty. It is not a copy of the Claude or Devin registry, and it is not a live hook registry.

A nonempty `CURSOR_INVOKED_AS` classifies the session as `cursor`. `CLAUDECODE` plus that marker still returns `claude`. `CURSOR_AGENT` is not the marker. Hooks are not a live registry yet, and this does not block a commit.

The repository `.claude/settings.json` is unmeasured. A scratch capture is not that file. This file does not say other hook sources are off.

A 2026-10-07 Cursor CLI capture (`cursor-agent` `2026.10.01-e373342`) exited at authentication before any hook ran. The shape note is `cursor/2026-10-07-cli-hook-shape.md`. That session did not load `cursor/hooks-empty.json`, did not show a working directory, and did not show tool names. `CURSOR_AGENT` was unset on the CLI process. `CURSOR_INVOKED_AS=cursor-agent` was set on the CLI process. `.claude/settings.json` is not marked already-fires and it is not marked dead. No guard command was copied from it.

A 2026-10-08 capture of the same CLI, after login, ran scratch probes. The shape note is `cursor/2026-10-08-cli-hook-shape.md`. Project `sessionStart` and `preToolUse` ran, and the tool name was `Read`. The hook stdin has `workspace_roots` and no `cwd` key. A probe at the manifest path `./cursor/hooks-empty.json` ran `sessionStart`. The repository file stays empty. `CURSOR_INVOKED_AS` was nonempty on the CLI process and `CURSOR_AGENT` was unset. The repository guard file is not marked already-fires and it is not marked dead. No guard command was copied. No email was stored.

A 2026-10-11 measurement launched Cursor `3.24.12` from the official Linux AppImage with a fresh user-data directory. The idle editor process tree had no `CURSOR_*` names. Nonempty `CURSOR_INVOKED_AS` is the CLI marker. The hidden IDE agent terminal was not started. The shape note is `cursor/2026-10-11-cli-hook-shape.md`. No email was stored.

This plugin is not called supported. `/go` and `/sync` stay bare. Every other skill is `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`. Cursor's `/plan`, `/help`, `/review`, and `/shell` are built-ins. Do not type those four for Soleur. Do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell. If a canonical file tells you to call those tools, stop. When `/go` or a stub names a skill, Read `plugins/soleur/skills/<name>/SKILL.md` and follow that file.

Local install prints `agent --plugin-dir` with the absolute plugin directory. A nonempty `CURSOR_INVOKED_AS` classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

No Soleur tools table is recorded here. The 2026-10-08 capture listed the tool name `Read` and did not list a poll tool.
