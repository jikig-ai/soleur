---
title: "feat: Project-Aware Agent Filtering in Review Command"
type: feat
date: 2026-02-12
---

# Project-Aware Agent Filtering in Review Command

## Overview

Move Rails-specific agents (`kieran-rails-reviewer`, `dhh-rails-reviewer`) from the unconditional parallel agents section to the existing conditional agents section in the review command. Gate them on `Gemfile + config/routes.rb` file existence, using the same pattern already established for migration and test agents.

**Issue:** #46
**Brainstorm:** `knowledge-base/brainstorms/2026-02-12-runtime-agent-discovery-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-runtime-agent-discovery/spec.md`
**Version bump:** PATCH (behavior improvement, no new commands/agents/skills)

## Problem Statement

The `/soleur:review` command hardcodes `kieran-rails-reviewer` and `dhh-rails-reviewer` in the unconditional parallel agents block. These run on every project regardless of type, wasting tokens and time on non-Rails projects.

## Proposed Solution

Move the two Rails agents into the existing `<conditional_agents>` section of `plugins/soleur/commands/soleur/review.md`, gated on Rails marker files. This follows the exact same pattern already used for `data-migration-expert` and `test-design-reviewer`.

### Changes to review.md

**Remove from `<parallel_tasks>` (lines 70-71):**

```markdown
1. Task kieran-rails-reviewer(PR content)
2. Task dhh-rails-reviewer(PR title)
```

**Add to `<conditional_agents>` section:**

```markdown
**If project is a Rails app (Gemfile AND config/routes.rb exist at repo root):**

1. Task kieran-rails-reviewer(PR content) - Rails conventions and quality bar
2. Task dhh-rails-reviewer(PR title) - Rails philosophy and anti-patterns

**When to run Rails review agents:**

- Repository root contains both `Gemfile` and `config/routes.rb`
- PR modifies Ruby files (*.rb)
- PR title/body mentions: Rails, Ruby, controller, model, migration, ActiveRecord

**What these agents check:**

- `kieran-rails-reviewer`: Strict Rails conventions, naming clarity, controller complexity, Turbo patterns
- `dhh-rails-reviewer`: Rails philosophy adherence, JavaScript framework contamination, unnecessary abstraction
```

**Renumber remaining parallel agents (now 8 instead of 10):**

```markdown
Run ALL or most of these agents at the same time:

1. Task git-history-analyzer(PR content)
2. Task pattern-recognition-specialist(PR content)
3. Task architecture-strategist(PR content)
4. Task security-sentinel(PR content)
5. Task performance-oracle(PR content)
6. Task data-integrity-guardian(PR content)
7. Task agent-native-reviewer(PR content)
8. Task code-quality-analyst(PR content)
```

## Acceptance Criteria

- [x] `kieran-rails-reviewer` and `dhh-rails-reviewer` are NOT in the `<parallel_tasks>` block
- [x] Both agents appear in the `<conditional_agents>` section, gated on `Gemfile + config/routes.rb`
- [x] Running `/soleur:review` on a non-Rails project (no `Gemfile`) does not spawn Rails agents
- [x] Running `/soleur:review` on a Rails project (has `Gemfile` + `config/routes.rb`) spawns Rails agents
- [x] Remaining 8 parallel agents are correctly renumbered
- [x] Non-regression: Rails projects see identical review behavior (all agents still run)

## Test Scenarios

- Given a TypeScript project (has `package.json`, no `Gemfile`), when `/soleur:review` runs, then `kieran-rails-reviewer` and `dhh-rails-reviewer` are not spawned
- Given a Rails project (has `Gemfile` + `config/routes.rb`), when `/soleur:review` runs, then both Rails agents are spawned alongside the 8 universal agents
- Given a plain Ruby gem (has `Gemfile`, no `config/routes.rb`), when `/soleur:review` runs, then Rails agents are not spawned (it is Ruby but not Rails)
- Given a monorepo with `Gemfile` + `config/routes.rb` + `package.json`, when `/soleur:review` runs, then Rails agents are spawned (Rails markers present)

## Rollback Plan

Move the two agents back from `<conditional_agents>` to `<parallel_tasks>`. Single file change, no frontmatter modifications.

## Future Work

External agent discovery via tessl.io and agent metadata tags are tracked separately in issue #55. The research and design work is preserved in the brainstorm document.

## References

- Review command: `plugins/soleur/commands/soleur/review.md` (lines 66-124)
- Existing conditional pattern: `data-migration-expert` gated on `db/migrate/*.rb` (lines 85-100)
- Existing conditional pattern: `test-design-reviewer` gated on test file patterns (lines 107-123)
