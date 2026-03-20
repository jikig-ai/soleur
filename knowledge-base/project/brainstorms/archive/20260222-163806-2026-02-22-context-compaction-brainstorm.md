# Context Compaction Optimization

**Date:** 2026-02-22
**Issue:** #268
**Status:** Brainstorm complete

## What We're Building

A two-pronged optimization to reduce context window pressure during multi-step workflows (brainstorm -> plan -> work -> review -> compound). The plugin's 60 agents, 46 skills, and 9 commands create ~10k tokens of always-on baseline, and pipeline runs accumulate 50k+ tokens of command/skill instructions by mid-pipeline with no compaction.

**Prong 1: Reduce baseline context pressure** by moving heavy content out of command bodies into references/ files and deduplicating repeated constitution loading.

**Prong 2: Safe compaction at the brainstorm-to-plan boundary** by spawning plan as an isolated Task subagent with error forwarding via a cumulative session-state file.

## Why This Approach

The core tension: compacting between workflow steps saves context but risks losing error history that compound's HARD RULEs depend on (Session Error Inventory, Route-to-Definition). The approach threads this needle by:

1. Reducing how fast context fills up (Prong 1) -- less pressure means compaction triggers later or not at all
2. Adding one safe compaction point where artifacts are richest (Prong 2) -- brainstorm produces spec.md + brainstorm.md + issue, so plan can re-read everything from disk
3. Preserving compound's error visibility via error forwarding -- subagent returns structured summary, parent appends to session-state.md

We explicitly chose NOT to compact between plan/work/compound because compound needs the work-session history intact.

## Key Decisions

### 1. Baseline reduction: three levers

- **Move command templates to references/**: plan.md has 3 issue templates (~350 words), brainstorm.md has an 8-row domain config table. Move to `references/` so they're loaded only when needed.
- **Deduplicate constitution loading**: Constitution (3,219 words) gets loaded 3-5x per pipeline. Commands should check if already in context before re-reading.
- **Trim command bodies**: Move procedural details into `references/` files, keeping only the flow skeleton in command bodies. Target: cut average command size from ~3,000 to ~1,500 words.

### 2. Brainstorm-to-plan compaction via subagent isolation

- When one-shot (or any pipeline) runs plan after brainstorm, spawn plan as an isolated Task agent with spec/brainstorm paths as input
- Plan subagent returns a structured summary: errors encountered, key decisions, components invoked
- Parent writes this to `knowledge-base/specs/feat-<name>/session-state.md`

### 3. Session-state file design

- **Location**: `knowledge-base/specs/feat-<name>/session-state.md` -- alongside spec.md and tasks.md
- **Mode**: Append-only (cumulative). Each pipeline step appends its section.
- **Consumers**: Compound reads this file in addition to scanning conversation history
- **Lifecycle**: Committed with feature artifacts. Cleaned up when worktree is removed.

### 4. What we're NOT doing

- No compaction between plan/work/compound (compound needs that history)
- No full session-state schema (YAGNI -- start with simple append file)
- No dynamic agent description trimming (already optimized 82%, diminishing returns)
- No programmatic /compact invocation (not available as a tool)

## Context Pressure Analysis

| Component | Words | Tokens (approx) | Loaded When |
|-----------|-------|-----------------|-------------|
| Agent descriptions (60) | 2,448 | 3,264 | Every turn |
| Skill descriptions (46) | 2,410 | 3,213 | Every turn |
| Root AGENTS.md | 1,408 | 1,877 | Every turn |
| Plugin AGENTS.md | 1,164 | 1,552 | Every turn |
| Constitution | 3,219 | 4,292 | Each command Phase 0 (3-5x) |
| brainstorm.md command | 2,906 | 3,875 | On brainstorm invocation |
| plan.md command | 3,274 | 4,365 | On plan invocation |
| work.md command | 2,946 | 3,928 | On work invocation |
| compound-docs SKILL.md | 3,072 | 4,096 | On compound invocation |

**One-shot pipeline total by step 6:** ~50,000+ tokens of instructions alone, before tool outputs and conversation.

## Open Questions

1. **Constitution deduplication mechanism**: How exactly do commands detect if constitution is already in context? Options: (a) check a flag set by the first loader, (b) skip loading if a prior command already ran in this session, (c) move constitution into CLAUDE.md so it's always-on and never re-loaded.
2. **Session-state format**: What sections should each step append? Minimum viable: `## Step: <name>`, errors list, decisions list, components invoked. Do we need more?
3. **Subagent return contract**: What exactly does the plan subagent return to the parent? A markdown string? A structured JSON block? The parent needs to parse it reliably.
4. **Measuring impact**: How do we validate that these changes actually reduce compaction frequency? No telemetry exists today.

## CTO Assessment Summary

- The subagent model is already the primary context relief valve
- Command-skill delegation chains create context stacking with no mitigation
- Compound's HARD RULEs are the hardest constraint -- must not break them
- Recommended Option C (brainstorm-to-plan compaction) + Option A (baseline reduction)
- Do NOT compact before compound runs
