---
name: resolve-parallel
description: "This skill should be used when resolving all TODO comments in the codebase using parallel processing. It analyzes dependencies, creates a resolution plan with a mermaid flow diagram, and spawns parallel resolver agents."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill lives at [`workflows/resolve-parallel.workflow.js`](./workflows/resolve-parallel.workflow.js) — deterministic fan-out, journaled resume, schema-validated output. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js", args: ... })`. The prose skill below stays the default; the two coexist during calibration. See [`knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`](../../../../knowledge-base/project/specs/feat-review-workflow-prototype/spec.md).

# Resolve TODO Comments in Parallel

Resolve all TODO comments using parallel processing.

## Workflow

### 1. Analyze

Gather the TODO items from the codebase.

### 2. Plan

Create a TodoWrite list of all unresolved items grouped by type. Look at dependencies that might occur and prioritize the ones needed by others. For example, if a name change is needed, wait to do the dependents. Output a mermaid flow diagram showing how the work can proceed. Can everything run in parallel? Does one item need to complete first before others can start? Structure the to-dos in the mermaid diagram flow-wise so the agent knows how to proceed in order.

### 3. Implement (PARALLEL)

Spawn a soleur:engineering:workflow:pr-comment-resolver agent for each unresolved item in parallel.

So if there are 3 items, spawn 3 soleur:engineering:workflow:pr-comment-resolver agents in parallel:

1. Task soleur:engineering:workflow:pr-comment-resolver(item1)
2. Task soleur:engineering:workflow:pr-comment-resolver(item2)
3. Task soleur:engineering:workflow:pr-comment-resolver(item3)

Always run all in parallel subagents/Tasks for each Todo item.

### 4. Commit & Resolve

- Commit changes
- Push to remote
