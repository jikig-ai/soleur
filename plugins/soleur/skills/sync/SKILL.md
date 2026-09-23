---
name: sync
description: This skill analyzes the codebase and populates the knowledge-base with conventions, patterns, and technical debt
argument-hint: "[area: conventions|architecture|testing|debt|project|c4|domain-model|all]"
# `/soleur:sync` also ships as plugins/soleur/commands/sync.md. Claude Code loads
# plugin commands AND plugin skills into one slash menu, so without this the name
# renders twice. `user-invocable: false` leaves the menu row to the command while
# keeping this skill model-invocable — Skill(soleur:sync) must keep working.
# Grok 1.0.40 validates plugin commands/ but does not register them as slash
# commands. Do not flip this flag to expose the sync row there — that
# re-duplicates Claude Code. The Grok slash row is `.grok/commands/sync.md`.
user-invocable: false
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

**Which harness this body is for.** Everything below the next heading is the **Devin CLI**
entry-point shim: it addresses itself as the `/soleur:sync` slash command, resolves paths through
`${CLAUDE_PLUGIN_ROOT}`, and names Devin's own adapter tools. The Grok block above says to run
this document to completion; read the two together, because on a harness other than Devin the
body below is not the thing to run:

- **Claude Code** — this skill is `user-invocable: false` and the operator-facing row is
  `plugins/soleur/commands/sync.md`. Read that file and act as its handler.
- **Grok Build** — the slash row is `.grok/commands/sync.md`, which resolves to the same
  `commands/sync.md`. Read that file and act as its handler. Do NOT detect the harness as Devin,
  and do not use `run_subagent`; Grok's spawn tool is `spawn_subagent` with hyphenated agent ids.
- **Codex** — `codex/skills/sync/SKILL.md` is the front door. Read `commands/sync.md` and act as
  its handler, translating tools through `codex/INSTRUCTIONS.md` §Tools.

In every case the AUTHORITY is `commands/sync.md`; the harness shims differ only in how they
address the operator and which tool names they use.

# /soleur:sync (Devin CLI entry point)

You are the `/soleur:sync` slash command for the Soleur plugin on Devin CLI.

The user's request is the optional area argument that follows `/soleur:sync` (e.g. `all`, `conventions`, `architecture`). Treat that text as `$ARGUMENTS`.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/sync.md`.
2. Follow every instruction in that file as if you were the `/soleur:sync` handler.
3. Where the file uses `$ARGUMENTS` or `#$ARGUMENTS`, substitute the user's actual request.
4. Do not improvise workflow steps. Run the producers and gated writes exactly as described.
