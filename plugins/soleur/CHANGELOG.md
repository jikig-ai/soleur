# Changelog

All notable changes to the Soleur plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.11.0] - 2026-02-10

### Added

- Consolidate & archive KB artifacts option in `/soleur:compound` decision menu (Option 2, `feat-*` branches only)
  - Branch-name glob discovery for brainstorms, plans, and specs
  - Single-agent knowledge extraction proposing updates to constitution, component docs, and overview README
  - One-at-a-time approval flow with Accept/Skip/Edit and idempotency checking
  - `git mv` archival with `YYYYMMDD-HHMMSS` timestamp prefix preserving git history
  - Context-aware archival confirmation (different message when all proposals skipped)
  - Single commit for all changes enabling clean `git revert`
- Consolidated 8 principles from 31 artifacts into constitution.md and overview README.md
- Archived 12 brainstorms, 8 plans, and 11 spec directories

## [1.10.0] - 2026-02-09

### Added

- Parallel subagent execution in `/soleur:work` -- when 3+ independent tasks exist, offers to spawn Task subagents (max 5) for parallel execution with lead-coordinated commits and failure fallback

## [1.9.1] - 2026-02-09

### Fixed

- `/ship` skill now offers post-merge worktree cleanup (Phase 8), closing the gap where worktrees were only cleaned on session start or `/soleur:work`, not after mid-session merges

## [1.9.0] - 2026-02-09

### Added

- 4 new review agents from claude-code-agents: code-quality-analyst (Fowler's smell detection + refactoring mapping), test-design-reviewer (Farley Score weighted rubric), legacy-code-expert (Feathers' dependency-breaking techniques), ddd-architect (Evans' strategic DDD)
- 2 new skills: atdd-developer (RED/GREEN/REFACTOR cycle with permission gates), user-story-writer (Elephant Carpaccio + INVEST criteria)
- Problem Analysis Mode in brainstorming skill for deep problem decomposition without solution suggestions

## [1.8.0] - 2026-02-09

### Removed

- 10 unused/inactive agents: design-implementation-reviewer, design-iterator, figma-design-sync, ankane-readme-writer, julik-frontend-races-reviewer, kieran-python-reviewer, kieran-typescript-reviewer, bug-reproduction-validator, lint, every-style-editor (agent duplicate of skill)
- Stale agent references in commands: rails-console-explorer, appsignal-log-investigator, rails-turbo-expert, dependency-detective, code-philosopher, devops-harmony-analyst, cora-test-reviewer
- Empty design/ and docs/ agent directories

### Fixed

- Broken agent references in reproduce-bug, review, and compound commands
- Stale component counts in README files

## [1.7.0] - 2026-02-09

### Added

- `/ship` skill for automated feature lifecycle enforcement (artifact validation, /compound check, README verification, version bump, PR creation)
- Runtime guardrails in root AGENTS.md: worktree awareness, workflow completion protocol, interaction style, plugin versioning reminders

## [1.6.0] - 2026-02-09

### Added

- `/help` command listing all available commands, agents, and skills
- CLAUDE.md auto-loading in Phase 0 of all 6 core workflow commands
- Workspace state reporting after worktree cleanup in `/soleur:work`
- CRUD management for knowledge-base entities:
  - Learnings update/archive/delete in `/soleur:compound`
  - Constitution rule edit/remove in `/soleur:compound`
  - Brainstorm update/archive in `/soleur:brainstorm`
  - Plan update/archive in `/soleur:plan`
- Auto-invoke trigger documentation for all 16 skills (was 5/16)
- Constitution rule documenting plugin infrastructure immutability

## [1.5.0] - 2026-02-06

### Added

- Fuzzy deduplication for `/sync` command (GitHub issue #12)
  - Detects near-duplicate findings using word-based Jaccard similarity
  - Prompts user to skip when similarity > 0.8 threshold
  - Loads existing constitution rules and learnings for comparison
  - Two-stage deduplication: exact match (silent skip) + fuzzy match (user prompt)

## [1.4.2] - 2026-02-06

### Fixed

- `soleur:brainstorm` now detects existing GitHub issue references and skips duplicate creation
  - Parses feature description for `#N` patterns
  - Validates issue state (OPEN/CLOSED/NOT FOUND) before deciding
  - Updates existing issue body with artifact links instead of creating new
  - Shows "Using existing issue: #N" in output summary

## [1.4.1] - 2026-02-06

### Fixed

- git-worktree `feature` command now pulls latest from remote before creating worktree
  - Matches existing behavior in `create_worktree()` for consistency
  - Prevents feature branches from being based on stale local refs
  - Uses `|| true` for graceful failure when offline

## [1.4.0] - 2026-02-06

### Added

- Project overview documentation system in `knowledge-base/overview/`
  - `README.md` with project purpose, architecture diagram, and component index
  - Component documentation files in `overview/components/` (agents, commands, skills, knowledge-base)
  - Component template added to `spec-templates` skill
- `overview` area for `/sync` command to generate/update project documentation
  - Component detection heuristics based on architectural boundaries
  - Preservation of user customizations via frontmatter
  - Review phase with Accept/Skip/Edit for each component
- Constitution conventions for overview vs constitution.md separation
- `cleanup-merged` command in git-worktree skill for automatic worktree cleanup after PR merge
  - Detects merged branches via git's `[gone]` status using `git for-each-ref`
  - Archives spec directories to `knowledge-base/specs/archive/YYYY-MM-DD-HHMMSS-<name>/`
  - Removes worktree and deletes local branch (safe delete)
  - TTY detection: verbose output in terminal, quiet otherwise
  - Safety checks: skips active worktrees and those with uncommitted changes
- SessionStart hook to automatically run cleanup on session start

## [1.3.0] - 2026-02-06

### Added

- `soleur:sync` command for analyzing existing codebases and populating knowledge-base
  - Analyzes coding conventions, architecture patterns, testing practices, and technical debt
  - Sequential review with approve/skip/edit per finding
  - Idempotent operation (exact match deduplication)
  - Supports area filtering: `/sync conventions`, `/sync architecture`, `/sync testing`, `/sync debt`, `/sync all`

## [1.2.0] - 2026-02-06

### Added

- Command integration for spec-driven workflow:
  - `soleur:brainstorm` now creates worktree + spec.md when knowledge-base/ exists
  - `soleur:plan` loads constitution + spec.md, creates tasks.md
  - `soleur:work` loads constitution + tasks.md for implementation guidance
  - `soleur:compound` saves learnings to knowledge-base/, offers manual constitution promotion
- Manual constitution promotion flow (no automation, human-in-the-loop)
- Worktree cleanup prompt after feature completion

## [1.1.0] - 2026-02-06

### Added

- `knowledge-base/` directory structure for spec-driven workflow
  - `specs/` - Feature specifications (spec.md + tasks.md per feature)
  - `learnings/` - Session learnings with date prefixes
  - `constitution.md` - Project principles (Always/Never/Prefer)
- `spec-templates` skill with templates for spec.md and tasks.md
- `feature` command in git-worktree skill to create worktree + spec directory
