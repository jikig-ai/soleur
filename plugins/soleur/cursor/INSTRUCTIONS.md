# Cursor CLI

This file is the slice 1 surface matrix for the Soleur plugin on the local Cursor CLI.

This plugin file registers no hook events. The manifest points `hooks` at `cursor/hooks-empty.json`, and that file's `hooks` object is empty. It is not a copy of the Claude or Devin registry, and it is not a live hook registry.

Slice 1 does not classify the session as `cursor`. Detection does not return `cursor` in this slice.

Unmeasured surfaces stay unmeasured. Whether the CLI loads `.claude/settings.json` is unmeasured. This file does not say other hook sources are off.

A 2026-10-07 Cursor CLI capture (`cursor-agent` `2026.10.01-e373342`) exited at authentication before any hook ran. The shape note is `cursor/2026-10-07-cli-hook-shape.md`. That session did not load `cursor/hooks-empty.json`, did not show a working directory, and did not show tool names. `CURSOR_AGENT` was unset on the CLI process. `CURSOR_INVOKED_AS=cursor-agent` was set on the CLI process and was not measured on a non-CLI Cursor process, so detection still does not return `cursor`. `.claude/settings.json` is not marked already-fires and it is not marked dead. No guard command was copied from it.

This slice does not call the plugin supported. `/go` and `/sync` stay bare. Every other skill is `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`. Cursor's `/plan`, `/help`, `/review`, and `/shell` are built-ins. Do not type those four for Soleur. Do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell. If a canonical file tells you to call those tools, stop. When `/go` or a stub names a skill, Read `plugins/soleur/skills/<name>/SKILL.md` and follow that file.

Local install prints `agent --plugin-dir` with the absolute plugin directory. This slice does not classify the session as cursor, does not run hooks, and does not block a commit.

No tools table is recorded here. Tool names stay unmeasured until a capture lists them.
