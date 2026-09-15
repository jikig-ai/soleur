# Devin CLI Hook Semantics — Empirical Envelope Capture

Issue: #8205 · PR: #8214 · Probe date: 2026-09-15
Harness: `devin` CLI (child sessions via `devin -p --respect-workspace-trust false --permission-mode <mode>`)
Scratch repo: `/var/tmp/devin-probe-8205` (stubs in `stubs/`, raw captures in `captures/`)
Stubs: `stubs/capture.sh` (records raw stdin + filtered env + pwd per fire), `stubs/decide.sh` (emits response-contract JSON for sentinels)
Registries under test (all populated simultaneously in the scratch repo):
`.claude/settings.json`, `.devin/config.json`, installed plugin `probe-8205` (`hooks.json` via `devin plugins install --local`).

Every claim below cites a capture file or observed session output. Where a fact could not be established it is marked **UNVERIFIED** — the dispositions that depend on it downgrade rather than assume.

---

## 1. Matcher semantics — CONFIRMED regex, unanchored substring

| Matcher | Registry | Fired on `exec`/`write`? | Evidence |
|---|---|---|---|
| `exec` (literal) | `.devin` | yes | `devin-exec-unanchored.txt` |
| `^exec$` (anchored) | `.devin` | yes | `devin-exec-anchored.txt` |
| `write` (literal) | `.devin` | yes — on `write` **and `todo_write`** | `devin-write-unanchored.txt` (1×`todo_write`, 2×`write`) |
| `^write$` (anchored) | `.devin` | yes — `write` only | `devin-write-anchored.txt` (2×`write`, 0×`todo_write`) |
| `.*` (wildcard) | `.devin` | yes — every tool | `devin-wildcard.txt` |
| `Bash` | `.devin` + `.claude` | **no** — never fired | no `devin-bash-deadname.txt`, no `claude-bash-matcher.txt` |
| `Write`, `AskUserQuestion` | `.claude` | **no** — never fired | no `claude-Write-deadname.txt`, no `claude-auq-deadname.txt` |

**Conclusions:**
- Matchers are regexes applied to the wire `tool_name`, evaluated as unanchored substrings (consistent with `jq test()` / partial-match semantics).
- **Anchored twins are required.** Unanchored `write` over-binds `todo_write` — measured, not hypothetical. All lowercase Devin twins must be `^name$`.
- There is no `Bash`→`exec` alias anywhere: TitleCase tool names are dead in every registry under Devin.

## 2. Registries — all three load and dispatch; NO cross-source dedup

| Registry | Loaded under Devin? | Evidence |
|---|---|---|
| `.devin/config.json` `hooks` | yes | all `devin-*.txt` captures |
| `.claude/settings.json` `hooks` | yes | `claude-exec-matcher.txt`, `claude-write-twin.txt`, `claude-stop.txt` |
| plugin `hooks.json` (installed `--local`) | yes | `plugin-exec-env.txt`, `plugin-stop.txt`, `plugin-ss-empty.txt` |

**Cross-source dedup: NONE.** The identical command string `bash …/capture.sh ssdedup …` registered under SessionStart `matcher:""` in all three registries fired **3 times** in one session (`ssdedup.txt`: three fires, same `session_id`). An earlier run also produced 3 fires once the plugin entry was installed. Any hook reachable from two registries **will** double-fire under Devin.

**Consequence for production:** each hook must be reachable through exactly one registry per tool. `devin-session-start.sh` is registered in both `.devin/config.json` and `plugins/soleur/hooks/hooks.json` today — both entries carry source matchers, so both are dead *now* (see §3), but any fix must pick a single home or the fix itself creates a double-fire.

## 3. SessionStart — non-empty matchers are DEAD under Devin

| Entry | Matcher | Fired? | Evidence |
|---|---|---|---|
| `.devin` SessionStart | `""` | yes | `devin-ss-empty.txt` |
| `.devin` SessionStart | `startup` | **no** | absent |
| `.devin` SessionStart | `startup|resume|clear|compact` | **no** | absent |
| `.claude` SessionStart | `startup|resume|clear|compact` | **no** | absent |
| plugin `hooks.json` SessionStart | `startup|resume|clear|compact` | **no** | absent |
| plugin `hooks.json` SessionStart | `""` | yes | `plugin-ss-empty.txt` |

