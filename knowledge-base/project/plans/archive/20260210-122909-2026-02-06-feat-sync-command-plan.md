---
title: "feat: Add /sync Command for Knowledge-Base Population"
type: feat
date: 2026-02-06
issue: "#8"
branch: feat-sync-command
spec: knowledge-base/specs/feat-sync-command/spec.md
brainstorm: knowledge-base/brainstorms/2026-02-06-sync-command-brainstorm.md
version: 2 (simplified per plan review)
---

# feat: Add /sync Command for Knowledge-Base Population

## Overview

Implement a `/sync` command that analyzes existing codebases and populates knowledge-base files with coding conventions, architecture decisions, testing practices, and technical debt.

## Problem Statement

Soleur works well for greenfield projects but requires manual knowledge-base population for existing codebases. Teams skip adoption due to high initial setup cost.

## Proposed Solution (Simplified)

A single command that:

1. Validates knowledge-base/ exists
2. Analyzes codebase for conventions, architecture, patterns, debt
3. Presents findings for user review (sequential y/n/edit)
4. Writes approved entries

**One file. One workflow. No agent army.**

## Technical Approach

### Architecture

```
/sync command
    │
    ├── Phase 0: Setup
    │   └── Validate knowledge-base/ exists (create if missing)
    │
    ├── Phase 1: Analyze
    │   └── Single pass: conventions, architecture, testing, debt
    │
    ├── Phase 2: Review
    │   └── Sequential: present each finding, user approves/skips/edits
    │
    └── Phase 3: Write
        └── constitution.md entries + learnings/ files
```

### Knowledge-Base Mapping

| Analysis Domain | Target | Format |
| --------------- | ------ | ------ |
| Coding conventions | constitution.md | Always/Never/Prefer rules |
| Architecture decisions | learnings/architecture/ | YAML frontmatter + markdown |
| Testing practices | constitution.md | Always/Never/Prefer rules |
| Technical debt | learnings/technical-debt/ | YAML with severity |

### File Structure

```
plugins/soleur/commands/soleur/
└── sync.md                    # The entire feature
```

**That's it. One file.**

### Implementation Phases

#### Phase 1: Foundation

Create the command with all four phases.

**Tasks:**

- [ ] Create `plugins/soleur/commands/soleur/sync.md` with YAML frontmatter
- [ ] Implement Phase 0: knowledge-base/ validation and creation
- [ ] Implement Phase 1: codebase analysis (inline, not separate agent)
- [ ] Implement Phase 2: sequential review via AskUserQuestion
- [ ] Implement Phase 3: write entries with proper formatting
- [ ] Add argument parsing for direct area specification (`/sync conventions`)

**Files:**

- `plugins/soleur/commands/soleur/sync.md`

**Success criteria:**

- Running `/sync` analyzes codebase
- User can approve/skip/edit each finding
- Approved entries written to knowledge-base/

#### Phase 2: Polish

Testing and documentation.

**Tasks:**

- [ ] Test on Soleur repo itself (meta-test)
- [ ] Test idempotency (run twice, verify no duplicates)
- [ ] Document command in README
- [ ] Add examples to command help text

**Files:**

- `plugins/soleur/commands/soleur/sync.md` (finalize)
- `README.md` (update)

**Success criteria:**

- Works end-to-end on real codebase
- Running twice produces same result
- Documentation complete

## Design Decisions

### 1. Single Command, No Separate Agents

**Why:** Multi-agent orchestration adds coordination overhead, failure modes, and maintenance burden without proven benefit for v1.

**Trade-off:** Less parallelism, but simpler debugging and iteration.

### 2. Sequential Review (y/n/edit per finding)

**Format:**
```
Found 12 items to review.

1/12: [conventions] Prefer early returns over nested conditionals
  Target: constitution.md > Code Style > Prefer
  Accept? [y/n/e to edit] _
```

**Why:** Familiar UX. No custom query syntax to learn.

### 3. Exact Match Deduplication Only

**Rule:** If identical entry exists in target location, skip silently.

**Why:** Fuzzy matching (80% threshold) is arbitrary and error-prone. Users can recognize near-duplicates during review and skip them manually.

### 4. Use Existing Learnings Schema

**Decision:** Map architecture decisions to existing `compound-docs` schema.

**Mapping:**
```yaml
---
module: [Extracted module name]
date: YYYY-MM-DD
problem_type: best_practice  # Use this for non-problem learnings
component: [Mapped from code area]
tags: [architecture, pattern, etc.]
---
```

**Why:** Avoids schema incompatibility. Learnings tooling continues to work.

## What's Cut (Deferred to v2)

| Feature | Why Cut |
| ------- | ------- |
| Multi-agent parallelization | YAGNI; optimize only if v1 is slow |
| PR insights analysis | Requires GitHub token, rate limits |
| Final review agents | User review is the quality gate |
| Fuzzy deduplication | Exact match is sufficient |
| Sampling strategy | Add when users hit 100k+ files |
| Complex batch review syntax | Sequential is simpler |

## Acceptance Criteria

- [ ] Running `/sync` on an existing codebase populates knowledge-base
- [ ] User can approve/skip/edit each finding
- [ ] Running `/sync` twice doesn't create duplicates
- [ ] Graceful handling if knowledge-base/ doesn't exist

## Risk Analysis

| Risk | Mitigation |
| ---- | ---------- |
| Too many findings overwhelm user | Limit to top 20 by confidence; option to continue |
| Analysis too slow | Acceptable for v1; optimize in v2 if needed |
| Findings miss important patterns | Users can run `/sync` again as codebase evolves |

## Future Considerations (v2)

- Multi-agent parallelization (if v1 is slow)
- PR analysis (if users request it)
- Quality scoring/gap analysis (if users want metrics)
- Large codebase sampling (if real users hit limits)

**Design for v2, implement for v1.**

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-06-sync-command-brainstorm.md`
- Spec: `knowledge-base/specs/feat-sync-command/spec.md`
- Issue: #8
- Plan reviews: DHH, Kieran, Simplicity (all recommended simplification)
