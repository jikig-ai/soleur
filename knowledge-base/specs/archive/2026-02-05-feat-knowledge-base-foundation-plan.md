---
title: "feat: Knowledge Base Foundation"
type: feat
date: 2026-02-05
layer: foundation
priority: 1
dependencies: none
---

# Knowledge Base Foundation

## Overview

Create the `knowledge-base/` directory structure that serves as the foundation for all spec-driven workflow enhancements. This is the prerequisite for all other features in the unified workflow.

## Problem Statement

Currently Soleur uses scattered directories (`docs/solutions/`, `docs/brainstorms/`, `docs/specs/`) for different knowledge artifacts. The new unified workflow needs a single, agent-agnostic location for:
- Feature specifications
- Session learnings
- Extracted patterns
- Review feedback memory
- Project constitution

## Proposed Solution

Create `knowledge-base/` directory at repo root with the following structure:

```text
knowledge-base/
  specs/              # Feature specifications (spec.md + tasks.md per feature)
  learnings/          # Session learnings (time-decaying, YYYY-MM-DD-topic.md)
  patterns/           # Extracted recurring patterns (permanent)
  reviews/            # Review feedback memory (time-decaying)
  overview/
    constitution.md   # Project principles (Always/Never/Prefer per domain)
```

## Technical Approach

### Phase 1: Directory Creation

Create the directory structure with placeholder README files explaining each directory's purpose.

**Files to create:**

```text
knowledge-base/
  README.md           # Overview of knowledge-base system
  specs/
    README.md         # How specs are organized
    .gitkeep
  learnings/
    README.md         # Learning format and decay policy
    .gitkeep
  patterns/
    README.md         # Pattern format and lifecycle
    .gitkeep
  reviews/
    README.md         # Review memory format
    .gitkeep
  overview/
    constitution.md   # Initial empty constitution with domain structure
```

### Phase 2: Constitution Scaffold

Create initial `constitution.md` with the 8 domain categories, each with empty Always/Never/Prefer sections:

1. Code Style
2. Architecture
3. Testing
4. Documentation
5. Git & Workflow
6. Security
7. CI/CD & DevSecOps
8. Operations

**Schema versioning:** Include `schema_version: 1` in YAML frontmatter to enable future migrations:

```yaml
---
schema_version: 1
last_updated: 2026-02-05
---
```

This allows tools to detect and migrate older constitution formats automatically.

### Phase 3: Migration Guidance

Document how existing artifacts can migrate:
- `docs/solutions/` content → `knowledge-base/learnings/` (with date prefix)
- `docs/specs/` content → `knowledge-base/specs/`
- Principles from `AGENTS.md` → `knowledge-base/overview/constitution.md`

**Note:** Actual migration is optional and can be done incrementally.

**Migration Script:**

Create `scripts/migrate-to-knowledge-base.ts`:

```typescript
// scripts/migrate-to-knowledge-base.ts
import { $ } from "bun";
import { readdirSync, statSync } from "fs";

async function migrate() {
  // 1. Migrate docs/solutions/ → knowledge-base/learnings/
  const solutions = readdirSync("docs/solutions").filter(f => f.endsWith(".md"));
  for (const file of solutions) {
    const stat = statSync(`docs/solutions/${file}`);
    const date = stat.mtime.toISOString().slice(0, 10);
    const newName = file.startsWith("20") ? file : `${date}-${file}`;
    await $`cp docs/solutions/${file} knowledge-base/learnings/${newName}`;
  }

  // 2. Migrate docs/specs/ → knowledge-base/specs/
  // (preserve directory structure)
  if (await Bun.file("docs/specs").exists()) {
    await $`cp -r docs/specs/* knowledge-base/specs/`;
  }

  console.log("Migration complete. Review changes before committing.");
}
```

**Migration checklist:**
- [ ] Run migration script
- [ ] Review migrated files for correct date prefixes
- [ ] Update any hardcoded paths in CLAUDE.md or AGENTS.md
- [ ] Run test suite to verify nothing broke
- [ ] Commit with message: "chore: migrate docs/ to knowledge-base/"

## Acceptance Criteria

- [ ] `knowledge-base/` directory exists at repo root
- [ ] All 5 subdirectories exist (specs/, learnings/, patterns/, reviews/, constitution.md)
- [ ] Each subdirectory has a README.md explaining its purpose and format
- [ ] `constitution.md` has all 8 domain categories with Always/Never/Prefer structure
- [ ] Root README.md explains the knowledge-base system
- [ ] `.gitkeep` files ensure empty directories are tracked

## Success Metrics

- Directory structure matches the brainstorm specification
- Other features (Worktree, Spec, Knowledge, Commands) can build on this foundation
- No breaking changes to existing `docs/` structure

## Test Strategy

- [ ] Unit test: Verify all directories exist after creation script runs
- [ ] Unit test: Verify README.md files have expected sections
- [ ] Unit test: Verify constitution.md has correct YAML frontmatter
- [ ] Integration test: Other plans can import/reference paths correctly

## Rollback Plan

If knowledge-base/ needs to be removed:
1. All commands check for existence before use (backward compatible)
2. Simply delete `knowledge-base/` directory
3. Commands fall back to `docs/` paths automatically

## Files to Create

| File | Purpose |
|------|---------|
| `knowledge-base/README.md` | Overview of knowledge-base system |
| `knowledge-base/specs/README.md` | Spec organization guide |
| `knowledge-base/specs/.gitkeep` | Track empty directory |
| `knowledge-base/learnings/README.md` | Learning format and decay policy |
| `knowledge-base/learnings/.gitkeep` | Track empty directory |
| `knowledge-base/patterns/README.md` | Pattern format and lifecycle |
| `knowledge-base/patterns/.gitkeep` | Track empty directory |
| `knowledge-base/reviews/README.md` | Review memory format |
| `knowledge-base/reviews/.gitkeep` | Track empty directory |
| `knowledge-base/overview/constitution.md` | Project principles scaffold |

## References

- Brainstorm: `docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md`
- Directory Structure section
- Constitution Format section
