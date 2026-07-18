---
title: Grok spawn_subagent matches .grok/agents filename stem, not colon-qualified name
date: 2026-07-17
category: workflow-patterns
tags: [grok, spawn_subagent, agent-discoverability, harness]
---

# Learning: Grok spawn_subagent matches filename stem, not colon-qualified name

## Problem

Brainstorm Phase 0.5 (and any Grok session) failed to spawn Soleur domain leaders:

```text
Unknown subagent type: soleur:product:cpo.
Available types: … soleur:product:cpo …
```

The type appeared in the available-types catalog (and in `grok inspect`) but spawn still rejected it. Session fell back to `general-purpose` role-prompts.

## Root cause

Phase E (#6324) registered agents as flat project stubs under `.grok/agents/`:

| Surface | Value |
|---------|--------|
| File | `.grok/agents/soleur-product-cpo.md` |
| Frontmatter `name:` (pre-fix) | `soleur:product:cpo` |
| Canonical Claude id | `soleur:product:cpo` |

Grok Build **0.2.102** validates `spawn_subagent.subagent_type` against the **filename stem** (`soleur-product-cpo`), not the frontmatter `name:`. Catalog/error text was built from frontmatter, so colon-form looked valid and then failed. Single-colon plugin agents (`feature-dev:code-reviewer`) still worked because their spawn key matches plugin discovery, not multi-segment Soleur IDs.

Empirical check (2026-07-17):

- `subagent_type=soleur:product:cpo` → Unknown subagent type
- `subagent_type=soleur-product-cpo` → spawns, loads stub body

## Solution

1. **`agentIdToGrokSubagentType(id)`** in `plugins/soleur/lib/agent-registry.ts` — `:` → `-`.
2. **`spawnAgent` / `formatAgentSpawn`** on Grok harness emit the hyphen key (canonical colon id still named in the instruction for humans).
3. **`sync-grok-agent-compat.ts`** writes frontmatter `name:` as the hyphen spawn key so available-types catalogs match what spawn accepts.
4. Re-run `bun run scripts/sync-grok-agent-compat.ts` after agent add/remove.

## Verification

```bash
cd plugins/soleur && bun test test/agent-registry.test.ts test/harness.test.ts test/grok-agent-discoverability.test.ts
# Live: spawn_subagent soleur-product-cpo succeeds; soleur:product:cpo fails until Grok fixes stem vs name
```

## Key insight

Discoverability (inspect lists the agent) ≠ spawnability (type key accepted by spawn). For Grok project agents, **filename stem is the load-bearing identity**; keep frontmatter `name` aligned with that stem, and map Claude colon IDs through the harness before `spawn_subagent`.
