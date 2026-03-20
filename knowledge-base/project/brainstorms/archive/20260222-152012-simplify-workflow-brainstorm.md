# Brainstorm: Simplify Workflow

**Date:** 2026-02-22
**Issue:** #267
**Status:** Complete

## What We're Building

Consolidate Soleur's 8 commands into 3 by creating a unified `/soleur` entry point that uses intent detection to route to the right workflow. The current commands (brainstorm, plan, work, review, compound, one-shot) become internal skills invoked by the router.

**The 3 commands:**

1. `/soleur` -- Smart entry point. Detects intent from natural language, proposes a route, user confirms with one click.
2. `/soleur:sync` -- Unchanged. Bootstrap/maintenance utility.
3. `/soleur:help` -- Unchanged. Lists capabilities.

## Why This Approach

**Observation:** After a week of daily use, 4 commands dominate usage: one-shot, brainstorm (which routes to one-shot for simple tasks), sync, and help. Brainstorm already functions as a unified entry point -- it just undersells itself with the name.

**The problem isn't missing capability -- it's unnecessary surface area.** All 8 commands exist and work, but most users (including the author) naturally converge on brainstorm as the starting point because it routes intelligently.

**Approach A (Thin Router) was chosen over:**
- Monolithic command (2000+ lines, unmaintainable)
- Progressive disclosure (adds a 9th command instead of reducing)

## Key Decisions

1. **Bare `/soleur` command.** Maximum simplicity. The command IS the brand. Fallback to `/soleur:go` if the plugin loader doesn't support bare namespace commands.

2. **All standalone use cases absorbed.** Review, compound, plan, work -- all reachable via intent detection in the unified command. No hidden commands or skill fallbacks.
   - "Review PR #123" triggers review mode
   - "I learned something" triggers compound mode
   - "Fix the typo" triggers one-shot mode
   - "Let's explore auth options" triggers brainstorm mode

3. **Smart detect + confirm once.** The system analyzes input, proposes an intent classification, user confirms or redirects. One confirmation step, not zero (avoids misrouting) and not many (avoids friction).

4. **Domain leader routing preserved.** CTO, CMO, CPO, COO, CLO, CRO assessments still happen for exploratory intents. Skipped for simple build/fix intents.

5. **Thin router architecture.** The `/soleur` command is ~100 lines that classifies intent and delegates to existing logic (moved from commands/ to skills/). Each phase remains independently testable.

6. **Existing commands become skills.** brainstorm, plan, work, review, compound, one-shot move from `commands/soleur/` to `skills/`. They lose `/` autocomplete visibility but remain invocable and agent-discoverable.

## Architecture

```
/soleur "fix the login bug"
    |
    v
[Intent Classification]
    |
    +-- explore  --> brainstorm skill (full domain routing, dialogue, spec)
    +-- plan     --> plan skill (research, tasks.md generation)
    +-- build    --> one-shot skill (autonomous pipeline)
    +-- review   --> review skill (multi-agent code review)
    +-- capture  --> compound skill (document a learning)
    +-- resume   --> detect existing plan/worktree, resume from last phase
    |
    v
[Propose route to user]
"This looks like a bug fix. I'll one-shot it. OK?"
    |
    v
[User confirms or redirects]
    |
    v
[Execute selected skill]
```

## Open Questions

1. **Plugin loader support for bare `/soleur`.** Commands are discovered from `commands/soleur/<name>.md`. Can a bare namespace command exist? Needs investigation during planning. If not, `/soleur:go` is the fallback name.

2. **Resume detection.** How does the system detect "you were mid-way through a feature" and offer to resume? Likely: check for active worktree + unfinished tasks.md.

3. **Cross-reference updates.** AGENTS.md, CLAUDE.md, constitution, ship skill, and ~15 other files reference specific command names. Migration scope needs assessment during planning.

4. **Help output redesign.** `/soleur:help` currently lists all commands. With 3 commands + 46 skills, what does the help output look like? Should skills be grouped by domain?

## Research Context

### CTO Assessment Highlights
- Smart routing accuracy is the highest risk -- threshold heuristic with user override is recommended
- Context window pressure if command file grows too large -- thin router solves this
- Plan/work/review serve dual purposes (pipeline stages AND standalone tools) -- absorbed via intent detection

### CPO Assessment Highlights
- Aligned with business validation verdict ("stop adding features" -- this is subtraction)
- Compound has ad-hoc use case outside feature lifecycle -- absorbed via "capture" intent
- Reversibility is high -- UX layer change only, underlying skills/agents unchanged

### Learnings Applied
- "Route through existing entry points" (2026-02-13) -- exactly what this does
- "Table-driven routing" (2026-02-22) -- domain config table pattern carries forward
- "Command vs skill criteria" (2026-02-12) -- commands that agents should invoke become skills
- "Plan review catches over-engineering" (2026-02-06) -- plan review should validate the routing logic isn't over-engineered
