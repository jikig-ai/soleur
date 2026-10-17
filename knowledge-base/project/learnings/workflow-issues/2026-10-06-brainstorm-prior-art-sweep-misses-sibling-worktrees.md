# Learning: brainstorm prior-art sweep only sees the current tree — sibling worktrees collide

## Problem

Two sessions ran `/soleur:go` on the identical Mistral feature within minutes on 2026-10-06. The first created worktree `feat-mistral-large-4-and-vibe-support` and wrote a complete brainstorm + spec (draft PR #9640, umbrella #9648). The second session ran the Phase 1.1 prior-art `find` — which scans only the current tree — found nothing, and `worktree-manager.sh feature mistral-support` created a duplicate worktree + pushed a second branch before the collision surfaced (via `git worktree list | grep mistral`, not via the artifact sweep).

**Prevention:** the prior-art sweep must extend past the current checkout. Before creating a worktree, sweep every path in `git worktree list` for `knowledge-base/project/{brainstorms,specs}/` entries matching the topic keywords — a same-topic artifact in a sibling worktree means the feature is already in flight, and the right move is amend-in-place, never a parallel branch. (A `gh pr list --state open` topic search also catches pushed-but-unwritten sessions.)

## Solution

Operator chose amend-in-place: the second worktree/branch was removed, and session 2's deltas (model-dogfood-first ordering, small-class self-host scope, #9609 checklist sequencing, BYOK→bundled-later) were folded into the first session's brainstorm + spec with per-row `[amended in second session]` markers and a Session Errors note.

## Key Insight

Free-prose brainstorm input carries no `#N` or `SOL-` key, so none of the input-keyed collision guards (`go.md` Step 1 worktree detection, the sharp-edge checks) fire — the *only* detector is a prior-art sweep that structurally cannot see sibling worktrees. Git worktree isolation is load-bearing everywhere else in this repo; it silently defeats artifact discovery. Any "does prior art exist?" check whose corpus is a single working tree under-claims by the number of live worktrees.

## Tags
category: workflow-issues
module: plugins/soleur/skills/brainstorm
