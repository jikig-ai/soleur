---
module: soleur
date: 2026-02-06
problem_type: best_practice
component: commands
tags:
  - plugin-development
  - command-creation
  - knowledge-base
  - versioning
---

# Adding New Plugin Commands

## Context

When implementing the `/soleur:sync` command, we established patterns for adding new commands to the Soleur plugin that can be reused for future command development.

## Pattern

### 1. Command File Structure

Commands live in `plugins/soleur/commands/` with YAML frontmatter:

```yaml
---
name: soleur:command-name
description: Brief description of what the command does
argument-hint: "[optional: argument format]"
---
```

Core workflow commands use `soleur:` prefix to avoid collisions with built-in Claude Code commands.

### 2. Four-Phase Execution Model

Complex commands benefit from a phased approach:

1. **Phase 0: Setup** - Validate prerequisites, create directories if needed
2. **Phase 1: Analyze** - Gather information, scan codebase
3. **Phase 2: Review** - Present findings for user approval
4. **Phase 3: Write** - Execute approved changes

### 3. Sequential Review UX

For commands that need user approval, use AskUserQuestion with three options:

- **Accept** - Proceed with the finding
- **Skip** - Don't include this finding
- **Edit** - Modify before accepting

This is familiar UX with no custom syntax to learn.

### 4. Idempotency via Exact Match

Before writing entries, check for exact duplicates:
- Prevents duplicate entries on repeated runs
- Users handle near-duplicates during review
- Avoids complexity of fuzzy matching

### 5. Versioning Checklist (Required)

Every plugin change must update three files:

1. `.claude-plugin/plugin.json` - Bump version (semver)
2. `CHANGELOG.md` - Document changes
3. `README.md` - Update counts and tables

### 6. Testing Commands

Since skill/command files are prompt instructions (not executable code), test by:

1. Manually executing the command's workflow
2. Verifying each phase produces expected output
3. Running the command on the repo itself (meta-test)

## Key Insight

Commands are instructions, not code. Test them by following the instructions manually. The "code" is the markdown that tells Claude what to do.

## Related

- Spec: `knowledge-base/specs/feat-sync-command/spec.md`
- Plan: `knowledge-base/plans/2026-02-06-feat-sync-command-plan.md`
- Versioning: `knowledge-base/learnings/plugin-versioning-requirements.md`
- Issue: #8
