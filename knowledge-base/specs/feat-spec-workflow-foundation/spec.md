---
title: "feat: Spec-Driven Workflow Foundation"
type: feat
date: 2026-02-06
priority: 1
dependencies: none
---

# Spec-Driven Workflow Foundation

## Overview

Create the minimal foundation for spec-driven development: a `knowledge-base/` directory, two markdown templates, and one worktree command.

## Problem Statement

Current workflow lacks structured specifications. Features start as brainstorms but have no standard format for requirements (FR/TR) or task tracking.

## Proposed Solution

Ship the simplest possible version:

1. Create `knowledge-base/` with 4 items (not 5 directories + 6 READMEs)
2. Two templates: spec.md and tasks.md
3. One worktree enhancement: `create-for-feature`

## What We're NOT Building (v2)

- Migration scripts (start fresh)
- Schema versioning (add when needed)
- Divergence detection (humans update specs)
- Pattern extraction (learnings cover this)
- Reviews directory (learnings cover this)
- Interactive worktree picker
- Auto-cleanup on merge

## Technical Approach

### Phase 1: Directory Structure

Create manually (no script needed):

```text
knowledge-base/
  specs/              # Feature specs (spec.md + tasks.md per feature)
  learnings/          # Session learnings (YYYY-MM-DD-topic.md)
  constitution.md     # Always/Never/Prefer (3 domains)
```

That's it. 3 items. No READMEs, no .gitkeep files.

### Phase 2: Constitution Scaffold

Create `knowledge-base/constitution.md` with 3 domains (expand when needed):

```markdown
# Project Constitution

## Code Style

### Always

### Never

### Prefer

## Architecture

### Always

### Never

### Prefer

## Testing

### Always

### Never

### Prefer
```

### Phase 3: Spec Templates

**spec.md template** (save in SKILL.md for reference):

```markdown
# Feature: [name]

## Problem Statement

[What problem are we solving?]

## Goals

- [What we want to achieve]

## Non-Goals

- [What is explicitly out of scope]

## Functional Requirements

### FR1: [name]

[User-facing behavior]

## Technical Requirements

### TR1: [name]

[Architecture, performance, security]
```

**tasks.md template:**

```markdown
# Tasks: [name]

## Phase 1: Setup

- [ ] 1.1 Task description

## Phase 2: Core Implementation

- [ ] 2.1 Main task

## Phase 3: Testing

- [ ] 3.1 Task description
```

### Phase 4: Worktree Enhancement

Add ONE function to existing `worktree-manager.sh`:

```bash
create_for_feature() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: create-for-feature <name>"
    return 1
  fi

  local branch="feat-$name"
  local worktree=".worktrees/$branch"
  local spec_dir="knowledge-base/specs/$branch"

  git worktree add -b "$branch" "$worktree" || return 1
  mkdir -p "$spec_dir"

  # Copy .env if exists
  [[ -f .env ]] && cp .env "$worktree/.env"

  echo "Created worktree: $worktree"
  echo "Created spec dir: $spec_dir"
}
```

## Acceptance Criteria

- [ ] `knowledge-base/` directory exists with specs/, learnings/, constitution.md
- [ ] constitution.md has 3 domains with Always/Never/Prefer sections
- [ ] `create-for-feature` command works and creates worktree + spec directory
- [ ] Spec template documented in spec-templates skill
- [ ] Tasks template documented in spec-templates skill

## Success Metrics

- Developers can create feature specs in < 2 minutes
- Knowledge-base structure is self-explanatory (no README needed)

## Files to Create

| File | Purpose |
| ---- | ------- |
| `knowledge-base/specs/.gitkeep` | Track empty specs directory |
| `knowledge-base/learnings/.gitkeep` | Track empty learnings directory |
| `knowledge-base/constitution.md` | Project principles (3 domains) |
| `plugins/soleur/skills/spec-templates/SKILL.md` | Templates for spec.md and tasks.md |

## Files to Modify

| File | Change |
| ---- | ------ |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Add create-for-feature function |

## References

- Archived plans: `docs/plans/archive/`
- Existing worktree skill: `plugins/soleur/skills/git-worktree/`
