---
title: "feat: Knowledge Layer - Compounding System"
type: feat
date: 2026-02-05
layer: knowledge
priority: 4
dependencies:
  - 2026-02-05-feat-knowledge-base-foundation-plan.md
---

# Knowledge Layer - Compounding System

## Overview

Implement the full knowledge compounding system including constitution management, learning decay, pattern extraction, review memory, and the promotion flow that bubbles important learnings up to the constitution.

## Problem Statement

Current `compound-docs` skill captures solutions but lacks:
- Structured constitution for project principles (Always/Never/Prefer)
- Learning decay to prevent context bloat (old learnings deleted after 6 months)
- Promotion flow to elevate important learnings to constitution
- Pattern extraction for recurring solutions
- Review memory to prevent repeating mistakes

## Proposed Solution

### 1. Constitution Management

Enhance constitution.md with:
- 8 domain categories
- Always/Never/Prefer structure per domain
- Skill for reading/updating constitution

### 2. Learning System

Update compound-docs skill to:
- Save learnings with YYYY-MM-DD prefix
- Check and delete learnings older than 6 months
- Suggest constitution promotions

### 3. Pattern Extraction

Add pattern detection to compound flow:
- Agent-detected patterns across sessions
- User-tagged patterns
- Permanent storage (no decay)

### 4. Review Memory

Capture and surface review feedback:
- Issue + Context + Resolution + Prevention format
- Surface during plan/review commands
- Decay like learnings (~6 months)

## Technical Approach

### Phase 1: Constitution Skill

**Create:** `plugins/soleur/skills/constitution/SKILL.md`

```markdown
---
name: constitution
description: Manage project constitution with domain-specific Always/Never/Prefer principles
---

# Constitution Management

## Reading the Constitution

Read `knowledge-base/overview/constitution.md` to understand project principles before:
- Planning new features
- Reviewing code
- Making architectural decisions

## Constitution Structure

```markdown
# Project Constitution

## Code Style
### Always
- [Principle]
### Never
- [Anti-pattern]
### Prefer
- [Preference]

## Architecture
...

## Testing
...

## Documentation
...

## Git & Workflow
...

## Security
...

## CI/CD & DevSecOps
...

## Operations
...
```

## Adding a Principle

1. Identify the domain (Code Style, Architecture, etc.)
2. Determine category (Always, Never, Prefer)
3. Write concise, actionable principle
4. Add to appropriate section
5. Commit with message: "constitution: add <domain> <category> principle"

## Principle Guidelines

- **Always**: Hard rules, must follow
- **Never**: Anti-patterns, avoid these
- **Prefer**: Soft preferences, use when applicable

Keep principles:
- Concise (one line if possible)
- Actionable (clear what to do)
- Specific (not vague platitudes)
```

### Phase 2: Enhanced Compound Flow

**Update:** `plugins/soleur/skills/compound-docs/SKILL.md`

Add these capabilities:

```markdown
## Learning Capture

Save learnings to `knowledge-base/learnings/YYYY-MM-DD-topic.md`:

```markdown
# Learning: <topic>

## Problem
[What we encountered]

## Solution
[How we solved it]

## Key Insight
[The generalizable lesson]

## Tags
category: <category>
module: <module>
```

## Learning Decay

During compound, check for old learnings:

1. List files in `knowledge-base/learnings/`
2. Extract date from filename (YYYY-MM-DD prefix)
3. If date > 6 months ago, delete file
4. Report: "Cleaned up N old learnings"

## Constitution Promotion

After capturing learnings, check for promotion candidates:

1. Scan recent learnings (last 30 days)
2. Look for patterns:
   - Same insight appearing 3+ times
   - High-impact fixes (prevented major issues)
   - Broadly applicable (not feature-specific)
3. Suggest promotions to user:
   - Show learning summary
   - Suggest domain and category
   - Ask for approval
4. If approved:
   - Distill to single concise principle
   - Add to constitution.md
   - Commit: "constitution: promote learning to <domain>/<category>"

## Promotion Confidence Scoring

To reduce noise, only suggest promotions above a confidence threshold:

| Factor | Points | Description |
|--------|--------|-------------|
| Frequency | +2 per occurrence | Same insight appears in multiple learnings |
| Impact | +5 if high | Prevented production issue or major bug |
| Breadth | +3 if cross-feature | Applies beyond single feature |
| User-tagged | +4 | User explicitly marked as important |
| Recency | +1 per week | More recent = more relevant |

**Threshold:** Only suggest when score >= 8 points

**User control:** Allow `--promotion-threshold=N` flag to adjust sensitivity

```typescript
interface PromotionCandidate {
  learning: Learning;
  score: number;
  factors: {
    frequency: number;
    impact: "high" | "medium" | "low";
    breadth: "cross-feature" | "single-feature";
    userTagged: boolean;
    ageWeeks: number;
  };
}
```
```

### Phase 3: Pattern Extraction

**Create:** `plugins/soleur/skills/patterns/SKILL.md`

```markdown
---
name: patterns
description: Extract and document recurring patterns from development sessions
---

# Pattern Extraction

## When to Extract Patterns

- During compound, when agent notices similar solutions across sessions
- When user explicitly tags something as a pattern
- When same approach is used 3+ times

## Pattern Format

Save to `knowledge-base/patterns/YYYY-MM-DD-pattern-name.md`:

```markdown
# Pattern: <name>

## Problem
[What problem does this pattern solve?]

## Solution
[Description of the approach]

## Example
[Code or usage example]

## When to Use
[Conditions when this pattern applies]

