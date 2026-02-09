---
title: "feat: Command Integration - Unified Workflow"
type: feat
date: 2026-02-05
layer: commands
priority: 5
dependencies:
  - 2026-02-05-feat-knowledge-base-foundation-plan.md
  - 2026-02-05-feat-worktree-layer-enhancements-plan.md
  - 2026-02-05-feat-spec-layer-artifacts-plan.md
  - 2026-02-05-feat-knowledge-layer-compounding-plan.md
---

# Command Integration - Unified Workflow

## Overview

Update the four core workflow commands (brainstorm, plan, work, compound) to integrate with all new layers: worktree creation, spec artifacts, constitution consultation, and knowledge compounding.

## Problem Statement

Current commands operate independently. The unified workflow requires:
- `soleur:brainstorm` to create worktree + spec.md
- `soleur:plan` to consult constitution + create tasks.md
- `soleur:work` to operate in worktree + track task progress
- `soleur:compound` to sync specs + capture learnings + promote to constitution + cleanup

## Proposed Solution

Update each command to integrate with the new layers while maintaining backward compatibility for repos without `knowledge-base/`.

### Progressive Disclosure Strategy

To avoid overwhelming users with context, each command uses **tiered disclosure**:

**Tier 1 (Always shown):**
- Current task status
- Immediate next action

**Tier 2 (On request or relevance):**
- Constitution principles (only when making decisions)
- Patterns (only when similar problem detected)
- Reviews (only when touching related code)

**Tier 3 (Explicit `--verbose`):**
- Full context dump
- All loaded knowledge sources
- Metrics and statistics

**Implementation:**

```typescript
interface ContextLoader {
  loadMinimal(): MinimalContext;    // Tier 1
  loadRelevant(query: string): RelevantContext;  // Tier 2
  loadFull(): FullContext;          // Tier 3
}

// Example: soleur:work only shows patterns when coding similar logic
if (currentCode.similarity(pattern) > 0.7) {
  showPattern(pattern);  // Tier 2 triggered
}
```

**User control:** Allow `--context=minimal|relevant|full` flag to override.

## Technical Approach

### Phase 1: Update soleur:brainstorm

**Modify:** `plugins/soleur/commands/soleur/brainstorm.md`

**New flow:**

```markdown
## Execution Flow

### Phase 0: Feature Setup (NEW)

1. **Get feature name** from user or derive from description
2. **Create worktree** (if knowledge-base/ exists):
   - Call: `worktree-manager.sh create-for-feature <name>`
   - Creates `.worktrees/feat-<name>/`
   - Creates `knowledge-base/specs/feat-<name>/`
3. **Announce:** "Created worktree and spec directory for feat-<name>"

### Phase 1-4: (existing brainstorm phases)
...

### Phase 5: Create Spec (NEW)

After brainstorm exploration is complete:

1. **Generate spec.md** using spec-templates skill
2. **Write to:** `knowledge-base/specs/feat-<name>/spec.md`
3. **Optionally save brainstorm.md** to same directory
4. **Announce:** "Spec created. Ready to plan? Run soleur:plan"

### Backward Compatibility

If `knowledge-base/` doesn't exist:
- Skip worktree creation
- Skip spec creation
- Behave as current brainstorm (output to docs/brainstorms/)
```

### Phase 2: Update soleur:plan

**Modify:** `plugins/soleur/commands/soleur/plan.md`

**New flow:**

```markdown
## Execution Flow

### Phase 0: Context Loading (NEW)

1. **Detect feature:** Check current branch for `feat-<name>` pattern
2. **Load constitution:** Read `knowledge-base/overview/constitution.md`
   - Use principles to guide planning decisions
3. **Load spec:** Read `knowledge-base/specs/feat-<name>/spec.md`
   - Use requirements as planning input
4. **Load relevant reviews:** Search `knowledge-base/reviews/` for related topics
   - Surface past feedback that might apply

### Phase 1: Research (existing)
...

### Phase 2: Planning (existing, enhanced)

When planning, consider:
- Constitution principles (especially Architecture and Code Style)
- Existing spec requirements (FR/TR)
- Past review feedback

### Phase 3: Create Tasks (NEW)

1. **Generate tasks.md** using spec-templates skill
2. **Write to:** `knowledge-base/specs/feat-<name>/tasks.md`
3. **Announce:** "Tasks created. Ready to work? Run soleur:work"

### Entry Point Behavior

If entering without spec.md:
- Ask: "No spec found. Create spec first? (Creates minimal spec from description)"
- If yes: Generate basic spec.md, then continue
- If no: Continue with plan-only flow

### Backward Compatibility

If `knowledge-base/` doesn't exist:
- Skip constitution loading
- Skip spec loading
- Output plan to docs/plans/ as current behavior
```

### Phase 3: Update soleur:work

**Modify:** `plugins/soleur/commands/soleur/work.md`

**New flow:**

```markdown
## Execution Flow

### Phase 0: Context Loading (NEW)

1. **Verify worktree:** Check if in `.worktrees/feat-<name>/`
   - If not, offer to switch: "Switch to feature worktree?"
2. **Load constitution:** Read `knowledge-base/overview/constitution.md`
   - Apply principles during implementation
3. **Load tasks:** Read `knowledge-base/specs/feat-<name>/tasks.md`
   - Use as work checklist
4. **Load patterns:** Search `knowledge-base/patterns/` for relevant patterns
   - Suggest applicable patterns

### Phase 1-N: Implementation (existing, enhanced)

During implementation:
- Reference constitution principles
- Check off tasks as completed
- Note patterns being used
- Flag potential review issues

### Task Tracking (NEW)

As work progresses:
- Update tasks.md checkboxes
- Add new tasks discovered during work
- Note which phases are complete

### Entry Point Behavior

If entering without tasks.md:
- Ask: "No tasks found. Create from spec? / Start without tasks?"
- If create: Generate tasks.md from spec.md
- If skip: Continue with TodoWrite tool for tracking

### Backward Compatibility

If `knowledge-base/` doesn't exist:
- Skip constitution loading
- Use TodoWrite for task tracking
- Behave as current work command
```

