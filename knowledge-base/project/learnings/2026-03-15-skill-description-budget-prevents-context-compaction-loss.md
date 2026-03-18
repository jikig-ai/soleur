# Learning: skill description budget prevents context compaction loss

## Problem

During multi-phase pipeline sessions (brainstorm -> plan -> work -> compound -> ship), skills invoked late in the session (`soleur:work`, `soleur:compound`, `soleur:ship`) failed with "Unknown skill" errors. Skills invoked early (`soleur:brainstorm`, `soleur:plan`) worked fine. All 58 SKILL.md files existed on disk with correct frontmatter.

The plugin had grown to 58 skills (2,729 description words / ~3.6k tokens) plus 40+ agents (2,501 description words / ~3.3k tokens). The Claude Code plugin loader injects all name+description metadata into the system prompt on every turn. At ~7k tokens of metadata baseline, sessions hit the context compaction threshold during multi-phase pipelines. When compaction triggers, the skill metadata table is silently truncated -- skills referenced earlier remain accessible (cached in compacted context), but unreferenced skills become "Unknown."

## Solution

Two-pronged approach: reduce metadata footprint and enforce a budget.

**Prong 1: Trim descriptions (2,729 -> 1,789 words, 34% reduction)**
- Removed `Triggers on "..."` phrases from 29 of 58 skills (~435 words saved). The model infers intent from skill name + core description without explicit trigger keywords.
- Shortened verbose restatements where the skill name already communicates intent.
- Preserved routing-critical keywords and third-person voice convention.

**Prong 2: Enforce budget via test**
- Added `SKILL_DESCRIPTION_WORD_BUDGET = 1800` ceiling in `components.test.ts`.
- Per-skill `SKILL_DESCRIPTION_CHAR_LIMIT = 1024` test.
- Budget test includes diagnostic output listing top 5 offenders on failure.
- Test runs in CI on every commit -- budget violations are caught before merge.

**What was NOT needed:**
- A separate shell script (`verify-skills.sh`) was initially created but deleted after 4 review agents identified it as redundant with the TypeScript tests. The TS tests use a proper YAML parser; the shell script used fragile sed-based extraction.

## Key Insight

Skill descriptions are for **routing**, not **instruction**. Trigger phrase lists (`Triggers on "ready to ship", "create PR", ...`) are the skill equivalent of agent `<example>` blocks -- verbose metadata that helps during authoring but consumes tokens on every turn without improving the model's routing accuracy. The model matches intent from `skill_name + concise_description` just as effectively.

This is the same class of problem solved for agent descriptions (2026-02-20): stripping `<example>` blocks from agent descriptions reduced them from ~15.8k to ~2.9k tokens (82% reduction). The skill fix applies the same principle at a smaller scale.

## Session Errors

1. **Bun segfault on broad `bun test`**: Running `bun test` without a file filter caused a segfault (Bun 1.3.5 bug on Linux x64). Workaround: target specific file with `bun test plugins/soleur/test/components.test.ts`.
2. **`git add` on already-rm'd file**: After `git rm verify-skills.sh`, attempted `git add verify-skills.sh` in commit staging, causing `fatal: pathspec did not match`. The rm was already staged; only the test file needed explicit staging.

## Prevention

- The word budget test (`SKILL_DESCRIPTION_WORD_BUDGET = 1800`) automatically prevents regression. Adding a new 50-word skill when the budget is near capacity will fail the test, forcing the developer to trim existing descriptions or justify raising the ceiling.
- When adding new skills, keep descriptions under 35 words average. Use the skill name to carry intent; the description only needs to disambiguate from similar skills.
- When running `bun test` on this codebase, always target specific test files rather than running the broad `bun test` command (Bun 1.3.5 segfault workaround).

## Cross-References

- Prior learning: `knowledge-base/project/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md` (identical pattern for agents)
- Prior learning: `knowledge-base/project/learnings/2026-02-22-context-compaction-command-optimization.md` (commands reduced from 13,292 to 9,794 words)
- Prior learning: `knowledge-base/project/learnings/2026-03-06-disambiguation-budget-compounds-with-domain-size.md` (agent budget at ceiling)
- GitHub issue: #618

## Tags
category: performance-issues
module: plugin-loader
