---
name: help
description: This skill lists all available Soleur commands, agents, and skills
argument-hint: ""
# `/soleur:help` also ships as plugins/soleur/commands/help.md. Claude Code loads
# plugin commands AND plugin skills into one slash menu, so without this the name
# renders twice. `user-invocable: false` leaves the menu row to the command while
# keeping this skill model-invocable — Skill(soleur:help) must keep working.
# Grok 1.0.40 validates plugin commands/ but does not register them as slash
# commands. Do not flip this flag to expose the help row there — that
# re-duplicates Claude Code. The Grok slash row is `.grok/commands/help.md`
# (collides with the Grok builtin, so the Soleur handler is local:help).
user-invocable: false
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

**Which harness this body is for.** Everything below the next heading is the **Devin CLI**
entry-point shim: it addresses itself as the `/soleur:help` slash command, resolves paths through
`${CLAUDE_PLUGIN_ROOT}`, and names Devin's own adapter tools. The Grok block above says to run
this document to completion; read the two together, because on a harness other than Devin the
body below is not the thing to run:

- **Claude Code** — this skill is `user-invocable: false` and the operator-facing row is
  `plugins/soleur/commands/help.md`. Read that file and act as its handler.
- **Grok Build** — the slash row is `.grok/commands/help.md`, which resolves to the same
  `commands/help.md`. Read that file and act as its handler. Do NOT detect the harness as Devin,
  and do not use `run_subagent`; Grok's spawn tool is `spawn_subagent` with hyphenated agent ids.
- **Codex** — `codex/skills/help/SKILL.md` is the front door. Read `commands/help.md` and act as
  its handler, translating tools through `codex/INSTRUCTIONS.md` §Tools.

In every case the AUTHORITY is `commands/help.md`; the harness shims differ only in how they
address the operator and which tool names they use.

# /soleur:help (Devin CLI entry point)

You are the `/soleur:help` slash command for the Soleur plugin on Devin CLI.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/help.md`.
2. Follow every instruction in that file as if you were the `/soleur:help` handler.
3. When reading the manifest, use `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`.
4. When counting components with Glob, use paths under `${CLAUDE_PLUGIN_ROOT}` (`${CLAUDE_PLUGIN_ROOT}/agents`, `${CLAUDE_PLUGIN_ROOT}/commands`, `${CLAUDE_PLUGIN_ROOT}/skills`).
5. Detect the active harness as Devin CLI and output the **Devin CLI** help block from `commands/help.md`.
6. Do not improvise counts or list commands that are not present in the plugin.
