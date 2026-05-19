---
category: workflow-patterns
module: one-shot
tags: [one-shot, cherry-pick, parallel-pipelines, code-review, cross-reconcile]
status: applied
---

# Parallel one-shot pipelines on the same root cause resolve via verbatim cherry-pick

## Problem

`/soleur:go #4089` and `/soleur:go #4082` were invoked separately for two issues filed against the same root cause (`vinngest-v1.0.0` colliding with the plugin-release tag-discovery glob in `reusable-release.yml`). The first pipeline produced PR #4087 (sibling) with 47 CI checks green; the second pipeline (this one) started planning on top of that — but the user's intent was to resolve #4089, not idle behind #4087.

Naïve options at plan time:
- **A. Wait for #4087 to merge, then close #4089** — but the user's pipeline is running NOW; idling burns API budget.
- **B. Re-author the fix on this branch from scratch** — duplicate effort, identical content, no value-add.
- **C. Cherry-pick #4087's commits verbatim** — preserves sibling parity, zero re-derivation.

## Solution

Cherry-pick the canonical sibling commits, then a cleanup commit to drop any sibling-scope artifacts that came along:

```bash
git cherry-pick <fix-sha>      # initial fix
git cherry-pick <hardening-sha> # review-hardening
git cherry-pick <learning-sha>  # compound learning file
git rm knowledge-base/project/{plans,specs}/<sibling-scope>...
git commit -m "chore: drop sibling-branch scope artifacts after cherry-pick"
```

Phase 0.5 of the plan explicitly checks sibling state (`gh issue view <sibling>`, `gh pr view <sibling>`) to handle the race: if sibling merged before /work started, the cherry-picks become a rebase no-op and the PR reduces to a body-update + `Closes #N`.

## Key Insight

**Whichever PR merges first wins; the other rebases to no-op.** This is operationally safe because both PRs target the same file with the same content — cherry-pick preserves byte-identical state with the sibling. The losing PR's `gh pr merge` either becomes empty (closes cleanly) or merges as a no-op patch with no behavior change.

Two non-obvious consequences:

1. **Code review should expect verbatim parity.** When reviewing a cherry-pick-shaped PR, the pattern-recognition agent's first probe is `diff <sibling-sha>:<file> <branch>:<file>` — a non-empty diff would defeat the cherry-pick justification and warrant a P1.
2. **The cross-reconcile triad applies hard.** code-simplicity may flag inherited code as YAGNI ("trim the metachar fixture from 155 lines to 130"). Two of three agents recommending Ship + the structural argument that trimming here splits coverage between parallel PRs → dispose wontfix with rationale, NOT fix-inline. Fixing inline would diverge from sibling and harm the parallel-pipeline justification.

## Prevention

Pre-flight: when /soleur:go fires against an issue, the planning subagent should `gh search prs --label one-shot --state open` and surface any sibling PR targeting the same root cause BEFORE proposing the implementation approach. The plan can then frame Approach C (cherry-pick) vs Approach A (idle and close) as a deliberate choice rather than a discovery during work.

## Tags

category: workflow-patterns
module: one-shot
