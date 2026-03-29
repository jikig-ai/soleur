---
title: "fix: commit UX gate artifacts incrementally after each review cycle"
type: fix
date: 2026-03-29
---

# fix: commit UX gate artifacts incrementally after each review cycle

Closes #1271

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 4 (Changes 1-3, edge cases)
**Research sources:** `/soleur:work` SKILL.md analysis, 5 institutional learnings, AGENTS.md compound rule audit, worktree-manager WIP precedent

### Key Improvements

1. Added exact SKILL.md prose for all three insertion points (ready to paste)
2. Identified compound/WIP tension -- explicit exemption needed for UX WIP commits
3. Added squash-merge safety analysis (WIP commits vanish on merge, so over-committing is safe)
4. Added edge case for specialist output location discovery (agents write to unpredictable paths)

### New Considerations Discovered

- AGENTS.md rule "before every commit, run compound" must be explicitly exempted for UX WIP commits, matching the existing exemption for Phase 2.3 incremental commits
- Specialist agents may write output files to unpredictable locations -- the commit checkpoint must discover output paths, not assume them
- The `wip:` prefix has existing precedent in `worktree-manager.sh` draft PRs

## Overview

During UX gate execution in `/soleur:work`, high-effort artifacts (wireframes, copy documents, review revisions, brand guide alignment passes) accumulate without commits. If the session crashes or the process dies, all artifacts are lost. This is the same class of data loss documented in the 2026-02-22 worktree stash loss learning, but specific to UX gate phases.

The existing incremental commit heuristic in Phase 2.3 covers code changes during task execution but not UX gate work, which happens at two distinct points:

1. **Phase 0.5, check 9** -- specialist pre-flight invocations (auto-invoke missing specialists in pipeline mode)
2. **Phase 2, step 2 (Design Artifact Gate)** -- `ux-design-lead` produces implementation brief before first UI task

Neither location has commit checkpoints. A 3+ hour UX revision session can produce dozens of files that remain untracked until someone manually commits.

### Research Insights

**Squash merge safety:** All PRs in this repo use squash merge (`gh pr merge --squash`). WIP commits are squashed into a single commit on merge, so they have zero impact on the final git history. This makes the "err on the side of committing too often" heuristic completely safe -- there is no cost to extra WIP commits, only cost to missing them (data loss).

**Precedent for `wip:` prefix:** The `worktree-manager.sh` script already creates draft PRs with `"WIP: $branch"` titles (line 854). The `wip:` commit prefix is consistent with this existing convention.

**Skill-enforced convention tier:** Per the 2026-03-19 learning, commit checkpoints at specific workflow phases are the right enforcement tier -- the LLM can identify when a specialist completed successfully (semantic judgment), which hooks cannot detect.

## Proposed Solution

Add commit checkpoints at three points in `plugins/soleur/skills/work/SKILL.md`:

### Change 1: Post-Specialist Commit in Phase 0.5 Check 9

**Location:** Phase 0.5, check 9 (specialist review checks, line 81), after specialist agent completes successfully.

**Current text ends with:** "Do not FAIL in pipeline mode. If all recommended specialists are accounted for (in `**Agents invoked:**` or `**Skipped specialists:**`): pass silently."

**Append after check 9, before the "On FAIL:" line (line 83):**

```markdown
   **UX artifact commit checkpoint (after each specialist in check 9):** After each specialist agent completes successfully (interactive "Run specialist now" or pipeline auto-invoke), commit the output:

   1. Run `git status --short` to discover new/modified files from the specialist
   2. Stage specialist output files: `git add <discovered files>`
   3. Commit: `git commit -m "wip: <specialist-name> artifacts for <feature-name>"`

   Each specialist gets its own commit so partial progress is preserved if a later specialist fails. Do not commit on specialist failure. Do not run compound before these WIP commits -- compound runs once in Phase 4, not before intermediate checkpoints.
```

### Research Insights (Change 1)

**Edge case -- output file discovery:** Specialist agents (ux-design-lead, copywriter) write output to unpredictable locations. The `ux-design-lead` writes `.pen` files and may create files under `knowledge-base/product/design/`. The copywriter writes markdown files to `knowledge-base/product/copy/` or similar. The commit checkpoint must use `git status --short` to discover what changed, not assume specific paths.

**Edge case -- concurrent specialist output:** When check 9 invokes multiple specialists (e.g., ux-design-lead then copywriter), each must commit before the next runs. This serialization is already enforced by the check 9 loop structure (interactive: one at a time via FAIL/prompt; pipeline: sequential auto-invoke).

### Change 2: Post-Design-Artifact-Gate Commit in Phase 2

**Location:** Phase 2, step 2 (Design Artifact Gate, line 184), after `ux-design-lead` produces the implementation brief.

**Current text ends with:** "Do not write any markup until the brief is received."

**Append after that sentence:**

```markdown

   **UX artifact commit checkpoint (after Design Artifact Gate):** After the implementation brief is received, commit before proceeding to UI tasks:

   1. Run `git status --short` to discover the implementation brief and any generated design files
   2. Stage: `git add <discovered files>`
   3. Commit: `git commit -m "wip: UX implementation brief for <feature-name>"`

   This checkpoint ensures the implementation brief (which drives all subsequent UI tasks) survives session crashes. Do not run compound before this WIP commit.
```

### Research Insights (Change 2)

**Why this matters specifically:** The implementation brief is the binding input for all UI tasks. If it is lost, every UI task must be re-derived from wireframes -- a costly rework cycle. The brief also represents the output of the `ux-design-lead` agent analyzing wireframes, which is non-deterministic and may produce different results on re-run.

