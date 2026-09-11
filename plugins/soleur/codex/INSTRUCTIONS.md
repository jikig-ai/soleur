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
| Monitor / AwaitShell / TaskOutput | Bounded shell probes; resume yielded commands with `write_stdin`, keeping progress visible |
| WebSearch / WebFetch / ToolSearch | Use the available search, fetch, or tool-discovery capability |
| Workflow scripts | Translate orchestration to the available tools; do not execute Claude tool calls as shell JavaScript |

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

Keep long-running workflows bounded by their iteration and cost gates.
Soleur's subscription and OpenAI model usage are separate charges; substitute
OpenAI for Anthropic in harness-specific billing disclosures. Soleur disclaims
warranty for runtime cost.

For asynchronous CI and merge work, own the wait, report changes, resolve
`BEHIND`, and finish the prescribed postmerge checks before claiming success.
If a required capability cannot be mapped, report the exact unsupported gate
and retain incomplete status instead of silently skipping it.
