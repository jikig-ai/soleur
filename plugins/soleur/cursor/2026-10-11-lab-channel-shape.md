# Cursor CLI lab channel — 2026-10-11

This note records a channel switch of the installed Cursor CLI. It does not replace `2026-10-07-cli-hook-shape.md`, `2026-10-08-cli-hook-shape.md`, `2026-10-11-cli-hook-shape.md`, `2026-10-11-repo-settings-shape.md`, `2026-10-11-edit-tool-shape.md`, or `2026-10-11-matcher-rewrite-shape.md`.

No email was stored.

This measurement is not the support-bar session.

## Install

`cursor-agent get-channel` printed nothing on `2026.10.01-e373342`, and `cursor-agent about` called that build up to date. The allowed channel values in that bundle are `static`, `prod`, `lab`, and `prod-stable-internal`. `prod-stable-internal` is fetched as `prod`. `static` does not download a build. `cursor-agent set-channel lab` downloaded `2026.10.10-6b851c2` and replaced the `~/.local/bin/cursor-agent` symlink. `cursor-agent get-channel` then printed `lab`. `cursor-agent --version` printed `2026.10.10-6b851c2`. The `2026.10.01-e373342` directory stayed on disk.

## Matcher rewrite

The hook rewrite slice in `index.js` is the same 3749 bytes in both builds. It starts at the map `{Bash:"Shell",Read:"Read",Write:"Write",Edit:"Write",Glob:null,Grep:"Grep",WebFetch:"WebFetch",WebSearch:"WebSearch",Task:"Task"}` and ends at `new RegExp(e.matcher).test(t)`. PreToolUse and PostToolUse matchers are still split on `|` before that test.

`AskUserQuestion`, `CronCreate`, and `ask_user_question` occur zero times in both `index.js` files. `toolName:"Skill"`, `toolName:"Monitor"`, `toolName:"Task"`, and `toolName:"Write"` occur zero times in both files.

No scratch session was run. No pipeline skill was run. `one-shot`, `brainstorm`, `drain-labeled-backlog`, and `drain-prs` still do not finish their gates without a commit, a push, or an issue or pull-request write.

## Ledger

No ledger row changes. The rows recorded by `2026-10-11-matcher-rewrite-shape.md` stay as written. `^write$` stays unmeasured. `Skill`, `AskUserQuestion`, `CronCreate`, and `Monitor` stay unmeasured. `Task` and pencil stay unmeasured. They are not `dead`.

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. No guard command was copied. This repository has no `.cursor/hooks.json`.

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. `Skill`, `AskUserQuestion`, `CronCreate`, `Monitor`, and `^write$` cannot be shown to fire on `2026.10.10-6b851c2`. The full guard set did not fire. The plugin is not supported. ADR-274 stays `adopting`. Draft pull request 9745 stays a draft. A pull request that cites this note does not close issue 9608.
