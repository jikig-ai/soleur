# Learning: Documentation Consolidation Migration

## Problem

After implementing the spec-driven workflow (GitHub issues #3 and #4), documentation was scattered across multiple locations:
- `/docs/plans/` - Feature plans and archived plans
- `/docs/specs/` - External platform specifications
- `/docs/solutions/` - Problem solutions and learnings
- `/docs/brainstorms/` - Feature exploration documents
- `/openspec/` - Unused scaffolding with config rules

Meanwhile, the new `/knowledge-base/` structure sat mostly empty. This created confusion about where to find and store documentation.

## Solution

Consolidated all documentation into a unified `/knowledge-base/` structure:

```
knowledge-base/
├── brainstorms/           # Feature exploration docs
├── learnings/             # Documented solutions (was docs/solutions/)
├── overview/
│   └── constitution.md    # Team principles + integrated openspec rules
├── plans/                 # Active plans (new)
└── specs/
    ├── archive/           # Completed specs (was docs/plans/archive/)
    ├── external/          # External platform specs (was docs/specs/)
    └── feat-*/            # Active feature specs
```

**Migration steps:**
1. Created new directory structure in knowledge-base/
2. Used `git mv` for tracked files to preserve history
3. Used regular `mv` for untracked files (brainstorms)
4. Integrated openspec/config.yaml rules into constitution.md
5. Updated 103 path references across 10+ command/skill files
6. Deleted empty source directories

## Key Insight

**Convention over configuration makes navigation intuitive.** Branch names (`feat-<name>`) now map directly to spec directories (`knowledge-base/specs/feat-<name>/`). No lookup needed - if you're on `feat-auth`, your spec is at `knowledge-base/specs/feat-auth/spec.md`.

**Secondary insight:** When migrating paths, grep is your friend. Run `grep -r "old/path" plugins/` to find all references before claiming migration is complete. We found 103 references that needed updating.

## Tags

category: workflow-issues
module: documentation
severity: medium
problem_type: documentation_gap
root_cause: inadequate_documentation
