# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-06-fix-go-session-start-mcp-json-dirty-restore-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking.

### Decisions
- Skip with `SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty` (not backup); probe is `git diff --quiet HEAD`, any non-zero probe status keeps the file.
- Guard also keeps symlinked and skip-worktree/assume-unchanged `.mcp.json`; equal-to-main is a silent skip.
- Suite's default fixture is tracked-dirty: add a `stale` fixture mode, re-point R3/R3e/R3f/R3g/R11, add R12-R12j, raise MIN_ASSERTIONS, regenerate baseline.
- No other go mirror carries the restore block (.grok/commands/go.md is a symlink).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; DHH, Kieran, simplicity, CTO, security-sentinel, spec-flow-analyzer
