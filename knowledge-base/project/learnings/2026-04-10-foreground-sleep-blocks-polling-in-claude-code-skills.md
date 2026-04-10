# Learning: Foreground sleep blocks polling in Claude Code skills

## Problem

Skill files (ship/SKILL.md, postmerge/SKILL.md) and AGENTS.md instructed the agent to "poll every N seconds" for PR merge state and CI run status but did not specify HOW to poll within Claude Code's tool constraints. The agent interpreted "poll every 10 seconds" as `sleep 10 && gh pr view ...` in a foreground Bash call, which Claude Code blocks (foreground `sleep` >= 2s is prohibited). This stalled the entire merge pipeline.

## Root Cause

The instructions described the *what* (poll every N seconds) without prescribing the *how* (which Claude Code tool to use). Claude Code has three relevant mechanisms:

1. **Foreground Bash** -- `sleep` >= 2s is blocked. This is what the agent chose.
2. **Monitor tool** -- runs a shell process in the background and streams stdout lines as notifications. `sleep` inside the monitored process is fine because it runs in the child process.
3. **Bash with `run_in_background: true`** -- runs a one-shot command in the background, notifies on completion. Good for "wait N seconds then check once."

The skill files gave no guidance on which mechanism to use, so the agent defaulted to the simplest interpretation (foreground Bash with sleep), which is the one that does not work.

## Solution

Three files modified:

**1. AGENTS.md -- New hard rule** prescribing Monitor for polling loops and `run_in_background` for one-shot delays. Prohibits foreground `sleep` >= 2s.

**2. ship/SKILL.md Phase 7 -- Three polling sections rewritten:**

- PR merge polling: Monitor with `while true` loop, echoes state each iteration, breaks on MERGED/CLOSED
- CI run status: `run_in_background` for 15s initial delay, then Monitor loop per run
- Workflow validation: Monitor loop per triggered workflow

**3. postmerge/SKILL.md Phase 2 -- CI polling rewritten** with bounded Monitor loop (`for i in $(seq 1 20)` at 15s = 5 min max).

### Design Decisions

| Decision | Rationale |
|---|---|
| Monitor over `run_in_background` for polling | Intermediate states matter (CLOSED vs MERGED, failure vs in-progress). Monitor delivers each echo as a notification. |
| `run_in_background` for one-shot delays | Step 2 of CI verification just needs to wait 15s then list runs. Only final output matters. |
| Bounded loop in postmerge (`seq 1 20`) | No human in the loop to interrupt. Unbounded `while true` could hang forever if a run gets stuck. |

## Key Insight

When writing Claude Code skill instructions that involve waiting or polling, always specify the mechanism -- not just the intent. "Poll every N seconds" is ambiguous and agents will default to the simplest (and often blocked) interpretation. The Monitor tool with a shell loop is the correct pattern for polling because `sleep` inside a monitored subprocess is not blocked.

## Session Errors

**Worktree creation succeeded but disappeared** -- First `worktree-manager.sh create fix-polling-patterns` reported success, but the worktree was not found at the expected path on subsequent access. Required a second creation. Likely a transient filesystem or cleanup race condition. **Prevention:** Verify worktree existence with `ls` immediately after creation before proceeding with edits. Consider adding a post-create verification step to `worktree-manager.sh`.

## Prevention

The AGENTS.md hard rule serves as the primary prevention -- it is loaded every turn via CLAUDE.md. Future skills that say "poll every N seconds" will be constrained to use Monitor or `run_in_background`, never foreground `sleep`.

A guardrails hook was considered but is not recommended because Claude Code already blocks foreground `sleep` >= 2s at the runtime level. The gap was in skill instructions, not runtime controls.

## Related Learnings

- `2026-03-29-post-merge-release-workflow-verification.md` -- Ship Phase 7 was added to poll CI/CD runs after merge
- `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md` -- Polling for merge state hangs when CI never runs
- `2026-03-03-pipeline-continuation-stalls.md` -- Polling loops face the same "stop vs. continue" ambiguity as pipeline handoffs
- `2026-03-09-depth-limited-api-retry-pattern.md` -- Bounded retry/polling pattern

## Tags

category: workflow-issues
module: soleur
component: plugins/soleur/skills/ship, plugins/soleur/skills/postmerge, AGENTS.md
severity: high
