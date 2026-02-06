# Tasks: /sync Command Implementation (Simplified)

**Branch:** `feat-sync-command`
**Plan:** [2026-02-06-feat-sync-command-plan.md](../../plans/2026-02-06-feat-sync-command-plan.md)
**Version:** 2 (simplified per plan review)

## Phase 1: Foundation

- [x] 1.1 Create command file
  - [x] 1.1.1 Create `plugins/soleur/commands/soleur/sync.md`
  - [x] 1.1.2 Add YAML frontmatter (name, description, argument-hint)
  - [x] 1.1.3 Define input capture for `$ARGUMENTS`

- [x] 1.2 Implement Phase 0: Setup
  - [x] 1.2.1 Check if `knowledge-base/` exists
  - [x] 1.2.2 Create directory structure if missing
  - [x] 1.2.3 Validate git repository (warn if not git)

- [x] 1.3 Implement Phase 1: Analyze
  - [x] 1.3.1 Parse argument for area filter (conventions, architecture, testing, debt, all)
  - [x] 1.3.2 If no argument, analyze all areas
  - [x] 1.3.3 Analyze codebase for coding conventions (naming, style)
  - [x] 1.3.4 Analyze codebase for architecture patterns (layers, modules)
  - [x] 1.3.5 Analyze codebase for testing practices
  - [x] 1.3.6 Analyze codebase for technical debt (TODOs, FIXMEs)
  - [x] 1.3.7 Assign confidence scores (high/medium/low)
  - [x] 1.3.8 Limit findings to top 20 by confidence

- [x] 1.4 Implement Phase 2: Review
  - [x] 1.4.1 Present findings sequentially using AskUserQuestion
  - [x] 1.4.2 Format: "1/N: [type] Finding text"
  - [x] 1.4.3 Options: Accept (y), Skip (n), Edit (e)
  - [x] 1.4.4 If Edit: show finding, accept modified text
  - [x] 1.4.5 Check for exact duplicates in existing knowledge-base
  - [x] 1.4.6 Skip duplicates silently (idempotency)

- [x] 1.5 Implement Phase 3: Write
  - [x] 1.5.1 Write constitution.md entries (Always/Never/Prefer format)
  - [x] 1.5.2 Write learnings/ entries (YAML frontmatter + markdown)
  - [x] 1.5.3 Use existing compound-docs schema with `problem_type: best_practice`
  - [x] 1.5.4 Generate summary: "Created N entries, skipped M duplicates"

## Phase 2: Polish

- [x] 2.1 Test on real codebase
  - [x] 2.1.1 Run `/sync` on Soleur repo itself
  - [x] 2.1.2 Verify findings are sensible
  - [x] 2.1.3 Run `/sync` twice, verify no duplicates created

- [x] 2.2 Documentation
  - [x] 2.2.1 Add command to README.md
  - [x] 2.2.2 Document available areas (conventions, architecture, testing, debt, all)
  - [x] 2.2.3 Add usage examples

---

## Definition of Done

- [x] `/sync` works end-to-end on Soleur repo
- [x] User can approve/skip/edit each finding
- [x] Idempotent: running twice produces same result
- [x] Knowledge-base/ created if missing
- [x] Documentation complete

---

## Deferred to v2

- Multi-agent parallelization
- PR insights analysis
- Final review agents (consistency, gaps, quality)
- Fuzzy deduplication
- Large codebase sampling
- Complex batch review syntax

---

**Total tasks:** ~25 (reduced from 77)
**Files to create:** 1 (reduced from 9)
