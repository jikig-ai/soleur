---
title: External agent discovery via registry integration and stack-based gap detection
date: 2026-02-18
category: implementation-patterns
module: soleur-plugin
component: agent-discovery
tags: [external-agents, registry-integration, stack-detection, gap-detection, provenance-tracking, plugin-loader]
severity: medium
---

# Learning: External Agent Discovery Patterns

## Problem

The Soleur plugin ships with agents for Rails, security, and architecture but has no way to discover community agents for uncovered stacks (Flutter, Rust, Elixir, etc.). Needed to add discovery without breaking the existing plugin loader or requiring loader changes.

## Key Insights

### 1. Plugin loader accepts arbitrary frontmatter fields

The Claude Code plugin loader parses YAML frontmatter and only checks for `name`, `description`, and `model`. Extra fields (`stack`, `source`, `registry`, `installed`, `verified`) are silently ignored. This was verified by creating a test agent with all extra fields and running the full test suite (513 tests passed).

This means provenance metadata can live directly in frontmatter -- no need for markdown comment blocks or sidecar files.

### 2. Stack-based gap detection beats filename heuristics

Instead of guessing coverage from agent filenames (e.g., "dhh-rails" contains "rails"), use an explicit `stack: rails` frontmatter field. Gap detection becomes a simple grep:

```bash
grep -rl "stack: flutter" plugins/soleur/agents/ 2>/dev/null
```

Benefits: no false positives from partial name matches, works for community agents (they include `stack:` in provenance), and re-running `/plan` after installing a community agent correctly detects coverage.

### 3. Directory asymmetry between agents and skills is intentional

- **Agents:** `agents/community/<name>.md` -- loader recurses into subdirectories
- **Skills:** `skills/community-<name>/SKILL.md` -- loader only discovers `skills/*/SKILL.md` (flat)

This is a Claude Code runtime limitation, not configurable. The workaround uses a naming prefix (`community-`) for skills instead of a subdirectory. Both patterns support easy bulk cleanup (`rm -rf agents/community/` or `rm -rf skills/community-*/`).

### 4. Use curl for JSON APIs, not WebFetch

WebFetch converts HTML to markdown and processes through an AI model. For JSON REST APIs (like registry endpoints), use Bash `curl` directly. The raw JSON is parseable by the agent without the HTML-to-markdown conversion overhead.

### 5. Discovery placement matters: Phase 1.5, not Phase 0.1

At Phase 0.1 of `/plan`, the feature description hasn't been refined yet. In a Rails + Flutter monorepo, you don't know which stack the feature touches until after idea refinement. Phase 1.5 (after idea refinement + local research) is the correct placement -- the idea is clear and the relevant stack is known.

Trade-off: agents installed at Phase 1.5 don't participate in the current `/plan` run. They benefit subsequent commands. This is acceptable.

## Solution

Created a 3-tier architecture:
1. `stack:` frontmatter field on agents for gap detection
2. `agent-finder` agent that queries 3 unauthenticated registries in parallel
3. Phase 1.5 in `/plan` that detects stacks, checks gaps, and conditionally spawns agent-finder

Trust model: Anthropic repos (always), Verified publishers (always), Unverified community (never suggested).

## Cross-References

- Plugin loader recursion: `knowledge-base/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md`
- MCP bundling constraints: `knowledge-base/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`
- Adding plugin commands: `knowledge-base/learnings/implementation-patterns/adding-new-plugin-commands.md`
- Spec: `knowledge-base/specs/feat-external-agent-discovery/spec.md`
- Registry research: `knowledge-base/specs/feat-external-agent-discovery/registry-research.md`
- Issue: #55
