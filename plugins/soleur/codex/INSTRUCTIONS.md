# Soleur on Codex

These mappings apply when running Soleur instructions in Codex. Keep the
canonical skill phases, decision gates, and completion checks. Tool names in
those instructions describe intent; use the tools actually available in the
current Codex session.

## Paths and entry points

The installed plugin root is the parent of this `codex/` directory. Resolve
Soleur's `plugins/soleur/...` references against that root; resolve project
files and `knowledge-base/` against the user's current project or worktree.
Never search another harness's cache for the plugin. In shell examples,
set `CLAUDE_PLUGIN_ROOT` to the verified installed root for that command.
Plugin hooks receive that variable automatically; ordinary shell tools need
not inherit a plugin hook's environment.

Use `$soleur:go <intent>`, `$soleur:sync`, and `$soleur:help` in the
Codex composer. These are skill mentions, not shell commands.
For help output, translate the canonical command names to these Codex names.

## Tools

| Soleur instruction | Codex execution |
| --- | --- |
| Read / Glob / Grep | Read files through shell tools; use `rg` for discovery |
| Write / Edit / MultiEdit | `apply_patch` |
| Bash / Shell | `exec_command`, or the available shell tool |
| Skill `soleur:<name>` | Load the matching installed skill using `skills.read` when available; otherwise read `skills/<name>/SKILL.md` and execute every required phase |
| Task / Agent / spawn_subagent | Use the available `spawn_agent` tool with canonical instructions as described below |
| AskUserQuestion | Use a question tool when available in the current mode; otherwise ask in chat |
| TodoWrite / TodoRead | Use the available plan tool or the project's file-based task tracking |
| Monitor / AwaitShell | Bounded shell probes; resume yielded commands with `write_stdin`, keeping progress visible |
| TaskOutput | `wait_agent` — the await primitive for an agent YOU spawned, not a shell probe. Codex's own guidance is to prefer waits of minutes over busy polling. Measured on Codex CLI 0.156.1 (`codex debug prompt-input`, `<multi_agent_role>`) |
| WebSearch / WebFetch / ToolSearch | Use the available search, fetch, or tool-discovery capability |
| SendMessage / ListAgents | `followup_task` gives an existing agent a new task and triggers its turn, keeping its context; `send_message` passes a message without a turn; `list_agents` enumerates them. Measured on Codex CLI 0.156.1 (`codex debug prompt-input` collaboration tools: `spawn_agent`, `followup_task`, `send_message`, `wait_agent`, `interrupt_agent`, `list_agents`) |
| TaskCreate / TaskGet / TaskList / TaskUpdate / TaskStop | Use the available plan tool, or the project's file-based task tracking. NOT measured as a distinct Codex tool — same hedge as the TodoWrite row above |
| RemoteTrigger / PushNotification / ScheduleWakeup / CronCreate / CronDelete / CronList | No equivalent. Report the unsupported gate rather than simulating it — a scheduled or push-triggered step that silently does not fire is worse than one that refuses |
| Workflow scripts | Translate orchestration to the available tools; do not execute Claude tool calls as shell JavaScript |

**Two properties of Codex's collaboration tools that change how a Soleur fan-out runs.** Both measured on Codex CLI 0.156.1 via `codex debug prompt-input` (`<multi_agent_role>`):

- **They are namespace-gated and cannot be called from inside `exec`.** `spawn_agent`, `followup_task`, `send_message`, `wait_agent`, `interrupt_agent` and `list_agents` are intentionally absent from the `functions.exec` `tools.*` namespace and must be issued as direct tool calls (`to=functions.collaboration.spawn_agent`). A fan-out written as a shell loop therefore cannot spawn anything — translate orchestration into direct tool calls, never into a script.
- **There are 4 concurrency slots in total, including the calling agent.** So at most THREE children are active at once. Soleur panels are sized for a harness with no such cap — `soleur:review`'s code class spawns 8. On Codex, run them in waves of at most three and `wait_agent` between waves; do not silently drop seats to fit the cap, and say in the deliverable that the panel ran in waves.

Loading a skill file is Codex's execution entry point when no skill-loading
tool exists. Follow its full workflow and referenced files; do not stop after
reading it, reproduce it selectively, or ask the user to run the next stage.
Treat `$ARGUMENTS` as the supplied request, never as an environment variable
that needs shell interpolation.

## Domain agents

Canonical definitions live in `agents/<domain>/**/*.md`. Find an agent by
its qualified ID (`soleur:engineering:review:security-sentinel` maps to
`agents/engineering/review/security-sentinel.md`) or its frontmatter name.
Read the definition before delegation. Spawn using the available tool's
actual schema, passing its absolute definition path, this instruction file,
the task, and the current worktree path. Do not pass a Claude registry ID as
a Codex agent type. Inherit the session model and permission policy; Claude
model aliases are not Codex model identifiers.

If subagents are unavailable, execute the requested role sequentially with
the same definition and disclose the lack of parallel execution. Never
claim that an independent review occurred when it did not.

## Hooks and completion

Review and trust the plugin hooks through `/hooks` before relying on them.
Installation does not grant hook trust. Codex supports the bundled Bash
credential guard and Stop hooks, but hook execution does not prove that every
Claude-only workflow primitive has an equivalent.

Compaction hooks do not fire. `compaction-state.sh` (`PreCompact` /
`SessionStart:compact`, #8323) is a Claude Code API with no Codex equivalent,
so no post-compaction re-read directive and no evidence-based fresh-session
recommendation are delivered here. The skill-prose fallback applies: the
end-of-work resume prompt still fires, carrying no `/clear` nudge. Do not
report the behaviour as present.

Keep long-running workflows bounded by their iteration and cost gates.
Soleur's subscription and OpenAI model usage are separate charges; substitute
OpenAI for Anthropic in harness-specific billing disclosures. Soleur disclaims
warranty for runtime cost.

For asynchronous CI and merge work, own the wait, report changes, resolve
`BEHIND`, and finish the prescribed postmerge checks before claiming success.
If a required capability cannot be mapped, report the exact unsupported gate
and retain incomplete status instead of silently skipping it.
