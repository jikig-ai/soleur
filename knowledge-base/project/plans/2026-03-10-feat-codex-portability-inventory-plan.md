---
title: feat: Codex Portability Inventory
type: feat
date: 2026-03-10
---

# Codex Portability Inventory

## Overview

Classify every Soleur component (62 agents, 57 skills, 3 commands) by Codex compatibility. Output is a markdown inventory document — no code changes. Grep-based scan with 10 primitives, four-tier classification (green/yellow/red/N/A), and gap annotations.

## Problem Statement / Motivation

Soleur is Claude Code-exclusive. Platform owner competition risk materialized with Anthropic's Cowork Plugins (Feb 2026). Cross-platform presence is identified as a survival moat. We need concrete data on what ports, what doesn't, and at what cost — before committing engineering effort.

## Proposed Solution

Grep all 122 components for 10 portability-critical primitives. Classify each as green/yellow/red/N/A using worst-primitive-wins logic. Write the results into an inventory document with gap annotations per primitive.

```
Phase 1: Baseline (refresh Codex docs, define 10 primitives + equivalence map)
   ↓
Phase 2: Scan & Classify (grep all components, classify as you go, note dependencies)
   ↓
Phase 3: Write inventory document (stats, table, gap analysis)
```

### Phase 1: Baseline

Refresh the Codex capability baseline so classifications are accurate.

- [x] 1.1 Fetch current Codex docs (skills, agents, MCP, hooks, config) via WebFetch
- [x] 1.2 Create `knowledge-base/project/specs/feat-codex-portability-inventory/codex-baseline.md` with current capabilities and verification date
- [x] 1.3 Create equivalence mapping table (each primitive → Codex equivalent or "none")

**Primitives to scan** (10 categories, MEDIUM and HIGH risk only):

| # | Primitive | Grep Pattern | Risk Level |
|---|-----------|-------------|------------|
| 1 | AskUserQuestion | `AskUserQuestion` | HIGH |
| 2 | Skill tool / inter-skill | `skill:` or `Skill tool` | HIGH |
| 3 | Task / subagent | `Task ` (with space) or `subagent_type` | HIGH |
| 4 | $ARGUMENTS | `\$ARGUMENTS` | MEDIUM |
| 5 | TodoWrite | `TodoWrite` | MEDIUM |
| 6 | hookSpecificOutput | `hookSpecificOutput` | HIGH |
| 7 | MCP tool refs | `mcp__plugin_` or `browser_navigate\|browser_snapshot\|browser_click` | HIGH |
| 8 | WebSearch / WebFetch | `WebSearch\|WebFetch` | MEDIUM |
| 9 | CLAUDE_PLUGIN_ROOT | `CLAUDE_PLUGIN_ROOT` | MEDIUM |
| 10 | SessionStart / Stop hooks | `SessionStart\|Stop` (in hooks context) | HIGH |

LOW-risk primitives excluded: `model: inherit` (config-level, trivial mapping), `allowed-tools` (1 active user), `PreToolUse` (conceptual refs only), built-in tool name refs (every component mentions these — noise, not signal).

### Phase 2: Scan & Classify

Grep all components in a single pass. Classify as you go using worst-primitive-wins.

- [x] 2.1 Enumerate all components:
  - Agents: `plugins/soleur/agents/**/*.md` (excluding AGENTS.md, README.md)
  - Skills: `plugins/soleur/skills/*/` (scan entire directory — SKILL.md + references/ + scripts/ + assets/)
  - Commands: `plugins/soleur/commands/*.md`
- [x] 2.2 For each component, grep for all 10 primitives and record matches
- [x] 2.3 Classify each component:

| Classification | Criteria | Color |
|---------------|----------|-------|
| **Green** | Zero primitives found. Ports to Codex as-is (modulo directory restructuring). | 🟢 |
| **Yellow** | Contains only MEDIUM-risk primitives ($ARGUMENTS, TodoWrite, WebSearch/WebFetch, CLAUDE_PLUGIN_ROOT). Needs adaptation but achievable. | 🟡 |
| **Red** | Contains any HIGH-risk primitive (AskUserQuestion, Task/subagent, Skill tool, hookSpecificOutput, MCP tools, SessionStart/Stop). Requires rewrite. | 🔴 |
| **N/A** | Component exists solely to serve Claude Code architecture (e.g., `heal-skill`, `skill-creator`, `pencil-setup`). No purpose on Codex. | ⚪ |

- [x] 2.4 Flag N/A candidates: must reference Claude Code plugin infrastructure with zero user-facing value independent of the platform
- [x] 2.5 Note inter-component dependencies as you scan (which skills invoke other skills via `skill:`, which spawn subagents via `Task`)

### Phase 3: Write Inventory Document

Compile into `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`.

- [x] 3.1 Summary statistics: green/yellow/red/N/A counts and percentages
- [x] 3.2 Full component inventory table: Name, Type, Domain, Classification, Primitives Found, Codex Equivalent
- [x] 3.3 Gap analysis per non-portable primitive: usage count, files affected, Codex equivalent (or "none")
- [x] 3.4 CI/Infrastructure note: mention GitHub Actions workflows and PreToolUse hook scripts as platform-locked infrastructure (not counted in the 122 components)

## Acceptance Criteria

- [x] All 122 components classified (green/yellow/red/N/A)
- [x] Each non-green component has gap annotation: which primitives block and Codex equivalent
- [x] Codex capability baseline documented with verification date
- [x] No code changes to existing Soleur plugin files

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Codex capabilities change between scan and consumption | Pin verification date in output |
| Grep misses implicit dependencies | Conservative classification (over-classifies, doesn't under-classify) |
| Component count drifts | Use dynamic discovery, not hardcoded count |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-10-codex-portability-inventory-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-codex-portability-inventory/spec.md`
- Component discovery: `plugins/soleur/test/helpers.ts`
- Staleness audit pattern: `knowledge-base/project/learnings/2026-02-09-plugin-staleness-audit-patterns.md`
- Grep proximity: `knowledge-base/project/learnings/2026-02-24-guardrails-grep-false-positive-worktree-text.md`
- Platform risk: `knowledge-base/project/learnings/2026-02-25-platform-risk-cowork-plugins.md`

### External References

- [Codex CLI docs](https://developers.openai.com/codex/cli/)
- [Codex Agent Skills](https://developers.openai.com/codex/skills/)
- [Codex Multi-agents](https://developers.openai.com/codex/multi-agent/)
- [Codex Config Reference](https://developers.openai.com/codex/config-reference/)
- [Codex Changelog](https://developers.openai.com/codex/changelog/)
- [SessionStart hook feature request (issue #13014)](https://github.com/openai/codex/issues/13014)

### Related Work

- Issue: #509
- PR: #511
