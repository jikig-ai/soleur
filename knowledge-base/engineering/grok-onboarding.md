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
grok inspect | grep -E 'soleur|agents|skills'
```

Today Grok may show fewer agents than Claude until Phase E (agent discoverability) lands. Skills and the three commands should appear after #6314 config.

## References

- CONTRIBUTING.md — contributor quickstart
- ADR-110 / #6316 — semantic model-tier map (Phase D)
- `plugins/soleur/lib/harness.ts` — Skill/Task vs slash/spawn_subagent adapter (Phase B)