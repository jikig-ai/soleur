---
module: soleur-plugin
date: 2026-04-09
problem_type: workflow-pattern
component: openhands-plugin
tags: [openhands, portability, agents, plugin-format, multi-platform]
severity: info
---

# OpenHands Plugin Agent Porting Pattern

## Problem

Porting 44 GREEN agents from Claude Code nested directory structure (`plugins/soleur/agents/<domain>/<subdomain>/<name>.md`) to OpenHands flat plugin format (`plugins/soleur/.openhands-plugin/agents/<name>.md`). Needed to transform frontmatter while preserving body content exactly.

## Solution

1. **Directory structure:** OpenHands plugins use `.plugin/plugin.json` manifest + flat `agents/*.md` directory (no nesting)
2. **Frontmatter changes:** Add `tools:` field (OpenHands requires explicit tool declaration), remove Claude Code-specific fields (`stack`, `color`), keep `model: inherit`
3. **Tool mapping:** All 44 GREEN agents are analysis/advisory — mapped to `[terminal, file_editor]` (covers bash commands, file reading, grep, git)
4. **Body preservation:** System prompt content copied verbatim — no content changes needed for GREEN agents

## Key Insight

OpenHands agents are structurally simpler than Claude Code agents: flat directory, explicit tool list, no domain-based nesting. The simplification is a feature — `load_agents_from_dir()` scans a single directory. Agent names must be globally unique (no domain namespace), which was already true for all 44 Soleur agents.

The `tools: [terminal, file_editor]` pair covers most agent needs because `terminal` subsumes git, curl, grep, semgrep, and gh CLI. Only agents that spawn sub-agents need `delegate` (YELLOW agents, not in this batch).

## Related

- Issue: #1774
- Parent research: #1770 (OpenHands portability inventory)
- Inventory: `knowledge-base/project/specs/openhands-portability/inventory.md`
- Recommendation: `knowledge-base/project/specs/openhands-portability/recommendation.md`
