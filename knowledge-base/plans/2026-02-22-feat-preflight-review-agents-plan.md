---
title: "feat: Pre-flight validation checks in /soleur:work"
type: feat
date: 2026-02-22
issue: "#215"
version-bump: PATCH
---

# Pre-Flight Validation Checks

## Overview

Add inline pre-flight assertions to `/soleur:work` Phase 0 that catch environment, convention, and scope issues before implementation begins. These are deterministic checks (shell commands + context verification), not LLM reasoning tasks -- they belong as inline instructions in the command, not as separate agents.

## Problem Statement

From Claude Code Insights (2026-01-29 to 2026-02-21):
- "wrong_approach" is the #1 friction type (45 instances)
- "misunderstood_request" accounts for 12 more incidents
- Wrong branch/worktree edits recurred across 4-5 sessions
- Convention violations (YAML vs markdown) required manual correction

Current state: AGENTS.md has instructions for worktree discipline, but nothing validates them before work begins. The `ship` skill has post-implementation gates, but by then the damage is done.

## Proposed Solution

Add a **Phase 0.5: Pre-Flight Checks** section to `plugins/soleur/commands/soleur/work.md`, immediately after existing Phase 0 (context loading) and before Phase 1 (quick start). The section contains inline assertions -- no new agents, no new files.

### Phase 0.5 Content

```markdown
### Phase 0.5: Pre-Flight Checks

Run these checks before proceeding. FAIL blocks with remediation. WARN displays and continues. All pass continues silently.

**Environment checks:**

1. Run `git branch --show-current`. If the result is the default branch (main or master), FAIL: "On default branch -- create a worktree before starting work. Run: `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`"
2. Run `pwd`. If the path does NOT contain `.worktrees/`, WARN: "Not in a worktree directory. Phase 1 will offer to create one."
3. Run `git status --short`. If output is non-empty, WARN: "Uncommitted changes detected. Consider committing or stashing before starting new work."
4. Run `git stash list`. If output is non-empty, WARN: "Stashed changes found. Review stash list to avoid forgotten work."

**Scope checks:**

5. If a plan file was provided as input, verify it exists and is readable. If not, FAIL: "Plan file not found at the specified path."
6. Run `git fetch origin main && git log origin/main..HEAD --name-only --pretty=format:""` to identify files changed on the current branch. Cross-reference with files likely to be modified by the plan. If overlap exists with recent changes on main, WARN: "Potential merge conflict zones detected in: [file list]. Consider merging main before starting."

**Convention reminder (in Phase 1, not Phase 0.5):**

In Phase 1's "Read Plan and Clarify" step, add: "Before proceeding, verify the plan does not contradict conventions in AGENTS.md (file format: markdown tables not YAML, kebab-case naming, directory structure)."
```

## Non-Goals

- No new agents -- these are deterministic checks, not LLM reasoning tasks
- No new skill -- checks are inline in work.md
- No changes to `/soleur:plan` -- plan runs before implementation; adding pre-flight there would be redundant validation
- No persistent reporting -- results displayed inline only
- No fast-path bypass -- the checks run in milliseconds; no evidence that pre-flight friction on trivial changes is a problem

## Acceptance Criteria

- [x] `/soleur:work` has a Phase 0.5 section with pre-flight assertions
- [x] Being on the default branch (main/master) is a FAIL that blocks with remediation
- [x] Not being in a worktree directory is a WARN (Phase 1 creates worktrees)
- [x] Uncommitted changes produce a WARN
- [x] Stashed changes produce a WARN
- [x] Missing plan file is a FAIL
- [x] Merge conflict zone detection produces a WARN with file list
- [x] Phase 1 includes a convention verification reminder
- [x] Version bump: PATCH (2.25.1 -> 2.25.2)

## Test Scenarios

