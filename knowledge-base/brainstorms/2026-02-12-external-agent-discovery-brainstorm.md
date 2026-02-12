# External Agent Discovery via Registry Integration

**Date:** 2026-02-12
**Status:** Active
**Issue:** #55
**Prior work:** Archived brainstorm from #46 in `knowledge-base/brainstorms/archive/`

## What We're Building

A discovery agent that can search external registries (tessl.io, skills.sh) for community-maintained agents, vet them against a quality threshold, and install approved agents as static markdown files in `plugins/soleur/agents/community/`.

Any command (review, plan, work) can invoke this discovery agent when it detects a capability gap for the current project type. The agent handles registry search, conflict prevention, quality filtering, and installation -- commands just say "find me relevant agents."

## Why This Approach

**Discovery Agent (Approach C)** was chosen over direct MCP integration or CLI wrappers because:

- **Encapsulation** -- All discovery logic lives in one agent. Commands stay simple.
- **Registry-agnostic** -- The agent can use MCP tools, CLI, or web APIs depending on what's available. Commands don't care how discovery works internally.
- **Nuanced decisions** -- The agent can reason about relevance, quality, and conflicts better than hardcoded logic. It can explain _why_ it's suggesting an agent.
- **Easy to evolve** -- Adding a new registry means updating one agent, not every command.

**Rejected alternatives:**
- **Direct MCP in commands (Approach A):** Spreads registry logic across every command. Harder to maintain.
- **CLI wrapper script (Approach B):** Parsing CLI output is fragile. Requires npm global install of `@tessl/cli`.

## Key Decisions

1. **Architecture: Discovery agent** -- A dedicated agent in `plugins/soleur/agents/discovery/` handles all registry interactions. Commands spawn this agent when they detect capability gaps.

2. **Registry access: MCP-first, CLI fallback** -- Try MCP HTTP endpoints first (same pattern as context7). If a registry doesn't expose MCP, fall back to its CLI tool.

3. **Installation: Static markdown** -- External agents are installed as standard markdown files in `plugins/soleur/agents/community/`. Once installed, they're indistinguishable from built-in agents at runtime. Tracking frontmatter (`source:`, `installed:`) records provenance.

4. **Conflict prevention** -- Only suggest external agents for genuinely missing capabilities. If a local agent covers the same category, the external agent is not surfaced.

5. **Quality bar: Score threshold** -- Agents must meet a minimum evaluation score from the registry (e.g., tessl.io percentage scores). Low-quality agents are filtered out before presentation.

6. **Updates: Skip for v1** -- No auto-update mechanism. If an agent is outdated, user deletes and reinstalls. Solve the update problem when it actually becomes painful.

7. **Discovery trigger: Command-level integration** -- Each command that could benefit (review, plan, work) gets explicit discovery logic: "Before starting, check if relevant community agents exist for this project type."

8. **User consent: Always required** -- No agent installs without explicit approval. Show registry source, score, description, and why it's relevant.

9. **Graceful degradation** -- Network failures warn and continue with local agents only. Registries being down never blocks a workflow.

## Open Questions

- **MCP endpoint availability** -- Do tessl.io and skills.sh expose MCP HTTP endpoints? If not, CLI fallback path needs to be built. Research needed before implementation.
- **Score threshold value** -- What minimum score is appropriate? Needs empirical testing against actual registry data.
- **Community directory structure** -- Should `community/` agents be organized into subcategories (review/, research/) matching the built-in structure, or kept flat?
- **Frontmatter schema** -- Exact fields for tracking provenance: `source`, `installed`, `registry-score`, `registry-url`?
