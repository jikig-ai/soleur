# Brainstorm: Merge features/ into project/

**Date:** 2026-03-13
**Status:** Decided

## What We're Building

Merge `knowledge-base/features/` contents (brainstorms, learnings, plans, specs) into `knowledge-base/project/` to simplify the top-level taxonomy. Also clean up the stale top-level `knowledge-base/project/specs/` leftover.

## Why This Approach

The knowledge-base taxonomy principle is "top-level directories = domains." `features/` breaks this principle — it's an artifact category, not a domain. Brainstorms, specs, plans, and learnings are all project-level artifacts that naturally belong under `project/`.

### Before

```
knowledge-base/
├── engineering/        # domain
├── features/           # artifact category (breaks taxonomy)
│   ├── brainstorms/
│   ├── learnings/
│   ├── plans/
│   └── specs/
├── marketing/          # domain
├── operations/         # domain
├── product/            # domain
├── project/            # project meta
│   ├── components/
│   └── constitution.md
├── sales/              # domain
├── specs/              # STALE leftover
└── support/            # domain
```

### After

```
knowledge-base/
├── engineering/        # domain
├── marketing/          # domain
├── operations/         # domain
├── product/            # domain
├── project/            # project meta + feature lifecycle
│   ├── brainstorms/
│   ├── components/
│   ├── constitution.md
│   ├── learnings/
│   ├── plans/
│   └── specs/
├── sales/              # domain
└── support/            # domain
```

## Key Decisions

1. **Merge features/ into project/** — brainstorms, learnings, plans, specs move under `project/`
2. **Delete stale knowledge-base/project/specs/** — leftover from prior refactor, contents preserved in git history
3. **Update all path references** — ~100+ references across 12 skills, 2 shell scripts, 1 agent

## Alternatives Considered

- **Flatten to top-level:** Promotes brainstorms/learnings/plans/specs back to top-level. Rejected: 11 top-level dirs, mixes domains with artifact types.
- **Keep as-is:** `features/` works but feels redundant alongside `project/`. Rejected: taxonomy principle is cleaner with the merge.

## Open Questions

None — approach is decided.

## Blast Radius

| Category | Count |
|----------|-------|
| Skill files to update | 12 |
| Shell scripts to update | 2 (worktree-manager.sh, archive-kb.sh) |
| Agents to update | 1 (cpo.md) |
| Total line references | ~100+ |
