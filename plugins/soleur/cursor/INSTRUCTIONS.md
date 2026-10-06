# Cursor CLI

This file is the slice 1 surface matrix for the Soleur plugin on the local Cursor CLI.

This plugin file registers no hook events. The manifest points `hooks` at `cursor/hooks-empty.json`, and that file's `hooks` object is empty. It is not a copy of the Claude or Devin registry, and it is not a live hook registry.

Slice 1 does not classify the session as `cursor`. Detection does not return `cursor` in this slice.

Unmeasured surfaces stay unmeasured. Whether the CLI loads `.claude/settings.json` is unmeasured. This file does not say other hook sources are off.

This slice does not call the plugin supported. `/go` and `/sync` stay bare. Every other skill is `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`. Cursor's `/plan`, `/help`, `/review`, and `/shell` are built-ins. Do not type those four for Soleur. Do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell. If a canonical file tells you to call those tools, stop. Do not follow a line that names the Skill tool or the Task tool.

Local install prints `agent --plugin-dir` with the absolute plugin directory. This slice does not classify the session as cursor, does not run hooks, and does not block a commit.

No tools table is recorded here. Tool names stay unmeasured until a capture lists them.
