# Cursor CLI edit tool — 2026-10-11

This note records a Cursor CLI session that classified `/go`, refused one agent in words, and wrote one file outside the repository. It does not replace `2026-10-07-cli-hook-shape.md`, `2026-10-08-cli-hook-shape.md`, `2026-10-11-cli-hook-shape.md`, or `2026-10-11-repo-settings-shape.md`.

No email was stored. The trace recorded process arguments and did not record the environment.

This session is not the support-bar session.

## Session

The CLI was already logged in. This session did not start a login.

The command was `cursor-agent --print --trust`, with `--workspace` set to this worktree and `--plugin-dir` set to `plugins/soleur`, and `--output-format stream-json`. It did not pass `--mode ask` and it did not pass `--force`. The prompt asked the model to classify `/go` for a request to explore whether a status line should say pong, and to implement nothing. If the route was brainstorm, the prompt said to name the exit gates and not run them. It asked for one spawn of `/soleur-product-cpo` or a refusal in words. It asked for one write of a file outside the git workspace, using the file tool. It forbade commit, push, issue creation, edits inside the git workspace, and creating a git worktree.

The process exited 0. Standard error was empty. After the session, `git status --porcelain` in this worktree was empty. The file outside the repository contains the word probe.

The stream had one `editToolCall`. That call was an arguments event, then a result whose key is `success`. The stream also had `readToolCall`, `grepToolCall`, `globToolCall`, and `getMcpToolsToolCall`. It had no `shellToolCall`. It had no Skill tool and no Task tool.

The model reply was:

```text
ROUTE brainstorm; exit gates: soleur:compound then commit/push remaining artifacts; not run
SPAWN refused: cannot type /soleur-product-cpo — no slash_command tool; Task forbidden on Cursor
WROTE /tmp/cursor-9608-bar/probe.txt
```

`/go` classified the request as brainstorm. The exit gates were named and were not run. The agent spawn was refused in words. One pipeline skill did not finish its gates.

## What exec'd

A command counts only when the executable basename is the script, or the executable is `bash`, `sh`, `python`, `python3`, or `node` and a later argument basename is the script. A basename inside prose is not an exec.

SessionStart commands exec'd again: `session-rules-loader.sh`, `supabase-loopback-warn.sh`, `memory-backstop-resolve.sh`, and `ensure-kb-index.sh`. Those rows stay `already-fires` from `2026-10-11-repo-settings-shape.md`. This session had no shell tool, so it does not re-prove the Bash rows. Those Bash rows stay `already-fires` from that earlier note.

`hooks/hooks.json` SessionStart commands exec'd while `cursor/hooks-empty.json` stayed empty: `codex-session-start.sh`, `devin-session-start.sh`, `welcome-hook.sh`, and `compaction-state.sh`. A home command, `herdr-agent-state.sh`, exec'd. That file is not this repository's `.claude/settings.json`. `memory-backstop-resolve.sh` exec'd `memory-backstop.sh`. `ensure-kb-index.sh` led to `generate-kb-index.sh`. Those children are not separate settings rows.

These write-family scripts exec'd once each, as the executable, on the one `editToolCall`:

`worktree-write-guard.sh`, `guardrails.sh`, `security_reminder_hook.py`, `skill-security-scan-write.sh`, `iac-plan-write-guard.sh`, `new-scheduled-cron-prefer-inngest.sh`, `no-memory-write.sh`, `kb-domain-allowlist-guard.sh`, and `docs-cli-verification.sh`.

`security_reminder_hook.py` has one settings matcher, `Edit`. That row is `already-fires`.

`skill-security-scan-write.sh` has `Write` and `^write$`, and it exec'd once. `worktree-write-guard.sh`, `iac-plan-write-guard.sh`, `new-scheduled-cron-prefer-inngest.sh`, `guardrails.sh`, `no-memory-write.sh`, and `kb-domain-allowlist-guard.sh` each have a combined write matcher and a `^write$` matcher, and each exec'd once. `docs-cli-verification.sh` is PostToolUse with `Write|Edit` and `^write$`, and it exec'd once. One exec does not separate those matchers. `^write$` is not marked `already-fires`. Those rows stay `unmeasured` with reason `script-execd-matcher-unseparated`.

`operator-stage-approval.sh` exec'd once. Its matcher is an alternation, and that alternation is not separated. It is not a settings row. It was not copied.

These scripts did not exec: `monitor-supersede-guard.sh`, `durable-reminder-prefer-inngest.sh`, `pencil-open-guard.sh`, `skill-invocation-logger.sh`, `pre-ask-technical-fork-gate.sh`, `agent-token-tee.sh`, `pencil-collapse-guard.sh`, `phase-surface-hint.sh`, `skill-context-queries.sh`, `monitor-arm-recorder.sh`, `prod-write-defer-gate.sh`, `post-dispatch-watch-gate.sh`, `rule-incident-marker-capture.sh`, `browser-snapshot-credential-guard.sh`, `stop-hook.sh`, and `unkept-promise-hook.sh`. Skill, Task, Monitor, CronCreate, AskUserQuestion, and pencil matchers stay `unmeasured`. They are not `dead`.

## Ledger rows this session changes

```text
repo-claude-project	.claude/hooks/worktree-write-guard.sh	PreToolUse	Write|Edit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/worktree-write-guard.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/security_reminder_hook.py	PreToolUse	Edit	already-fires	edit-matcher-execd-on-edit-tool	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/skill-security-scan-write.sh	PreToolUse	Write	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/skill-security-scan-write.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/iac-plan-write-guard.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/iac-plan-write-guard.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/new-scheduled-cron-prefer-inngest.sh	PreToolUse	Write|Edit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/new-scheduled-cron-prefer-inngest.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/docs-cli-verification.sh	PostToolUse	Write|Edit	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
repo-claude-project	.claude/hooks/docs-cli-verification.sh	PostToolUse	^write$	unmeasured	script-execd-matcher-unseparated	shape-note-2026-10-11-edit-tool
```

## Registry decision

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. The commands this capture showed the CLI can run already fire from `.claude/settings.json` or from `hooks/hooks.json`. The unseparated matchers were not copied. The matchers that did not exec were not copied. This repository has no `.cursor/hooks.json`. Guard 3's empty-object row stays.

## Support bar

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. This session showed the classification and the refusal. It did not show a pipeline skill finishing its gates. It did not show the full guard set firing. The plugin is not supported. ADR-274 stays `adopting`. A pull request that cites this note does not close issue 9608.
