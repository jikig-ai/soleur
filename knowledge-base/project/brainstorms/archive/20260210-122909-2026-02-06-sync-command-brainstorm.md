# Brainstorm: /sync Command for Existing Codebases

**Date:** 2026-02-06
**Issue:** [#8 - New Sync Plugin command](https://github.com/jikig-ai/soleur/issues/8)
**Status:** Ready for planning

## What We're Building

A `/sync` command that analyzes existing codebases and populates knowledge-base files with:
- Coding conventions and principles (constitution.md)
- Documented solutions and patterns (learnings/)
- Architecture decisions and technical debt areas
- Testing practices and standards

This solves the problem that Soleur works well for greenfield projects but requires manual knowledge-base population for existing codebases.

## Why Multi-Agent Pipeline Approach

**Chosen over:**
- Single Deep-Dive Agent (too slow, context limits)
- Incremental Discovery (may miss stable but important code)

**Rationale:**
1. Parallel execution makes analysis faster
2. Specialized agents produce higher-quality domain analysis
3. Aligns with existing Soleur command patterns
4. Final review agents fulfill the issue's requirement for "another review at the end"

## Key Decisions

### 1. Scope and Targeting
- **Decision:** Interactive area selection at runtime
- **Options:** User chooses which areas to sync (architecture, conventions, testing, debt, all)
- **Why:** Flexible for both quick targeted syncs and comprehensive analysis

### 2. Data Sources
- **Decision:** Analyze code + git history + docs + closed PRs
- **Why:** PRs contain valuable context about *why* decisions were made
- **Trade-off:** More comprehensive but slower; PRs require GitHub API access

### 3. User Control
- **Decision:** Batch review before writing
- **Why:** Efficient (analyze all first) while maintaining user control
- **Flow:** Analyze → Present summary → User approves/edits → Write

### 4. Idempotency
- **Decision:** Safe to run multiple times
- **Implementation:** Detect existing entries, propose updates vs. new entries
- **Why:** Supports both initial bootstrap and ongoing maintenance

### 5. Final Review Phase
- **Decision:** Full validation suite with dedicated agents
- **Components:**
  - Consistency checker (docs match each other and code)
  - Gap analyzer (identify what's still missing)
  - Quality scorer (coverage and completeness metrics)

## Proposed Architecture

```
/sync
  │
  ├─ Phase 0: Setup
  │   └─ Check/create knowledge-base directory
  │
  ├─ Phase 1: Area Selection (Interactive)
  │   └─ User chooses: architecture, conventions, testing, debt, all
  │
  ├─ Phase 2: Analysis (Parallel Agents)
  │   ├─ Architecture Analyzer
  │   │   └─ Source: code structure, imports, layer patterns
  │   ├─ Conventions Analyzer
  │   │   └─ Source: code style, naming, comments, linting config
  │   ├─ Testing Analyzer
  │   │   └─ Source: test files, coverage config, test patterns
  │   ├─ Technical Debt Analyzer
  │   │   └─ Source: TODOs, FIXMEs, git churn, complexity
  │   ├─ Git History Analyzer
  │   │   └─ Source: commits, contributors, evolution patterns
  │   └─ PR Insights Analyzer
  │       └─ Source: closed PR discussions, review comments
  │
  ├─ Phase 3: Consolidation
  │   ├─ Merge findings from all agents
  │   ├─ Resolve conflicts/duplicates
  │   └─ Map to knowledge-base structure
  │
  ├─ Phase 4: Batch Review
  │   ├─ Present summary of proposed changes
  │   ├─ User can view details, edit, approve, skip
  │   └─ Collect final approved set
  │
  ├─ Phase 5: Write
  │   ├─ Update constitution.md with new principles
  │   ├─ Create learnings/ entries with proper YAML
  │   └─ Generate summary report
  │
  └─ Phase 6: Final Review (Dedicated Agents)
      ├─ Consistency Agent
      │   └─ Verify docs align with code and each other
      ├─ Gap Analyzer Agent
      │   └─ Identify missing coverage areas
      └─ Quality Scorer Agent
          └─ Rate coverage, completeness, actionability
```

## Knowledge-Base Mapping

| Analysis Domain | Target Location | Format |
|-----------------|-----------------|--------|
| Coding conventions | constitution.md | Always/Never/Prefer rules |
| Architecture decisions | learnings/architecture/ | YAML frontmatter + markdown |
| Testing practices | constitution.md + learnings/testing/ | Mixed |
| Technical debt | learnings/technical-debt/ | YAML with severity tags |
| Historical patterns | learnings/patterns/ | YAML with context |

## Open Questions

1. **PR Access:** Should we require GitHub token, or make PR analysis optional?
   - Recommendation: Make optional, gracefully degrade if unavailable

2. **Large Codebases:** How to handle repos with 100k+ files?
   - Recommendation: Sampling strategy with focus on most-changed areas

3. **Existing Entries:** When sync finds something already documented, should it update or skip?
   - Recommendation: Flag as "potential update" for user review

## Next Steps

1. `/soleur:plan` to create detailed implementation tasks
2. Create agents for each analysis domain
3. Build the orchestration command
4. Add review agents
5. Test on real existing codebase

---

*This brainstorm was created collaboratively to explore the /sync command design.*
