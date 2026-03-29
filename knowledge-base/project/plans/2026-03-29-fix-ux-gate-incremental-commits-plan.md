---
title: "fix: commit UX gate artifacts incrementally after each review cycle"
type: fix
date: 2026-03-29
---

# fix: commit UX gate artifacts incrementally after each review cycle

Closes #1271

## Overview

During UX gate execution in `/soleur:work`, high-effort artifacts (wireframes, copy documents, review revisions, brand guide alignment passes) accumulate without commits. If the session crashes or the process dies, all artifacts are lost. This is the same class of data loss documented in the 2026-02-22 worktree stash loss learning, but specific to UX gate phases.

The existing incremental commit heuristic in Phase 2.3 covers code changes during task execution but not UX gate work, which happens at two distinct points:

1. **Phase 0.5, check 9** -- specialist pre-flight invocations (auto-invoke missing specialists in pipeline mode)
2. **Phase 2, step 2 (Design Artifact Gate)** -- `ux-design-lead` produces implementation brief before first UI task

Neither location has commit checkpoints. A 3+ hour UX revision session can produce dozens of files that remain untracked until someone manually commits.

## Proposed Solution

Add commit checkpoints at three points in `plugins/soleur/skills/work/SKILL.md`:

### Change 1: Post-Specialist Commit in Phase 0.5 Check 9

**Location:** Phase 0.5, check 9 (specialist review checks), after specialist agent completes successfully.

After each specialist agent runs successfully (step a "Run specialist now" or pipeline auto-invoke), commit the artifacts:

```text
After each specialist completes successfully:
  1. Stage specialist output files (wireframes, copy docs, design files)
  2. Commit: "wip: <specialist-name> artifacts for <feature-name>"
  3. Continue to next specialist or proceed
```

This covers the case where `/work` auto-invokes missing specialists from the plan's Domain Review section. Each specialist gets its own commit so partial progress is preserved if a later specialist fails.

### Change 2: Post-Design-Artifact-Gate Commit in Phase 2

**Location:** Phase 2, step 2 (Design Artifact Gate), after `ux-design-lead` produces the implementation brief.

After the implementation brief is received:

```text
After ux-design-lead produces implementation brief:
  1. Stage the implementation brief and any generated design files
  2. Commit: "wip: UX implementation brief for <feature-name>"
  3. Proceed to first UI task
```

### Change 3: UX Review Cycle Commits in Incremental Commits Section

**Location:** Phase 2, step 3 (Incremental Commits section), add a UX-specific commit trigger to the existing table.

Extend the "Commit when..." column in the incremental commit heuristic table to include UX review cycle completions:

| Commit when... | Don't commit when... |
|----------------|---------------------|
| *(existing rows)* | *(existing rows)* |
| UX specialist produces artifacts (wireframes, copy, brief) | Specialist is still generating (mid-output) |
| Domain leader review cycle completes (CMO/CPO feedback applied) | Review feedback not yet incorporated |
| Brand guide alignment pass completes | Alignment still in progress |

Add a UX-specific heuristic below the existing one:

```text
**UX artifact heuristic:** "Did a specialist just produce or revise artifacts?
If yes, commit with 'wip: UX <description> for feat-X'. UX artifacts are
high-effort and low-recoverability -- err on the side of committing too often."
```

The `wip:` prefix is intentional for UX artifacts. Unlike code commits where a "WIP" message signals incompleteness, UX artifacts are valuable at every revision stage. The existing heuristic says "don't commit if the message would be 'WIP'" -- this UX-specific override acknowledges that WIP commits are the correct pattern for design artifacts where each revision is a recoverable checkpoint.

## Files Modified

| File | Change |
|------|--------|
| `plugins/soleur/skills/work/SKILL.md` | Add commit checkpoints at specialist invocation (Phase 0.5 check 9), Design Artifact Gate (Phase 2 step 2), and UX review heuristic (Phase 2 step 3) |

## Acceptance Criteria

- [x] `/soleur:work` skill commits after specialist agent produces artifacts in Phase 0.5 check 9
- [x] `/soleur:work` skill commits after Design Artifact Gate produces implementation brief in Phase 2
- [x] Incremental commit heuristic table includes UX-specific triggers (specialist output, review cycle, brand guide alignment)
- [x] UX artifact heuristic documented explaining `wip:` prefix pattern for design artifacts
- [x] Commit messages use conventional format: `wip: UX <description> for feat-X`
- [x] No data loss risk from untracked UX artifacts across long sessions

## Test Scenarios

- Given a work session where check 9 auto-invokes a missing ux-design-lead, when the specialist completes, then artifacts are committed with `wip: ux-design-lead artifacts for feat-X`
- Given a work session where check 9 auto-invokes both copywriter and ux-design-lead, when each completes, then each gets a separate commit (partial progress preserved)
- Given a work session where the Design Artifact Gate produces an implementation brief, when the brief is received, then it is committed before UI task execution begins
- Given a work session with multiple CMO review cycles on UX artifacts, when each review round's feedback is applied, then each revision is committed
- Given a work session where brand guide alignment is applied to UX artifacts, when alignment completes, then artifacts are committed
- Given a specialist that fails (timeout, error), when failure is detected, then no commit is attempted for that specialist (only successful outputs are committed)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Minimal risk. Single SKILL.md file modification. Extends the existing incremental commit pattern (Phase 2.3) to cover UX gate phases. No new mechanisms -- reuses the existing `git add` + `git commit` workflow with UX-specific commit message conventions. The `wip:` prefix is consistent with the issue's proposed format.

## Context

- Origin session: feat-repo-connection (2026-03-29), 3+ revision cycles with all UX artifacts untracked
- Related learning: `knowledge-base/project/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` -- documents the class of data loss from uncommitted work
- Related plan: `knowledge-base/project/plans/2026-03-25-fix-enforce-ux-content-gates-plan.md` (Closes #1137) -- covers UX gate enforcement, not commit checkpoints
- Existing pattern: Phase 2.3 incremental commit heuristic in `/soleur:work` SKILL.md

## References

- Issue: [#1271](https://github.com/jikig-ai/soleur/issues/1271)
- Work skill target: `plugins/soleur/skills/work/SKILL.md:79-81` (check 9), `plugins/soleur/skills/work/SKILL.md:184` (Design Artifact Gate), `plugins/soleur/skills/work/SKILL.md:207-235` (Incremental Commits)
