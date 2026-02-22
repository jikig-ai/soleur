# Learning: Plan review collapses agent architecture to inline instructions

## Problem

Issue #215 proposed three parallel pre-flight agents (environment-guard, convention-checker, scope-validator) to run before implementation in `/soleur:work`. The original plan specified 3 new agent files, a severity matrix, a result aggregation truth table, and a fast-path bypass system -- approximately 150 lines of new code across 4 files.

## Solution

Three plan reviewers (DHH, code-simplicity, Kieran) independently converged on the same conclusion: the pre-flight checks are deterministic shell commands (`pwd`, `git branch`, `git status`, `git stash list`, `git diff`) and context verification, not LLM reasoning tasks. They don't need agents.

The final implementation: 23 lines of inline instructions added to work.md Phase 0.5, plus a one-line convention reminder in Phase 1. No new files. PATCH bump instead of MINOR.

## Key Insight

When checks are deterministic (shell commands with binary pass/fail outcomes), inline instructions in the existing command are simpler and faster than spawning Task agents. Agents add LLM round-trip latency to what would otherwise be millisecond shell commands. The existing pattern in work.md (`cleanup-merged` runs inline in Phase 0 without an agent) already demonstrated this.

The review also caught an inverted git command: `git log origin/main..HEAD` (files changed on current branch) vs `git diff --name-only HEAD...origin/main` (files diverged between branch and main). The original command would have compared the wrong set of files.

## Session Errors

- SpecFlow analyzer wrote temp files to wrong location (worktree root)
- Pre-existing merge conflict marker in README.md HEAD
- Stale branch version required merge before bump (2.23.18 vs 2.25.1)
- Glob tool returned empty for files that existed (required find fallback)
- Edit tool required explicit Read even after Grep had searched the file

## Tags

category: architecture-decisions
module: plugins/soleur/commands