- Given a session on the default branch (main), when `/soleur:work` runs, then Phase 0.5 FAILS with "On default branch -- create a worktree"
- Given a session in the main repo root with no worktree, when `/soleur:work` runs, then Phase 0.5 WARNS "Not in a worktree directory"
- Given uncommitted changes in the worktree, when Phase 0.5 runs, then it WARNS "Uncommitted changes detected"
- Given stashed changes exist, when Phase 0.5 runs, then it WARNS "Stashed changes found"
- Given a plan file path that does not exist, when Phase 0.5 runs, then it FAILS "Plan file not found"
- Given files changed on main that overlap with the plan's target files, when Phase 0.5 runs, then it WARNS about merge conflict zones
- Given a clean environment (feature branch, worktree, no changes), when Phase 0.5 runs, then all checks pass silently and Phase 1 begins
- Given a detached HEAD state, when Phase 0.5 runs, then it FAILS "Detached HEAD state -- checkout a feature branch"
- Given ad-hoc work with a text description (not a file path), when Phase 0.5 runs, then it WARNS "Input appears to be a description, not a file path. Scope validation limited."

## Dependencies and Risks

- **Risk:** Added instructions in work.md increase command length. Mitigation: Phase 0.5 is ~15 lines of instruction, minimal impact.
- **Risk:** Merge conflict zone detection requires `git fetch` which adds network latency. Mitigation: Phase 0 already runs `cleanup-merged` which may fetch. If fetch fails (offline), skip the conflict check with a WARN.

## Enhancement Summary

**Deepened on:** 2026-02-22

### Implementation Details

**Exact insertion point in work.md:** Between line 54 (`- Continue with standard work flow (use input document only)`) and line 56 (`### Phase 1: Quick Start`). The new Phase 0.5 section goes immediately after Phase 0's knowledge-base loading and before Phase 1.

**Ad-hoc work handling:** The `<input_document>` comes from `#$ARGUMENTS`. If the argument is a text description (not a file path), check 5 (plan file existence) should detect this: if the argument does not end in `.md` or does not start with a path-like pattern, skip the file existence check and WARN: "Input appears to be a description, not a file path. Scope validation limited."

**Git fetch deduplication:** Phase 0 runs `cleanup-merged` which internally runs `git fetch`. The scope check in Phase 0.5 can skip the redundant `git fetch origin main` and just run `git log origin/main..HEAD --name-only --pretty=format:""` since the fetch already happened. If cleanup-merged was skipped (no knowledge-base), include the fetch.

**Convention reminder specificity:** The Phase 1 convention reminder should check these concrete conventions from AGENTS.md and constitution.md:
- File format: markdown tables, not YAML files (constitution.md "Markdown-first" rule)
- Naming: kebab-case for files and directories
- Directory structure: agents recurse, skills flat at root level
- Frontmatter: `name`, `description`, `model` fields required for agents; `name`, `description` for skills
- Shell scripts: `#!/usr/bin/env bash` shebang, `set -euo pipefail`

### Edge Cases

- **Phase 0.5 + Phase 1 overlap:** Phase 1 Step 2 also checks the branch and offers to create a worktree. Phase 0.5 does this earlier with FAIL/WARN semantics. If Phase 0.5 fails (on default branch), Phase 1 never runs. If Phase 0.5 warns (no worktree), Phase 1's worktree creation path handles it. No conflict.
- **Empty git stash list:** `git stash list` returns empty string with exit code 0 when no stashes exist. Safe to check for non-empty output.
- **Detached HEAD:** `git branch --show-current` returns empty string on detached HEAD. Treat as FAIL: "Detached HEAD state -- checkout a feature branch or create a worktree."

## References

- Issue: #215
- Target file: `plugins/soleur/commands/soleur/work.md` (insertion between lines 54-56)
- Worktree validation instructions: `AGENTS.md` "Worktree Awareness" section
- Learnings on duplicate validation gates: `knowledge-base/learnings/2026-02-19-plan-review-catches-redundant-validation-gates.md`
- Learnings on worktree discipline: `knowledge-base/learnings/workflow-patterns/2026-02-11-worktree-edit-discipline.md`
- Plan review feedback: DHH, Kieran, and simplicity reviewers all converged on inline checks over agents
