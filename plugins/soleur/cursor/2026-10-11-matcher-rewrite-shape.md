# Cursor CLI matcher rewrite — 2026-10-11

<!-- markdownlint-disable MD010 -->

This note records how Cursor CLI `2026.10.01-e373342` rewrites Claude hook matchers, and which repository rows that separates. It does not replace `2026-10-07-cli-hook-shape.md`, `2026-10-08-cli-hook-shape.md`, `2026-10-11-cli-hook-shape.md`, `2026-10-11-repo-settings-shape.md`, or `2026-10-11-edit-tool-shape.md`.

No email was stored.

This session is not the support-bar session.

## Pipeline skills

`PIPELINE_SKILLS` in `plugins/soleur/lib/workflow-fidelity.ts` names `one-shot`, `brainstorm`, `drain-labeled-backlog`, and `drain-prs`.

`brainstorm` exits through `git commit`, `git push`, and `gh issue create`. `one-shot` finishes at a merged pull request. `drain-labeled-backlog` finishes by delegating to `one-shot`. Its `--dry-run` flag and the empty-cluster exit stop before that delegation. `drain-prs` finishes by merging pull requests. Its `--dry-run` flag prints the tier table and does not merge.

None of the four finishes every exit gate without a commit, a push, or an issue or pull-request write. A dry run is not that finish. No pipeline skill was run for this note.

## Matcher rewrite

Measured in `index.js` of `cursor-agent` `2026.10.01-e373342`. PreToolUse and PostToolUse matchers are split on `|` before `new RegExp(matcher).test(tool_name)`.

The map sends `Bash` to `Shell`, `Read` to `Read`, `Write` to `Write`, `Edit` to `Write`, `Grep` to `Grep`, `WebFetch` to `WebFetch`, `WebSearch` to `WebSearch`, and `Task` to `Task`. `Glob` is dropped. A `mcp__` name of at least three `__`-separated parts becomes `MCP:` plus the remainder after the second `__`, so `mcp__pencil__open_document` becomes `MCP:open_document`. A known value is substituted once. An unknown token is kept.

`Write|Edit` becomes `Write`. `Write|Edit|MultiEdit|NotebookEdit` becomes `Write|MultiEdit|NotebookEdit`. `^write$`, `Skill`, `AskUserQuestion`, `^ask_user_question$`, `CronCreate`, and `Monitor` stay as written.

An empty matcher, `*`, a missing tool name, or a matcher that is not a valid regular expression matches every hook.

The same bundle has `toolName:"Write"`. It has no `toolName:"write"`, no `toolName:"Edit"`, no `toolName:"Task"`, no `toolName:"Skill"`, no `toolName:"Bash"`, and no `toolName:"Monitor"`. The strings `AskUserQuestion` and `CronCreate` are absent. `askQuestion` is present and does not match `AskUserQuestion` or `^ask_user_question$`. `_toolName:"task"` is present and does not match `Task`.

## Scratch stdin

The scratch workspace was `/tmp/cursor-9608-matcher-probe`. It is not this repository. The command was `cursor-agent --print --trust`, with `--workspace` set to that directory and `--output-format stream-json`. It did not pass `--plugin-dir`, `--mode ask`, or `--force`. The prompt asked for `out.txt` whose only contents are the word probe. It forbade a shell command, reading other files, and spawning a subagent.

The process exited 0. Standard error was empty. The stream's tool case was `editToolCall`. The result subtype was `success`. The file contains the word probe. The model also read a file. The hook log lines were:

```text
preToolUse	Read
preToolUse	Write
postToolUse	Write
```

The scratch hook `tool_name` for `editToolCall` is `Write`. The logger stored `hook_event_name` and `tool_name` only. This scratch did not load this repository's `.claude/settings.json`.

## What that separates

The edit-tool session exec'd `security_reminder_hook.py` on one `editToolCall`. Its only matcher is `Edit`. `new RegExp("Edit").test("Write")` is false, so that exec is the rewrite of `Edit` to `Write`. That row stays `already-fires` on `shape-note-2026-10-11-edit-tool`.

The same rewrite makes `Write` and the combined write matchers match tool name `Write`. Those eight rows are `already-fires` with reason `write-matcher-execd-tool-name-Write`.

`^write$` is preserved. `new RegExp("^write$").test("Write")` is false. The eight `^write$` rows stay `unmeasured` with reason `matcher-preserved-does-not-match-tool-name-Write`. They are not `already-fires`. They are not `dead`.

`Skill`, `AskUserQuestion`, `^ask_user_question$`, `CronCreate`, and `Monitor` cannot match a hook tool name on this CLI. Their rows stay `unmeasured`. They are not `dead`.

`Task` is preserved as `Task`. No executor uses `toolName:"Task"`. `_toolName:"task"` does not match `Task`. That row stays `unmeasured`. It is not `dead`.

`mcp__pencil__open_document` would become `MCP:open_document` and can fire only when that MCP tool is called. It was not called. Those rows stay `unmeasured`. They are not `dead`.

## Ledger rows this note changes

```text
repo-claude-project	.claude/hooks/worktree-write-guard.sh	PreToolUse	Write|Edit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/worktree-write-guard.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/skill-security-scan-write.sh	PreToolUse	Write	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/skill-security-scan-write.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/iac-plan-write-guard.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/iac-plan-write-guard.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/new-scheduled-cron-prefer-inngest.sh	PreToolUse	Write|Edit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/new-scheduled-cron-prefer-inngest.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/docs-cli-verification.sh	PostToolUse	Write|Edit	already-fires	write-matcher-execd-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
repo-claude-project	.claude/hooks/docs-cli-verification.sh	PostToolUse	^write$	unmeasured	matcher-preserved-does-not-match-tool-name-Write	shape-note-2026-10-11-matcher-rewrite
```

## Registry decision

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. The commands this measurement showed the CLI can run already fire from `.claude/settings.json` or from `hooks/hooks.json`. The preserved matchers were not copied. The matchers that cannot be shown were not copied. This repository has no `.cursor/hooks.json`. Guard 3's empty-object row stays.

## Support bar

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. No pipeline skill finishes its gates without a commit, a push, or an issue or pull-request write. `Skill`, `AskUserQuestion`, `CronCreate`, `Monitor`, and `^write$` cannot be shown to fire. The full guard set did not fire. The plugin is not supported. ADR-274 stays `adopting`. Draft pull request 9745 stays a draft. A pull request that cites this note does not close issue 9608.
