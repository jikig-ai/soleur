# Soleur on Devin CLI

These mappings apply when running Soleur instructions in Devin CLI. Keep the
canonical skill phases, decision gates, and completion checks. Tool names in
those instructions describe intent; use the tools actually available in the
current Devin session.

## Paths and entry points

The installed plugin root is available via `${CLAUDE_PLUGIN_ROOT}` (Devin inherits this from Claude plugin format compatibility).
Resolve Soleur's `plugins/soleur/...` references against that root; resolve project
files and `knowledge-base/` against the user's current project or worktree.
Never search another harness's cache for the plugin. In shell examples,
set `CLAUDE_PLUGIN_ROOT` to the verified installed root for that command.
Plugin hooks receive that variable automatically; ordinary shell tools need
not inherit a plugin hook's environment.

Use `/soleur:go <intent>`, `/soleur:sync`, and `/soleur:help` as Devin slash commands.
These are skill invocations, not shell commands.

## Tools

| Soleur instruction | Devin execution |
| --- | --- |
| Read / Glob / Grep | read, grep, glob tools |
| Write / Edit | write, edit tools |
| Bash / Shell | exec tool |
| Skill `soleur:<name>` | Skill tool with `soleur:<skill>` namespace |
| Task / Agent / spawn_subagent | run_subagent tool |
| AskUserQuestion | ask_user_question tool |
| TodoWrite / TodoRead | todo_write tool |
| Monitor / AwaitShell / TaskOutput | get_output with timeout for polling |
| WebSearch / WebFetch / ToolSearch | web_search, webfetch tools |
| Workflow scripts | Translate orchestration to available tools; do not execute Claude tool calls as shell JavaScript |

Loading a skill file is Devin's execution entry point. Follow its full workflow and referenced files; do not stop after reading it, reproduce it selectively, or ask the user to run the next stage.
Treat `$ARGUMENTS` as the supplied request, never as an environment variable that needs shell interpolation.

## Domain agents

Canonical definitions live in `agents/<domain>/**/*.md`. Find an agent by
its qualified ID (`soleur:engineering:review:security-sentinel` maps to
`agents/engineering/review/security-sentinel.md`) or its frontmatter name.
Read the definition before delegation. Spawn using the available tool's
actual schema, passing its absolute definition path, this instruction file,
the task, and the current worktree path. Do not pass a Claude registry ID as
a Devin agent type. Inherit the session model and permission policy; Claude
model aliases are not Devin model identifiers.

If subagents are unavailable, execute the requested role sequentially with
the same definition and disclose the lack of parallel execution. Never
claim that an independent review occurred when it did not.

## Hooks and completion

Review and trust the plugin hooks through `/hooks` before relying on them.
Installation does not grant hook trust. Devin supports the bundled Bash
credential guard and Stop hooks, but hook execution does not prove that every
Claude-only workflow primitive has an equivalent.

Keep long-running workflows bounded by their iteration and cost gates.
Soleur's subscription and model usage are separate charges; substitute
Devin's model pricing in harness-specific billing disclosures. Soleur disclaims
warranty for runtime cost.

For asynchronous CI and merge work, own the wait, report changes, resolve
`BEHIND`, and finish the prescribed postmerge checks before claiming success.
If a required capability cannot be mapped, report the exact unsupported gate
and retain incomplete status instead of silently skipping it.

## Devin-specific considerations

- **Skill invocation**: Devin uses the same Skill tool format as Claude Code with `soleur:<skill>` namespace
- **Agent spawning**: Devin uses `run_subagent` tool instead of Claude's `Task` tool
- **Polling**: Use `get_output` with timeout instead of Claude's Monitor tool
- **Permissions**: Devin's permission system differs from Claude's; use permissive defaults initially
- **MCP servers**: Devin supports the same MCP server format as Claude, so existing servers should work without modification
