# Learnings: Spec-Driven Workflow Implementation

**Date:** 2026-02-06
**Issues:** #3 (Foundation), #4 (Command Integration)
**Tags:** architecture, workflow, simplification

## Context

Implemented a spec-driven workflow system for the Soleur plugin, enabling structured feature development through brainstorm -> plan -> work -> compound cycle.

## Key Learnings

### 1. Simplification Over Complexity

**Original:** 8-domain constitution model (Code Style, Architecture, Testing, Naming, Documentation, Errors, Security, Performance)

**Final:** 3-domain model (Code Style, Architecture, Testing)

**Why it worked:** Starting with fewer domains reduced cognitive overhead. Additional domains can be added as needed, but starting minimal avoids premature structure. Empty sections are fine - they signal where principles can be captured later.

### 2. Human-in-the-Loop for v1

**Original:** Automatic behaviors planned:
- Auto-cleanup on merge detection
- Auto-update spec from implementation
- Automatic divergence detection
- Automatic constitution promotion

**Final:** All manual, user-initiated actions.

**Why it worked:** Manual workflows are easier to debug, easier to understand, and build user trust. Automation can be added in v2 once the patterns are proven and users request it. "Architect for v2, implement for v1."

### 3. Fall-back Patterns Ensure Backward Compatibility

All commands check for `knowledge-base/` existence before using it:
- If exists: Use new workflow
- If not: Fall back to `docs/` patterns

**Why it matters:** Existing repositories without knowledge-base/ continue to work. Migration is opt-in, not forced. Users can adopt gradually.

### 4. Convention Over Configuration

Branch naming convention: `feat-<name>` automatically maps to:
- Spec directory: `knowledge-base/specs/feat-<name>/`
- Worktree path: `.worktrees/feat-<name>/`

**Why it works:** No manifest files to maintain. Directory structure is the configuration. Branch name is the single source of truth for feature identity.

### 5. Skill-Based Architecture Promotes Reuse

Created reusable skills:
- `spec-templates` - provides spec.md and tasks.md templates
- `git-worktree` - manages worktrees with `create-for-feature` function

**Why it matters:** Commands can invoke skills without duplicating logic. Skills can evolve independently. New commands can reuse existing capabilities.

## Anti-Patterns Avoided

1. **No new abstractions before proving value** - Used existing file/directory conventions
2. **No complex state management** - Files are the state, git is the history
3. **No automation without user request** - Every action is explicit and traceable

## Recommendations for Future Work

1. Add v2 automation features only when users explicitly request them
2. Keep constitution updates manual until patterns stabilize
3. Consider adding more domains to constitution as specific needs arise
4. Worktree cleanup could be automated after successful PR merge (v2)

## Related Files

- knowledge-base/specs/feat-spec-workflow-foundation/spec.md
- knowledge-base/specs/feat-command-integration/spec.md
- plugins/soleur/commands/soleur/brainstorm.md
- plugins/soleur/commands/soleur/plan.md
- plugins/soleur/commands/soleur/work.md
- plugins/soleur/commands/soleur/compound.md
