---
title: "Platform Portability Comparison"
last_updated: 2026-04-07
platforms:
  - codex-cli
  - gemini-cli
  - openhands
---

# Platform Portability Comparison

Unified comparison of Soleur portability across all analyzed agent platforms. Updated when new inventories are produced or platform capabilities change.

## Summary

| Metric | Codex CLI | Gemini CLI | OpenHands |
|---|---|---|---|
| **Scan date** | 2026-03-10 | 2026-04-07 | 2026-04-07 |
| **Platform version** | 0.113.0 | 0.36.0 | SDK 1.15.0 |
| **Components scanned** | 122 | 129 | 129 |
| **GREEN** (ports as-is) | 47.5% (58) | 54.3% (70) | 46.5% (60) |
| **YELLOW** (needs adaptation) | 7.4% (9) | 45.0% (58) | 53.5% (69) |
| **RED** (requires rewrite) | 43.4% (53) | 0.8% (1) | 0% (0) |
| **Decision** | Wait and monitor | Conditional go | Conditional go |
| **Issue** | #509 | #1738 | #1770 |

## Primitive Mapping

| Claude Code Primitive | Codex CLI | Gemini CLI | OpenHands |
|---|---|---|---|
| AskUserQuestion | RED: no equivalent | GREEN: `ask_user` | YELLOW: freeform only |
| TodoWrite / TaskCreate | RED: no equivalent | GREEN: `write_todos` | GREEN: `TaskTrackerTool` (plan/view) |
| WebSearch | YELLOW: `web_search` flag | GREEN: `google_web_search` | GREEN: MCP bundled |
| WebFetch | YELLOW: unclear | GREEN: `web_fetch` | GREEN: MCP bundled |
| MCP tools | YELLOW: stdio only | GREEN: stdio + HTTP | GREEN: stdio + HTTP |
| Task / Agent (subagent) | RED: no equivalent | YELLOW: single-level sequential | GREEN: multi-level parallel |
| Skill tool (chaining) | RED: no equivalent | YELLOW: `activate_skill` (context) | YELLOW: context injection |
| $ARGUMENTS | RED: no equivalent | YELLOW: commands only (`{{args}}`) | YELLOW: TaskTrigger `inputs` |
| hookSpecificOutput | RED: no equivalent | RED: different protocol | GREEN: JSON `additionalContext` |
| SessionStart/Stop hooks | RED: no equivalent | RED: no equivalent | GREEN: full lifecycle |

## Architecture Comparison

| Capability | Codex CLI | Gemini CLI | OpenHands |
|---|---|---|---|
| Agent format | Config YAML (agents/openai.yaml) | `.gemini/agents/*.md` (flat) | `.agents/agents/*.md` (flat) |
| Skill format | SKILL.md (same frontmatter) | SKILL.md (same frontmatter) | SKILL.md (same frontmatter) |
| Agent discovery | Config-based registration | Flat directory scan | Flat directory scan |
| Subagent nesting | None (max_depth=1) | Single-level only | Multi-level (unlimited documented) |
| Subagent parallelism | N/A | Sequential only | Parallel threads |
| Hook system | SessionStart (feature request) | Post-hoc only (notify) | Full lifecycle (6 event types) |
| Plugin system | None | None | Full (install/enable/disable/uninstall) |
| Model support | OpenAI models only | Gemini models only | Any LLM (Claude, GPT, Gemini, open-source) |
| Execution sandbox | None | None (direct shell) | Docker sandbox (optional) |
| Per-agent tool scoping | No | No | Yes (tools field in frontmatter) |
| Per-agent hooks | No | No | Yes (hooks field in frontmatter) |
| Per-agent MCP | No | No | Yes (mcp_servers field in frontmatter) |

## Platform Strengths

### Codex CLI

- Identical SKILL.md format (zero content changes for green skills)
- Growing ecosystem backed by OpenAI

### Gemini CLI

- Best developer UX primitives (`ask_user`, `write_todos` — direct equivalents)
- Highest GREEN percentage (54.3%)
- Command argument interpolation (`{{args}}` in TOML)
- Unlimited skill chaining depth (context injection)

### OpenHands

- Only platform with 0% RED (zero blockers)
- Multi-level parallel subagent support (preserves domain leader architecture)
- Full lifecycle hook system (PreToolUse, PostToolUse, Stop, SessionStart, SessionEnd)
- Plugin system with install/enable/disable/uninstall
- Model-agnostic (Claude, GPT, Gemini, open-source)
- Per-agent tool scoping, hooks, and MCP configuration
- AgentDefinition is a superset of Soleur's format (gains features on port)
- Docker sandbox for security isolation

## Platform Weaknesses

### Codex CLI

- 43.4% RED — 4 fundamental blockers with no equivalent
- No hooks, no subagent delegation, no plugin system
- Verdict: not viable without major platform changes

### Gemini CLI

- Single-level subagent nesting (breaks domain leader hierarchy)
- Sequential-only agent execution (no parallelism)
- No hook system (post-hoc only)
- No plugin system (manual file distribution)
- Flat agent directory (no subdirectory organization)

### OpenHands

- No structured user prompts (no `ask_user` equivalent)
- Skills are context injection only (no programmatic invocation with args)
- Flat agent directory (no subdirectory organization)
- Docker sandbox may limit host-level operations
- Young plugin ecosystem (no public registry)

## Investment Triggers

| Platform | Trigger | Estimated Effort |
|---|---|---|
| Codex CLI | Wait for: PreToolUse hooks, subagent delegation | N/A (not viable today) |
| Gemini CLI | Any of: Anthropic restricts Max plan, API rate limits, competitor ships multi-harness, Gemini adds multi-level subagents | 1-2 weeks (degraded pipeline) |
| OpenHands | Any of: open-source demand, model flexibility need, enterprise sandbox requirement, Gemini port done first, OpenHands adds ask_user | 1-2 weeks (degraded pipeline) |

## Source Inventories

- Codex: `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`
- Gemini CLI: `knowledge-base/project/specs/gemini-cli-portability/inventory.md`
- OpenHands: `knowledge-base/project/specs/openhands-portability/inventory.md`
- OpenHands PoC: `knowledge-base/project/specs/openhands-portability/poc-results.md`
- Gemini CLI PoC: `knowledge-base/project/specs/gemini-cli-portability/poc-results.md`
