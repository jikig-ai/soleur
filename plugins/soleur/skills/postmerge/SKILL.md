---
name: postmerge
description: "This skill should be used when verifying a merged PR deployed correctly and production is healthy."
---

# postmerge Skill

**Purpose:** Enforce post-merge verification so bugs that only appear in production context are caught immediately after merge -- not days later. This closes the "last mile" gap where QA passes locally but production diverges (stale files, unapplied migrations, CSP violations from injected scripts).

**CRITICAL: No command substitution.** Never use `$()` in Bash commands. When a step says "get value X, then use it in command Y", run them as **two separate Bash tool calls** -- first get the value, then use it literally in the next call.

## Arguments

`$ARGUMENTS` should contain the PR number. If omitted, detect from the most recently merged PR on the current branch.

## Phase 1: Verify PR is Merged

Confirm the PR reached MERGED state:

```bash
gh pr view <number> --json state,mergeCommit,headRefName --jq '{state, mergeCommit: .mergeCommit.oid, branch: .headRefName}'
```

If state is not `MERGED`, stop:

```text
STOPPED: PR #<number> is not merged (state: <state>). Run /soleur:merge-pr first.
```

Record the merge commit SHA for later verification.

## Phase 2: Wait for CI on Main

Check the latest CI run on main triggered by the merge:

```bash
gh run list --branch main --limit 3 --json databaseId,status,conclusion,headSha
```

Find the run matching the merge commit SHA. If no matching run yet, use the **Monitor tool** with a polling loop (max 5 minutes). Do NOT use foreground `sleep`:

```bash
for i in $(seq 1 20); do
  result=$(gh run view <run-id> --json status,conclusion --jq '{status, conclusion}')
  echo "$(date +%H:%M:%S) $result"
  echo "$result" | grep -q '"completed"' && break
  sleep 15
done
```

React to the final status from the Monitor output.

**If CI passes:** Proceed to Phase 3.

**If CI fails:** Report the failure with details:

```bash
gh run view <run-id> --log-failed 2>&1 | tail -50
```

Stop:

```text
STOPPED: CI failed on main after merge.

Run ID: <run-id>
Conclusion: <conclusion>

Failed log tail:
<last 50 lines>

Investigate before proceeding. The merge is complete but production may not deploy.
```

## Phase 3: Verify Production Deployment

Check if a health endpoint is configured. Look for deployment URLs in environment or project config:

```bash
# Check for DEPLOY_URL or PRODUCTION_URL in environment
echo "${DEPLOY_URL:-not_set}"
echo "${PRODUCTION_URL:-not_set}"
```

If a production URL is available, verify the deployment:

```bash
curl -sf --max-time 10 "<production-url>/api/health" | jq .
```

**If health check succeeds:** Record the response and proceed.

**If health check fails or no URL configured:** Warn and proceed (not all PRs trigger deployments):

```text
WARNING: No production health check available. Skipping deployment verification.
```

## Phase 4: Verify File Freshness

Read key files from the merged commit to verify they match expectations -- NOT from the bare repo filesystem which may contain stale content.

For each file changed in the PR:

```bash
gh pr diff <number> --name-only
```

Spot-check up to 5 files by reading from the merged main:

```bash
git show main:<filepath>
```

Compare against expectations from the PR description and review. Flag if any file content seems stale or doesn't reflect the PR changes.

## Phase 5: Browser Verification (Conditional)

**Skip if:** The PR has no UI changes (no `.tsx`, `.css`, `.html` files in the diff).

**If UI changes exist:**

1. Start the dev server if not running (or use the production URL if available)
2. Use Playwright MCP to navigate to affected pages
3. Take screenshots of key states
4. Check browser console for errors (especially CSP violations)
5. Verify no broken resources or layout regressions

If Playwright MCP is unavailable, warn and skip:

```text
WARNING: Playwright MCP unavailable. Skipping browser verification.
```

## Phase 6: Update Issue and Compound

If the PR body contained `Closes #N`, update the linked issue with verification results:

```bash
gh issue comment <issue-number> --body "Post-merge verification complete for PR #<pr-number>.

- CI on main: PASSED
- Production health: <PASSED/SKIPPED/FAILED>
- File freshness: <PASSED/N files checked>
- Browser verification: <PASSED/SKIPPED>
"
```

Run compound to capture any learnings from the merge:

```
skill: soleur:compound
```

## Phase 7: Report

Print a summary:

```text
postmerge verification complete!

PR: #<number>
Merge commit: <sha>
CI on main: PASSED
Production health: <PASSED/SKIPPED/FAILED>
File freshness: <N files verified>
Browser verification: <PASSED/SKIPPED>
```

## Graceful Degradation

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No production URL | Skip health check with warning |
| Playwright MCP unavailable | Skip browser verification with warning |
| CI run not found | Poll up to 5 minutes, then warn and proceed |
| No UI files in diff | Skip browser verification entirely |
| No linked issue | Skip issue comment |

## Notes

- Always use `git show main:<path>` to read merged files -- never read from the bare repo filesystem directly.
- MCP tools resolve paths from the repo root. Use absolute paths when in a worktree.
- This skill is designed to run after `/soleur:merge-pr` completes. It can also be invoked standalone with a PR number.

## Production Debugging

- For production debugging use Sentry API (`SENTRY_API_TOKEN` in Doppler `prd`), Better Stack, or `/health` — never SSH for logs. SSH is for infra provisioning only. (ex-`cq-for-production-debugging-use`)
- For deploy webhook debugging, fetch `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` from Doppler `prd_terraform` (not `prd`). GET `https://deploy.soleur.ai/hooks/deploy-status` with CF Access headers + HMAC-sha256 over empty body. Full runbook: [deploy-status-debugging.md](./references/deploy-status-debugging.md). (ex-`cq-deploy-webhook-observability-debug`)
