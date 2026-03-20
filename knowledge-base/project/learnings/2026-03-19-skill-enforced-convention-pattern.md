# Learning: Skill-enforced convention pattern for semantic rules

## Problem

Constitution rules that require semantic judgment (e.g., "detect UI signals in the plan") cannot be enforced by PreToolUse hooks. Hooks are syntactic — they pattern-match on tool inputs (file paths, command strings). Detecting whether a plan creates user-facing pages requires reading the plan content and making a classification judgment.

Constitution line 122 mandated UX review for user-facing pages but had no enforcement mechanism. Line 147 says "Never state conventions in constitution.md without tooling enforcement." The rule existed as prose for weeks before PR #637 exposed the gap — 5+ UI screens shipped without any product/UX agent involvement.

## Solution

Introduced a new enforcement tier: `[skill-enforced: <skill> <phase>]`. The skill instruction itself contains the detection logic and agent invocation pipeline. Unlike hooks (which fire on every tool call), skill-enforced rules fire at specific workflow phases where the LLM can apply semantic judgment.

Implementation pattern:
1. Add detection logic to the skill's SKILL.md at the appropriate phase
2. Use LLM semantic assessment (not keyword matching) for classification
3. Write a structured heading contract (`## UX Review`) so downstream skills can verify the gate ran
4. Add a lightweight keyword-based backstop in a downstream skill for defense-in-depth
5. Annotate the constitution rule with `[skill-enforced: ...]` to mark it as no longer aspirational

## Key Insight

There are three enforcement tiers, each suited to different rule types:
- **PreToolUse hooks**: Syntactic rules (file patterns, branch names, command flags). Mechanical prevention. Strongest.
- **Skill instructions**: Semantic rules (classify content, assess intent, detect signals). LLM-evaluated at specific phases. Medium.
- **Prose rules**: Advisory guidance. Weakest — requires agent compliance with no verification.

Rules that need semantic judgment but were previously stuck as prose (weakest tier) can now be elevated to skill-enforced (medium tier) without requiring a hook. The key is placing the gate at a workflow phase where the LLM already has the relevant context loaded.

## Tags
category: architecture
module: plugins/soleur/skills/plan, plugins/soleur/skills/work
