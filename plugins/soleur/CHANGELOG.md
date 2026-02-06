# Changelog

All notable changes to the Soleur plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

