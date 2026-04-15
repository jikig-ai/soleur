---
date: 2026-04-15
category: bug-fixes
module: ci-workflows
tags: [github-actions, jq, bash, workflow-safety, retroactive-sweep]
related:
  - knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md
  - AGENTS.md#cq-ci-steps-polling-json-endpoints-under
  - PR #2283
  - issue #2236
---

# Learning: jq -e guard placement must precede side effects, not just jq -r

## Problem

When applying the `jq -e .` guard pattern (AGENTS.md `cq-ci-steps-polling-json-endpoints-under`) retroactively to a new workflow, it's tempting to place the guard immediately before the first `jq -r` call. In `scheduled-linkedin-token-check.yml`, the naive placement (between the "LinkedIn token is valid" echo and the `jq -r` call) would have still allowed a non-JSON 2xx body to drive the downstream `gh issue close` block — auto-closing any open renewal issue on unvalidated data before the crash.

The failure surface is wider than the jq crash itself:

1. HTTP 2xx check passes.
2. Step echoes "LinkedIn token is valid".
3. `gh issue close` runs to close the stale renewal issue as "resolved".
4. `jq -r` crashes on non-JSON body — but the damage is already done.

## Solution

Place the `jq -e .` guard **before** any code that runs on the assumption that the body is valid, not just before the first `jq -r` call. In the LinkedIn workflow this means placing the guard immediately after the HTTP 2xx check, before the "token is valid" branch including its `gh issue close` side effect.

```bash
if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
  # ... non-2xx handling
fi

# GUARD HERE -- before any code that trusts the body
if ! jq -e . /tmp/li-response.json >/dev/null 2>&1; then
  echo "::warning::non-JSON body on HTTP $HTTP_CODE. Skipping."
  exit 0
fi

echo "Token is valid."
# ... jq -r calls AND gh issue close side effects safely follow
```

## Key Insight

The `jq -e` guard is not just a crash-prevention mechanism — it's a validity gate for the whole 2xx code path. Ask: "what else in this branch trusts the body shape?" before choosing placement. The `jq -r` crash under `bash -e` is the loud failure; the silent failure (closing issues on unvalidated data, wrong auto-comments, phantom cleanups) is worse.

## Related Process Note (retroactive sweeps)

When PR #2226 codified the `jq -e` pattern, the git-history analyst identified two other files affected. The plan for this PR (#2283) ran a full `jq -r` sweep across `.github/workflows/*.yml` and found a third latent case (`web-platform-release.yml:177-190` health-check loop) that was NOT in #2236's scope but is the same bug class. Filed as #2286 rather than scope-creeping this PR. Pattern: **codified fix → named cases → proactive sweep → defer new finds via issues, don't balloon scope.**

## Prevention

- Before placing a `jq -e` guard, read the full 2xx branch end-to-end and identify every side effect (`gh issue close`, webhook calls, state writes).
- When applying a codified pattern retroactively, always run a full `grep jq -r` across all workflows and file issues for any latent cases not in the original scope (per `wg-when-an-audit-identifies-pre-existing` + `wg-when-deferring-a-capability-create-a`).
- Prefer `exit 0` + `::warning::` over `continue` in single-shot workflows — retry loops mask vendor state, scheduled health checks should not.

## Session Errors

1. **Used `sleep 8 && gh run list` in a foreground Bash call** to poll for workflow completion. **Recovery:** Command ran successfully (harness did not block). **Prevention:** Rule `hr-never-use-sleep-2-seconds-in-foreground` already covers this — use `run_in_background: true` for one-shot delayed checks or Monitor tool for polling loops. No new enforcement needed; this was operator inattention to an existing rule.
2. **Planning subagent harness limitation** (forwarded from session-state.md): `Task` tool unavailable for per-section parallel research. **Recovery:** Compensated with focused inline research. **Prevention:** documented in plan's Enhancement Summary. Not a workflow error — a harness constraint.
