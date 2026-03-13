# Codex Platform Portability Inventory

**Date:** 2026-03-10
**Issue:** #509
**Status:** Decided
**Branch:** feat-codex-portability-inventory

## What We're Building

A comprehensive portability inventory that classifies every Soleur component (62 agents, 57 skills, 3 commands) by Codex compatibility: green (ports as-is), yellow (needs adaptation), red (requires rewrite). Each yellow/red component includes gap annotations identifying which Claude Code primitives block portability and what the Codex equivalent is (or "none exists"). The inventory concludes with a recommended porting sequence for maximum value with minimum effort.

This is a research artifact — no code changes, no abstraction layer, no port. Pure feasibility data.

## Why This Approach

### Motivation (all three apply)
- **Strategic hedge:** De-risk against Claude Code platform dependency. Anthropic's Cowork Plugins launch (Feb 2026) showed platform owners can absorb horizontal features.
- **Market opportunity:** Codex adoption is growing; Soleur's domain knowledge (62 agents' worth of business expertise) has value beyond Claude Code.
- **Sizing:** Understand the concrete engineering cost before committing to any multi-platform strategy.

### Why inventory-first (not build)
- Codex's plugin system shipped March 2026. Key primitives (PreToolUse hooks, structured interactive prompts, SessionStart hooks) don't exist yet.
- Building now risks investing on shifting foundations.
- An inventory gives concrete data to inform the build-vs-wait decision without engineering commitment.

## Key Decisions

1. **Scope: Codex only** — No Cursor, Windsurf, or Copilot analysis. Keeps the inventory tight and actionable.

2. **Classification: Traffic light with gap annotations** — Green/yellow/red per component, plus specific Claude Code primitives that block portability and Codex equivalents (or absence thereof).

3. **Includes porting sequence** — Recommended order for maximum value with minimum effort, not just a flat inventory.

4. **Production method: Hybrid scan + agent review** — Automated scan of all 122 components for Claude Code-specific primitives (AskUserQuestion, Skill tool, Task, $ARGUMENTS, hookSpecificOutput, model: inherit, allowed-tools). Research agent validates yellow/red classifications for accuracy.

5. **No engineering output** — This is a research document. No abstraction layers, no platform adapters, no code changes.

## Research Findings

### Portable Content (~70-80% by file count)

| Category | Count | Portability | Notes |
|----------|-------|-------------|-------|
| Agent instruction prose | 62 | HIGH | Both platforms read markdown agents. `model: inherit` is minor. Domain knowledge is pure prose. |
| Skill instruction text | 57 | HIGH | Both use SKILL.md with YAML frontmatter (name, description). Phases/references are model-agnostic. |
| Shell scripts | ~15 | HIGH | Pure bash — worktree-manager, deploy, SEO validators, archive. |
| Knowledge base | All | HIGH | Constitution, learnings, brainstorms, specs, plans — platform-agnostic markdown. |
| CI/CD workflows | All | HIGH | GitHub Actions, Docker — independent of coding agent. |
| Docs site (Eleventy) | 1 | HIGH | Completely independent. |

### Non-Portable Orchestration (~20-30% of files, core value)

| Primitive | Usage | Codex Equivalent | Gap Severity |
|-----------|-------|-------------------|-------------|
| PreToolUse hooks | 3 scripts (guardrails, rebase, worktree guard) | `notify` (post-hoc only); SessionStart is feature request #13014 | CRITICAL |
| AskUserQuestion | 20+ skills | No structured equivalent — freeform only | HIGH |
| Skill tool chaining | go→brainstorm→plan→work→review→compound→ship | `$skill-name` mentions (different semantics) | HIGH |
| Task/subagent delegation | Domain leader fan-out, parallel review | Config-based `max_depth` roles in config.toml | HIGH |
| Agent discovery (.md recursion) | 62 agents | Config-based registration (agents/openai.yaml) | MEDIUM |
| plugin.json manifest | 1 file | config.toml (different schema) | MEDIUM |
| $ARGUMENTS interpolation | Skills + commands | Undocumented/different mechanism | MEDIUM |
| hookSpecificOutput protocol | Hook response JSON | No equivalent | CRITICAL |

### CTO Assessment Summary

**Recommendation: Wait and monitor.** Revisit when Codex ships PreToolUse-equivalent hooks and structured interactive prompts.

**Key risk:** An abstraction layer would be "inner platform effect" — building a meta-plugin-system over two fundamentally different design philosophies (Claude Code: file-per-agent with hooks; Codex: config-based roles with depth hierarchies).

**The real reuse is the knowledge, not the wiring.** The 200+ lines of constitution, domain leader frameworks, brainstorm techniques, compound learning patterns — this is the hard-won IP. YAML frontmatter and tool invocations are plumbing.

## Open Questions

1. **When does Codex ship PreToolUse hooks?** SessionStart is issue #13014. Without pre-tool interception, Soleur's safety model degrades from "safe by default" to "safe by convention."
2. **How stable is Codex's skill format?** SKILL.md looks identical today, but the platform is weeks old. Will it diverge?
3. **What's the actual Codex adoption trajectory?** Market opportunity depends on whether Codex reaches critical mass.
4. **Which pure-prose skills have the highest standalone value on Codex?** The inventory will answer this.

## Capability Gaps

- **Engineering:** No existing tooling for cross-platform component classification. The inventory scan needs to be built as part of this work.
- **Product:** No competitive intelligence on Codex adoption metrics. Would need external research to validate the market opportunity hypothesis.
