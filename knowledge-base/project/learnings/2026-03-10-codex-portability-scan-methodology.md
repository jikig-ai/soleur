# Learning: Codex Portability Scan Methodology

## Problem

Needed to assess how much of the Soleur Claude Code plugin (122 components) could port to OpenAI Codex. No existing tooling or methodology existed for cross-platform portability analysis of Claude Code plugins.

## Solution

Built a grep-based scan methodology that classifies components by checking for 10 Claude Code-specific primitives. Components are classified using worst-primitive-wins logic across four tiers (green/yellow/red/N/A).

**Key primitives that determine portability** (ordered by impact):

1. Task/subagent spawning (100+ refs, 30+ files) — Codex has no programmatic agent spawning
2. Skill tool chaining (80+ refs, 20+ files) — Codex has `$skill-name` mentions but no mid-execution invocation
3. AskUserQuestion (54 refs, 29 files) — Codex has no structured interactive prompt tool
4. $ARGUMENTS interpolation (30 refs, 22 files) — No documented Codex equivalent

**Results:** 47.5% green (58 components), 7.4% yellow (9), 43.4% red (53), 1.6% N/A (2).

**Critical pattern:** Agents are highly portable (67.7% green) because they are prose instructions. Skills are mostly non-portable (57.9% red) because they contain orchestration logic. The domain knowledge is portable; the wiring is not.

## Key Insight

When assessing cross-platform portability, scan for orchestration primitives (tool invocations, inter-component chaining, hook protocols), not content format. Both Claude Code and Codex use SKILL.md with YAML frontmatter — the format is identical, but the orchestration semantics are incompatible. The real reuse is the knowledge (agent prose, domain frameworks), not the wiring (tool calls, hook scripts).

Also: grep-based scans with `grep -rl` return exit code 1 when no match is found. For scan scripts that check many patterns across many files, use `|| true` or check counts rather than exit codes to avoid false "failure" signals.

## Tags

category: implementation-patterns
module: plugin-architecture
