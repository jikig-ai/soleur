# Feature Spec: /sync Command

**Branch:** `feat-sync-command`
**Issue:** #8
**Brainstorm:** [2026-02-06-sync-command-brainstorm.md](../../brainstorms/2026-02-06-sync-command-brainstorm.md)

## Problem Statement

Soleur works well for greenfield projects but requires manual knowledge-base population for existing codebases. Teams adopting Soleur on established projects must manually document conventions, architecture decisions, and patterns—a tedious and often incomplete process.

## Goals

1. Automate extraction of institutional knowledge from existing codebases
2. Populate knowledge-base with coding conventions, architecture decisions, testing practices, and technical debt
3. Support both initial bootstrap and ongoing maintenance (incremental sync)
4. Ensure generated documentation is consistent and complete via dedicated review agents

## Non-Goals

- Modifying source code (read-only analysis)
- Replacing human judgment (batch review required)
- Supporting non-git repositories
- Real-time continuous sync (manual invocation only)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Interactive area selection (architecture, conventions, testing, debt, all) |
| FR2 | Parallel analysis using specialized agents per domain |
| FR3 | Analyze sources: code, git history, docs, and closed PRs (optional) |
| FR4 | Batch review: present all findings before writing |
| FR5 | Map findings to knowledge-base structure (constitution.md, learnings/) |
| FR6 | Idempotent operation: detect existing entries, propose updates |
| FR7 | Final review phase with consistency, gap, and quality agents |
| FR8 | Graceful degradation if PR access unavailable |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Command located at `plugins/soleur/commands/soleur/sync.md` |
| TR2 | Agents located at `plugins/soleur/agents/sync/` |
| TR3 | Follow existing SKILL.md and agent patterns |
| TR4 | Use AskUserQuestion for interactive selection |
| TR5 | Learnings must follow YAML schema from compound-docs |
| TR6 | Large codebase support: sampling strategy for 100k+ files |

## Architecture

```
/sync command
    │
    ├── Phase 0: Setup (validate knowledge-base/)
    ├── Phase 1: Area Selection (AskUserQuestion)
    ├── Phase 2: Analysis (parallel Task agents)
    │   ├── architecture-analyzer
    │   ├── conventions-analyzer
    │   ├── testing-analyzer
    │   ├── debt-analyzer
    │   ├── git-history-analyzer (existing)
    │   └── pr-insights-analyzer
    ├── Phase 3: Consolidation (merge, dedupe, map)
    ├── Phase 4: Batch Review (AskUserQuestion)
    ├── Phase 5: Write (constitution.md, learnings/)
    └── Phase 6: Final Review (review agents)
        ├── consistency-checker
        ├── gap-analyzer
        └── quality-scorer
```

## Acceptance Criteria

- [ ] Running `/sync` on an existing codebase populates knowledge-base with relevant entries
- [ ] User can select which areas to analyze
- [ ] All findings presented for review before writing
- [ ] Running `/sync` twice doesn't create duplicates
- [ ] Final review agents provide actionable feedback
- [ ] Works on codebases with 10k+ files without timeout
