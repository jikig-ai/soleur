---
title: "feat: External agent discovery via registry integration"
type: feat
date: 2026-02-12
---

# External Agent Discovery via Registry Integration

## Overview

Research spike to verify whether external registries (tessl.io, skills.sh) expose usable APIs for agent discovery. Implementation deferred until real user demand emerges.

## Problem Statement

The Soleur plugin ships with a fixed set of agents covering specific stacks (Rails, security, architecture). When a project uses a framework not covered by built-in agents (Flutter, Rust, Elixir, etc.), users have no way to discover community-maintained agents.

## Plan Review Outcome [Updated 2026-02-12]

Three reviewers (DHH, Kieran, Simplicity) unanimously challenged the original multi-phase plan:

- **No community demand exists.** The feature was separated from #46 specifically because of this.
- **The existing conditional agents pattern already works.** When a new stack needs support, write an agent and add a conditional block. 15 minutes.
- **The constitution warns against this.** "Start with manual workflows; add automation only when users explicitly request it." "Before designing new infrastructure, check if existing patterns solve the problem."
- **Security model inadequate.** "User consent only" for community agents that become system prompts is insufficient.

**Decision: Research spike only.** Verify registry APIs exist and document findings. Do not build discovery infrastructure until real demand emerges.

## Scope: Research Spike Only

- [x] Check if tessl.io exposes an MCP HTTP endpoint -- **No.** Stdio-only MCP, auth-walled CLI, no public REST API.
- [x] Check if skills.sh or Anthropic's skills repo expose MCP/API endpoints -- **skills.sh: CLI only, no API.** Anthropic repos: GitHub API, structured JSON.
- [x] Check SkillsMP (skillsmp.com) and MCP Market (mcpmarket.com) for API access -- **SkillsMP: REST API + MCP servers.** MCP Market: no API.
- [x] Document response schemas for each registry that has an API
- [x] If MCP endpoints exist, test with a sample query and record the response -- **SkillsMP has community MCP servers.**
- [x] If CLI tools exist, install and test (`tessl skill search <query>`) -- **Documented, not tested (auth wall).**
- [x] Write findings to `knowledge-base/specs/feat-external-agent-discovery/registry-research.md`

**Exit criteria:** A document describing what each registry exposes, with sample responses. No implementation decisions.

## What Happens After the Spike

If registries have usable APIs:
- Document the manual workflow: "How to add a community agent" (drop markdown file in `agents/`)
- Wait for user demand before building any automation
- When demand emerges, start with a single `/find-agent` command (no command hooks, no new directories)

If registries do not have usable APIs:
- Close or park #55
- The feature is blocked on external infrastructure

## Original Plan (Archived)

The original multi-phase plan (discovery agent, community directory, command integration, MCP fallback chains) is preserved in git history. Key design decisions from the brainstorm remain valid if/when demand emerges:

- Discovery agent pattern (dedicated agent handles registry logic)
- Install-as-static (community agents become regular markdown files)
- User consent always required
- Graceful degradation (network failures warn, don't block)

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-12-external-agent-discovery-brainstorm.md`
- Spec: `knowledge-base/specs/feat-external-agent-discovery/spec.md`
- Registry research: `knowledge-base/specs/feat-external-agent-discovery/registry-research.md`
- Issue: #55
- Review command conditional agents: `plugins/soleur/commands/soleur/review.md:81-138`
- Constitution: `knowledge-base/overview/constitution.md`
