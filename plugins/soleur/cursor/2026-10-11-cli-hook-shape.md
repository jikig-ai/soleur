# Cursor CLI hook shape — 2026-10-11

This note records the non-CLI process measurement that slice 2 required before any `CURSOR_*` name could be a predicate. It does not replace `2026-10-07-cli-hook-shape.md` or `2026-10-08-cli-hook-shape.md`. Those notes remain the authentication-exit record and the authenticated scratch-workspace record.

No email was stored. The AppImage and its user-data directory stayed under `/tmp` and were not copied into this repository.

## Non-CLI process

The host had no Cursor desktop package, desktop file, flatpak, or snap. The CLI binary `cursor-agent` `2026.10.01-e373342` was already logged in. This measurement did not start a login.

Cursor `3.24.12` was downloaded as the official Linux x64 AppImage from `https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/` and extracted under `/tmp`. That download is a measurement of the editor process. It is not IDE product work.

A clean-environment launch of the extracted `cursor` binary used a fresh `--user-data-dir`, a fresh `--extensions-dir`, `--disable-gpu`, `--no-sandbox`, and a scratch workspace outside this repository. After 15 seconds, 25 processes whose command name was `cursor` or `chrome_crashpad_handler` had no environment name starting with `CURSOR_` and no environment name starting with `CLAUDE`. An earlier headless ozone launch of the AppImage wrapper showed the same absence on the child `cursor` process. The wrapper process inherited only `CLAUDE_CODE_EFFORT_LEVEL` and `ELECTRON_OZONE_PLATFORM_HINT` from the parent shell. Those processes were then stopped.

The hidden IDE agent terminal was not started, so that terminal's environment was not process-measured. In this same build, the editor source that creates that terminal sets `CURSOR_AGENT` and does not set `CURSOR_INVOKED_AS`. The worker bundle sets `CURSOR_INVOKED_AS` on a `cursor-agent` child, not on the editor process.

## Marker

`CURSOR_AGENT` is not the predicate. It was unset on the 2026-10-08 CLI process, and the IDE terminal source sets it.

`CURSOR_INVOKED_AS` is the predicate when it is nonempty. The 2026-10-08 CLI process had it nonempty. Every sampled process in this idle editor tree lacked it. An empty value is not a match. A session that lacks the marker stays `unknown`.

The check is after the Claude, Grok, Codex, and Devin arms in `detectHarness` and in `emit-decision.sh`. `CLAUDECODE` plus the marker returns `claude`. `formatSkillInvocation`, `invokeSkill`, `formatAgentSpawn`, and `spawnAgent` use the Cursor slash form in that same change. They do not return the Skill tool or the Task tool.

`CURSOR_PROJECT_DIR`, `CURSOR_RIPGREP_PATH`, `CURSOR_USER_EMAIL`, `CURSOR_VERSION`, `CURSOR_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` are not predicates. `CURSOR_USER_EMAIL` was not stored.

If a later capture shows the IDE editor, or an IDE shell that is not a `cursor-agent` child, also has `CURSOR_INVOKED_AS`, this predicate fails and must be removed.

## Registry

`plugins/soleur/cursor/hooks-empty.json` stays `{ "hooks": {} }`. A later capture the same day, with the workspace set to this repository, is `2026-10-11-repo-settings-shape.md`. That note marks the SessionStart commands and the Bash matchers `already-fires`. It does not mark the other matchers `dead`. No guard command was copied. This repository has no `.cursor/hooks.json`. The plugin is not called supported.

## Support bar

The plugin is called supported only when a Cursor CLI session shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the full guard set firing. This note does not record those events. The plugin is not supported. ADR-274 stays `adopting`. A pull request that cites this note does not close issue 9608.
