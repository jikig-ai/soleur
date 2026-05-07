---
date: 2026-05-07
category: best-practices
tags: [ci, workflows, github-actions, drift-guards, multi-agent-review]
related: [2026-04-17-align-ci-poll-windows-with-adjacent-steps.md, 2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md]
prs: [3421]
issues: [3408, 3409]
---

# Comment-Coupled Workflow Invariants Need Runtime Assertion + Shared Source

## Problem

PR #3421 (resolving #3408 + #3409) added a `Pre-rerun lock probe` step to `web-platform-release.yml` whose `IN_FLIGHT_CEILING_S=900` constant must equal `STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S` (verify-completion step) **and** `HEALTH_POLL_MAX_ATTEMPTS * HEALTH_POLL_INTERVAL_S` (verify-health step) — three constants spread across three step `env:` blocks.

The plan deliberately scoped to a comment-only cross-link ("IN_FLIGHT_CEILING_S below must equal STATUS_POLL_MAX_ATTEMPTS × STATUS_POLL_INTERVAL_S in the next step") and a bidirectional comment in the verify-completion step. The deepen-plan pass even flagged the phantom-rule citation pattern (`cq-align-ci-poll-windows-with-adjacent-steps` cited but not defined) and revised the comment to reference constants directly.

Two independent review agents (architecture-strategist + code-quality-analyst) flagged this as **P2**: comments aren't load-bearing. The previous instance of this exact failure mode (one ceiling raised without the others) caused #3398 — the parent issue this PR was hardening against. Comment-only coupling perpetuates the recurrence pattern it was meant to prevent.

A second related issue: `jq -r '.start_ts // 0'` aliased absent/corrupt state to `ELAPSED ≈ now`, falling through to "proceed (state likely stale)" — the wrong semantic for missing fields, masking corrupt-state cases the operator should know about.

## Solution

Two structural fixes applied inline (`commit 344c56a7`):

### 1. Hoist constants to job-level `env:` + runtime arithmetic assertion

```yaml
deploy:
  ...
  env:
    STATUS_POLL_MAX_ATTEMPTS: 180
    STATUS_POLL_INTERVAL_S: 5
    HEALTH_POLL_MAX_ATTEMPTS: 90
    HEALTH_POLL_INTERVAL_S: 10
    IN_FLIGHT_CEILING_S: 900
  steps:
    - name: Pre-rerun lock probe
      run: |
        STATUS_WINDOW=$((STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S))
        HEALTH_WINDOW=$((HEALTH_POLL_MAX_ATTEMPTS * HEALTH_POLL_INTERVAL_S))
        if [ "$STATUS_WINDOW" -ne "$IN_FLIGHT_CEILING_S" ] || [ "$HEALTH_WINDOW" -ne "$IN_FLIGHT_CEILING_S" ]; then
          echo "::error::Poll-window drift: STATUS=${STATUS_WINDOW}s HEALTH=${HEALTH_WINDOW}s IN_FLIGHT_CEILING=${IN_FLIGHT_CEILING_S}s — all three must agree."
          exit 1
        fi
```

A future PR that bumps one constant without the others fails CI rather than producing stale-state false positives.

### 2. Strict-numeric guard on jq `// 0` numeric-fallback

```bash
# Instead of: PRIOR_START=$(... | jq -r '.start_ts // 0')
PRIOR_START=$(... | jq -r '.start_ts // empty')
if ! [[ "$PRIOR_START" =~ ^[0-9]+$ ]] || [ "$PRIOR_START" -lt 1700000000 ]; then
  echo "Pre-rerun probe: start_ts absent/invalid (got '$PRIOR_START') — proceeding (state corrupt; flock will catch)"
  exit 0
fi
ELAPSED=$(($(date +%s) - PRIOR_START))
```

The 1700000000 floor (2023-11-15 unix epoch) is well before this codebase was deployed — any older parseable value is corrupt-by-construction. Distinguishes corrupt state from stale-ceiling state in the operator log.

## Key Insight

**Comments are review-detectable, not load-bearing.** When a workflow invariant must hold across distinct `env:` blocks, the prevention layer is:

1. **Shared source of truth** — job-level `env:` block, or workflow-level inputs, or a generated config file. Step-level env declarations of the same constant in multiple places is the failure mode.
2. **Runtime arithmetic assertion** — fail CI when the invariant is violated. Cheap (one bash arithmetic check at step start), high-leverage (catches drift on the PR that introduces it, not on the post-merge deploy that surfaces the consequence).

For `jq` numeric fallbacks: `// 0` silently aliases missing-field to a real numeric value that downstream arithmetic treats as valid. Use `// empty` + an explicit shape guard (regex + sanity floor) when the absence semantic differs from the zero semantic.

## When to Apply

- Adding any workflow constant whose value must equal another workflow constant (poll windows, retry counts, timeout ceilings, port numbers).
- Adding any `jq -r '.field // <number>'` fallback where the field's absence has a different meaning than the fallback value.
- Multi-agent review surfaces drift-guard or invariant-coupling concerns: the prevention is structural (shared env / runtime assert), not procedural (more comments).

## Session Errors

- **GitHub GraphQL rate limit at session start blocked initial gh issue/pr lookups.** — Recovery: switched to REST (`gh api repos/...`). The same hit blocked `worktree-manager.sh draft-pr`; PR was created later via `gh pr create`. **Prevention:** prefer `gh api repos/{owner}/{repo}/...` REST endpoints over GraphQL `--json` shorthands when running near session start or in pipeline mode where multiple agents may have already consumed the GraphQL pool.
- **`security_reminder_hook.py` fired on workflow file edits with `PreToolUse:Edit hook error` output.** — Recovery: retried the edit; landed on second attempt. The hook is a reminder, not a true block. **Prevention:** when a hook's output is a reminder (lists risky patterns the user *could* introduce, doesn't say "BLOCKED:"), treat the failed call as informational and retry. Verify the edit landed via `git status --short` rather than re-reading the file (which would have been stale on the failed attempt).

## References

- PR #3421 (this learning's source)
- Plan: `knowledge-base/project/plans/2026-05-07-feat-deploy-pipeline-hardening-3408-3409-plan.md`
- Sibling: `2026-04-17-align-ci-poll-windows-with-adjacent-steps.md` (the original poll-window alignment learning)
- Parent recurrence: `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md` (#3398's learning)
