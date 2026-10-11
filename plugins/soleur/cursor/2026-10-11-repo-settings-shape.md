# Cursor CLI repository settings — 2026-10-11

<!-- markdownlint-disable MD010 -->

This note records which commands in the repository `.claude/settings.json` already fire when the Cursor CLI workspace is this repository. It does not replace `2026-10-07-cli-hook-shape.md`, `2026-10-08-cli-hook-shape.md`, or `2026-10-11-cli-hook-shape.md`.

No email was stored. The trace recorded process arguments and did not record the environment.

## Session

The CLI was already logged in. This session did not start a login.

The command was `cursor-agent --print --trust`, with `--workspace` set to this worktree, `--plugin-dir` set to `plugins/soleur`, `--output-format stream-json`, and `--mode ask`. The prompt asked the model to run the shell command `true`, reply `pong`, and leave files unchanged. The process exited 0. The stream contained one `shellToolCall`. After the session, `git status --porcelain` in this worktree was empty.

## Repository settings

`.claude/settings.json` in this worktree was the guard file. Its SessionStart commands exec'd. Its PreToolUse and PostToolUse commands whose matcher is `Bash` exec'd for that shell tool. Those rows are `already-fires`. Copying them into another registry would run them twice.

Matchers this session did not exercise stay `unmeasured`. They are not `dead`. A script that also has a Bash row is `already-fires` only on that Bash row. Its other matchers stay `unmeasured` with reason `script-ran-via-another-matcher`, because the exec is explained by the Bash row.

No guard command was copied.

## Commands

Each line is one ledger row for this session.

```text
repo-claude-project	.claude/hooks/session-rules-loader.sh	SessionStart	startup|resume|clear|compact	already-fires	session-start-command-execd	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/supabase-loopback-warn.sh	SessionStart	startup|resume|clear|compact	already-fires	session-start-command-execd	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/memory-backstop-resolve.sh	SessionStart	startup|resume|clear|compact	already-fires	session-start-command-execd	shape-note-2026-10-11-repo-settings
repo-claude-project	scripts/ensure-kb-index.sh	SessionStart	startup|resume|clear|compact	already-fires	session-start-command-execd	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pre-merge-rebase.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pre-merge-auto-close-scan.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/ship-unpushed-commits-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/ship-operator-step-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/ship-soak-followthrough-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/ship-net-issue-flow-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/follow-through-directive-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/context-reviewed-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/cla-signed-author-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/ship-runbook-ssh-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/prod-write-defer-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/git-commit-secret-scan.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/brand-hex-commit-gate.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/doppler-secrets-delete-redirect.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/background-poll-prefer-monitor.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pkill-self-match-guard.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	plugins/soleur/hooks/browser-snapshot-credential-guard.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	Monitor	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/monitor-supersede-guard.sh	PreToolUse	Monitor	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/prod-write-defer-gate.sh	PreToolUse	Monitor	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/worktree-write-guard.sh	PreToolUse	Write|Edit	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/worktree-write-guard.sh	PreToolUse	^write$	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	^write$	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/security_reminder_hook.py	PreToolUse	Edit	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/skill-security-scan-write.sh	PreToolUse	Write	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/skill-security-scan-write.sh	PreToolUse	^write$	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/iac-plan-write-guard.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/iac-plan-write-guard.sh	PreToolUse	^write$	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/new-scheduled-cron-prefer-inngest.sh	PreToolUse	Write|Edit	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/new-scheduled-cron-prefer-inngest.sh	PreToolUse	^write$	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/durable-reminder-prefer-inngest.sh	PreToolUse	CronCreate	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pencil-open-guard.sh	PreToolUse	mcp__pencil__open_document	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/skill-invocation-logger.sh	PreToolUse	Skill	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	^write$	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/no-memory-write.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	Write|Edit|MultiEdit|NotebookEdit	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	^write$	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/kb-domain-allowlist-guard.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/grep-rewrite.sh	PreToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	AskUserQuestion	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pre-ask-technical-fork-gate.sh	PreToolUse	AskUserQuestion	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/guardrails.sh	PreToolUse	^ask_user_question$	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pre-ask-technical-fork-gate.sh	PreToolUse	^ask_user_question$	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/docs-cli-verification.sh	PostToolUse	Write|Edit	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/docs-cli-verification.sh	PostToolUse	^write$	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/agent-token-tee.sh	PostToolUse	Task	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/pencil-collapse-guard.sh	PostToolUse	mcp__pencil__open_document	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/phase-surface-hint.sh	PostToolUse	Skill	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/skill-context-queries.sh	PostToolUse	Skill	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/rule-incident-marker-capture.sh	PostToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/post-dispatch-watch-gate.sh	PostToolUse	Bash	already-fires	bash-matcher-execd-on-shell-tool	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/post-dispatch-watch-gate.sh	PostToolUse	Monitor	unmeasured	script-ran-via-another-matcher	shape-note-2026-10-11-repo-settings
repo-claude-project	.claude/hooks/monitor-arm-recorder.sh	PostToolUse	Monitor|TaskStop	unmeasured	matcher-not-exercised	shape-note-2026-10-11-repo-settings
```

## Other sources in the same session

`hooks/hooks.json` SessionStart commands exec'd while `cursor/hooks-empty.json` stayed empty: `codex-session-start.sh`, `devin-session-start.sh`, `welcome-hook.sh`, and `compaction-state.sh`. Those commands already fire from the Claude plugin registry. This session did not exec `operator-stage-approval.sh`, `stop-hook.sh`, or `unkept-promise-hook.sh`. Those three are not marked `dead`.

A home SessionStart command, `herdr-agent-state.sh`, exec'd. That file is not this repository's `.claude/settings.json`.

`memory-backstop-resolve.sh` exec'd `memory-backstop.sh`. `ensure-kb-index.sh` was invoked with `--soft`, and `generate-kb-index.sh` exec'd from that command. Those two are not separate settings rows.

## Registry decision

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. The commands this capture showed the CLI can run already fire from `.claude/settings.json` or from `hooks/hooks.json`. The unmeasured matchers were not shown to run, so they were not copied. This repository has no `.cursor/hooks.json`. Guard 3's empty-object row stays.

## Support bar

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. This session did not show those events. Bash matchers fired. The other matchers did not. The plugin is not supported. ADR-274 stays `adopting`. A pull request that cites this note does not close issue 9608.
