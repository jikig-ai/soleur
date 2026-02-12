# Learning: Command vs Skill Selection Criteria

## Problem

The plugin had 26 commands and 19 skills with unclear criteria for when to use each. 10 utility commands were invisible to agents because commands are user-invokable only, while skills are both user-invokable and agent-discoverable.

## Solution

Established a three-category classification for deciding whether functionality belongs as a command or skill:

1. **Skills** (agent-discoverable): Any standalone capability that agents should be able to invoke autonomously during workflows. Examples: `changelog`, `test-browser`, `resolve-pr-parallel`.

2. **Commands (orchestration)**: Multi-phase workflows that compose multiple skills/agents into coordinated sequences. Examples: `soleur:work`, `soleur:review`, `triage`.

3. **Commands (user-only)**: Actions requiring human intent or judgment that agents should never invoke autonomously. Examples: `report-bug`, `lfg`, `deploy-docs`.

Migrated 10 command-only items to skills, deleted 1 pure-wrapper command, kept 15 commands (8 orchestration + 7 user-only).

## Key Insight

The deciding question is: "Should an agent be able to invoke this during an autonomous workflow?" If yes, it must be a skill -- commands are invisible to agents. The SKILL.md frontmatter format (third-person description with trigger keywords) is what enables agent discovery. The body content is identical between commands and skills; only the frontmatter differs.

## Migration Pattern

When converting a command to a skill:
1. Create `skills/<kebab-name>/SKILL.md`
2. Rewrite frontmatter: normalize name to kebab-case, rewrite description to third person with trigger keywords, drop `argument-hint`
3. Keep body content unchanged -- `$ARGUMENTS` injection works identically in both
4. Delete the command file
5. Update versioning triad (MINOR bump for new skills)

## Tags

category: workflow-patterns
module: plugin-architecture
symptoms: agents-cant-find-commands, command-skill-overlap