SessionStart stdin under Devin: `{"hook_event_name":"SessionStart","source":"startup","session_id":"…"}` — the `source` field IS present in the envelope, but the registry matcher is not evaluated against it (or the match target isn't `source`). Non-empty matchers never fire regardless of source value.

**Conclusions:**
- The existing `.devin/config.json` SessionStart block (matcher `startup|resume|clear|compact`) is **dead** — `session-rules-loader.sh` and `devin-session-start.sh` never ran under Devin. Same for soleur `hooks.json` SessionStart (`codex-session-start.sh`, `devin-session-start.sh`, `welcome-hook.sh`) — dead under Devin.
- Devin SessionStart bindings require `matcher:""`. Source filtering, if needed, must happen inside the hook body reading `.source` from stdin (the field is present).
- Stop fires with `matcher:""` from all three registries (`devin-stop.txt`, `claude-stop.txt`, `plugin-stop.txt`).

## 4. Environment — both var families populated

Hook-process env (filtered to `CLAUDE*`/`DEVIN*`/`PWD`; full dumps in capture files):

| Var | settings.json hook | .devin hook | plugin hooks.json hook |
|---|---|---|---|
| `CLAUDE_PROJECT_DIR` | `=/var/tmp/devin-probe-8205` | same | (not captured; see DEVIN_PROJECT_DIR) |
| `DEVIN_PROJECT_DIR` | `=/var/tmp/devin-probe-8205` | same | `=/var/tmp/devin-probe-8205` |
| `CLAUDE_PLUGIN_ROOT` | n/a | n/a | `=…/plugins/cache/var_tmp_devin-probe-8205_probe-plugin-263b33fa/0.0.0-unversioned` |
| `DEVIN_PLUGIN_ROOT` | n/a | n/a | same path |
| `PWD` | project root | project root | project root |

Evidence: `claude-exec-env.txt`, `devin-env.txt`, `plugin-exec-env.txt`, `plugin-ss-empty.txt`; plus `claude-exec-projectdir.txt` — a settings-dispatched command interpolating `"${CLAUDE_PROJECT_DIR}/captures/…"` wrote successfully.

**Conclusions:**
- **`CLAUDE_PROJECT_DIR` is set under Devin** and equals the project root. The SpecFlow P0-1 failure branch does not trigger: `$CLAUDE_PROJECT_DIR`-spelled commands in `.claude/settings.json` resolve correctly when dispatched by a live matcher. `covered-by-twin` is viable.
- **`CLAUDE_PLUGIN_ROOT` is set for plugin-manifest hooks** — `${CLAUDE_PLUGIN_ROOT}/hooks/x.sh` in `hooks.json` resolves under Devin.
- No env var observed that distinguishes "running under Devin" vs "running under Claude" other than `DEVIN_*` presence (`DEVIN_PROJECT_DIR`, `DEVIN_PLUGIN_ROOT`). Harness detection inside hook bodies: `[[ -n "${DEVIN_PROJECT_DIR:-}" ]]`.

## 5. Response contract — both shapes honored

Stub `decide.sh` emitted each contract for a distinct sentinel command:

| Emitted JSON | Tool call | Observed result | Evidence |
|---|---|---|---|
| `{"decision":"block","reason":"probe: devin-shape block"}` | `exec "echo PROBE_DEVIN_BLOCK"` | **rejected**; agent saw `Tool rejected: probe: devin-shape block` | session transcript |
| `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"probe: claude-shape deny"}}` | `exec "echo PROBE_CLAUDE_DENY"` | **rejected**; agent saw `Tool rejected: probe: claude-shape deny` | session transcript |
| `{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"echo PROBE_REWRITE_APPLIED > …/REWRITE_OUT.txt"}}}` | `exec "echo PROBE_REWRITE"` | **input rewritten**; PostToolUse records the *rewritten* `tool_input.command`; `REWRITE_OUT.txt` contains `PROBE_REWRITE_APPLIED` | `devin-posttool-exec.txt`, `captures/REWRITE_OUT.txt` |

**Conclusions:**
- Devin honors the Claude-shape PreToolUse response contract (`permissionDecision` + `updatedInput` inside `hookSpecificOutput`) AND its own top-level `decision:block` shape. Existing hook bodies emitting `hookSpecificOutput` JSON work unchanged once dispatched.
- PostToolUse stdin carries `tool_response:{"success":bool,"output":string,"error":…}` — Claude-shaped.
- Denied/blocked calls produce a PreToolUse fire but **no** PostToolUse fire (measured: `read` of `.devin`-denied file → PreToolUse in `devin-wildcard.txt`, no entry in `devin-posttool-all.txt`, while a successful `read` of `w.txt` produced both).

## 6. Permissions — `.devin` enforced, `.claude` NOT imported

Setup: `.devin/config.json` `permissions.deny:["Read(**/*.devin-denied)"]`, `allow:["Exec(echo PPROBE_DEVIN_ALLOW)"]`; `.claude/settings.json` `permissions.deny:["Read(**/*.claude-denied)"]`, `allow:["Bash(echo PPROBE_CLAUDE_ALLOW)","Read(**/*.claude-denied-allowed)"]`. Non-empty files behind each pattern.

| Mode | Action | Result | Evidence |
|---|---|---|---|
| `dangerous` | read `blocked.devin-denied` | **succeeded** — denies bypassed | session transcript |
| `dangerous` | read `blocked.claude-denied` | succeeded | session transcript |
| `smart` | read `blocked.devin-denied` | **blocked** — PreToolUse fired, no PostToolUse, no content returned | `devin-wildcard.txt` vs `devin-posttool-all.txt` |
| `smart` | read `blocked.claude-denied` | **succeeded** — full content returned | session transcript + `devin-posttool-all.txt` |
| `smart` | read `allowed.claude-denied-allowed` | succeeded | `devin-posttool-all.txt` |

**Conclusions:**
- `.devin/config.json` `permissions` is live and enforced under `smart` (deny wins).
- **`.claude/settings.json` `permissions.{allow,deny}` is NOT imported** — `read_config_from.claude` covers rules/skills/commands/MCP, not permissions. Every `Bash(…)`/`Read(…)`/`Edit(…)` permission rule in `.claude/settings.json` is dead under Devin; a Devin analog exists only via `.devin/config.json` `permissions` with `Exec(prefix)`/`Read(glob)`/`Write(glob)`/`Fetch(pattern)` syntax.
- `PermissionRequest` hook event: **UNVERIFIED** — never fired under `smart` (auto-resolved) or `dangerous`; under `auto` the print-mode session stalled on what appeared to be an unserviceable prompt. No `devin-permreq.txt` was produced. Hooks keyed to `PermissionRequest` cannot be claimed live without further evidence.
- `SessionEnd`: not probed (no stub registered); no claim made.

## 7. Tool vocabulary — measured wire names

Distinct `tool_name` values observed in captures (`devin-wildcard.txt`, `devin-posttool-all.txt`):

`exec` · `read` · `write` · `edit` · `glob` · `todo_write` · `get_output` · `skill` · `run_subagent` · `read_subagent` · `ask_user_question`

Plus per Devin docs (not driven in probe): `grep`, `kill_shell`, `write_to_process`, `web_search`, `webfetch`, `request_scope`, `exit_plan_mode`, `mcp__<server>__<tool>`.

**Absent / dead names (measured):**
- `apply_patch` — child agent reported it is not in its toolset; no envelope produced. Dispositions referencing it → `n/a`/`skip`.
- `multi_edit` — absent from docs' tool table and never observed.
- `Monitor`, `CronCreate`, `Task`, `NotebookEdit`, `MultiEdit`, `Write`, `Edit`, `AskUserQuestion`, `Bash` — TitleCase names never fire (§1).
- `notebook_edit` — present in docs; not driven (no .ipynb created); envelope UNVERIFIED but dispatch expected given `edit` fires.
- Internal names differ from wire names: `tool_use_id` prefixes show `find_file_by_name` for `glob`, `exec_N`/`write_N`/`edit_N`/`todo_write_N`/`read_N`/`skill_N`/`run_subagent_N`/`ask_user_question_N`/`read_subagent_N` elsewhere. Hooks must match on `tool_name`, never on `tool_use_id` shape.

**Envelope field names (PreToolUse):** `hook_event_name`, `tool_name`, `tool_input` (per-tool object), `tool_use_id`, `session_id`, `prompt_id`.
Observed `tool_input` shapes:
- `exec`: `{command}`
- `write`: `{file_path, content}`
- `edit`: `{file_path, old_string, new_string}`
- `read`: `{file_path, …}`
- `glob`: `{pattern}`
- `todo_write`: `{todos:[{content,status}]}`
- `ask_user_question`: `{questions:[{question,header,options:[{label,description}]}]}`
- `run_subagent`: `{title, task, profile, is_background}`
- `read_subagent`: `{agent_id, …}`
- `skill`: `{command, path}` (list) / `{skill:"<name>"}` (invoke — captured on a nonexistent-skill call that errored after PreToolUse fired)
- `get_output`: `{shell_id, …}`

Field names are Claude-compatible (`file_path`, `old_string`, `new_string`, `command`, `todos`, `questions`) — hooks reading these fields via jq work unchanged once dispatched.

## 8. Disposition-relevant verdicts

| Plan question | Verdict |
|---|---|
| Regex matchers? | **Yes** — anchored twins mandatory |
| `CLAUDE_PROJECT_DIR` set? | **Yes** — `covered-by-twin` viable |
| `CLAUDE_PLUGIN_ROOT` set? | **Yes** — plugin-manifest commands resolve |
| Response contract? | **Yes** — both `decision:block` and `hookSpecificOutput` (deny + updatedInput) honored |
| Cross-source dedup? | **None** — one registry per hook per tool, enforced by parity test |
| SessionStart matchers? | **All dead** — Devin needs `""` matcher; source filter moves into body |
| `.claude` permissions imported? | **No** — Devin analog lives in `.devin/config.json` only; `reason=no-analog` applies only where no `Exec/Read/Write/Fetch` mapping exists |
| `apply_patch`/`multi_edit` tools? | **Absent** — matchers referencing them are dead tokens under Devin |
| PermissionRequest event? | **UNVERIFIED** |
