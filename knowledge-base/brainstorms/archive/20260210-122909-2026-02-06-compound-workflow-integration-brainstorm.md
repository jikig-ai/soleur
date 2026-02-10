# Brainstorm: Integrate /soleur:compound into Work Workflow

**Date:** 2026-02-06
**Status:** Ready for planning

## What We're Building

Add `/soleur:compound` as a standard step in the `/soleur:work` command workflow, ensuring knowledge capture happens consistently before PRs are created.

### Problem Statement

Currently, `/soleur:compound` (which documents solved problems to compound team knowledge) is only triggered by explicit phrases like "that worked" or "it's fixed". This means valuable learnings from implementation work can be missed unless someone remembers to run it.

### Desired Outcome

Every `/soleur:work` execution prompts the engineer to consider running `/soleur:compound` before creating a PR, capturing any learnings from the implementation process.

## Why This Approach

### Chosen Approach: Key Principle + Quality Checklist

1. **Key Principle** - Add "Compound Your Learnings" to the Key Principles section
   - Explains *why* knowledge capture matters
   - Provides philosophical grounding
   - Positions it alongside other important principles like "Test As You Go"

2. **Quality Checklist Item** - Add checkbox for `/soleur:compound`
   - Ensures the action isn't forgotten
   - Non-blocking but prominent
   - Consistent with existing checklist pattern

### Why Not Other Approaches

- **Pre-push hook**: Too aggressive - WIP pushes shouldn't require compound
- **PR blocking**: Too strict - not every PR has learnings worth documenting
- **Phase 4 dedicated step**: Adds friction for simple changes
- **Principle only**: Easy to forget without checklist reminder

## Key Decisions

1. **Integration point**: Key Principles section + Quality Checklist (not a blocking step)
2. **Enforcement level**: Strong recommendation, not mandatory
3. **When to run**: Always consider it - learnings can come from any implementation
4. **Principle name**: "Compound Your Learnings" (active, clear)

## Implementation Specification

### Changes to `/soleur:work` command

**1. Add to Key Principles section (after "Quality is Built In"):**

```markdown
### Compound Your Learnings

- Run `/soleur:compound` before creating a PR
- Document debugging breakthroughs, non-obvious patterns, and framework gotchas
- Even "simple" implementations can yield valuable insights
- Future-you and teammates will thank present-you
```

**2. Add to Quality Checklist (after "PR description includes Compound Engineered badge"):**

```markdown
- [ ] Considered `/soleur:compound` for any learnings from this work
```

### Files to Modify

- `plugins/soleur/commands/soleur/work.md` - Add principle and checklist item

## Open Questions

None - approach is well-defined.

## Next Steps

1. Run `/soleur:plan` to generate implementation tasks
2. Edit `work.md` to add the Key Principle
3. Edit `work.md` to add the checklist item
4. Test by running `/soleur:work` on a sample task
