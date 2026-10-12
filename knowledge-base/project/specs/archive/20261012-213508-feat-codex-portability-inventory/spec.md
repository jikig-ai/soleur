# Feature: Codex Portability Inventory

## Problem Statement

Soleur is a Claude Code-exclusive plugin with 62 agents, 57 skills, and 3 commands. As OpenAI Codex gains adoption and Anthropic's Cowork Plugins materialize platform owner competition risk, we need concrete data on how much of Soleur could run on Codex — and at what cost. Currently there is no inventory of which components are platform-portable vs. platform-locked.

## Goals

- Classify every Soleur component (agents, skills, commands) by Codex portability: green (as-is), yellow (needs adaptation), red (requires rewrite)
- Annotate each yellow/red component with the specific Claude Code primitives that block portability and Codex equivalents (or absence)
- Produce a recommended porting sequence (highest value, lowest effort first)
- Provide concrete data for a future build-vs-wait decision

## Non-Goals

- Building an abstraction layer or platform adapter
- Actually porting any components to Codex
- Analyzing platforms beyond Codex (Cursor, Windsurf, Copilot)
- Modifying any existing Soleur code

## Functional Requirements

### FR1: Automated Component Scan

Scan all 122 components for Claude Code-specific primitive references: AskUserQuestion, Skill tool, Task (subagent), $ARGUMENTS, hookSpecificOutput, model: inherit, allowed-tools, PreToolUse.

### FR2: Traffic Light Classification

Assign each component a portability rating:

- **Green**: No Claude Code-specific primitives; ports to Codex SKILL.md/AGENTS.md format as-is
- **Yellow**: Contains Claude Code-specific primitives that have partial Codex equivalents; needs adaptation
- **Red**: Depends on Claude Code primitives with no Codex equivalent; requires rewrite or is non-portable

### FR3: Gap Annotations

For each yellow/red component, document:

- Which Claude Code primitives are used
- What the Codex equivalent is (or "none exists")
- Estimated adaptation complexity (trivial / moderate / significant)

### FR4: Porting Sequence Recommendation

Ordered list of components to port first, optimized for maximum standalone value on Codex with minimum adaptation effort. Group into tiers (quick wins, moderate effort, heavy lift).

## Technical Requirements

### TR1: Scan Methodology

Hybrid approach: automated grep-based scan for primitive references, followed by agent-assisted validation of yellow/red classifications to catch implicit dependencies (e.g., skills that assume hooks exist without referencing them directly).

### TR2: Output Format

Markdown document in `knowledge-base/project/specs/feat-codex-portability-inventory/` with:

- Summary statistics (green/yellow/red counts and percentages)
- Full component inventory table
- Gap analysis per non-portable primitive
- Porting sequence recommendation with rationale

### TR3: Reproducibility

The scan methodology should be documented well enough to re-run when Codex's platform capabilities change (e.g., when they ship PreToolUse hooks).