### Phase 4: Update soleur:compound

**Modify:** `plugins/soleur/commands/soleur/compound.md`

**New flow:**

```markdown
## Execution Flow

### Phase 1: Spec Sync (NEW)

1. **Check spec exists:** `knowledge-base/specs/feat-<name>/spec.md`
2. **Detect divergence:** Compare spec to implementation
3. **Auto-update spec:** Add new requirements, update changed ones
4. **Commit:** "sync: spec updated to match implementation"

### Phase 2: Learning Capture (existing, enhanced)

1. **Capture session learning** to `knowledge-base/learnings/YYYY-MM-DD-topic.md`
2. **Capture review feedback** (if any) to `knowledge-base/reviews/`
3. **Check for patterns** across sessions

### Phase 3: Constitution Promotion (NEW)

1. **Scan recent learnings** (last 30 days)
2. **Identify candidates** based on:
   - Frequency (3+ occurrences)
   - Impact (prevented major issues)
   - Generality (broadly applicable)
3. **Suggest promotions** to user
4. **On approval:** Distill to principle, add to constitution.md

### Phase 4: Cleanup (NEW)

1. **Delete old learnings:** Files > 6 months old
2. **Delete old reviews:** Files > 6 months old
3. **Report:** "Cleaned up N learnings, M reviews"

### Phase 5: Worktree Cleanup (NEW)

1. **Check PR status:** `gh pr list --state merged --head feat-<name>`
2. **If merged:** Ask "PR merged. Clean up worktree?"
3. **If yes:** Remove worktree, optionally archive spec

### Command Chaining

After compound:
- "Feature complete! Worktree cleaned."
- Or: "Learning captured. Continue working? Run soleur:work"

### Backward Compatibility

If `knowledge-base/` doesn't exist:
- Skip spec sync
- Save learning to docs/solutions/ (current behavior)
- Skip constitution promotion
- Skip decay cleanup
```

## Acceptance Criteria

### soleur:brainstorm
- [ ] Creates worktree at start (if knowledge-base/ exists)
- [ ] Creates spec directory
- [ ] Generates spec.md at end of brainstorm
- [ ] Suggests next command: soleur:plan
- [ ] Backward compatible without knowledge-base/

### soleur:plan
- [ ] Loads constitution for guidance
- [ ] Loads existing spec.md if available
- [ ] Surfaces relevant past reviews
- [ ] Generates tasks.md
- [ ] Prompts to create spec if missing
- [ ] Suggests next command: soleur:work
- [ ] Backward compatible without knowledge-base/

### soleur:work
- [ ] Verifies worktree context
- [ ] Loads constitution principles
- [ ] Loads tasks.md as checklist
- [ ] Surfaces relevant patterns
- [ ] Updates task checkboxes during work
- [ ] Prompts to create tasks if missing
- [ ] Suggests next command: soleur:compound
- [ ] Backward compatible without knowledge-base/

### soleur:compound
- [ ] Syncs spec with implementation
- [ ] Captures learning to knowledge-base/learnings/
- [ ] Captures review feedback if applicable
- [ ] Checks for patterns
- [ ] Suggests constitution promotions
- [ ] Cleans up old learnings/reviews (>6 months)
- [ ] Offers worktree cleanup if PR merged
- [ ] Backward compatible without knowledge-base/

## Success Metrics

- Full workflow runs seamlessly: brainstorm → plan → work → compound
- Knowledge compounds over time (constitution grows, patterns accumulate)
- Old knowledge decays (no context bloat)
- Existing repos without knowledge-base/ still work

## Test Strategy

- [ ] Unit test: Each command detects knowledge-base/ presence correctly
- [ ] Unit test: Context loader respects disclosure tiers
- [ ] Unit test: Backward compatibility when knowledge-base/ absent
- [ ] Fixture: Test repo with and without knowledge-base/
- [ ] Integration test: Full brainstorm→plan→work→compound cycle
- [ ] E2E test: User journey through entire workflow

## Files to Modify

| File | Changes |
|------|---------|
| `plugins/soleur/commands/soleur/brainstorm.md` | Add worktree creation, spec generation |
| `plugins/soleur/commands/soleur/plan.md` | Add constitution/spec loading, tasks generation |
| `plugins/soleur/commands/soleur/work.md` | Add context loading, task tracking |
| `plugins/soleur/commands/soleur/compound.md` | Add spec sync, promotion, decay, cleanup |

## Command Chaining Summary

```text
soleur:brainstorm
  ├── Creates worktree + spec directory
  ├── Explores requirements
  ├── Creates spec.md
  └── "Ready to plan? Run soleur:plan"
           │
           v
soleur:plan
  ├── Loads constitution + spec + reviews
  ├── Plans implementation
  ├── Creates tasks.md
  └── "Ready to work? Run soleur:work"
           │
           v
soleur:work
  ├── Verifies worktree
  ├── Loads constitution + tasks + patterns
  ├── Implements features
  ├── Updates task checkboxes
  └── "Done? Run soleur:compound"
           │
           v
soleur:compound
  ├── Syncs spec with implementation
  ├── Captures learnings
  ├── Suggests constitution promotions
  ├── Cleans up old knowledge
  ├── Offers worktree cleanup
  └── "Feature complete!"
```

## References

- Brainstorm: `docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md`
- Workflow section
- Command Flow & Entry Points section
