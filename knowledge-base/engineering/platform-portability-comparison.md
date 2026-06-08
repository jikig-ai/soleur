---
title: "Platform Portability Comparison"
last_updated: 2026-06-08
platforms:
  - codex-cli
  - gemini-cli
  - openhands
  - deepagents
---

# Platform Portability Comparison

Unified comparison of Soleur portability across all analyzed agent platforms. Updated when new inventories are produced or platform capabilities change.

## Summary

| Metric | Codex CLI | Gemini CLI | OpenHands | deepagents |
|---|---|---|---|---|
| **Scan date** | 2026-03-10 | 2026-04-07 | 2026-04-07 | 2026-06-08 |
| **Platform version** | 0.113.0 | 0.36.0 | SDK 1.15.0 | 0.6.8 + dcode |
| **Components scanned** | 122 | 129 | 129 | 152 |
| **GREEN** (ports as-is) | 47.5% (58) | 54.3% (70) | 46.5% (60) | 19.7% (30) |
| **YELLOW** (needs adaptation) | 7.4% (9) | 45.0% (58) | 53.5% (69) | 80.3% (122) |
| **RED** (requires rewrite) | 43.4% (53) | 0.8% (1) | 0% (0) | 0% (0) |
| **Decision** | Wait and monitor | Conditional go | Conditional go | No-go (port) / conditional (rebuild) |
| **Issue** | #509 | #1738 | #1770 | #5034 |

**deepagents is the second zero-RED target but has the lowest GREEN% of any platform.** Every Soleur primitive has an equivalent (like OpenHands), yet GREEN drops to 19.7% because deepagents subagents are Python `SubAgent` dicts — there is no markdown-agent loader, so all 67 markdown agents flip to YELLOW. Skills port *better* than on any prior target (identical `SKILL.md` format). The OpenHands portability pattern inverts: agents expensive, skills cheap, no plugin distribution.

## Primitive Mapping

| Claude Code Primitive | Codex CLI | Gemini CLI | OpenHands | deepagents |
|---|---|---|---|---|
| AskUserQuestion | RED: no equivalent | GREEN: `ask_user` | YELLOW: freeform only | YELLOW: HITL respond (no options) |
| TodoWrite / TaskCreate | RED: no equivalent | GREEN: `write_todos` | GREEN: `TaskTrackerTool` | GREEN: `write_todos` (built-in) |
| WebSearch | YELLOW: `web_search` flag | GREEN: `google_web_search` | GREEN: MCP bundled | YELLOW: BYO tool |
| WebFetch | YELLOW: unclear | GREEN: `web_fetch` | GREEN: MCP bundled | YELLOW: BYO tool |
| MCP tools | YELLOW: stdio only | GREEN: stdio + HTTP | GREEN: stdio + HTTP | GREEN: stdio+HTTP+SSE+WS (explicit wiring) |
| Task / Agent (subagent) | RED: no equivalent | YELLOW: single-level sequential | GREEN: multi-level parallel | GREEN: parallel (Python dicts; nesting untested) |
| Skill tool (chaining) | RED: no equivalent | YELLOW: `activate_skill` (context) | YELLOW: context injection | YELLOW: SkillsMiddleware (identical SKILL.md) |
| $ARGUMENTS | RED: no equivalent | YELLOW: commands only (`{{args}}`) | YELLOW: TaskTrigger inputs | YELLOW: dcode `/skill` args only |
| hookSpecificOutput | RED: no equivalent | RED: different protocol | GREEN: JSON additionalContext | GREEN: middleware (Python) |
| SessionStart/Stop hooks | RED: no equivalent | RED: no equivalent | GREEN: full lifecycle | GREEN: before/after_agent + checkpointers |
| Agent authoring format | Config YAML | Markdown (flat) | Markdown (flat) | **Python `SubAgent` dict** |
| Plugin / distribution | None | None | Full (install/enable/disable) | None (Python pkg + skills dir) |

## Architecture Comparison

