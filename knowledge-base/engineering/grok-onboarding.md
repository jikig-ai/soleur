---
title: Grok Build onboarding for Soleur contributors
last_updated: 2026-09-11
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
grok            # interactive session
```

**Hooks / trust:** live `grok --help` on CLI 1.0.29 (2026-09-11) has **no** `--trust` flag. Do not invent one. Until a live trust token is confirmed, treat unarmed hooks as `SOLEUR_HOOK_SKIP reason=untrusted-session` — PreToolUse aliases in `.claude/settings.json` may not fire. Distinct from `SOLEUR_HOOK_SKIP reason=no-tool` (Grok has no Skill or Monitor tool).

**Fail-loud checks:** `grok inspect` must list the Soleur plugin. Spawn requires `[subagents] enabled = true` in user `~/.grok/config.toml` or `GROK_SUBAGENTS=1` for one session. `grok --no-subagents` disables spawn. If inspect is missing Soleur, stop — do not improvise.

Project plugin config lives in `.grok/config.toml` (merged #6314). Supported project keys are **`[plugins]`**, **`[mcp_servers]`**, and **`[permission]`** only — no `permission_mode` or `[compat.claude]` in project config (those belong in user `~/.grok/config.toml`).

## Command naming (harness-specific)

| Surface | Claude Code | Grok Build |
|--------|-------------|------------|
| Entry command | `/soleur:go <intent>` | `/go <intent>` |
| Sync | `/soleur:sync` | `/sync` |
| Help | `/soleur:help` | `/help` |
| Workflow skills | Skill tool: `soleur:<skill>` | Slash `/<skill>` names the skill — **Read** `plugins/soleur/skills/<name>/SKILL.md` **in this process** (Grok has no nested Skill tool) |
| Agents | Task tool (`subagent_type`) | `spawn_subagent` |

**Do not** tell Grok users to run `/soleur:go` — that is the Claude-qualified form. Grok exposes plugin commands by their frontmatter `name` (`go`, `sync`, `help`).

## Routing fidelity

`/go` (and `plugins/soleur/commands/go.md`) classify intent and **must** then Read the routed skill's `SKILL.md` in this process and run it to completion — never improvise filesystem exploration or ad-hoc multi-step workflows. The harness adapter at `plugins/soleur/lib/harness.ts` maps invocation surfaces.

**Workflow fidelity:** After `/go` routes to `one-shot`, Read `plugins/soleur/skills/one-shot/SKILL.md` in this process and run Steps 0–8 to a **merged PR** — not inline implementation + push. See `go.md` Step 2.1 (`go-post-route` block), `one-shot` anti-bypass protocol, and `plugins/soleur/lib/workflow-fidelity.ts`. Golden eval: `bun test plugins/soleur/test/workflow-fidelity.test.ts`.

### Slash collisions (`/help`, `/plan`, `/review`)

Grok built-in slashes can collide with Soleur plugin commands of the same name. Prefer `/go` to classify, then Read the routed `SKILL.md` in this process. If a slash lands on the wrong surface, Read `plugins/soleur/skills/<name>/SKILL.md` directly — do not invent a nested Skill tool.

### Training opt-in

Refuse xAI CLI prompts that offer to "improve the product and model" (or similar training opt-in) on non-personal Soleur / customer repos. Personal-only dogfood is the operator's call.

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
spawn_subagent subagent_type=soleur-engineering-review-security-sentinel prompt="Review the auth changes in PR #123"
```

Grok matches `subagent_type` to the **`.grok/agents/` filename stem** (colons → hyphens), not Claude's colon-qualified registry id. Prefer `spawnAgent()` / `agentIdToGrokSubagentType()` from `plugins/soleur/lib/harness.ts` so `soleur:engineering:review:security-sentinel` becomes `soleur-engineering-review-security-sentinel`. Passing the colon form is listed in some catalogs but is **rejected** at spawn (Grok ≤0.2.102).

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

**Run `grok-pre-push-gate.sh` locally before every `git push` under Grok Build:**

```bash
bash plugins/soleur/scripts/grok-pre-push-gate.sh > /tmp/grok-pre-push-gate.log 2>&1; rc=$?; echo "EXIT=$rc"
```

The gate mirrors reproducible CI: fast required jobs (`readme-counts`, `adr-ordinals`, `rule-body-lint`, `lockfile-sync`, …), `scripts/test-all.sh` (the `test` required check), `web-platform` build, and `grok-fidelity-gate.sh`. It DOES reach `infra-validation`'s suites: the gate invokes `test-all.sh` with no `TEST_GROUP`, which runs `apps/web-platform/infra/run-registered-suites.sh` as a nested suite when the diff touches that directory (#7103 R5(a)). Read the epilogue rather than launching that runner concurrently — both default `TMPDIR=/var/tmp`. CI-only checks (CodeQL, CLA, e2e, tenant-integration) still run on GitHub. Claude Code gets commit-time lint via lefthook; Grok does not — running only `grok-fidelity-gate.sh` misses the `test-scripts` shard (e.g. `B_ALWAYS` budget).

## References

- CONTRIBUTING.md — contributor quickstart
- ADR-110 / #8064 — semantic model-tier map (Accepted)
- `plugins/soleur/lib/harness.ts` — Skill/Task vs slash/spawn_subagent adapter (Phase B)