## Related
- [Links to related patterns or learnings]
```

## Pattern Lifecycle

- Patterns don't decay (permanent reference)
- Can be deprecated with `## Deprecated` section
- May be elevated to constitution if universally applicable

## Detection Heuristics

Agent looks for:
- Similar code structures across features
- Repeated problem/solution pairs
- Common architectural decisions
```

### Phase 4: Review Memory

**Create:** `plugins/soleur/skills/review-memory/SKILL.md`

```markdown
---
name: review-memory
description: Capture and surface review feedback to prevent repeating mistakes
---

# Review Memory

## Capturing Reviews

After code review (PR comments or soleur:review), save to `knowledge-base/reviews/YYYY-MM-DD-topic.md`:

```markdown
# Review: <topic>

## Issue
[What was flagged in review]

## Context
[Where this occurred - file, feature, PR]

## Resolution
[How the issue was fixed]

## Prevention
[How to avoid this in the future]
```

## Surfacing Reviews

During `soleur:plan`:
- Search reviews for keywords related to current feature
- Surface relevant past feedback

During `soleur:review`:
- Check if current code repeats past issues
- Flag potential repeated mistakes

## Review Lifecycle

- Reviews decay like learnings (~6 months)
- Repeated issues get promoted to constitution
- Reviews can reference related patterns
```

### Phase 5: Integration in Compound

**Update:** `plugins/soleur/commands/soleur/compound.md`

Full compound flow:

```markdown
## Compound Flow

1. **Capture Learning**
   - Summarize what was learned in this session
   - Save to `knowledge-base/learnings/YYYY-MM-DD-topic.md`

2. **Capture Review Feedback** (if applicable)
   - Extract key review comments
   - Save to `knowledge-base/reviews/YYYY-MM-DD-topic.md`

3. **Check for Patterns**
   - Analyze session against previous work
   - If pattern detected, ask to document it
   - Save to `knowledge-base/patterns/YYYY-MM-DD-pattern.md`

4. **Constitution Promotion**
   - Check learnings for promotion candidates
   - Suggest promotions based on frequency/impact
   - On approval, add to constitution.md

5. **Cleanup Old Learnings**
   - Delete learnings older than 6 months
   - Delete reviews older than 6 months
   - Report cleanup summary

6. **Spec Sync** (from Spec Layer plan)
   - Check for divergence
   - Auto-update spec if needed
```

## Acceptance Criteria

### Constitution
- [ ] `plugins/soleur/skills/constitution/SKILL.md` exists
- [ ] `knowledge-base/overview/constitution.md` has 8 domain categories
- [ ] Each domain has Always/Never/Prefer sections
- [ ] Constitution can be read and updated by commands

### Learning Decay
- [ ] Learnings saved with YYYY-MM-DD prefix
- [ ] Compound checks and deletes learnings > 6 months old
- [ ] Cleanup is reported to user

### Constitution Promotion
- [ ] Compound suggests promotion candidates
- [ ] User can approve/reject promotions
- [ ] Approved learnings distilled to single principle
- [ ] Principles added to correct domain/category

### Patterns
- [ ] `plugins/soleur/skills/patterns/SKILL.md` exists
- [ ] Patterns saved to `knowledge-base/patterns/`
- [ ] Patterns have Problem/Solution/Example/When to Use sections
- [ ] Patterns don't decay (permanent)

### Review Memory
- [ ] `plugins/soleur/skills/review-memory/SKILL.md` exists
- [ ] Reviews saved to `knowledge-base/reviews/`
- [ ] Reviews have Issue/Context/Resolution/Prevention sections
- [ ] Reviews decay after 6 months

## Success Metrics

- Constitution grows with valuable principles over time
- Old learnings don't bloat context
- Patterns are reusable across features
- Review mistakes aren't repeated

## Measurable KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| Constitution principles | +1-2 per month | Count principles in constitution.md |
| Learning decay | <50 learnings active | Count files in learnings/ |
| Pattern reuse | Patterns referenced 2+ times | Track pattern mentions in specs |
| Promotion acceptance rate | >50% | Accepted / suggested promotions |
| Review repetition | <10% | Same issue flagged twice |

**Tracking:** Add `knowledge-base/metrics.json` updated by compound:

```json
{
  "lastUpdated": "2026-02-05",
  "constitution": { "principles": 12, "lastAdded": "2026-02-01" },
  "learnings": { "active": 23, "decayed": 45 },
  "patterns": { "total": 8, "referenced": 15 },
  "promotions": { "suggested": 10, "accepted": 7 }
}
```

## Test Strategy

- [ ] Unit test: Promotion scoring calculates correctly
- [ ] Unit test: Decay removes files older than 6 months
- [ ] Unit test: Pattern detection identifies duplicates
- [ ] Fixture: Sample learnings with known promotion candidates
- [ ] Integration test: Full compound cycle updates metrics.json

## Files to Create

| File | Purpose |
|------|---------|
| `plugins/soleur/skills/constitution/SKILL.md` | Constitution management |
| `plugins/soleur/skills/patterns/SKILL.md` | Pattern extraction |
| `plugins/soleur/skills/review-memory/SKILL.md` | Review memory |

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/compound-docs/SKILL.md` | Add decay, promotion, pattern detection |
| `plugins/soleur/commands/soleur/compound.md` | Integrate full compounding flow |

## References

- Brainstorm: `docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md`
- Compounding & Knowledge Hierarchy section
- Learning Decay Mechanism section
- Constitution Promotion Flow section
- Pattern Extraction section
- Review Memory section
