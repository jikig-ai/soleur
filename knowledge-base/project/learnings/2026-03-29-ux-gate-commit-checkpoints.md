# Learning: UX gate artifacts need incremental commit checkpoints

## Problem

During long UX gate sessions (3+ hours of specialist invocations, domain leader review cycles, and brand guide alignment passes), all artifacts accumulated without commits. If the session crashed or the process died, everything was lost. This was the same class of data loss as the worktree stash loss (2026-02-22), but specific to UX workflow phases that had no commit checkpoints.

## Solution

Added three commit checkpoints to `/soleur:work` SKILL.md:

1. **Phase 0.5 check 9** -- commit after each specialist agent completes (one commit per specialist for partial progress preservation)
2. **Phase 2 Design Artifact Gate** -- commit the implementation brief before UI task execution
3. **Phase 2 incremental commits** -- extended the heuristic table with UX-specific triggers and a `wip:` prefix convention

Key design decisions:

- `git status --short` discovers output files (specialists write to unpredictable paths)
- `wip:` prefix is intentional for UX artifacts (each revision is self-contained, unlike code WIP)
- Compound exemption: WIP commits skip compound (runs once in Phase 4)
- Squash merge safety: WIP commits vanish on merge, so over-committing is free

## Key Insight

UX artifacts are high-effort and low-recoverability -- the opposite of code, which can be regenerated from specs. The existing incremental commit heuristic ("don't commit if the message would be WIP") is a code-centric heuristic that actively harms UX workflows. Domain-specific refinements to general heuristics are not contradictions -- they are necessary when different artifact types have different recoverability profiles.

## Session Errors

1. **Wrong script path for Ralph loop setup** -- used `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` instead of `./plugins/soleur/scripts/setup-ralph-loop.sh`. Self-corrected on next attempt. **Prevention:** The one-shot skill references this path in its instructions; verify the path exists before executing.

## Tags

category: workflow-improvement
module: soleur:work
