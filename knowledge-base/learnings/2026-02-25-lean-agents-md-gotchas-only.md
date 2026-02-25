# Learning: Lean AGENTS.md -- gotchas-only based on research

## Problem
The root AGENTS.md was 127 lines loaded into the system prompt on every turn. Per ETH Zurich research (Feb 2026), context files increase reasoning tokens by 10-22% and cost by 15-20% per interaction, even when the instructions are followed. Most content was procedural (Workflow Completion Protocol, Feature Lifecycle) or discoverable (Browser Automation, Diagnostic-First Rule) -- information the agent could find in skills or already knew.

## Solution
Restructured AGENTS.md from 127 lines to 26 lines using the "gotchas-only" principle: keep only rules the agent would violate without being told on every turn.

**What stayed (non-discoverable gotchas):**
- Worktree hard rules (commit to main, edit in wrong directory, git stash danger)
- MCP tool path resolution (repo root vs shell CWD)
- Workflow gates (compound before commit, version triad, zero-agents-until-confirmed)
- Communication style (challenge reasoning, delegate verbose exploration)

**What moved out:**
- Workflow Completion Protocol (10 steps) -> already in `/ship` skill
- Session-Start Hygiene -> already in constitution.md line 56
- Browser Automation -> discoverable via `agent-browser --help`
- Diagnostic-First Rule -> general LLM knowledge; added one-liner to constitution.md
- Feature Lifecycle -> discoverable from skill descriptions
- Context compaction note -> already in one-shot skill
- FAILURE MODE blocks -> underlying rules already in constitution.md and skills

**What was added:**
- Subagent delegation heuristic: "Delegate verbose exploration (3+ file reads, research, analysis) to subagents"
- Explicit pointer to constitution.md for detailed conventions

## Key Insight
The litmus test for every line in a context file: "Can the agent discover this on its own?" If yes, delete it. Context files are most valuable when they contain minimal, non-redundant information the agent cannot find elsewhere. Procedural checklists belong in the skills that automate them, not in the system prompt that loads on every turn.

## References
- ETH Zurich: "Evaluating AGENTS.md" (arxiv.org/abs/2602.11988)
- Lulla et al. 2026: AGENTS.md efficiency study (arxiv.org/abs/2601.20404)
- Dominic Elm: "Your AGENTS.md Is Just Band-Aid" (x.com/elmd_/article/2025976479276806294)
- fullstackpm.com: Context Management subagent delegation pattern

## Tags
category: architecture
module: AGENTS.md