### Change 3: UX Review Cycle Commits in Incremental Commits Section

**Location:** Phase 2, step 3 (Incremental Commits section, lines 207-235), extend the existing table and heuristic.

**After the existing table (line 216), add new rows:**

The existing table:

```markdown
   | Commit when... | Don't commit when... |
   |----------------|---------------------|
   | Logical unit complete (model, service, component) | Small part of a larger unit |
   | Tests pass + meaningful progress | Tests failing |
   | About to switch contexts (backend → frontend) | Purely scaffolding with no behavior |
   | About to attempt risky/uncertain changes | Would need a "WIP" commit message |
```

**Replace with:**

```markdown
   | Commit when... | Don't commit when... |
   |----------------|---------------------|
   | Logical unit complete (model, service, component) | Small part of a larger unit |
   | Tests pass + meaningful progress | Tests failing |
   | About to switch contexts (backend → frontend) | Purely scaffolding with no behavior |
   | About to attempt risky/uncertain changes | Would need a "WIP" commit message |
   | UX specialist produces artifacts (wireframes, copy, brief) | Specialist is still generating (mid-output) |
   | Domain leader review cycle completes (feedback applied) | Review feedback not yet incorporated |
   | Brand guide alignment pass completes | Alignment still in progress |
```

**After the existing heuristic (line 218), add:**

```markdown
   **UX artifact heuristic:** "Did a specialist just produce or revise artifacts? If yes, commit with `wip: UX <description> for feat-X`. UX artifacts are high-effort and low-recoverability -- err on the side of committing too often rather than too rarely."

   The `wip:` prefix is intentional for UX artifacts. Unlike code commits where "WIP" signals an incomplete unit, UX artifacts are valuable at every revision stage. Each revision is a recoverable checkpoint. WIP commits are squashed on merge, so they have no impact on final git history. Do not run compound before UX WIP commits -- compound runs once in Phase 4.
```

### Research Insights (Change 3)

**Compound exemption rationale:** The AGENTS.md rule "Before every commit, run compound" applies to the final feature commit, not intermediate WIP checkpoints. Phase 2.3 incremental commits already skip compound implicitly (the `/work` skill only invokes compound in Phase 4). Making this explicit for UX WIP commits prevents confusion and avoids the absurdity of running a learning-capture workflow before every design revision.

**The "WIP" contradiction:** The existing heuristic says "don't commit if the message would be 'WIP'." The UX-specific heuristic explicitly overrides this for design artifacts, where WIP commits are the correct pattern. This is not a contradiction -- it is a domain-specific refinement. Code WIP commits are bad (incomplete logic, failing tests). Design WIP commits are good (each revision is self-contained and valuable).

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
- [x] Compound is explicitly exempted from UX WIP commits (runs once in Phase 4)
- [x] Output file discovery uses `git status --short`, not hardcoded paths

## Test Scenarios

- Given a work session where check 9 auto-invokes a missing ux-design-lead, when the specialist completes, then artifacts are committed with `wip: ux-design-lead artifacts for feat-X`
- Given a work session where check 9 auto-invokes both copywriter and ux-design-lead, when each completes, then each gets a separate commit (partial progress preserved)
- Given a work session where the Design Artifact Gate produces an implementation brief, when the brief is received, then it is committed before UI task execution begins
- Given a work session with multiple CMO review cycles on UX artifacts, when each review round's feedback is applied, then each revision is committed
- Given a work session where brand guide alignment is applied to UX artifacts, when alignment completes, then artifacts are committed
- Given a specialist that fails (timeout, error), when failure is detected, then no commit is attempted for that specialist (only successful outputs are committed)
- Given a UX WIP commit, when the commit is created, then compound is NOT invoked (compound runs only in Phase 4)
- Given a specialist that writes output to an unexpected path, when the commit checkpoint runs, then `git status --short` discovers the files correctly

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Minimal risk. Single SKILL.md file modification. Extends the existing incremental commit pattern (Phase 2.3) to cover UX gate phases. No new mechanisms -- reuses the existing `git add` + `git commit` workflow with UX-specific commit message conventions. The `wip:` prefix is consistent with the existing worktree-manager draft PR convention. Compound exemption is consistent with existing Phase 2.3 behavior (incremental commits already skip compound).

## Context

- Origin session: feat-repo-connection (2026-03-29), 3+ revision cycles with all UX artifacts untracked
- Related learning: `knowledge-base/project/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` -- documents the class of data loss from uncommitted work
- Related learning: `knowledge-base/project/learnings/2026-03-19-skill-enforced-convention-pattern.md` -- validates skill instructions as enforcement tier for semantic commit decisions
- Related learning: `knowledge-base/project/learnings/2026-03-27-skill-defense-in-depth-gate-pattern.md` -- Phase N.5 pattern for always-run gates
- Related learning: `knowledge-base/project/learnings/2026-02-12-review-compound-before-commit-workflow.md` -- compound before final commit, not WIP commits
- Related plan: `knowledge-base/project/plans/2026-03-25-fix-enforce-ux-content-gates-plan.md` (Closes #1137) -- covers UX gate enforcement, not commit checkpoints
- Existing pattern: Phase 2.3 incremental commit heuristic in `/soleur:work` SKILL.md
- Existing precedent: `worktree-manager.sh` line 854 uses `"WIP: $branch"` for draft PRs

## References

- Issue: [#1271](https://github.com/jikig-ai/soleur/issues/1271)
- Work skill target: `plugins/soleur/skills/work/SKILL.md:81` (check 9), `plugins/soleur/skills/work/SKILL.md:184` (Design Artifact Gate), `plugins/soleur/skills/work/SKILL.md:207-235` (Incremental Commits)
