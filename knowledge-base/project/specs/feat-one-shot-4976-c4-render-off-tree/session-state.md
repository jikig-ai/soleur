# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-05-fix-c4-render-off-tree-plan.md
- Status: complete

### Errors
None. (Two write-hook blocks hit and self-corrected during planning: an IaC-routing gate on negation prose, and an initial bare-root mirror write redirected to the worktree. Task tool was not in the planning subagent's deferred-tool set, so deepen-plan gates 4.6-4.9, verify-the-negative, and precedent-diff were run directly rather than via fan-out agents.)

### Decisions
- Chose Option A (render off-tree): `renderC4Model` returns validated bytes instead of writing the tracked `model.likec4.json`; `rerenderAndCommit` commits returned bytes and the existing `op:"manual"` resync pull lands them on the clone. Removes the dirty-tree source by construction.
- Verified GET `/api/kb/c4/project` (route.ts:66) is the sole on-disk reader of `model.likec4.json`; committed bytes still reach disk via the resync pull, no route change required.
- Precedent-diff confirmed: `c4-render.ts` header cites `pdf-linearize.ts`, which returns `{ ok, buffer }` rather than writing in place — Option A restores the stated precedent (caller owns persistence).
- Justified removing the `O_NOFOLLOW`/TOCTOU re-read in the writer: it existed only because the writer re-read a tracked file; Option A eliminates the on-disk re-read.
- Brand-survival threshold = none (worst case is a self-healing per-user stale-diagram banner; no data leak). Dogfood verification tracked by existing issue #4966.

### Components Invoked
- Skill soleur:plan (args #4976)
- Skill soleur:deepen-plan (args plan file path)
- deepen-plan gates 4.6-4.9, verify-the-negative, 4.4 precedent-diff executed directly via gh/git/grep
- Committed + pushed plan and tasks.md to branch feat-one-shot-4976-c4-render-off-tree
