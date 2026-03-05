---
title: Headless Mode Bypass Convention for LLM Skill Instructions
date: 2026-03-03
category: plugin-architecture
tags: [integration-issues, soleur plugin skills]
---

# Learning: Headless Mode Bypass Convention for LLM Skill Instructions

## Problem
Soleur skills use `AskUserQuestion` for interactive prompts (865 calls across sessions), but many are routine confirmations that block automated/headless execution. The existing constitution rule (line 71) mandated `$ARGUMENTS` bypass paths but was unenforced across 23+ prompts in ship, compound, compound-capture, and work skills.

## Solution
Implemented a two-layer flag convention:
- **`--headless` for skills:** Detected in `$ARGUMENTS`, stripped before processing remaining args, forwarded explicitly to child skill invocations (ship -> compound -> compound-capture)
- **`--yes` for bash scripts:** POSIX convention, parsed from `$@` before dispatch, sets a global `YES_FLAG` that bypasses `read -r` prompts

Each skill handles headless independently (bottom-up compliance) with sensible defaults per prompt. No new orchestration layer needed.

## Key Insight
LLM skill instructions can support both interactive and headless modes by adding conditional blocks at each prompt site. The pattern is: check a flag variable, then either prompt the user or apply a default. The critical design choice is making each skill responsible for its own flag detection and forwarding — automatic propagation through the Skill tool invocation chain would be fragile and invisible.

Safety constraints (branch checks, deduplication) still run in headless mode. Only user confirmation prompts are bypassed.

## Cross-References
- Schedule skill flag pattern: `plugins/soleur/skills/schedule/SKILL.md` (reference implementation)
- Constitution `$ARGUMENTS` bypass rule: `knowledge-base/overview/constitution.md:71-72`
- Plugin auto-load failure: `knowledge-base/learnings/2026-02-25-plugin-command-double-namespace.md`

## Tags
category: integration-issues
module: Soleur Plugin Skills
