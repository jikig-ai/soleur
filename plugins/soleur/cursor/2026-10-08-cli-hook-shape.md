# Cursor CLI hook shape — 2026-10-08

CLI binary: `cursor-agent` `2026.10.01-e373342`. `cursor-agent status` printed a logged-in line. No email was stored.

This note records one authenticated `--print` session. It does not replace `2026-10-07-cli-hook-shape.md`. That note remains the authentication-exit record.

## Session

Command, from a scratch workspace outside this repository, with two `--plugin-dir` values:

`cursor-agent --print --trust --workspace <scratch> --plugin-dir <probe-manifest> --plugin-dir <probe-default> --output-format stream-json --mode ask`

The prompt asked the CLI to read `README.txt` and reply with one word. Exit code 0. The stream result subtype was `success`.

Probe commands append a log and print `{}`. Raw stdin was deleted. `user_email` was redacted.

## Marker

On the CLI process, the only environment name starting with `CURSOR_` was `CURSOR_INVOKED_AS`, and it was nonempty. `CURSOR_AGENT` was unset.

A non-CLI shell on the same host had both names unset. No Cursor desktop process and no `cursor` desktop binary were present, so a non-CLI Cursor process was not measured.

Hook child processes also had nonempty `CURSOR_PROJECT_DIR`, `CURSOR_RIPGREP_PATH`, `CURSOR_USER_EMAIL`, and `CURSOR_VERSION`. Plugin-hook children also had nonempty `CURSOR_PLUGIN_ROOT` and `CLAUDE_PLUGIN_ROOT`. Those names were not on the parent CLI process. Their values were not stored. `CURSOR_USER_EMAIL` is not a marker.

`CURSOR_AGENT` is not the predicate. `CURSOR_INVOKED_AS` is not the predicate. A non-CLI Cursor process was not measured. `detectHarness` does not read either name. A session that lacks a measured CLI-only marker stays `unknown`.

## Envelope, working directory, tool names

`sessionStart` stdin keys, values omitted where they are identifiers:

- `conversation_id`, `generation_id`, `session_id`
- `model` value `default`
- `is_background_agent` value false
- `composer_mode` value `ask`
- `hook_event_name` value `sessionStart`
- `cursor_version` value `2026.10.01-e373342`
- `workspace_roots`, a list of length 1
- `user_email`, redacted, not stored
- `transcript_path` value null

There is no key named `cwd` in the hook stdin. The hook process working directory was the scratch workspace for the project hook and for both Claude project settings. It was the plugin root for both plugin hooks.

The stream `system` event, which is not the hook stdin, had `cwd` set to the scratch workspace.

`preToolUse` added `tool_name` value `Read`, `tool_input.file_path`, and `tool_use_id`. The stream named the same call `readToolCall`. No other tool ran. No poll-tool name was present. `pollInstructions("cursor")` stays the slice 1 stop.

`beforeSubmitPrompt` was configured in the project `hooks.json` and did not run.

## Sources

| Source | Path | This session |
| --- | --- | --- |
| enterprise | `/etc/cursor/hooks.json` | file absent, not opened |
| team | `<workspace>/.cursor/managed/active-team-hooks/hooks.json` | file present, not opened |
| user | `~/.cursor/hooks.json` | file absent, not opened |
| project | `<workspace>/.cursor/hooks.json` | `sessionStart` and `preToolUse` ran; `beforeSubmitPrompt` did not |
| claude-user | `~/.claude/settings.json` | home file and its SessionStart command were opened; this is not the repository guard file |
| claude-project | `<workspace>/.claude/settings.json` | `SessionStart` ran, mapped to hook event `sessionStart` |
| claude-project-local | `<workspace>/.claude/settings.local.json` | `SessionStart` ran |
| plugin manifest | manifest `hooks` value `./cursor/hooks-empty.json` | `sessionStart` ran |
| plugin default | `hooks/hooks.json` when the manifest omits `hooks` | `sessionStart` ran |

The repository `.claude/settings.json` was not the workspace of this session. It is not marked `already-fires` and it is not marked `dead`. No guard command was copied from it. `user_email` was not stored.

## Registry

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. The manifest path loads when that file contains a command, which this probe showed. The repository file stays empty because the repository guard commands are still unmarked. No second registry was added. This repository has no `.cursor/hooks.json`. The plugin is not called supported.

## Support bar

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. This note does not record those events. The plugin is not supported. ADR-274 stays `adopting`. A pull request that cites this note does not close issue 9608.
