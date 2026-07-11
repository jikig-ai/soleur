---
title: Grok Build onboarding for Soleur contributors
last_updated: 2026-07-10
tags:
  - grok
  - harness
  - onboarding
domain: engineering
---

# Grok Build onboarding

Soleur loads the same in-repo plugin under [Grok Build](https://docs.x.ai/build/overview) as under Claude Code. This brief covers first-run setup and **command naming** — the most common fidelity failure mode.

## First session

From the repository root:

```bash
grok inspect    # soleur plugin, skills, agents, MCP servers must appear
grok --trust    # first run only — activates .claude/settings.json hooks
grok            # interactive session
```

Without trust, Soleur's PreToolUse guards stay inactive and workflows may skip safety gates.

Project plugin config lives in `.grok/config.toml` (merged #6314). Supported project keys are **`[plugins]`**, **`[mcp_servers]`**, and **`[permission]`** only — no `permission_mode` or `[compat.claude]` in project config (those belong in user `~/.grok/config.toml`).

## Command naming (harness-specific)

| Surface | Claude Code | Grok Build |
|--------|-------------|------------|
| Entry command | `/soleur:go <intent>` | `/go <intent>` |
| Sync | `/soleur:sync` | `/sync` |
| Help | `/soleur:help` | `/help` |
| Workflow skills | Skill tool: `soleur:<skill>` | Slash: `/<skill>` (e.g. `/one-shot`, `/brainstorm`) |
| Agents | Task tool (`subagent_type`) | `spawn_subagent` |

**Do not** tell Grok users to run `/soleur:go` — that is the Claude-qualified form. Grok exposes plugin commands by their frontmatter `name` (`go`, `sync`, `help`).

## Routing fidelity

`/go` (and `plugins/soleur/commands/go.md`) classify intent and **must** invoke registered skills or agents — never improvise filesystem exploration or ad-hoc multi-step workflows. The harness adapter at `plugins/soleur/lib/harness.ts` maps invocation surfaces; see epic children for the full fidelity stack.

## Verify discovery

```bash
grok inspect | grep -E 'soleur|Agents \(|skills'
```

After Phase E (#6324), **67** Soleur agents appear as `soleur:<domain>:…` **project** rows in the `Agents` section (generated compat stubs under `.grok/agents/`). Skills and the three commands (`/go`, `/sync`, `/help`) load via the in-repo plugin.

### Subagents

Enable subagent spawning in user config (`~/.grok/config.toml` — project config cannot set `[subagents]`):

```toml
[subagents]
enabled = true
```

Or set `GROK_SUBAGENTS=1` for a single session. Without this, `spawn_subagent` instructions in skills are inert.

### Spawning domain agents

```text
spawn_subagent agent=soleur:engineering:review:security-sentinel prompt="Review the auth changes in PR #123"
```

Qualified IDs match Claude's `Task` `subagent_type` names. The harness adapter (`plugins/soleur/lib/harness.ts`) emits the same IDs under Grok.

### Adding or renaming agents

Canonical sources live under `plugins/soleur/agents/**`. After editing, regenerate Grok compat artifacts:

```bash
cd plugins/soleur && bun run scripts/sync-grok-agent-compat.ts
```

CI drift checks (Phase F #6325):

```bash
bash plugins/soleur/scripts/grok-fidelity-gate.sh   # full gate (CI job grok-fidelity)
cd plugins/soleur && bun run scripts/sync-grok-agent-compat.ts --check
```

## References

- CONTRIBUTING.md — contributor quickstart
- ADR-110 / #6316 — semantic model-tier map (Phase D)
- `plugins/soleur/lib/harness.ts` — Skill/Task vs slash/spawn_subagent adapter (Phase B)