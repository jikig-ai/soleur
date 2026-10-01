---
name: resolve-pr-parallel
description: "This skill should be used when resolving all PR comments using parallel processing. It fetches unresolved comments, spawns parallel resolver agents, and verifies all threads are resolved."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill lives at [`workflows/resolve-pr-parallel.workflow.js`](./workflows/resolve-pr-parallel.workflow.js) — deterministic fan-out, journaled resume, schema-validated output. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js", args: ... })`. The prose skill below stays the default; the two coexist during calibration. See [`knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`](../../../../knowledge-base/project/specs/feat-review-workflow-prototype/spec.md).

# Resolve PR Comments in Parallel

Resolve all PR comments using parallel processing.

Claude Code automatically detects and understands git context:

- Current branch detection
- Associated PR context
- All PR comments and review threads
- Can work with any PR by specifying the PR number, or ask it.

<decision_gate>
**API budget.** This skill spawns one `soleur:engineering:workflow:pr-comment-resolver` agent in parallel per unresolved PR comment (N comments = N agents). Each agent runs an independent task with its own context window and token cost; parallel fan-out compresses wall-clock but not aggregate token consumption. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Confirm the unresolved-comment count before allowing the fan-out. A PR with 40 unresolved threads spawns 40 parallel agents.
</decision_gate>

## Workflow

### 1. Analyze

Get all unresolved comments for the PR:

```bash
gh pr status
bin/get-pr-comments PR_NUMBER
```

### 2. Plan

Create a TodoWrite list of all unresolved items grouped by type.

### 3. Implement (PARALLEL)

Spawn a soleur:engineering:workflow:pr-comment-resolver agent for each unresolved item in parallel.

So if there are 3 comments, spawn 3 soleur:engineering:workflow:pr-comment-resolver agents in parallel:

1. Task soleur:engineering:workflow:pr-comment-resolver(comment1)
2. Task soleur:engineering:workflow:pr-comment-resolver(comment2)
3. Task soleur:engineering:workflow:pr-comment-resolver(comment3)

Always run all in parallel subagents/Tasks for each Todo item.

### 4. Commit & Resolve

- Commit changes
- Run bin/resolve-pr-thread THREAD_ID_1
- Push to remote

Last, check bin/get-pr-comments PR_NUMBER again to see if all comments are resolved. They should be; if not, repeat the process from step 1.
