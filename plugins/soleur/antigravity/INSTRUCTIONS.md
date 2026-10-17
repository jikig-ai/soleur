# Soleur on Antigravity CLI (`agy`)

These mappings apply when running Soleur instructions in the Antigravity CLI (`agy`). Keep all
canonical skill phases, decision gates, and completion checks. Tool names in
those instructions describe intent; use the tools available in the
current Antigravity session.

## Paths and entry points

The installed plugin root is the parent of this `antigravity/` directory. Resolve
Soleur's `plugins/soleur/...` references against that root; resolve project
files and `knowledge-base/` against the active workspace or worktree path.
Never search another harness's cache for the plugin.

Use `/soleur:go <intent>`, `/soleur:sync`, and `/soleur:help`. These are
skill invocations and slash commands.

## Tools

| Soleur instruction | Antigravity execution |
| --- | --- |
| Read / Glob / Grep | `view_file` (with `AbsolutePath`, line ranges, `ContentOffset`) |
| Write / Edit / MultiEdit | `write_to_file` to create or overwrite; `replace_file_content` for precise block edits |
| Bash / Shell | `run_command` (with `CommandLine`, `Cwd`, `WaitMsBeforeAsync`, `IsDaemon`, and task management via `manage_task`) |
| Skill `soleur:<name>` | Loaded via Antigravity progressive disclosure; read `skills/<name>/SKILL.md` using `view_file` and execute every required phase, or invoke via slash command `/soleur:<skill>` |
| Task / Agent / spawn_subagent | `invoke_subagent` (using built-in types `self`, `research`, or specialized roles defined dynamically via `define_subagent`) |
| AskUserQuestion | `ask_question` (interactive structured question modal with selectable options and default write-in) |
| TodoWrite / TodoRead | Native Antigravity Markdown artifacts in `<appDataDir>/brain/<conversation-id>/` or project-level file-based task tracking |
| Monitor / AwaitShell | `schedule` tool (one-shot timer or recurring cron) or background `run_command` with reactive notifications via `manage_task` |
| TaskOutput | Native reactive wakeup — background tasks and subagents deliver completion messages automatically without manual polling loops |
| WebSearch / WebFetch / ToolSearch | `search_web`, `read_url_content`, and MCP servers configured via `mcp_config.json` |
| SendMessage / ListAgents | `send_message` (messaging specific subagent by `Recipient` conversation ID) / `manage_subagents` (`list`, `kill`, `kill_all`) |
| TaskCreate / TaskGet / TaskList / TaskUpdate / TaskStop | `manage_subagents` (`kill`, `list`) / `manage_task` (`kill`, `list`, `status`) / Artifact task lists |
| RemoteTrigger / PushNotification / ScheduleWakeup / CronCreate / CronDelete / CronList | `schedule` tool (supports one-shot timers with `DurationSeconds` and `TimerCondition`, or recurring cron via `CronExpression` with `MaxIterations`) |
| Workflow scripts | Translate orchestration to native Antigravity tool calls; do not execute Claude tool calls as shell JavaScript |

## Domain agents

Canonical definitions live in `agents/<domain>/**/*.md`. Find an agent by
its qualified ID (`soleur:engineering:review:security-sentinel` maps to
`agents/engineering/review/security-sentinel.md`) or its frontmatter name.
Read the definition before delegation.

In Antigravity CLI, domain specialists are spawned dynamically:
1. Read the agent's markdown definition at its absolute path.
2. If the subagent role is not yet registered in this session, call `define_subagent` with:
   - `name`: the normalized identifier (e.g., `soleur-engineering-cto` or `security-sentinel`).
   - `description`: brief summary of the role.
   - `system_prompt`: the complete agent definition from the markdown file.
   - `enable_write_tools`: `false` for review and audit roles (enforcing the read-only review invariant); `true` for implementation roles.
   - `enable_mcp_tools`: `true` when external services or browsers are needed.
3. Call `invoke_subagent` with `TypeName`, `Role`, `Prompt`, `Workspace: 'inherit'`, and `Model: 'inherit'`.

Subagents execute asynchronously in the background. Communicate with active subagents using
`send_message`. When a subagent completes, the system automatically wakes the parent session
with the result.

## Polling and watches

Antigravity CLI provides native reactive wakeup for background tasks and timers:
- For background checks (CI settling, PR merge status, release workflows), launch `run_command` with `IsDaemon: false` and adequate `WaitMsBeforeAsync` or schedule wakeups using `schedule` (`DurationSeconds` with `TimerCondition: 'never'` or task ID).
- Do NOT run blocking `sleep` loops or busy-polling bash scripts in the foreground.
- Poll PR state + `mergeStateStatus` on every tick; resync on `BEHIND` before watching checks (except when `main` has a merge queue and the PR is armed).
- After `/soleur:ship` merge: poll release workflows, invoke `/soleur:postmerge <PR>`, then emit `<promise>DONE</promise>`.

## Artifacts

Antigravity CLI provides a first-class artifact directory at `<appDataDir>/brain/<conversation-id>/`.
Store extensive reports, design plans, and review deliverables as markdown artifacts with GitHub-style alerts, mermaid diagrams, and clickable file links.
