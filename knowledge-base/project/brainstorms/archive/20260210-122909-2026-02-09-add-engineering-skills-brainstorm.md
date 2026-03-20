# Brainstorm: Add Engineering Skills from claude-code-agents

**Date:** 2026-02-09
**Issue:** #27 - Review Adding Additional Skills
**Source repo:** [andlaf-ak/claude-code-agents](https://github.com/andlaf-ak/claude-code-agents)
**Status:** Ready for planning

## What We're Building

Adopt 9 software engineering methodology agents from the claude-code-agents repository into the soleur plugin. These cover Clean Code, refactoring, code smell detection, test quality review, DDD, legacy code analysis, ATDD, problem analysis, and user story writing.

All 9 are language-agnostic and grounded in industry-standard books (Fowler, Martin, Feathers, Farley, Evans). They fill clear gaps in soleur's current skill catalog, which leans toward workflow/process skills rather than methodology/analysis.

## Why This Approach

### Agents vs Skills Decision (Opus 4.6 Context)

Opus 4.6 already has deep knowledge of Clean Code principles, Fowler's refactoring catalog, DDD patterns, etc. The agent prompts don't need to embed 14KB of domain knowledge - they need opinionated framing: when to apply what, from which perspective, and in what output format.

**6 as Agents** (expert review/analysis, naturally parallel):

| Agent | Purpose | Book/Methodology |
|---|---|---|
| code-smell-detector | Detect smells with language-adaptive thresholds | Fowler, luzkan.github.io/smells |
| refactoring-expert | Recommend techniques based on detected smells | Fowler's 66 refactoring techniques |
| clean-coder | Review for Clean Code/SOLID/GRASP | Robert C. Martin |
| test-design-reviewer | Score test quality (Farley Score) | Dave Farley's 8 properties |
| legacy-code-expert | Analyze legacy code for safe modification | Michael Feathers |
| ddd-architect | Review domain design, contexts, aggregates | Eric Evans |

Rationale: These are analytical - they look at code and give expert opinions. They benefit from parallel execution via `Task()` and don't need bundled resources.

**3 as Skills** (interactive workflows with templates):

| Skill | Purpose | Book/Methodology |
|---|---|---|
| atdd-developer | Guide RED/GREEN/REFACTOR cycle | ATDD methodology |
| user-story-writer | Decompose into INVEST-compliant stories | Elephant Carpaccio |
| problem-analyst | Structured analysis before solutioning | First-principles analysis |

Rationale: These guide step-by-step processes inline. They benefit from templates, reference docs, and progressive disclosure.

### Overlap Analysis

| claude-code-agents | Soleur equivalent | Action |
|---|---|---|
| problem-analyst | brainstorming (partial) | Add as skill - covers structured analysis brainstorming doesn't |
| user-story-writer | spec-templates (partial) | Add as skill - user stories != specs |
| atdd-developer | None | Add as skill |
| clean-coder | dhh-rails-style (Rails only) | Add as agent - generic vs Rails-specific |
| code-smell-detector | None | Add as agent |
| refactoring-expert | None | Add as agent |
| test-design-reviewer | None | Add as agent |
| legacy-code-expert | None | Add as agent |
| ddd-architect | None | Add as agent |

No duplicates. Minimal overlap with existing skills.

## Key Decisions

1. **Format split:** 6 agents + 3 skills based on usage pattern (review vs workflow)
2. **Lean prompts:** 500-800 lines max per agent, leveraging Opus 4.6's built-in domain knowledge
3. **Language-agnostic:** All 9 work across any programming language
4. **Integration points:** Agents can be composed into `/soleur:review` pipelines; skills invoked standalone
5. **Source adaptation:** Convert from claude-code-agents YAML frontmatter format to soleur agent/skill format

## Open Questions

- Should the review command (`/soleur:review`) be updated to optionally include the new agents?
- Should code-smell-detector and refactoring-expert be chained (smell report feeds refactoring recommendations)?
- What category directories should the agents go in? (`review/`? `engineering/`? new category?)

## References

- Source repo: https://github.com/andlaf-ak/claude-code-agents
- Local clone: /home/jean/git-repositories/jikig-ai/claude-code-agents
- Soleur agents: plugins/soleur/agents/
- Soleur skills: plugins/soleur/skills/
