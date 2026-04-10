---
title: "OpenHands Portability Recommendation"
date: 2026-04-07
issue: 1770
---

# Recommendation: OpenHands as Alternative Harness

## Decision: CONDITIONAL GO (same as Gemini CLI, different trigger)

OpenHands is a viable second harness for Soleur with distinct trade-offs vs Gemini CLI. Invest in a **minimal OpenHands plugin** when the specific trigger conditions materialize, not preemptively.

## Evidence Summary

| Metric | Codex CLI | Gemini CLI | OpenHands |
|---|---|---|---|
| GREEN (ports as-is) | 47.5% (58/122) | 54.3% (70/129) | 46.5% (60/129) |
| YELLOW (needs adaptation) | 7.4% (9/122) | 45.0% (58/129) | 53.5% (69/129) |
| RED (requires rewrite) | 43.4% (53/122) | 0.8% (1/129) | 0% (0/129) |
| Blockers with no equivalent | 4 | 1 | **0** |
| Subagent parallelism | None | Sequential only | **Parallel (multi-level)** |
| Hook system | None | Post-hoc only | **Full lifecycle** |
| Plugin system | None | None | **Full (install/enable/disable)** |
| AskUserQuestion | None | `ask_user` (direct) | **None (freeform only)** |
| TodoWrite | None | `write_todos` (direct) | **None** |

## OpenHands vs Gemini CLI: Head-to-Head

| Dimension | Gemini CLI | OpenHands | Winner |
|---|---|---|---|
| Overall portability (RED %) | 0.8% RED | 0% RED | **OpenHands** |
| Domain leader fidelity | Degraded (sequential skills) | **Preserved (parallel agents)** | **OpenHands** |
| Hook system | Post-hoc only | **Full PreToolUse + lifecycle** | **OpenHands** |
| Plugin distribution | Manual install | **Plugin system with install/uninstall** | **OpenHands** |
| Interactive prompts | `ask_user` (structured) | Freeform only | **Gemini CLI** |
| Task tracking | `write_todos` | None | **Gemini CLI** |
| Ecosystem maturity | Backed by Google, large user base | Open-source, growing community | **Gemini CLI** |
| Model flexibility | Gemini models only | Claude, GPT, any LLM | **OpenHands** |
| Sandbox isolation | None (direct shell) | Docker sandbox | **OpenHands** (for security) |

**Summary:** OpenHands is architecturally superior (better subagent model, full hooks, plugin system, model-agnostic) but has worse developer UX (no structured prompts, no task tracking). Gemini CLI has better DX primitives but worse architecture (single-level agents, no hooks, no plugins).

## Critical Constraint

**No structured user prompts.** This is OpenHands' primary limitation. Soleur's workflow skills (brainstorm, plan, ship) depend heavily on AskUserQuestion for routing decisions and approval gates. Freeform fallback works but degrades the reliability of multi-option routing.

This is an easier constraint to work around than Gemini CLI's single-level subagent limit — prompt reliability can be improved with careful prompt engineering, while architectural constraints require code restructuring.

## What to Build (when triggered)

### Minimum Viable OpenHands Plugin

A `.plugin/` directory bundled as a GitHub repo, installable via `install_plugin()`:

1. **44 GREEN agents** as `.agents/agents/*.md` — direct port, tool name changes only, flat directory
2. **19 YELLOW agents** (domain leaders + interactive agents) — DelegateTool instructions, freeform prompt fallbacks
3. **15 GREEN skills** as `.agents/skills/*/SKILL.md` — direct port
4. **MCP servers** — Context7, Cloudflare, Vercel, Playwright via `mcp_config`
5. **Hooks** — guardrails.sh, pre-merge-rebase.sh, worktree-write-guard.sh as PreToolUse hooks; welcome-hook.sh as SessionStart hook
6. **AGENTS.md** context file — adapted from CLAUDE.md/AGENTS.md
7. **plugin.json** manifest — name, version, description, author

### What NOT to build

- The 48 YELLOW skills — most are workflow orchestrators that require skill argument passing and chaining. Port only the 5-6 core pipeline skills and accept degraded argument handling.
- A dual-harness abstraction layer — the three platforms (Claude Code, Gemini CLI, OpenHands) have fundamentally different orchestration semantics (isolated execution vs. context injection vs. delegate+spawn).
- A maintained parallel port — maintenance cost exceeds risk mitigation value.

### Unique OpenHands Advantage to Exploit

OpenHands' multi-level parallel DelegateTool means Soleur's hierarchical domain leader architecture ports with FULL FIDELITY for the first time. Neither Codex nor Gemini CLI could preserve this. A marketing angle: "Soleur on OpenHands: the only harness that preserves parallel multi-agent orchestration."

## Trigger for Investment

Invest in the OpenHands plugin when ANY of:

1. **Open-source demand** — Soleur users request OpenHands support (GitHub issues, Discord)
2. **Model flexibility need** — Users want to run Soleur agents with non-Claude models (GPT, Gemini, open-source)
3. **Enterprise sandbox requirement** — Users need Docker-isolated agent execution for compliance
4. **Gemini CLI port is done first** — If Gemini CLI port materializes, OpenHands becomes the natural second target (shared constraint: no skill args)
5. **OpenHands adds ask_user** — Eliminates the primary DX limitation

## Estimated Effort

| Scope | Effort | Outcome |
|---|---|---|
| GREEN agents only (44) | 1-2 days | Basic agent library, no workflows |
| GREEN agents + core skills (15) | 2-3 days | Agent library + simple skills |
| Full plugin (agents + 5 core pipeline skills + hooks) | 1-2 weeks | Degraded but functional workflow pipeline |
| Dual-harness abstraction (Claude Code + OpenHands) | 4+ weeks | Not recommended |

## Follow-up Issues

If proceeding to build:

1. Create issue: "feat: build OpenHands plugin with GREEN agents and hooks"
2. Create issue: "research: verify DelegateTool nesting depth and file-based agent delegation"
3. Create issue: "feat: restructure domain leaders for freeform prompt fallback"
4. Monitor: All-Hands-AI/OpenHands for `ask_user` tool feature requests

## References

- OpenHands portability inventory: `knowledge-base/project/specs/openhands-portability/inventory.md`
- OpenHands critical unknowns: `knowledge-base/project/specs/openhands-portability/critical-unknowns.md`
- Gemini CLI portability inventory: `knowledge-base/project/specs/gemini-cli-portability/inventory.md`
- Gemini CLI recommendation: `knowledge-base/project/specs/gemini-cli-portability/recommendation.md`
- Codex portability inventory: `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`