| Capability | Codex CLI | Gemini CLI | OpenHands | deepagents |
|---|---|---|---|---|
| Agent format | Config YAML | `.gemini/agents/*.md` | `.agents/agents/*.md` | Python `SubAgent` TypedDict |
| Skill format | SKILL.md | SKILL.md | SKILL.md | SKILL.md (progressive disclosure) |
| Agent discovery | Config registration | Flat dir scan | Flat dir scan | Python (passed to `create_deep_agent`) |
| Subagent nesting | None | Single-level | Multi-level | Multi-level (not prevented; untested) |
| Subagent parallelism | N/A | Sequential | Parallel | Parallel |
| Hook system | SessionStart (request) | Post-hoc only | Full lifecycle (6 events) | LangGraph middleware (Python) |
| Plugin system | None | None | Full | None (skills dir only) |
| Model support | OpenAI only | Gemini only | Any LLM | Any LangChain chat model |
| Execution sandbox | None | None (direct shell) | Docker | Remote sandbox backends (optional) |
| Persistence | None | None | Docker state | Durable checkpointers (Postgres/Redis) |
| Per-agent tool scoping | No | No | Yes | Yes (`tools` on SubAgent) |
| Per-agent hooks | No | No | Yes | Yes (`middleware` on SubAgent) |
| Per-agent MCP | No | No | Yes | Yes (via tools) |
| Operator harness | CLI | CLI | CLI + SDK | SDK + dcode CLI (young) |

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
- First zero-RED target; multi-level parallel subagents preserve the domain-leader hierarchy as markdown
- Full lifecycle hook system + full plugin system (install/enable/disable)
- Model-agnostic; Docker sandbox; per-agent scoping
- AgentDefinition is a superset of Soleur's markdown format (cheapest mechanical port)

### deepagents
- Second zero-RED target; every primitive has an equivalent
- **Identical SKILL.md format** — skills port better than any prior target
- **Built-in `write_todos`** (only OpenHands lacked it)
- **True model-agnosticism** — any LangChain chat model (the #1 differentiator)
- **Durable checkpointer persistence** (Postgres/Redis) — strongest of any target; ideal for a server-side runtime
- **Now a real harness** (`dcode`), explicitly modeled on Claude Code
- MIT, ~24k★, LangChain Inc.-backed, frequent releases; LangSmith observability

## Platform Weaknesses

### Codex CLI
- 43.4% RED — 4 fundamental blockers; not viable without major platform changes

### Gemini CLI
- Single-level sequential subagents (breaks domain-leader hierarchy); no hooks; no plugin system; flat agent dir

### OpenHands
- No structured user prompts; skills are context-injection only; flat agent directory; young plugin ecosystem

### deepagents
- **Lowest GREEN% (19.7%)** — all 67 agents require markdown→Python rewrite (no markdown-agent loader)
- **No plugin/distribution system** — ship as Python package + skills dir; no enable/disable/marketplace (worse than OpenHands)
- No structured user prompts (HITL respond only)
- Bash hooks must be rewritten as Python middleware
- `dcode` harness is young (v0.1.0, packaging churn); long-pipeline maturity unverified
- MCP requires explicit Python wiring (no `.mcp.json` auto-load)

## Investment Triggers

| Platform | Trigger | Estimated Effort |
|---|---|---|
| Codex CLI | Wait for: PreToolUse hooks, subagent delegation | N/A (not viable today) |
| Gemini CLI | Any of: Anthropic restricts Max plan, API rate limits, competitor ships multi-harness, Gemini adds multi-level subagents | 1-2 weeks (degraded pipeline) |
| OpenHands | Any of: open-source demand, model flexibility, enterprise sandbox, Gemini port done first, OpenHands adds ask_user | 1-2 weeks (degraded pipeline) |
| deepagents | Any of: hard model-agnosticism requirement, server-side durable runtime greenlit, LangGraph/LangSmith adopted in stack, skills-as-product, dcode matures past v0.1.0 | Skills-only 1-2 wk; full port 6-10 wk (not recommended); server-side rebuild = separate initiative |

**Harness redundancy → OpenHands. Model-agnosticism / server-side durable runtime → deepagents.** They serve different goals; deepagents is not a cheaper OpenHands.

## Source Inventories

- Codex: `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`
- Gemini CLI: `knowledge-base/project/specs/gemini-cli-portability/inventory.md`
- OpenHands: `knowledge-base/project/specs/openhands-portability/inventory.md`
- OpenHands PoC: `knowledge-base/project/specs/openhands-portability/poc-results.md`
- Gemini CLI PoC: `knowledge-base/project/specs/gemini-cli-portability/poc-results.md`
- deepagents: `knowledge-base/project/specs/feat-deepagents-portability/inventory.md`
- deepagents recommendation: `knowledge-base/project/specs/feat-deepagents-portability/recommendation.md`
- deepagents critical unknowns: `knowledge-base/project/specs/feat-deepagents-portability/critical-unknowns.md`
