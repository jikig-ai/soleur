# OpenHands Portability Inventory

**Date:** 2026-04-07
**Issue:** #1770
**Status:** Decided
**Branch:** openhands-portability

## What We're Building

A comprehensive portability inventory that classifies every Soleur component (63 agents, 63 skills, 3 commands) by OpenHands compatibility: green (ports as-is), yellow (needs adaptation), red (requires rewrite). Each yellow component includes gap annotations identifying which Claude Code primitives differ and what the OpenHands equivalent is. The inventory concludes with a recommendation and critical unknowns requiring PoC verification.

This follows the same methodology used for the Codex portability inventory (#509, 2026-03-10) and the Gemini CLI portability inventory (#1738, 2026-04-07). The three inventories together provide a complete platform risk assessment across all viable alternative harnesses.

## Why This Approach

### Motivation

- **Strategic completeness:** Codex (OpenAI) and Gemini CLI (Google) inventories already exist. OpenHands is the third major alternative harness. Completing this inventory gives a full picture of platform portability options.
- **Architectural uniqueness:** OpenHands is the only target with multi-level parallel subagent support and a full lifecycle hook system — features that could preserve Soleur's hierarchical domain leader architecture.
- **Open-source hedge:** Unlike Codex and Gemini CLI (proprietary platforms), OpenHands is open-source and model-agnostic. It represents a fundamentally different risk profile.

### Why inventory-first (not build)

- Same rationale as Codex: understand the concrete engineering cost before committing.
- OpenHands' plugin system is young. Building now risks investing on shifting foundations.
- The Gemini CLI inventory is fresher (same day) and provides a direct comparison baseline.

## Key Decisions

1. **Scope: OpenHands only** — Completes the three-platform analysis (Codex, Gemini CLI, OpenHands). No other platforms analyzed.

2. **Same 10 primitives + delta** — Uses identical primitive list as Codex/Gemini for direct comparison. OpenHands-specific considerations (Docker sandbox, Python SDK) noted separately.

3. **Classification: Traffic light with three-way comparison** — Each component shows its OpenHands classification alongside its Gemini CLI status, highlighting where OpenHands is better or worse.

4. **Production method: Grep scan + doc analysis** — Automated scan for Claude Code primitives, classified against OpenHands SDK documentation (not source code). Critical unknowns flagged for PoC verification.

5. **No engineering output** — Research document only. No abstraction layers, no plugin build.

## Research Findings

### Three-Platform Summary

| Platform | GREEN | YELLOW | RED | Best For |
|---|---|---|---|---|
| Codex CLI | 47.5% | 7.4% | 43.4% | N/A — too many blockers |
| Gemini CLI | 54.3% | 45.0% | 0.8% | Quick port, structured DX (ask_user, write_todos) |
| OpenHands | 46.5% | 53.5% | 0% | Architecture fidelity (parallel subagents, hooks, plugins) |

### OpenHands Unique Advantages

1. **Multi-level parallel DelegateTool** — Only platform that preserves Soleur's hierarchical domain leader → specialist pattern with parallel execution.
2. **Full lifecycle hook system** — PreToolUse, PostToolUse, UserPromptSubmit, Stop, SessionStart, SessionEnd with JSON blocking/context injection.
3. **Plugin system** — install/enable/disable/uninstall with manifest. Distribution model for Soleur as a package.
4. **Model-agnostic** — Supports Claude, GPT, Gemini, and open-source models. Users not locked to one provider.

### OpenHands Unique Disadvantages

1. **No ask_user** — No structured multi-choice prompt tool. Biggest DX gap vs Gemini CLI.
2. **No write_todos** — No task tracking tool. File-based workaround needed.
3. **Flat agent directory** — Same constraint as Gemini CLI (no subdirectory recursion).
4. **Docker sandbox** — Adds isolation (good for security) but may limit host-level operations.

## Open Questions

1. **DelegateTool nesting depth** — Documented as unlimited but not verified. If limited, domain leader architecture degrades.
2. **File-based agent delegation** — Can file-based `.md` agents use DelegateTool to spawn other file-based agents? Not shown in docs.
3. **Plugin system maturity** — How robust is install/uninstall from GitHub repos? No public registry exists.
4. **AskUserQuestion workaround quality** — How reliably do models parse freeform option-list responses?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** OpenHands eliminates 4 of 5 Codex blockers. Projected ~80% green (optimistic, counts tool-name changes as green). The remaining blocker — skill-to-skill chaining (13 skills, 49 call sites) — is concentrated in the workflow pipeline and requires an architecture decision on the orchestration model (agent-chain, mega-skill, or hybrid). Estimated 2-3 weeks for a full port if triggered. No abstraction layer recommended.
