# Cursor CLI hook shape — 2026-10-07

CLI binary: `cursor-agent` `2026.10.01-e373342` (`cursor-agent --version`).
`cursor-agent status` printed `Not logged in`. `cursor-agent about` printed `User Email: Not logged in`. No email was stored.

Host facts for this capture:

- No `~/.cursor` directory, so `~/.cursor/hooks.json` was absent.
- `/etc/cursor/hooks.json` was absent.
- No process whose command contained `cursor` was running, other than the CLI process this capture started.
- No `cursor` desktop binary was on `PATH`. A non-CLI Cursor process was not measured.

## Session

Command, from a scratch workspace outside this repository:

`cursor-agent --print --trust --workspace <scratch> --plugin-dir <probe-plugin> --mode ask`

Exit code 1. Stderr:

`Error: Authentication required. Please run 'agent login' first, or set CURSOR_API_KEY environment variable.`

The scratch workspace held three probe commands that append a log and then exit. None of them ran:

- project `.cursor/hooks.json` on `sessionStart` and `beforeSubmitPrompt`
- project `.claude/settings.json` on `SessionStart`
- a plugin whose manifest `hooks` field was `./cursor/hooks-empty.json`, with one `sessionStart` command in that file

No hook log was written. This session did not load a hook source. That is an authentication exit before the agent loop, not a measurement that the CLI ignores those paths.

`session-exited-at-auth`

## Marker

On the CLI process, during both `cursor-agent --version` and the authentication failure above, the only environment name starting with `CURSOR_` was `CURSOR_INVOKED_AS`, and its value was `cursor-agent`. `CURSOR_AGENT` was unset.

A non-CLI shell on the same host had `CURSOR_INVOKED_AS` unset and `CURSOR_AGENT` unset.

`CURSOR_AGENT` is not the predicate. It was unset on the CLI process this capture measured. `CURSOR_INVOKED_AS` is not the predicate. A non-CLI Cursor process was not measured, so a marker that also matches the IDE is still possible. `detectHarness` does not read either name. A session that lacks a measured CLI-only marker stays `unknown`.

## Envelope, working directory, tool names

Not observed. The process exited before a hook or a tool call. No working-directory field was present. No tool name was present. No poll-tool name was present. `pollInstructions("cursor")` stays the slice 1 stop.

## Sources the CLI names, and what this session loaded

CLI `2026.10.01-e373342` contains path builders for these hook configs. This session loaded none of them (`loaded:` lines are absent on purpose):

| Source | Path | This session |
| --- | --- | --- |
| enterprise | `/etc/cursor/hooks.json` | file absent, not loaded |
| team | `<workspace>/.cursor/managed/active-team-hooks/hooks.json` | not loaded |
| user | `~/.cursor/hooks.json` | file absent, not loaded |
| project | `<workspace>/.cursor/hooks.json` | probe did not run |
| claude-user | `~/.claude/settings.json` | not loaded |
| claude-project | `<workspace>/.claude/settings.json` | probe did not run |
| claude-project-local | `<workspace>/.claude/settings.local.json` | not loaded |
| plugin | manifest `hooks` path, else `hooks/hooks.json` | probe did not run |

`.claude/settings.json` is not marked `already-fires` and it is not marked `dead`. No guard command was copied from it. `user_email` was not stored.

## Registry

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. This capture does not show the CLI loading that path. No second registry was added. This repository has no `.cursor/hooks.json`.

## Support bar

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. This note does not record those events. The plugin is not supported. ADR-274 stays `adopting`. A pull request that cites this note does not close issue 9608.
